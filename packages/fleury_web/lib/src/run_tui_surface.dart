import 'dart:async';

import 'package:fleury/fleury_host.dart';

import 'browser_frame_flush_scheduler.dart';
import 'focus/web_focus_coordinator.dart';
import 'frame_presentation.dart';
import 'input/input_source.dart';
import 'instrumentation/web_host_instrumentation.dart';
import 'metrics/cell_metrics.dart';
import 'semantics/semantic_coverage.dart';
import 'semantics/semantic_presenter.dart';

/// Handle returned by [runTuiSurface].
final class TuiSurfaceHost {
  TuiSurfaceHost._({
    required TuiRuntime runtime,
    required FrameScheduler frameScheduler,
    required FrameSurface surface,
    CellMetrics? cellMetrics,
    TuiInputSource? inputSource,
    SemanticsOwner? semanticsOwner,
    SemanticFramePresenter? semanticPresenter,
    Clipboard? previousClipboard,
    FutureOr<void> Function()? disposeHostResources,
    required void Function() markDisposed,
  }) : _runtime = runtime,
       _frameScheduler = frameScheduler,
       _surface = surface,
       _cellMetrics = cellMetrics,
       _inputSource = inputSource,
       _semanticsOwner = semanticsOwner,
       _semanticPresenter = semanticPresenter,
       _previousClipboard = previousClipboard,
       _disposeHostResources = disposeHostResources,
       _markDisposed = markDisposed;

  final TuiRuntime _runtime;
  final FrameScheduler _frameScheduler;
  final FrameSurface _surface;
  final CellMetrics? _cellMetrics;
  final TuiInputSource? _inputSource;
  final SemanticsOwner? _semanticsOwner;
  final SemanticFramePresenter? _semanticPresenter;
  final Clipboard? _previousClipboard;
  final FutureOr<void> Function()? _disposeHostResources;
  final void Function() _markDisposed;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Requests a frame from host-owned browser code.
  void requestFrame([String reason = 'host']) {
    if (_disposed) return;
    _frameScheduler.requestFrame(reason);
  }

  /// Disposes the mounted Fleury tree and visual surface.
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposed = true;
    _markDisposed();
    return _disposeFuture = _dispose();
  }

  void _startFrameFailureCleanup() {
    if (_disposeFuture != null) return;
    _disposed = true;
    _markDisposed();
    _disposeFuture = _dispose().catchError((_) {
      // Preserve the frame failure as the visible error. Cleanup remains
      // awaitable by a later dispose() call, but cleanup failures are still
      // best-effort in this path.
    });
  }

  Future<void> _dispose() async {
    await _disposeHostResourcesBestEffort(
      inputSource: _inputSource,
      frameScheduler: _frameScheduler,
      cellMetrics: _cellMetrics,
      semanticsOwner: _semanticsOwner,
      semanticPresenter: _semanticPresenter,
      runtime: _runtime,
      surface: _surface,
      disposeHostResources: _disposeHostResources,
      previousClipboard: _previousClipboard,
    );
  }
}

