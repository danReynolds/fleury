// FrameDriver: the frame program, extracted from runApp's render closure
// so every host runs the SAME choreography instead of hand-mirroring it.
//
// The phase order is fixed and not overridable:
//
//   skip gate (no work → drain post-frame callbacks, write nothing)
//   → render (clear-without-damage → build → layout → paint;
//     damage taken exactly once by TuiFrameLoop)
//   → plan (only when the presenter wants one)
//   → present (exactly once, BEFORE commit)
//   → semantics hook (ship the tree while the dirty tracker still has
//     this frame's dirt)
//   → commit (the presented frame becomes the diff base)
//   → observer (debug/instrumentation, after commit)
//   → post-frame callbacks (geometry now matches what the user sees).
//
// Hosts supply strategy objects (presenter, semantics hook, observer) and
// call [requestFrame]; the driver owns the scheduler, the frame loop, and
// the ordering invariants. The choreography test
// (frame_driver_choreography_test) and the ANSI byte golden pin the
// contract.

import '../foundation/geometry.dart';
import '../rendering/error_presentation.dart';
import '../rendering/render_layout_stats.dart';
import '../rendering/render_repaint_boundary.dart';
import '../widgets/framework.dart';
import 'frame_presentation.dart';
import 'frame_scheduler.dart';
import 'tui_frame_loop.dart';
import 'tui_runtime.dart';

/// Read phase: the host's viewport, sampled once at the top of every
/// frame. The ONLY phase permitted to perform host layout reads (DOM
/// measurement, terminal size ioctls).
final class FrameViewportSnapshot {
  const FrameViewportSnapshot(this.size, {this.metricsChanged = false});

  final CellSize size;

  /// Host cell geometry changed (font/DPR/zoom) without necessarily
  /// changing the cell count — forces a render (and a full-fidelity plan)
  /// even when the runtime reports no frame work.
  final bool metricsChanged;
}

/// Write phase: turns one rendered frame into host output (ANSI bytes,
/// wire frames, DOM mutations). Called exactly once per rendered frame,
/// after damage capture and BEFORE commit.
abstract interface class FramePresenter {
  /// Whether the driver should build a [FramePresentationPlan] for this
  /// presenter. False for the ANSI path, which diffs internally from
  /// [TuiRenderedFrame.damage] and must not pay for span-model
  /// construction — [FramePresentInfo.plan] is null then.
  bool get wantsPresentationPlan;

  /// Presents one rendered frame.
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info);

  /// Called after the presented frame was committed — the point where
  /// debug/telemetry emission belongs (the frame is now the diff base).
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {}
}

/// Per-frame context handed to the presenter: the trigger, the plan (when
/// requested), and debug-phase timings (zero durations when no debug
/// consumer is watching).
final class FramePresentInfo {
  const FramePresentInfo({
    required this.reason,
    required this.plan,
    required this.debugWatching,
    required this.layoutStats,
    required this.repaintBoundaryStats,
    this.phaseBuild = Duration.zero,
    this.phaseLayout = Duration.zero,
    this.phasePaint = Duration.zero,
    this.renderTime = Duration.zero,
    this.buildStats = BuildFlushStats.zero,
  });

  final String reason;
  final FramePresentationPlan? plan;

  /// Debug frame stats captured across build/layout/paint (empty when not
  /// watching). Consumed by the ANSI presenter's frame telemetry.
  final RenderLayoutFrameStats layoutStats;
  final RepaintBoundaryFrameStats repaintBoundaryStats;

  /// True when a debug consumer is subscribed this frame; presenters use
  /// it to gate their own capture work.
  final bool debugWatching;

  final Duration phaseBuild;
  final Duration phaseLayout;
  final Duration phasePaint;

  /// Wall time of the whole render call (build+layout+paint+bookkeeping).
  final Duration renderTime;
  final BuildFlushStats buildStats;
}

