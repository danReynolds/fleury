// FrameSemanticsPipeline: the semantics half of the frame program,
// extracted from the browser host so EVERY structured surface (embed,
// serve, the web render backend) runs the same engine instead of the
// serve path shipping a poorer copy.
//
// What it owns, per flush:
//   - deferred scheduling (semantics never spend the visual frame budget;
//     the wire binding uses a same-task microtask so agents still see
//     "semantics for the just-rendered frame"),
//   - the retained-output fast path (nothing changed → present nothing),
//   - retained-leaf replacement (a value change patches one node instead
//     of rebuilding the tree) with the debug divergence oracle,
//   - the text-coverage fallback (painted regions without semantics get
//     synthetic text nodes, so assistive tech never hits a silent gap —
//     the visual surface is aria-hidden on every browser path),
//   - consuming the SemanticDirtyTracker exactly once per flush.
//
// Host-specific concerns stay host-side via callbacks: focus-coordinator
// sync (web), instrumentation, and flush-failure cleanup.

import 'dart:async';

import '../rendering/cell_buffer.dart';
import '../semantics/semantic_coverage.dart';
import '../semantics/semantic_presenter.dart';
import '../semantics/semantics.dart';
import '../semantics/semantics_owner.dart';
import '../widgets/framework.dart';
import 'frame_presentation.dart';
import 'semantic_flush_scheduler.dart';
import 'tui_frame_loop.dart';

/// Neutral per-flush stats; hosts adapt them into their own
/// instrumentation records.
final class SemanticFlushStats {
  const SemanticFlushStats({
    required this.reason,
    required this.coalescedFrameCount,
    required this.scheduleLatency,
    required this.retainedOutput,
    required this.presentation,
    required this.coverageAudit,
    required this.treeBuildTime,
    required this.coverageTime,
    required this.diffTime,
    required this.presenterTime,
    required this.totalFlushTime,
  });

  final String reason;
  final int coalescedFrameCount;
  final Duration scheduleLatency;
  final bool retainedOutput;
  final SemanticPresentationStats presentation;
  final SemanticCoverageAudit coverageAudit;
  final Duration treeBuildTime;
  final Duration coverageTime;
  final Duration diffTime;
  final Duration presenterTime;
  final Duration totalFlushTime;
}

/// The shared semantics engine for one runtime.
final class FrameSemanticsPipeline {
  FrameSemanticsPipeline({
    required SemanticFramePresenter presenter,
    required SemanticDirtyTracker dirtyTracker,
    required Element? Function() readRoot,
    SemanticsOwner? owner,
    SemanticFlushScheduler? flushScheduler,
    bool coverageFallback = true,
    void Function(SemanticTree presentedTree)? onTreePresented,
    void Function(SemanticFlushStats stats)? onFlushStats,
    void Function(Object error, StackTrace stack)? onFlushError,
  }) : _presenter = presenter,
       _dirtyTracker = dirtyTracker,
       _readRoot = readRoot,
       _owner = owner ?? SemanticsOwner(),
       _scheduler = flushScheduler ?? TimerSemanticFlushScheduler(),
       _coverageFallback = coverageFallback,
       _onTreePresented = onTreePresented,
       _onFlushStats = onFlushStats,
       _onFlushError = onFlushError;

  final SemanticFramePresenter _presenter;
  final SemanticDirtyTracker _dirtyTracker;
  final Element? Function() _readRoot;
  final SemanticsOwner _owner;
  final SemanticFlushScheduler _scheduler;
  final bool _coverageFallback;
  final void Function(SemanticTree)? _onTreePresented;
  final void Function(SemanticFlushStats)? _onFlushStats;
  final void Function(Object, StackTrace)? _onFlushError;

  /// The retained semantics owner — hosts read [SemanticsOwner.currentTree]
  /// for diagnostics and AT dispatch.
  SemanticsOwner get owner => _owner;

  /// The last flush's coverage audit — instrumentation reads it between
  /// flushes (e.g. for skipped-frame records).
  SemanticCoverageAudit get lastCoverageAudit => _lastCoverageAudit;