/// Runs a Fleury widget tree against a visual [FrameSurface].
///
/// This host proves the framework can render real widgets into a retained web
/// surface without going through ANSI/xterm. Geometry may be supplied through
/// [cellMetrics], which is read only during the frame read phase. Browser input
/// may be supplied through [inputSource], which is queued by event handlers and
/// dispatched during the frame update phase. A web clipboard backend may be
/// installed through [clipboard] for the lifetime of the host. A semantic
/// presenter may be supplied through [semanticPresenter]; it receives a full
/// semantic snapshot after visual presentation for the same frame.
Future<TuiSurfaceHost> runTuiSurface(
  Widget Function() rootFactory, {
  required FrameSurface surface,
  CellMetrics? cellMetrics,
  TuiInputSource? inputSource,
  SemanticFramePresenter? semanticPresenter,
  Clipboard? clipboard,
  Duration frameInterval = Duration.zero,
  FrameFlushScheduler? flushScheduler,
  FramePresentationPlanner planner = const FramePresentationPlanner(),
  WebHostInstrumentation instrumentation = const NoopWebHostInstrumentation(),
  WebFocusCoordinator? focusCoordinator,
  FutureOr<void> Function()? disposeHostResources,
}) async {
  RenderDamageTracker.reset();
  SemanticDirtyTracker.reset();
  Clipboard? previousClipboard;
  if (clipboard != null) {
    previousClipboard = _tryReadClipboardInstance();
    Clipboard.instance = clipboard;
  }
  final runtime = TuiRuntime();
  final owner = runtime.owner;
  final focusManager = runtime.focusManager;
  final binding = runtime.binding;
  final pointerRouter = runtime.pointerRouter;
  final inputDispatcher = InputDispatcher(
    focusManager: focusManager,
    pointerRouter: pointerRouter,
  );
  final semanticsOwner = semanticPresenter == null ? null : SemanticsOwner();
  final pendingInput = <TuiEvent>[];
  final pendingSemanticActions = <_PendingSemanticAction>[];
  final frameLoop = TuiFrameLoop();
  Element.errorBuilder ??= (error, stack) => ErrorWidget.builder(error, stack);

  Element? root;
  var disposed = false;
  var semanticDirty = true;
  MeasuredCellBox? lastMetrics;
  var lastSemanticCoverageAudit = SemanticCoverageAudit.empty;
  var lastSize = surface.size;
  FrameScheduler? frameScheduler;
  TuiSurfaceHost? returnedHost;

  Future<void> cleanupSetupFailure() async {
    if (disposed) return;
    disposed = true;
    await _disposeHostResourcesBestEffort(
      inputSource: inputSource,
      frameScheduler: frameScheduler,
      cellMetrics: cellMetrics,
      semanticsOwner: semanticsOwner,
      semanticPresenter: semanticPresenter,
      runtime: runtime,
      surface: surface,
      disposeHostResources: disposeHostResources,
      previousClipboard: previousClipboard,
    );
  }

  void scheduleFrame([String reason = 'scheduled']) {
    final scheduler = frameScheduler;
    if (disposed || scheduler == null) return;
    scheduler.requestFrame(reason);
  }

  final rootEntry = OverlayEntry(
    builder: (_) => Navigator(home: rootFactory()),
  );

  Widget buildRoot() => TuiBindingScope(
    binding: binding,
    child: MediaQuery(
      data: MediaQueryData(
        size: surface.size,
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
      ),
      child: FocusManagerScope(
        manager: focusManager,
        child: PointerRouterScope(
          router: pointerRouter,
          child: Overlay(initialEntries: [rootEntry]),
        ),
      ),
    ),
  );

  void renderFrameBody(String reason) {
    final totalFrameStopwatch = Stopwatch()..start();
    if (disposed) {
      runtime.flushPostFrameCallbacks();
      return;
    }
    final mounted = root;
    if (mounted == null) return;

    var metricsReadCount = 0;
    final measured = cellMetrics?.measure();
    if (cellMetrics != null) metricsReadCount = 1;
    final metricsChanged = measured != null && measured != lastMetrics;
    if (metricsChanged) semanticDirty = true;
    if (measured != null) {
      lastMetrics = measured;
      surface.resize(measured.size, metrics: measured);
    }
    if (pendingInput.isNotEmpty) {
      semanticDirty = true;
      final input = List<TuiEvent>.of(pendingInput);
      pendingInput.clear();
      for (final event in input) {
        inputDispatcher.dispatch(event);
      }
    }
    SemanticNodeId? semanticActivationInFrame;
    if (pendingSemanticActions.isNotEmpty) {
      semanticDirty = true;
      final actions = List<_PendingSemanticAction>.of(pendingSemanticActions);
      pendingSemanticActions.clear();
      final semanticTree = semanticsOwner?.currentTree;
      if (semanticTree == null) {
        for (final request in actions) {
          scheduleFrame(
            'semantic-action:${request.action.name}:'
            '${SemanticActionInvocationStatus.notFound.name}',
          );
        }
      } else {
        for (final request in actions) {
          semanticActivationInFrame = request.id;
          focusCoordinator?.handleSemanticActivation(request.id);
          final keyboardCapture = inputSource is KeyboardCaptureTarget
              ? inputSource as KeyboardCaptureTarget
              : null;
          unawaited(
            invokeSemanticActionFromElement(
              root: mounted,
              tree: semanticTree,
              id: request.id,
              action: request.action,
            ).then((result) {
              if (disposed) return;
              if (focusCoordinator
                      ?.shouldRestoreKeyboardCaptureAfterSemanticActivation() ??
                  true) {
                if (keyboardCapture != null) {
                  try {
                    keyboardCapture.ensureKeyboardCapture();
                    focusCoordinator?.handleBrowserFocusIn(
                      WebFocusTarget.keyboardCapture,
                    );
                  } catch (_) {
                    // Browser focus restoration is best-effort; action status
                    // reporting and the follow-up frame must still be emitted.
                  }
                }
              }
              scheduleFrame(
                'semantic-action:${request.action.name}:${result.status.name}',
              );
            }),
          );
        }
      }
    }
    final currentSize = surface.size;
    if (currentSize.isEmpty) return;
    Element currentRoot = mounted;
    if (currentSize != lastSize) {
      lastSize = currentSize;
      semanticDirty = true;
      currentRoot = runtime.updateRoot(buildRoot());
      root = currentRoot;
      frameLoop.resetBuffers();
    }

    var runtimeBuildTime = Duration.zero;
    var runtimeLayoutTime = Duration.zero;
    var runtimePaintTime = Duration.zero;
    var runtimeBuildStats = BuildFlushStats.zero;
    final runtimeRenderStopwatch = Stopwatch()..start();
    final frame = frameLoop.render(
      size: currentSize,
      paint: (buffer) {
        runtime.renderFrame(
          buffer,
          onPhaseTiming: (build, layout, paint) {
            runtimeBuildTime = build;
            runtimeLayoutTime = layout;
            runtimePaintTime = paint;
          },
          onBuildStats: (stats) {
            runtimeBuildStats = stats;
          },
        );
      },
    );
    runtimeRenderStopwatch.stop();
    if (frame == null) return;
    final semanticDirtySnapshot = SemanticDirtyTracker.takeDirtySnapshot();
    final plan = planner.build(
      reason: reason,
      frame: frame,
      metricsChanged: metricsChanged,
    );

    final domApplyStopwatch = Stopwatch()..start();
    final surfaceStats = surface.present(frame.previous, frame.next, plan);
    domApplyStopwatch.stop();

    var semanticStats = SemanticPresentationStats.none;
    var semanticCoverageAudit = SemanticCoverageAudit.empty;
    var semanticTreeBuildTime = Duration.zero;
    var semanticCoverageTime = Duration.zero;
    var semanticDiffTime = Duration.zero;
    var semanticPresenterTime = Duration.zero;
    var semanticFocusSyncTime = Duration.zero;
    final semanticApplyStopwatch = Stopwatch()..start();
    if (semanticPresenter != null && semanticsOwner != null) {
      final retainedTree = semanticsOwner.currentTree;
      final visualCellsUnchanged = _dirtyRowsUnchanged(
        frame.previous,
        frame.next,
        plan.damage.dirtyRows,
      );
      final canRetainSemanticOutput =
          retainedTree != null &&
          !semanticDirty &&
          semanticDirtySnapshot.isClean &&
          !lastSemanticCoverageAudit.hasUncoveredText &&
          visualCellsUnchanged;
      if (canRetainSemanticOutput) {
        semanticCoverageAudit = lastSemanticCoverageAudit;
        semanticStats = SemanticPresentationStats.retained(
          nodeCount: retainedTree.nodeCount,
        );
      } else {
        Map<SemanticNodeId, SemanticNode>? retainedLeafUpdates;
        final canApplyRetainedLeafUpdates =
            retainedTree != null &&
            !semanticDirtySnapshot.requiresFullRebuild &&
            semanticDirtySnapshot.leafUpdates.isNotEmpty &&
            _semanticTreeContainsAll(
              retainedTree,
              semanticDirtySnapshot.leafUpdates.keys,
            );
        final semanticTreeBuildStopwatch = Stopwatch()..start();
        final semanticTree = canApplyRetainedLeafUpdates
            ? retainedTree.replaceNodes(semanticDirtySnapshot.leafUpdates)
            : SemanticTree.fromElement(currentRoot);
        if (canApplyRetainedLeafUpdates) {
          retainedLeafUpdates = semanticDirtySnapshot.leafUpdates;
        }
        semanticTreeBuildStopwatch.stop();
        semanticTreeBuildTime = semanticTreeBuildStopwatch.elapsed;

        final semanticCoverageStopwatch = Stopwatch()..start();
        final semanticCoverage = applySemanticTextFallback(
          tree: semanticTree,
          buffer: frame.next,
          dirtyRows: plan.damage.dirtyRows,
          previousAudit: lastSemanticCoverageAudit,
        );
        semanticCoverageStopwatch.stop();
        semanticCoverageTime = semanticCoverageStopwatch.elapsed;

        semanticCoverageAudit = semanticCoverage.audit;
        lastSemanticCoverageAudit = semanticCoverage.audit;
        final presentedSemanticTree = semanticCoverage.tree;
        final semanticFocusSyncStopwatch = Stopwatch()..start();
        focusCoordinator?.syncFromSemanticTree(
          presentedSemanticTree,
          activeCaretRect: focusManager.focusedNode?.caretRect,
        );
        semanticFocusSyncStopwatch.stop();
        semanticFocusSyncTime += semanticFocusSyncStopwatch.elapsed;

        final semanticDiffStopwatch = Stopwatch()..start();
        final retainedUpdate =
            retainedLeafUpdates == null ||
                !identical(presentedSemanticTree, semanticTree)
            ? null
            : semanticsOwner.updateRetainedNodes(
                next: presentedSemanticTree,
                replacements: retainedLeafUpdates,
              );
        final semanticUpdate =
            retainedUpdate ?? semanticsOwner.update(presentedSemanticTree);
        semanticDiffStopwatch.stop();
        semanticDiffTime = semanticDiffStopwatch.elapsed;

        final semanticPresenterStopwatch = Stopwatch()..start();
        semanticStats = semanticPresenter.present(
          presentedSemanticTree,
          update: semanticUpdate,
        );
        semanticPresenterStopwatch.stop();
        semanticPresenterTime = semanticPresenterStopwatch.elapsed;
        semanticDirty = false;
      }
    } else {
      final semanticFocusSyncStopwatch = Stopwatch()..start();
      focusCoordinator?.syncFromFleuryFocus(
        WebFocusSnapshot(
          activeSemanticNode: null,
          activeCaretRect: focusManager.focusedNode?.caretRect,
        ),
      );
      semanticFocusSyncStopwatch.stop();
      semanticFocusSyncTime += semanticFocusSyncStopwatch.elapsed;
    }
    if (semanticActivationInFrame != null) {
      final semanticFocusSyncStopwatch = Stopwatch()..start();
      focusCoordinator?.handleSemanticActivation(semanticActivationInFrame);
      semanticFocusSyncStopwatch.stop();
      semanticFocusSyncTime += semanticFocusSyncStopwatch.elapsed;
    }
    semanticApplyStopwatch.stop();
    inputSource?.syncCaretGeometry(
      focusManager.focusedNode?.caretRect,
      lastMetrics,
    );
    frameLoop.commit(frame);
    runtime.flushPostFrameCallbacks();
    totalFrameStopwatch.stop();
    instrumentation.recordFrame(
      WebFrameInstrumentation.fromPresentation(
        plan: plan,
        surfaceStats: surfaceStats,
        semanticStats: semanticStats,
        coverageAudit: semanticCoverageAudit,
        metricsReadCount: metricsReadCount,
        runtimeRenderTime: runtimeRenderStopwatch.elapsed,
        runtimeBuildStats: runtimeBuildStats,
        runtimeBufferPrepareTime: frame.bufferPrepareTime,
        runtimeBuildTime: runtimeBuildTime,
        runtimeLayoutTime: runtimeLayoutTime,
        runtimePaintTime: runtimePaintTime,
        dirtyRowDiffTime: plan.dirtyRowDiffTime,
        spanBuildTime: plan.spanBuildTime,
        domApplyTime: domApplyStopwatch.elapsed,
        semanticTreeBuildTime: semanticTreeBuildTime,
        semanticCoverageTime: semanticCoverageTime,
        semanticDiffTime: semanticDiffTime,
        semanticPresenterTime: semanticPresenterTime,
        semanticFocusSyncTime: semanticFocusSyncTime,
        semanticApplyTime: semanticApplyStopwatch.elapsed,
        totalFrameTime: totalFrameStopwatch.elapsed,
      ),
    );
  }

  void renderFrame(String reason) {
    try {
      renderFrameBody(reason);
    } catch (_) {
      final host = returnedHost;
      if (host == null) {
        unawaited(cleanupSetupFailure().catchError((_) {}));
      } else {
        host._startFrameFailureCleanup();
      }
      rethrow;
    }
  }

  try {
    final initialMetrics = cellMetrics?.measure();
    if (initialMetrics != null) {
      lastMetrics = initialMetrics;
      surface.resize(initialMetrics.size, metrics: initialMetrics);
    }
    lastSize = surface.size;

    final scheduler = FrameScheduler(
      clock: binding.tickerScheduler.clock,
      minFrameInterval: frameInterval,
      onRender: renderFrame,
      flushScheduler: flushScheduler ?? browserFrameFlushScheduler,
    );
    frameScheduler = scheduler;

    owner.onScheduleBuild = () {
      semanticDirty = true;
      scheduleFrame('build');
    };
    binding.onPostFrameCallback = () => scheduleFrame('post-frame');
    cellMetrics?.startObserving(() {
      semanticDirty = true;
      scheduleFrame('metrics');
    });
    inputSource?.start((event) {
      if (disposed) return;
      pendingInput.add(event);
      semanticDirty = true;
      scheduleFrame(_frameReasonForEvent(event));
    });
    if (semanticPresenter case SemanticActionRequestSink actionSink) {
      actionSink.onSemanticActionRequest = (id, action) {
        if (disposed) return;
        pendingSemanticActions.add(_PendingSemanticAction(id, action));
        semanticDirty = true;
        scheduleFrame('semantic-action-request:${action.name}');
      };
    }

    root = runtime.mountRoot(buildRoot());
    scheduleFrame('initial');

    final host = TuiSurfaceHost._(
      runtime: runtime,
      frameScheduler: scheduler,
      surface: surface,
      cellMetrics: cellMetrics,
      inputSource: inputSource,
      semanticsOwner: semanticsOwner,
      semanticPresenter: semanticPresenter,
      previousClipboard: previousClipboard,
      disposeHostResources: disposeHostResources,
      markDisposed: () {
        disposed = true;
      },
    );
    returnedHost = host;

    return host;
  } catch (_) {
    try {
      await cleanupSetupFailure();
    } catch (_) {
      // Preserve the setup failure as the primary error. Cleanup is best effort
      // and should not hide why host construction failed.
    }
    rethrow;
  }
}

