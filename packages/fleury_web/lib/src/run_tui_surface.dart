import 'dart:async';
import 'dart:js_interop';

import 'package:fleury/fleury_host.dart';

import 'package:web/web.dart' as web;

import 'browser_frame_flush_scheduler.dart';
import 'clipboard/web_clipboard.dart';
import 'focus/web_focus_coordinator.dart';
import 'frame_presentation.dart';
import 'input/input_source.dart';
import 'instrumentation/web_host_instrumentation.dart';
import 'metrics/cell_metrics.dart';

/// Handle returned by [runTuiSurface].
final class MountedApp {
  MountedApp._({
    required TuiRuntime runtime,
    required FrameDriver frameDriver,
    required FrameSurface surface,
    CellMetrics? cellMetrics,
    TuiInputSource? inputSource,
    SemanticsOwner? semanticsOwner,
    SemanticFramePresenter? semanticPresenter,
    FrameSemanticsPipeline? semanticsPipeline,
    FutureOr<void> Function()? disposeHostResources,
    required void Function() markDisposed,
    SemanticFlushScheduler? semanticFlushScheduler,
    Future<void> Function()? awaitSemanticIdle,
  }) : _runtime = runtime,
       _frameDriver = frameDriver,
       _surface = surface,
       _cellMetrics = cellMetrics,
       _inputSource = inputSource,
       _semanticsOwner = semanticsOwner,
       _semanticPresenter = semanticPresenter,
       _semanticsPipeline = semanticsPipeline,
       _semanticFlushScheduler = semanticFlushScheduler,
       _awaitSemanticIdle = awaitSemanticIdle,
       _disposeHostResources = disposeHostResources,
       _markDisposed = markDisposed;

  /// A session driven by a [BrowserFrameSource] with no local runtime —
  /// the serve client: frames arrive over the wire, so there is no
  /// FrameDriver to request frames from and no runtime to dispose.
  MountedApp.forFrameSource({
    required FrameSurface surface,
    CellMetrics? cellMetrics,
    TuiInputSource? inputSource,
    SemanticFramePresenter? semanticPresenter,
    SemanticFlushScheduler? semanticFlushScheduler,
    FutureOr<void> Function()? disposeHostResources,
  }) : _runtime = null,
       _frameDriver = null,
       _surface = surface,
       _cellMetrics = cellMetrics,
       _inputSource = inputSource,
       _semanticsOwner = null,
       _semanticPresenter = semanticPresenter,
       _semanticsPipeline = null,
       _semanticFlushScheduler = semanticFlushScheduler,
       _awaitSemanticIdle = null,
       _disposeHostResources = disposeHostResources,
       _markDisposed = (() {});

  final TuiRuntime? _runtime;
  final FrameDriver? _frameDriver;
  final FrameSurface _surface;
  final CellMetrics? _cellMetrics;
  final TuiInputSource? _inputSource;
  final SemanticsOwner? _semanticsOwner;
  final SemanticFramePresenter? _semanticPresenter;
  final FrameSemanticsPipeline? _semanticsPipeline;
  final SemanticFlushScheduler? _semanticFlushScheduler;
  final Future<void> Function()? _awaitSemanticIdle;
  final FutureOr<void> Function()? _disposeHostResources;
  final void Function() _markDisposed;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Requests a frame from host-owned browser code.
  void requestFrame([String reason = 'host']) {
    if (_disposed) return;
    // Wire-driven sessions have no local frame program; the server owns
    // frame production.
    _frameDriver?.requestFrame(reason);
  }

  /// Completes when no deferred semantic flush is outstanding.
  ///
  /// Semantic presentation runs off the visual frame; harnesses that need
  /// "frame AND its semantics are on the page" await this after their frame
  /// signal.
  Future<void> awaitSemanticIdle() {
    final awaiter = _awaitSemanticIdle;
    if (_disposed || awaiter == null) return Future.value();
    return awaiter();
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
      frameDriver: _frameDriver,
      cellMetrics: _cellMetrics,
      semanticsPipeline: _semanticsPipeline,
      semanticFlushScheduler: _semanticFlushScheduler,
      semanticsOwner: _semanticsOwner,
      semanticPresenter: _semanticPresenter,
      runtime: _runtime,
      surface: _surface,
      disposeHostResources: _disposeHostResources,
    );
  }
}