  CellBuffer? _lastPresentedBuffer;
  final Set<int> _pendingCoverageRows = <int>{};
  var _pendingCoverageFull = false;
  var _coalescedFramesSinceFlush = 0;
  final Stopwatch _scheduleLatency = Stopwatch();
  var _flushScheduled = false;
  var _semanticDirty = true;
  var _disposed = false;
  SemanticCoverageAudit _lastCoverageAudit = SemanticCoverageAudit.empty;
  Completer<void>? _idleCompleter;

  /// Conservative input rule: dispatched input marks semantics dirty even
  /// when the dirty tracker saw nothing — some state a handler mutates is
  /// only visible on the next tree walk. The retained-output fast path
  /// skips the walk again once a flush confirms nothing changed.
  void markSemanticsDirty() {
    _semanticDirty = true;
  }

  /// Accumulates one presented frame and schedules a deferred flush when
  /// semantic work is pending. Call AFTER present, with the committed
  /// buffer still current. [plan] carries the visual damage the coverage
  /// re-scan needs; null forces a full-coverage re-scan.
  void onFramePresented(TuiRenderedFrame frame, FramePresentationPlan? plan) {
    if (_disposed) return;
    _lastPresentedBuffer = frame.next;
    final dirtyRows = plan?.damage.dirtyRows;
    if (dirtyRows == null) {
      _pendingCoverageFull = true;
    } else if (!_dirtyRowsUnchanged(frame.previous, frame.next, dirtyRows)) {
      // Plans can be conservative (damage recorded for identical
      // repaints), so confirm cells actually differ before treating the
      // frame as a visual change.
      if (dirtyRows.isFull) {
        _pendingCoverageFull = true;
      } else {
        _pendingCoverageRows.addAll(dirtyRows.rows);
      }
    }
    final workPending =
        _semanticDirty ||
        _dirtyTracker.hasDirt ||
        _owner.currentTree == null ||
        _pendingCoverageFull ||
        _pendingCoverageRows.isNotEmpty;
    if (!workPending) return;
    _coalescedFramesSinceFlush += 1;
    if (_flushScheduled) return;
    _flushScheduled = true;
    _scheduleLatency
      ..reset()
      ..start();
    _scheduler.schedule(_runScheduledFlush);
  }

  /// Schedules a flush for a frame the visual pipeline SKIPPED (no render
  /// work) when semantic work is still owed — dispatched input that changed
  /// no visuals keeps the conservative rebuild contract.
  void onFrameSkippedWithPendingWork() {
    if (_disposed || _lastPresentedBuffer == null) return;
    if (!(_semanticDirty || _dirtyTracker.hasDirt)) return;
    _coalescedFramesSinceFlush += 1;
    if (_flushScheduled) return;
    _flushScheduled = true;
    _scheduleLatency
      ..reset()
      ..start();
    _scheduler.schedule(_runScheduledFlush);
  }

  /// Force-flushes ONLY when a deferred flush is outstanding — the
  /// before-action-dispatch contract (the peer's view must be current, but
  /// an idle pipeline has nothing newer to show).
  void flushPendingNow(String reason) {
    if (_flushScheduled) flushNow(reason);
  }

  void _runScheduledFlush() {
    // A force-flush may have run since this task was scheduled; the flag
    // is the single source of truth for outstanding work.
    if (!_flushScheduled) {
      _completeIdleIfQuiet();
      return;
    }
    try {
      flushNow('deferred');
    } catch (error, stack) {
      _onFlushError?.call(error, stack);
      rethrow;
    }
  }

  /// Completes when no deferred flush is outstanding.
  Future<void> awaitIdle() {
    if (!_flushScheduled) return Future.value();
    return (_idleCompleter ??= Completer<void>()).future;
  }

  void _completeIdleIfQuiet() {
    if (_flushScheduled) return;
    final completer = _idleCompleter;
    _idleCompleter = null;
    completer?.complete();
  }