Future<void> _disposeHostResourcesBestEffort({
  TuiInputSource? inputSource,
  FrameScheduler? frameScheduler,
  CellMetrics? cellMetrics,
  SemanticsOwner? semanticsOwner,
  SemanticFramePresenter? semanticPresenter,
  TuiRuntime? runtime,
  FrameSurface? surface,
  FutureOr<void> Function()? disposeHostResources,
  Clipboard? previousClipboard,
}) async {
  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> runStep(FutureOr<void> Function() step) async {
    try {
      await step();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  await runStep(() {
    inputSource?.dispose();
  });
  await runStep(() {
    frameScheduler?.dispose();
  });
  await runStep(() {
    cellMetrics?.dispose();
  });
  await runStep(() {
    semanticsOwner?.dispose();
  });
  await runStep(() {
    if (semanticPresenter case SemanticActionRequestSink actionSink) {
      actionSink.onSemanticActionRequest = null;
    }
  });
  await runStep(() => semanticPresenter?.dispose());
  await runStep(() {
    runtime?.dispose();
  });
  await runStep(() => surface?.dispose());
  await runStep(() => disposeHostResources?.call());
  await runStep(() {
    if (previousClipboard != null) Clipboard.instance = previousClipboard;
  });

  final error = firstError;
  final stackTrace = firstStackTrace;
  if (error != null && stackTrace != null) {
    Error.throwWithStackTrace(error, stackTrace);
  }
}

final class _PendingSemanticAction {
  const _PendingSemanticAction(this.id, this.action);

  final SemanticNodeId id;
  final SemanticAction action;
}

Clipboard? _tryReadClipboardInstance() {
  try {
    return Clipboard.instance;
  } catch (_) {
    return null;
  }
}

String _frameReasonForEvent(TuiEvent event) {
  return switch (event) {
    ResizeEvent() => 'resize',
    KeyEvent(:final keyCode, :final char) =>
      'key:${keyCode?.name ?? char ?? '?'}',
    TextInputEvent() => 'text-input',
    TextCompositionEvent(:final kind) => 'text-composition:${kind.name}',
    PasteEvent() => 'paste',
    MouseEvent() => 'mouse',
  };
}

bool _semanticTreeContainsAll(SemanticTree tree, Iterable<SemanticNodeId> ids) {
  final nodesById = tree.nodesById;
  for (final id in ids) {
    if (!nodesById.containsKey(id)) return false;
  }
  return true;
}

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