/// The frame program for one Fleury runtime.
final class FrameDriver {
  FrameDriver({
    required this.runtime,
    required TuiFrameLoop frameLoop,
    required FrameViewportSnapshot Function() readViewport,
    required FramePresenter presenter,
    FramePresentationPlanner planner = const FramePresentationPlanner(),
    void Function(String reason)? onBeforeFrame,
    void Function(TuiRenderedFrame frame, FramePresentationPlan? plan)?
    onFramePresented,
    void Function(String reason, CellSize size)? onFrameSkipped,
    void Function(Object error, StackTrace stack)? onBackstopError,
    void Function(Object error, StackTrace stack)? onFrameError,
    this.backstopStormLimit = 8,
    bool Function()? isDebugWatching,
    void Function(Duration build, Duration layout, Duration paint)?
    onPhaseTiming,
    void Function(String marker)? markOnce,
    Duration frameInterval = Duration.zero,
    FrameFlushScheduler? flushScheduler,
  }) : _frameLoop = frameLoop,
       _readViewport = readViewport,
       _presenter = presenter,
       _planner = planner,
       _onBeforeFrame = onBeforeFrame,
       _onFramePresented = onFramePresented,
       _onFrameSkipped = onFrameSkipped,
       _onBackstopError = onBackstopError,
       _onFrameError = onFrameError,
       _isDebugWatching = isDebugWatching,
       _onPhaseTiming = onPhaseTiming,
       _markOnce = markOnce {
    _scheduler = FrameScheduler(
      clock: runtime.binding.tickerScheduler.clock,
      minFrameInterval: frameInterval,
      flushScheduler: flushScheduler,
      onRender: renderNow,
    );
    runtime.owner.onScheduleBuild = () => requestFrame('build');
    // Pump the next frame whenever a post-frame callback is enqueued — a
    // Timer.run that adds one while the app is idle would otherwise queue
    // indefinitely (no setState, no event).
    runtime.binding.onPostFrameCallback = () => requestFrame('post-frame');
  }

  final TuiRuntime runtime;
  final TuiFrameLoop _frameLoop;
  final FrameViewportSnapshot Function() _readViewport;
  final FramePresenter _presenter;
  final FramePresentationPlanner _planner;
  final void Function(String reason)? _onBeforeFrame;
  final void Function(TuiRenderedFrame, FramePresentationPlan?)?
  _onFramePresented;
  final void Function(String reason, CellSize size)? _onFrameSkipped;
  final void Function(Object, StackTrace)? _onBackstopError;
  final void Function(Object, StackTrace)? _onFrameError;

  /// Consecutive backstop frames before the driver declares the session
  /// unrecoverable (an every-frame hard crash outside all boundaries).
  final int backstopStormLimit;
  final bool Function()? _isDebugWatching;
  final void Function(Duration, Duration, Duration)? _onPhaseTiming;
  final void Function(String marker)? _markOnce;
  late final FrameScheduler _scheduler;

  Element? _rootElement;
  Widget Function()? _rootBuilder;
  CellSize? _lastSize;
  var _disposed = false;
  var _inFrameRender = false;
  var _consecutiveBackstopFrames = 0;
  var _renderUnrecoverable = false;

  /// True only while the synchronous render pipeline (build/layout/paint)
  /// runs. Hosts' zone guards read it to classify a throw as a render
  /// crash versus a survivable event-handler/async error.
  bool get inFrameRender => _inFrameRender;

  /// True once the backstop storm limit tripped: the session cannot
  /// render. Hosts' fatal-error criteria read it.
  bool get renderUnrecoverable => _renderUnrecoverable;

  /// The mounted root element, or null before [mountRoot].
  Element? get rootElement => _rootElement;

  /// Mounts the root. [rootBuilder] is re-invoked (and the root updated in
  /// place) on [handleResize], exactly like the hosts' `buildRoot()`
  /// closures — the driver installs nothing inside the widget tree; hosts
  /// own their scope stack.
  Element mountRoot(Widget Function() rootBuilder) {
    _rootBuilder = rootBuilder;
    return _rootElement = runtime.mountRoot(rootBuilder());
  }

  /// Resets the diff base and rebuilds the root against the new viewport.
  /// The next rendered frame is a full repaint at the new size.
  void handleResize() {
    if (_disposed) return;
    _frameLoop.resetBuffers();
    final builder = _rootBuilder;
    if (_rootElement != null && builder != null) {
      _rootElement = runtime.updateRoot(builder());
    }
  }

  /// Coalesced frame request.
  void requestFrame([String reason = 'scheduled']) {
    if (_disposed) return;
    _scheduler.requestFrame(reason);
  }

  /// Runs the frame program now — the scheduler's callback. Hosts call
  /// [requestFrame]; tests may call this directly for determinism.
  void renderNow(String reason) {
    if (_disposed) {
      // Late frame after cleanup started: drain any callbacks that arrived
      // between dispose and the scheduled flush so their side effects (a
      // final log line, releasing a captured resource) aren't dropped.
      runtime.flushPostFrameCallbacks();
      return;
    }
    try {
      _renderNowBody(reason);
    } catch (error, stack) {
      // Only genuinely unrecoverable failures escape the program now (the
      // backstop absorbs render throws): the host gets first look — the
      // browser host starts teardown — and the error still propagates to
      // the guarded zone / scheduler task.
      _onFrameError?.call(error, stack);
      rethrow;
    }
  }