/// Runs a Fleury widget tree against a visual [FrameSurface].
///
/// This host proves the framework can render real widgets into a retained web
/// surface without going through ANSI or a terminal emulator. Geometry may be
/// supplied through
/// [cellMetrics], which is read only during the frame read phase. Browser input
/// may be supplied through [inputSource], which is queued by event handlers and
/// dispatched during the frame update phase. A web clipboard backend may be
/// installed through [clipboard] for the lifetime of the host. A semantic
/// presenter may be supplied through [semanticPresenter]; it receives a full
/// semantic snapshot after visual presentation for the same frame.
Future<MountedApp> runTuiSurface(
  Widget Function() rootFactory, {
  required FrameSurface surface,
  CellMetrics? cellMetrics,
  TuiInputSource? inputSource,
  SemanticFramePresenter? semanticPresenter,
  SemanticFlushScheduler? semanticFlushScheduler,
  Clipboard? clipboard,
  Duration frameInterval = Duration.zero,
  FrameFlushScheduler? flushScheduler,
  FramePresentationPlanner planner = const FramePresentationPlanner(),
  WebHostInstrumentation instrumentation = const NoopWebHostInstrumentation(),
  WebFocusCoordinator? focusCoordinator,
  FutureOr<void> Function()? disposeHostResources,
}) async {
  // The clipboard is a host service shared via ClipboardScope in
  // buildRoot — no process-global mutation, no restore-on-dispose dance.
  final effectiveClipboard = clipboard ?? WebClipboard();
  final runtime = TuiRuntime();
  // Contained layout/paint failures surface in the console (the boundary
  // renders the in-place presentation; without this they'd be silent).
  runtime.owner.onContainedRenderError = (contained) => web.console.error(
    'fleury: contained render failure (${contained.phase.name}): '
            '${contained.error}\n${contained.stack}'
        .toJS,
  );
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
  final frameLoop = TuiFrameLoop(renderDamage: runtime.renderDamageTracker);
  final semanticScheduler = semanticPresenter == null
      ? null
      : (semanticFlushScheduler ?? TimerSemanticFlushScheduler());
  var disposed = false;
  SemanticNodeId? semanticActivationForFlush;
  MeasuredCellBox? lastMetrics;
  FrameDriver? frameDriver;
  MountedApp? returnedHost;
  // The shared semantics engine (deferred flush, retained-leaf updates,
  // coverage fallback); host-specific focus sync + instrumentation ride
  // its callbacks. Assigned right after the host closures it needs exist.
  FrameSemanticsPipeline? semanticsPipeline;
  var semanticFocusSyncTimeForFlush = Duration.zero;

  Future<void> cleanupSetupFailure() async {
    if (disposed) return;
    disposed = true;
    await _disposeHostResourcesBestEffort(
      inputSource: inputSource,
      frameDriver: frameDriver,
      cellMetrics: cellMetrics,
      semanticsPipeline: semanticsPipeline,
      semanticFlushScheduler: semanticScheduler,
      semanticsOwner: semanticsOwner,
      semanticPresenter: semanticPresenter,
      runtime: runtime,
      surface: surface,
      disposeHostResources: disposeHostResources,
    );
  }

  void scheduleFrame([String reason = 'scheduled']) {
    if (disposed) return;
    frameDriver?.requestFrame(reason);
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
          child: ClipboardScope(
            clipboard: effectiveClipboard,
            child: Overlay(initialEntries: [rootEntry]),
          ),
        ),
      ),
    ),
  );

  if (semanticPresenter != null) {
    semanticsPipeline = FrameSemanticsPipeline(
      presenter: semanticPresenter,
      dirtyTracker: runtime.semanticDirtyTracker,
      readRoot: () => frameDriver?.rootElement,
      owner: semanticsOwner,
      flushScheduler: semanticScheduler,
      onTreePresented: (tree) {
        // Host-side per-flush work: browser focus projection, and restoring
        // an AT activation performed since the last flush without
        // disturbing later browser focus ownership.
        final focusSyncStopwatch = Stopwatch()..start();
        focusCoordinator?.syncFromSemanticTree(
          tree,
          activeCaretRect: focusManager.focusedNode?.caretRect,
        );
        final activation = semanticActivationForFlush;
        if (activation != null) {
          semanticActivationForFlush = null;
          focusCoordinator?.restoreSemanticActivationNode(activation);
        }
        focusSyncStopwatch.stop();
        semanticFocusSyncTimeForFlush = focusSyncStopwatch.elapsed;
      },
      onFlushStats: (stats) {
        instrumentation.recordSemanticFlush(
          WebSemanticFlushInstrumentation(
            reason: stats.reason,
            coalescedFrameCount: stats.coalescedFrameCount,
            scheduleLatency: stats.scheduleLatency,
            retainedOutput: stats.retainedOutput,
            semanticNodeCount: stats.presentation.nodeCount,
            semanticAddedNodeCount: stats.presentation.addedNodeCount,
            semanticRemovedNodeCount: stats.presentation.removedNodeCount,
            semanticUpdatedNodeCount: stats.presentation.updatedNodeCount,
            semanticDomCreatedElementCount:
                stats.presentation.createdElementCount,
            semanticDomReusedElementCount:
                stats.presentation.reusedElementCount,
            semanticDomReplacedElementCount:
                stats.presentation.replacedElementCount,
            semanticFallbackNodeCount: stats.coverageAudit.fallbackNodeCount,
            semanticUncoveredCellCount: stats.coverageAudit.uncoveredCellCount,
            semanticTreeBuildTime: stats.treeBuildTime,
            semanticCoverageTime: stats.coverageTime,
            semanticDiffTime: stats.diffTime,
            semanticPresenterTime: stats.presenterTime,
            semanticFocusSyncTime: semanticFocusSyncTimeForFlush,
            totalFlushTime: stats.totalFlushTime,
          ),
        );
        semanticFocusSyncTimeForFlush = Duration.zero;
      },
      onFlushError: (error, stack) {
        final host = returnedHost;
        if (host == null) {
          unawaited(cleanupSetupFailure().catchError((_) {}));
        } else {
          host._startFrameFailureCleanup();
        }
      },
    );
  }

  // Per-frame state shared between the driver hooks and the presenter.
  var metricsReadCountThisFrame = 0;
  SemanticNodeId? semanticActivationInFrame;

  FrameViewportSnapshot readViewport() {
    if (disposed) {
      return FrameViewportSnapshot(surface.size);
    }
    metricsReadCountThisFrame = cellMetrics != null ? 1 : 0;
    final measured = cellMetrics?.measure();
    final metricsChanged = measured != null && measured != lastMetrics;
    if (metricsChanged) semanticsPipeline?.markSemanticsDirty();
    if (measured != null) {
      lastMetrics = measured;
      surface.resize(measured.size, metrics: measured);
    }
    return FrameViewportSnapshot(surface.size, metricsChanged: metricsChanged);
  }

  void dispatchPendingWork(String reason) {
    if (disposed) return;
    final mounted = frameDriver?.rootElement;
    if (mounted == null) return;
    if (pendingInput.isNotEmpty) {
      semanticsPipeline?.markSemanticsDirty();
      final input = List<TuiEvent>.of(pendingInput);
      pendingInput.clear();
      for (final event in input) {
        inputDispatcher.dispatch(event);
      }
    }
    if (pendingSemanticActions.isNotEmpty) {
      semanticsPipeline?.markSemanticsDirty();
      final actions = List<_PendingSemanticAction>.of(pendingSemanticActions);
      pendingSemanticActions.clear();
      // Force-flush so the displayed tree reflects the action's target, not a
      // stale retained snapshot.
      semanticsPipeline?.flushPendingNow('semantic-action');
      // A semantic frame must have been presented (so the AT/agent had ids to
      // hold) before an action can resolve; if none has yet, it's notFound.
      if (semanticsOwner?.currentTree == null) {
        for (final request in actions) {
          scheduleFrame(
            'semantic-action:${request.action.name}:'
            '${SemanticActionInvocationStatus.notFound.name}',
          );
        }
      } else {
        // Dispatch resolves against a FRESH fromElement tree from the live
        // mounted root — NOT `currentTree`, which can be a const-constructed
        // coverage-fallback or retained-leaf tree with a null element map
        // (elementById → null → the action silently no-ops). Actionable ids are
        // always real element nodes (text fallbacks carry no actions), so this
        // resolves the same ids the AT saw, with a live element map.
        final semanticTree = SemanticTree.fromElement(mounted);
        for (final request in actions) {
          semanticActivationInFrame = request.id;
          semanticActivationForFlush = request.id;
          focusCoordinator?.handleSemanticActivation(request.id);
          final keyboardCapture = inputSource is KeyboardCaptureTarget
              ? inputSource as KeyboardCaptureTarget
              : null;
          unawaited(
            invokeSemanticActionFromElement(
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
  }

  try {
    final initialMetrics = cellMetrics?.measure();
    if (initialMetrics != null) {
      lastMetrics = initialMetrics;
      surface.resize(initialMetrics.size, metrics: initialMetrics);
    }

    final driver = frameDriver = FrameDriver(
      runtime: runtime,
      frameLoop: frameLoop,
      readViewport: readViewport,
      presenter: _SurfaceFramePresenter(
        surface: surface,
        inputSource: inputSource,
        focusCoordinator: focusCoordinator,
        focusManager: focusManager,
        instrumentation: instrumentation,
        hasSemanticPresenter: semanticPresenter != null,
        readSemanticsOwner: () => semanticsOwner,
        readPipeline: () => semanticsPipeline,
        readLastMetrics: () => lastMetrics,
        takeActivation: () {
          final activation = semanticActivationInFrame;
          semanticActivationInFrame = null;
          return activation;
        },
        takeMetricsReadCount: () {
          final count = metricsReadCountThisFrame;
          metricsReadCountThisFrame = 0;
          return count;
        },
      ),
      planner: planner,
      onBeforeFrame: dispatchPendingWork,
      onFramePresented: (frame, plan) =>
          semanticsPipeline?.onFramePresented(frame, plan),
      onFrameSkipped: (reason, size) {
        semanticsPipeline?.onFrameSkippedWithPendingWork();
        instrumentation.recordFrame(
          WebFrameInstrumentation.skipped(
            reason: reason,
            viewportSize: size,
            semanticNodeCount: semanticsOwner?.currentTree?.nodeCount ?? 0,
            semanticFallbackNodeCount:
                (semanticsPipeline?.lastCoverageAudit ??
                        SemanticCoverageAudit.empty)
                    .fallbackNodeCount,
            semanticUncoveredCellCount:
                (semanticsPipeline?.lastCoverageAudit ??
                        SemanticCoverageAudit.empty)
                    .uncoveredCellCount,
            totalFrameTime: Duration.zero,
          ),
        );
      },
      // Backstop errors keep the session (the driver substitutes a
      // full-screen error frame); surface them in the console so they
      // don't vanish.
      onBackstopError: (error, stack) => web.console.error(
        'fleury: render crashed outside all error boundaries: '
                '$error\n$stack'
            .toJS,
      ),
      // Only unrecoverable failures escape the driver now (backstop
      // storm): tear the host down.
      onFrameError: (error, stack) {
        final host = returnedHost;
        if (host == null) {
          unawaited(cleanupSetupFailure().catchError((_) {}));
        } else {
          host._startFrameFailureCleanup();
        }
      },
      frameInterval: frameInterval,
      flushScheduler: flushScheduler ?? browserFrameFlushScheduler,
    );

    owner.onScheduleBuild = () {
      semanticsPipeline?.markSemanticsDirty();
      scheduleFrame('build');
    };
    binding.onPostFrameCallback = () => scheduleFrame('post-frame');
    cellMetrics?.startObserving(() {
      semanticsPipeline?.markSemanticsDirty();
      scheduleFrame('metrics');
    });
    inputSource?.start((event) {
      if (disposed) return;
      pendingInput.add(event);
      semanticsPipeline?.markSemanticsDirty();
      scheduleFrame(_frameReasonForEvent(event));
    });
    if (semanticPresenter case SemanticActionRequestSink actionSink) {
      actionSink.onSemanticActionRequest = (id, action) {
        if (disposed) return;
        pendingSemanticActions.add(_PendingSemanticAction(id, action));
        semanticsPipeline?.markSemanticsDirty();
        scheduleFrame('semantic-action-request:${action.name}');
      };
    }

    driver.mountRoot(buildRoot);
    scheduleFrame('initial');

    final host = MountedApp._(
      runtime: runtime,
      frameDriver: driver,
      surface: surface,
      cellMetrics: cellMetrics,
      inputSource: inputSource,
      semanticsOwner: semanticsOwner,
      semanticPresenter: semanticPresenter,
      semanticsPipeline: semanticsPipeline,
      semanticFlushScheduler: semanticScheduler,
      awaitSemanticIdle: () =>
          semanticsPipeline?.awaitIdle() ?? Future<void>.value(),
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

/// Whether every cell in [dirtyRows] is identical between the two buffers.
///

Future<void> _disposeHostResourcesBestEffort({
  TuiInputSource? inputSource,
  FrameDriver? frameDriver,
  CellMetrics? cellMetrics,
  FrameSemanticsPipeline? semanticsPipeline,
  SemanticFlushScheduler? semanticFlushScheduler,
  SemanticsOwner? semanticsOwner,
  SemanticFramePresenter? semanticPresenter,
  TuiRuntime? runtime,
  FrameSurface? surface,
  FutureOr<void> Function()? disposeHostResources,
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
    frameDriver?.dispose();
  });
  await runStep(() {
    cellMetrics?.dispose();
  });
  await runStep(() {
    // Also completes any outstanding awaitIdle() so a disposed host can't
    // leave a test (or caller) hanging on a cancelled flush.
    semanticsPipeline?.dispose();
  });
  await runStep(() {
    semanticFlushScheduler?.dispose();
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
  await runStep(() {});

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

/// The embed host's write phase: paints the frame into the retained DOM
/// surface, projects focus, syncs the IME caret, and records per-frame
/// instrumentation after commit.
final class _SurfaceFramePresenter implements FramePresenter {
  _SurfaceFramePresenter({
    required this.surface,
    required this.inputSource,
    required this.focusCoordinator,
    required this.focusManager,
    required this.instrumentation,
    required this.hasSemanticPresenter,
    required this.readSemanticsOwner,
    required this.readPipeline,
    required this.readLastMetrics,
    required this.takeActivation,
    required this.takeMetricsReadCount,
  });

  final FrameSurface surface;
  final TuiInputSource? inputSource;
  final WebFocusCoordinator? focusCoordinator;
  final FocusManager focusManager;
  final WebHostInstrumentation instrumentation;
  final bool hasSemanticPresenter;
  final SemanticsOwner? Function() readSemanticsOwner;
  final FrameSemanticsPipeline? Function() readPipeline;
  final MeasuredCellBox? Function() readLastMetrics;
  final SemanticNodeId? Function() takeActivation;
  final int Function() takeMetricsReadCount;

  FrameSurfacePresentationStats? _surfaceStats;
  Duration _domApplyTime = Duration.zero;
  Duration _semanticApplyTime = Duration.zero;
  Duration _semanticFocusSyncTime = Duration.zero;

  @override
  bool get wantsPresentationPlan => true;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {
    final plan = info.plan!;
    final domApplyStopwatch = Stopwatch()..start();
    _surfaceStats = surface.present(frame.previous, frame.next, plan);
    domApplyStopwatch.stop();
    _domApplyTime = domApplyStopwatch.elapsed;

    final semanticApplyStopwatch = Stopwatch()..start();
    var semanticFocusSyncTime = Duration.zero;
    if (!hasSemanticPresenter) {
      final focusSyncStopwatch = Stopwatch()..start();
      focusCoordinator?.syncFromFleuryFocus(
        WebFocusSnapshot(
          activeSemanticNode: null,
          activeCaretRect: focusManager.focusedNode?.caretRect,
        ),
      );
      focusSyncStopwatch.stop();
      semanticFocusSyncTime += focusSyncStopwatch.elapsed;
    }
    final activation = takeActivation();
    if (activation != null) {
      final focusSyncStopwatch = Stopwatch()..start();
      focusCoordinator?.handleSemanticActivation(activation);
      focusSyncStopwatch.stop();
      semanticFocusSyncTime += focusSyncStopwatch.elapsed;
    }
    semanticApplyStopwatch.stop();
    _semanticApplyTime = semanticApplyStopwatch.elapsed;
    _semanticFocusSyncTime = semanticFocusSyncTime;
    inputSource?.syncCaretGeometry(
      focusManager.focusedNode?.caretRect,
      readLastMetrics(),
    );
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {
    final semanticsOwner = readSemanticsOwner();
    final pipeline = readPipeline();
    instrumentation.recordFrame(
      WebFrameInstrumentation.fromPresentation(
        plan: info.plan!,
        surfaceStats: _surfaceStats!,
        semanticStats: semanticsOwner?.currentTree == null
            ? SemanticPresentationStats.none
            : SemanticPresentationStats.retained(
                nodeCount: semanticsOwner!.currentTree!.nodeCount,
              ),
        coverageAudit:
            pipeline?.lastCoverageAudit ?? SemanticCoverageAudit.empty,
        metricsReadCount: takeMetricsReadCount(),
        runtimeRenderTime: info.renderTime,
        runtimeBuildStats: info.buildStats,
        runtimeBufferPrepareTime: frame.bufferPrepareTime,
        runtimeBuildTime: info.phaseBuild,
        runtimeLayoutTime: info.phaseLayout,
        runtimePaintTime: info.phasePaint,
        dirtyRowDiffTime: info.plan!.dirtyRowDiffTime,
        spanBuildTime: info.plan!.spanBuildTime,
        domApplyTime: _domApplyTime,
        semanticFocusSyncTime: _semanticFocusSyncTime,
        semanticApplyTime: _semanticApplyTime,
        totalFrameTime: info.renderTime + _domApplyTime + _semanticApplyTime,
      ),
    );
  }
}