  /// Presents accumulated semantic state to the presenter.
  ///
  /// Runs in a deferred task (or synchronously as a force-flush before
  /// semantic action dispatch) — never inside the visual frame budget. One
  /// flush covers every frame presented since the previous flush.
  void flushNow(String reason) {
    _flushScheduled = false;
    if (_disposed) {
      _completeIdleIfQuiet();
      return;
    }
    final currentRoot = _readRoot();
    final buffer = _lastPresentedBuffer;
    if (currentRoot == null || buffer == null) {
      _completeIdleIfQuiet();
      return;
    }
    final scheduleLatency = _scheduleLatency.isRunning
        ? _scheduleLatency.elapsed
        : Duration.zero;
    _scheduleLatency
      ..stop()
      ..reset();
    final coalescedFrameCount = _coalescedFramesSinceFlush;
    _coalescedFramesSinceFlush = 0;
    final coverageRows = _pendingCoverageFull
        ? TuiDirtyRows.full(buffer.size.rows)
        : TuiDirtyRows.fromRows(
            _pendingCoverageRows,
            rowCount: buffer.size.rows,
          );
    _pendingCoverageRows.clear();
    _pendingCoverageFull = false;

    final totalFlushStopwatch = Stopwatch()..start();
    final semanticDirtySnapshot = _dirtyTracker.takeDirtySnapshot();
    final retainedTree = _owner.currentTree;

    var stats = SemanticPresentationStats.none;
    var coverageAudit = _lastCoverageAudit;
    var treeBuildTime = Duration.zero;
    var coverageTime = Duration.zero;
    var diffTime = Duration.zero;
    var presenterTime = Duration.zero;

    // No semantic dirt, no repainted rows, and full coverage: the retained
    // semantic output is still exact.
    final canRetainSemanticOutput =
        retainedTree != null &&
        !_semanticDirty &&
        semanticDirtySnapshot.isClean &&
        !_lastCoverageAudit.hasUncoveredText &&
        coverageRows.isEmpty;
    var retainedOutput = false;
    if (canRetainSemanticOutput) {
      retainedOutput = true;
      stats = SemanticPresentationStats.retained(
        nodeCount: retainedTree.nodeCount,
      );
    } else {
      Map<SemanticNodeId, SemanticNode>? retainedLeafUpdates;
      // Leaf replacement requires a fallback-free retained tree: coverage
      // fallback nodes mirror painted buffer text, and patching around one
      // would keep its stale label "covering" cells whose text has since
      // changed. A full rebuild regenerates fallback from the live buffer.
      //
      // It also requires `!_semanticDirty` — the same conservative gate the
      // retain-OUTPUT fast path above uses. `_semanticDirty` means input was
      // dispatched and a handler may have mutated contributor state that only
      // a tree walk reveals (a `DataTable` selection, an app/command scope
      // counter). Those contributors record no leaf/structure dirt, so patching
      // only the recorded leaf would ship their nodes STALE. Taking the full
      // walk when input-dirtied keeps the retained path indistinguishable from
      // a rebuild (the divergence oracle below enforces exactly that).
      final canApplyRetainedLeafUpdates =
          retainedTree != null &&
          !_semanticDirty &&
          !_lastCoverageAudit.hasUncoveredText &&
          !semanticDirtySnapshot.requiresFullRebuild &&
          semanticDirtySnapshot.leafUpdates.isNotEmpty &&
          _semanticTreeContainsAll(
            retainedTree,
            semanticDirtySnapshot.leafUpdates.keys,
          );
      final treeBuildStopwatch = Stopwatch()..start();
      final semanticTree = canApplyRetainedLeafUpdates
          ? retainedTree.replaceNodes(semanticDirtySnapshot.leafUpdates)
          : SemanticTree.fromElement(currentRoot);
      if (canApplyRetainedLeafUpdates) {
        retainedLeafUpdates = semanticDirtySnapshot.leafUpdates;
      }
      treeBuildStopwatch.stop();
      treeBuildTime = treeBuildStopwatch.elapsed;
      assert(() {
        // The retained path must be indistinguishable from a full rebuild.
        // A divergence here means SemanticDirtyTracker failed to escalate a
        // structural change, which would silently corrupt the accessible
        // projection; fail loudly in debug builds instead.
        if (canApplyRetainedLeafUpdates) {
          final divergence = debugSemanticTreeDivergence(
            SemanticTree.fromElement(currentRoot),
            semanticTree,
          );
          if (divergence != null) {
            throw StateError(
              'Retained semantic leaf replacement diverged from a full '
              'semantic rebuild at $divergence',
            );
          }
        }
        return true;
      }());

      final SemanticTree presentedSemanticTree;
      if (_coverageFallback) {
        final coverageStopwatch = Stopwatch()..start();
        final coverage = applySemanticTextFallback(
          tree: semanticTree,
          buffer: buffer,
          dirtyRows: coverageRows,
          previousAudit: _lastCoverageAudit,
        );
        coverageStopwatch.stop();
        coverageTime = coverageStopwatch.elapsed;
        coverageAudit = coverage.audit;
        _lastCoverageAudit = coverage.audit;
        presentedSemanticTree = coverage.tree;
      } else {
        coverageAudit = SemanticCoverageAudit.empty;
        _lastCoverageAudit = SemanticCoverageAudit.empty;
        presentedSemanticTree = semanticTree;
      }

      _onTreePresented?.call(presentedSemanticTree);

      final diffStopwatch = Stopwatch()..start();
      final retainedUpdate =
          retainedLeafUpdates == null ||
              !identical(presentedSemanticTree, semanticTree)
          ? null
          : _owner.updateRetainedNodes(
              next: presentedSemanticTree,
              replacements: retainedLeafUpdates,
            );
      final semanticUpdate =
          retainedUpdate ?? _owner.update(presentedSemanticTree);
      diffStopwatch.stop();
      diffTime = diffStopwatch.elapsed;

      final presenterStopwatch = Stopwatch()..start();
      stats = _presenter.present(presentedSemanticTree, update: semanticUpdate);
      presenterStopwatch.stop();
      presenterTime = presenterStopwatch.elapsed;
      _semanticDirty = false;
    }
    totalFlushStopwatch.stop();
    _onFlushStats?.call(
      SemanticFlushStats(
        reason: reason,
        coalescedFrameCount: coalescedFrameCount,
        scheduleLatency: scheduleLatency,
        retainedOutput: retainedOutput,
        presentation: stats,
        coverageAudit: coverageAudit,
        treeBuildTime: treeBuildTime,
        coverageTime: coverageTime,
        diffTime: diffTime,
        presenterTime: presenterTime,
        totalFlushTime: totalFlushStopwatch.elapsed,
      ),
    );
    _completeIdleIfQuiet();
  }

