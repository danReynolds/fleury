import 'dart:async';

import 'package:fleury/fleury_host.dart';

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
    required FrameScheduler frameScheduler,
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
       _frameScheduler = frameScheduler,
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

  final TuiRuntime _runtime;
  final FrameScheduler _frameScheduler;
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
    _frameScheduler.requestFrame(reason);
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
      frameScheduler: _frameScheduler,
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
  Element? root;
  var disposed = false;
  SemanticNodeId? semanticActivationForFlush;
  MeasuredCellBox? lastMetrics;
  var lastSize = surface.size;
  FrameScheduler? frameScheduler;
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
      frameScheduler: frameScheduler,
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
      readRoot: () => root,
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
    if (metricsChanged) semanticsPipeline?.markSemanticsDirty();
    if (measured != null) {
      lastMetrics = measured;
      surface.resize(measured.size, metrics: measured);
    }
    if (pendingInput.isNotEmpty) {
      semanticsPipeline?.markSemanticsDirty();
      final input = List<TuiEvent>.of(pendingInput);
      pendingInput.clear();
      for (final event in input) {
        inputDispatcher.dispatch(event);
      }
    }
    SemanticNodeId? semanticActivationInFrame;
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
    final currentSize = surface.size;
    if (currentSize.isEmpty) return;
    Element currentRoot = mounted;
    if (currentSize != lastSize) {
      lastSize = currentSize;
      semanticsPipeline?.markSemanticsDirty();
      currentRoot = runtime.updateRoot(buildRoot());
      root = currentRoot;
      frameLoop.resetBuffers();
    }

    if (!metricsChanged &&
        !frameLoop.needsRender(currentSize) &&
        !runtime.hasFrameWork) {
      // No-change frame: nothing rebuilt, nothing invalidated, buffers warm.
      // Skip build/layout/paint/present entirely — the committed frame is
      // still exact. Semantic work may still be owed (e.g. dispatched input
      // that changed no visuals keeps the conservative rebuild contract).
      semanticsPipeline?.onFrameSkippedWithPendingWork();
      runtime.flushPostFrameCallbacks();
      totalFrameStopwatch.stop();
      instrumentation.recordFrame(
        WebFrameInstrumentation.skipped(
          reason: reason,
          viewportSize: currentSize,
          semanticNodeCount: semanticsOwner?.currentTree?.nodeCount ?? 0,
          semanticFallbackNodeCount:
              (semanticsPipeline?.lastCoverageAudit ??
                      SemanticCoverageAudit.empty)
                  .fallbackNodeCount,
          semanticUncoveredCellCount:
              (semanticsPipeline?.lastCoverageAudit ??
                      SemanticCoverageAudit.empty)
                  .uncoveredCellCount,
          totalFrameTime: totalFrameStopwatch.elapsed,
        ),
      );
      return;
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
    final plan = planner.build(
      reason: reason,
      frame: frame,
      metricsChanged: metricsChanged,
    );

    final domApplyStopwatch = Stopwatch()..start();
    final surfaceStats = surface.present(frame.previous, frame.next, plan);
    domApplyStopwatch.stop();

    final semanticApplyStopwatch = Stopwatch()..start();
    var semanticFocusSyncTime = Duration.zero;
    if (semanticPresenter == null) {
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
    semanticsPipeline?.onFramePresented(frame, plan);
    runtime.flushPostFrameCallbacks();
    totalFrameStopwatch.stop();
    instrumentation.recordFrame(
      WebFrameInstrumentation.fromPresentation(
        plan: plan,
        surfaceStats: surfaceStats,
        semanticStats: semanticsOwner?.currentTree == null
            ? SemanticPresentationStats.none
            : SemanticPresentationStats.retained(
                nodeCount: semanticsOwner!.currentTree!.nodeCount,
              ),
        coverageAudit:
            semanticsPipeline?.lastCoverageAudit ?? SemanticCoverageAudit.empty,
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

    root = runtime.mountRoot(buildRoot());
    scheduleFrame('initial');

    final host = MountedApp._(
      runtime: runtime,
      frameScheduler: scheduler,
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
  FrameScheduler? frameScheduler,
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
    frameScheduler?.dispose();
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