  void _renderNowBody(String reason) {
    if (_rootElement == null) return;
    final snapshot = _readViewport();
    final size = snapshot.size;
    if (size.isEmpty) return;
    // Host frame-entry work (the browser host dispatches queued input and
    // semantic actions here) runs after the viewport read, before the
    // resize check — the order the embed host always had.
    _onBeforeFrame?.call(reason);
    if (_lastSize != null && size != _lastSize) {
      // The viewport changed size: reset the diff base and rebuild the
      // root (propagates through MediaQuery). The rendered frame below is
      // a full repaint at the new size.
      handleResize();
    }
    _lastSize = size;
    if (!snapshot.metricsChanged &&
        !_frameLoop.needsRender(size) &&
        !runtime.hasFrameWork) {
      // No-change frame: nothing rebuilt, nothing invalidated, buffers
      // warm. Skip build/layout/paint and write nothing — the surface
      // already shows exactly this frame. Semantic work may still be owed
      // (the host's skip hook keeps the conservative rebuild contract).
      _onFrameSkipped?.call(reason, size);
      runtime.flushPostFrameCallbacks();
      return;
    }
    _markOnce?.call('first.render.start');

    final debugWatching = _isDebugWatching?.call() ?? false;
    var phaseBuild = Duration.zero;
    var phaseLayout = Duration.zero;
    var phasePaint = Duration.zero;
    var buildStats = BuildFlushStats.zero;
    final renderStopwatch = Stopwatch()..start();
    _inFrameRender = true;
    TuiRenderedFrame? frame;
    try {
      frame = _frameLoop.render(
        size: size,
        paint: (next) {
          RenderLayoutDebugStats.beginFrame(enabled: debugWatching);
          RepaintBoundaryDebugStats.beginFrame(enabled: debugWatching);
          runtime.renderFrame(
            next,
            onPhaseTiming: (b, l, p) {
              phaseBuild = b;
              phaseLayout = l;
              phasePaint = p;
              if (debugWatching) _onPhaseTiming?.call(b, l, p);
            },
            onBuildStats: (stats) {
              buildStats = stats;
            },
          );
        },
      );
      _consecutiveBackstopFrames = 0;
    } catch (error, stack) {
      // Root backstop: whatever escaped every ErrorBoundary (a throw in
      // the scope stack above the first boundary, framework bookkeeping,
      // a boundary-free embedded host). Substitute a full-screen error
      // frame and keep the session — the input loop stays live and hot
      // reload becomes a recovery path — unless it storms.
      _inFrameRender = false;
      _onBackstopError?.call(error, stack);
      _consecutiveBackstopFrames += 1;
      if (_consecutiveBackstopFrames >= backstopStormLimit) {
        _renderUnrecoverable = true;
        rethrow;
      }
      _frameLoop.resetBuffers();
      try {
        frame = _frameLoop.render(
          size: size,
          paint: (next) =>
              paintCellErrorPresentation(next, CellOffset.zero, size, error),
        );
      } catch (_) {
        // The backstop frame itself failed to render: nothing left to
        // try locally.
        _renderUnrecoverable = true;
        rethrow;
      }
    }
    _inFrameRender = false;
    renderStopwatch.stop();
    if (frame == null) return;
    final layoutStats = RenderLayoutDebugStats.takeFrameStats();
    final repaintBoundaryStats = RepaintBoundaryDebugStats.takeFrameStats();

    final info = FramePresentInfo(
      reason: reason,
      plan: _presenter.wantsPresentationPlan
          ? _planner.build(
              reason: reason,
              frame: frame,
              metricsChanged: snapshot.metricsChanged,
            )
          : null,
      debugWatching: debugWatching,
      layoutStats: layoutStats,
      repaintBoundaryStats: repaintBoundaryStats,
      phaseBuild: phaseBuild,
      phaseLayout: phaseLayout,
      phasePaint: phasePaint,
      renderTime: renderStopwatch.elapsed,
      buildStats: buildStats,
    );
    _presenter.presentFrame(frame, info);
    // Semantics ride the same frame: the pipeline accumulates the
    // presented buffer + visual damage and schedules its flush.
    _onFramePresented?.call(frame, info.plan);
    _markOnce?.call('first.render.end');
    _frameLoop.commit(frame);
    _presenter.onFrameCommitted(frame, info);

    // Drain post-frame callbacks AFTER output is out: callers can now
    // safely read render-object geometry (sizes/offsets reflect the frame
    // the user is seeing). A callback that schedules another frame goes
    // through requestFrame; the scheduler already cleared its pending flag
    // before invoking us, so the new request schedules a fresh flush.
    runtime.flushPostFrameCallbacks();
  }

  /// Stops scheduling. Late scheduler fires drain callbacks only.
  void dispose() {
    _disposed = true;
    _scheduler.dispose();
  }
}