  void dispose() {
    _disposed = true;
    // Clear the outstanding-flush flag BEFORE completing idle: disposing the
    // scheduler cancels the one callback that would have cleared it (the
    // deferred flush), and `_completeIdleIfQuiet` refuses to complete while
    // the flag is set. Without this, any awaitIdle() future outstanding at
    // dispose (which implies `_flushScheduled == true`) would hang forever,
    // contradicting the dispose-completes-pending contract hosts rely on.
    _flushScheduled = false;
    _scheduler.dispose();
    _completeIdleIfQuiet();
  }
}

/// True when every [ids] entry resolves to a node in [tree].
bool _semanticTreeContainsAll(SemanticTree tree, Iterable<SemanticNodeId> ids) {
  final nodesById = tree.nodesById;
  for (final id in ids) {
    if (!nodesById.containsKey(id)) return false;
  }
  return true;
}

/// True when every row [dirtyRows] marks is byte-identical between
/// [previous] and [next] — a conservative repaint with no visual change.
bool _dirtyRowsUnchanged(
  CellBuffer previous,
  CellBuffer next,
  TuiDirtyRows dirtyRows,
) {
  if (previous.size != next.size) return false;
  final cols = next.size.cols;
  for (final range in dirtyRows.ranges) {
    for (var row = range.startRow; row < range.endRow; row++) {
      for (var col = 0; col < cols; col++) {
        if (previous.atColRow(col, row) != next.atColRow(col, row)) {
          return false;
        }
      }
    }
  }
  return true;
}
