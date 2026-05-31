// TickerScheduler: the single timer the animation system shares
// across all active Tickers.
//
// When at least one Ticker is registered, a Timer.periodic fires at
// the configured frameInterval; on each fire, every registered
// Ticker is invoked with the current monotonic clock reading. When
// the last Ticker unregisters, the timer is cancelled — idle apps
// burn zero CPU on animation.
//
// FakeTickerScheduler is the test variant: no real Timer is ever
// created. Tests advance time via the wired-in FakeClock and call
// advanceFrame() to simulate a tick. Animation tests must NEVER
// use TickerScheduler (the real one) — only FakeTickerScheduler.

import 'dart:async';

import 'package:meta/meta.dart';

import '../widgets/framework.dart' show VoidCallback;
import 'clock.dart';

/// Signature for tick callbacks registered with a [TickerScheduler].
/// Receives the scheduler's clock reading at the moment of the tick.
typedef SchedulerTickCallback = void Function(Duration clockNow);

/// Signature for one-shot callbacks registered via
/// [TickerScheduler.addPostFrameCallback] (and the corresponding
/// [TuiBinding.addPostFrameCallback]). Receives the clock reading at
/// the moment the frame was drained. Named for Flutter parity with
/// `SchedulerBinding.addPostFrameCallback`.
typedef FrameCallback = void Function(Duration timeStamp);

/// One process-wide consolidation point for animation ticks.
///
/// All [Ticker]s share a single [Timer.periodic] managed by their
/// [TickerScheduler]. When the first [Ticker] registers, the timer
/// starts; when the last unregisters, the timer stops. This means a
/// TUI app with no active animations does zero scheduler work; an
/// app with N concurrent animations still has exactly one timer.
class TickerScheduler {
  TickerScheduler({
    Duration frameInterval = const Duration(milliseconds: 33),
    Clock clock = const SystemClock(),
  }) : _frameInterval = frameInterval,
       _clock = clock;

  /// How often the scheduler fires while at least one tick callback
  /// is registered. 33 ms by default (≈30 Hz).
  final Duration _frameInterval;

  Duration get frameInterval => _frameInterval;

  /// Monotonic time source. Read once per tick and passed to every
  /// registered callback.
  final Clock _clock;

  Clock get clock => _clock;

  /// Identity-based set so the same callback registered twice is
  /// only added once, and so two equal-but-different closures don't
  /// collide.
  final Set<SchedulerTickCallback> _callbacks =
      Set<SchedulerTickCallback>.identity();

  /// Identity-based set of reassemble callbacks. Distinct from
  /// [_callbacks] because reassemble fires on a different signal
  /// (post-hot-reload) and on a different cadence (once per
  /// reassemble, not per frame).
  final Set<VoidCallback> _reassembleCallbacks = Set<VoidCallback>.identity();

  /// One-shot callbacks scheduled to fire after the next rendered
  /// frame's bytes are emitted. Ordered; a callback registered during
  /// a drain enqueues into a fresh list and fires on the FOLLOWING
  /// frame (see [flushPostFrameCallbacks]).
  List<FrameCallback> _postFrameCallbacks = <FrameCallback>[];

  /// Re-entrance guard for [flushPostFrameCallbacks]. A callback that
  /// drove a re-entrant pump or renderFrame would consume the freshly-
  /// queued next-frame batch, defeating the "queues for the FOLLOWING
  /// frame" semantics.
  int _drainDepth = 0;

  /// Optional hook fired the moment a post-frame callback is enqueued.
  /// The runtime wires this to `scheduleFrame` so a callback added from
  /// an idle Timer.run (no event, no setState) still produces a frame —
  /// without it, the drain would never run because nothing scheduled
  /// the next frame.
  void Function()? onPostFrameCallbackRegistered;

  Timer? _timer;

  /// Whether the scheduler currently has a periodic source running.
  /// Structural assertion target: should be `false` when no
  /// callbacks are registered, `true` while at least one is.
  bool get isActive => _timer != null;

  /// Number of currently registered callbacks. Used by stress tests
  /// to assert "no ticker leak."
  int get activeTickerCount => _callbacks.length;

  /// Registers [callback] to receive a clock reading on every tick.
  /// Idempotent: re-registering the same callback is a no-op.
  /// Starts the underlying periodic source if this was the first
  /// callback.
  void register(SchedulerTickCallback callback) {
    final wasEmpty = _callbacks.isEmpty;
    if (!_callbacks.add(callback)) return;
    if (wasEmpty) _startTimer();
  }

  /// Unregisters a previously-registered [callback]. No-op when
  /// [callback] isn't currently registered. Stops the underlying
  /// periodic source if no callbacks remain.
  void unregister(SchedulerTickCallback callback) {
    if (!_callbacks.remove(callback)) return;
    if (_callbacks.isEmpty) _stopTimer();
  }

  /// Registers [callback] to fire on the next [reassemble].
  /// Idempotent: re-registering the same callback is a no-op.
  ///
  /// Used by long-lived animation primitives (Animation,
  /// FrameTicker) to reset to a known state after hot reload. The
  /// runtime calls [reassemble] from its hot-reload hook
  /// immediately after `BuildOwner.reassembleApplication`.
  void registerReassembleCallback(VoidCallback callback) {
    _reassembleCallbacks.add(callback);
  }

  /// Unregisters a previously-registered reassemble [callback]. No-op
  /// when [callback] isn't currently registered.
  void unregisterReassembleCallback(VoidCallback callback) {
    _reassembleCallbacks.remove(callback);
  }

  /// Fires every registered reassemble callback. Called by the
  /// runtime (via the `onReassemble` hook in `runTui`) after the
  /// build owner has walked the element tree.
  ///
  /// Iterates over a snapshot so a callback can safely unregister
  /// itself (e.g. an `Animation.dispose` triggered by a
  /// freshly-reloaded build).
  void reassemble() {
    if (_reassembleCallbacks.isEmpty) return;
    final snapshot = List<VoidCallback>.from(_reassembleCallbacks);
    for (final cb in snapshot) {
      cb();
    }
  }

  /// Queues [callback] to fire once, after the next rendered frame's
  /// bytes have been emitted (in the runtime) or after the next
  /// [FleuryTester.pump] completes its build flush (in tests). A
  /// callback registered DURING a drain enqueues for the next frame —
  /// never re-entrantly within the same drain.
  ///
  /// Fires [onPostFrameCallbackRegistered] so the runtime can schedule
  /// a frame; without that, a callback added from an idle Timer.run
  /// would queue indefinitely (no setState, no event, no frame).
  void addPostFrameCallback(FrameCallback callback) {
    _postFrameCallbacks.add(callback);
    onPostFrameCallbackRegistered?.call();
  }

  /// Fires every queued post-frame callback in registration order with
  /// [timeStamp] (the clock reading at the moment the frame was drained).
  /// Swaps the queue with an empty list BEFORE iterating so callbacks
  /// that register a new post-frame callback land on the NEXT frame
  /// (Flutter divergence; prevents same-frame infinite loops). An
  /// exception in one callback is caught and reported so the rest of
  /// the drain still runs.
  ///
  /// Asserts in debug that the drain is not re-entered — a callback
  /// that drove a re-entrant pump or renderFrame would consume the
  /// freshly-queued next-frame batch and defeat the FOLLOWING-frame
  /// guarantee. Defer to a Future or a setState instead.
  ///
  /// Internal: driven by `TuiBinding` / `FleuryTester.pump` /
  /// `run_tui_web` after a frame; app code should use
  /// [addPostFrameCallback].
  @internal
  void flushPostFrameCallbacks(Duration timeStamp) {
    assert(
      _drainDepth == 0,
      'Nested flushPostFrameCallbacks: a callback called pump() or '
      'renderFrame() re-entrantly. This consumes the next-frame queue. '
      'Defer with a Future or a setState instead.',
    );
    if (_postFrameCallbacks.isEmpty) return;
    final batch = _postFrameCallbacks;
    _postFrameCallbacks = <FrameCallback>[];
    _drainDepth++;
    try {
      for (final cb in batch) {
        try {
          cb(timeStamp);
        } catch (error, stack) {
          Zone.current.handleUncaughtError(error, stack);
        }
      }
    } finally {
      _drainDepth--;
    }
  }

  /// Override point for [FakeTickerScheduler], which never creates
  /// a real timer.
  void _startTimer() {
    _timer = Timer.periodic(_frameInterval, (_) => _fire());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Called by the underlying periodic source. Snapshots the
  /// callback set before iterating so that callbacks can safely
  /// register or unregister during a tick without confusing
  /// iteration.
  void _fire() {
    if (_callbacks.isEmpty) return;
    final snapshot = List<SchedulerTickCallback>.from(_callbacks);
    final now = _clock.now;
    for (final cb in snapshot) {
      cb(now);
    }
  }

  /// Releases scheduler resources. Idempotent. Tickers that were
  /// registered with this scheduler should be disposed first; after
  /// [dispose] the scheduler will not invoke any callbacks.
  ///
  /// Drains pending post-frame callbacks before clearing — a callback
  /// registered just before runtime shutdown otherwise vanishes
  /// silently, even though "after the next frame" is the contract.
  /// Exceptions in a callback are routed through Zone.current and do
  /// not abort the rest of the drain.
  void dispose() {
    _stopTimer();
    // Drain first so a callback can still run side effects (e.g. log
    // a final state) before everything is torn down. Snapshot+swap
    // matches `flushPostFrameCallbacks`'s next-frame discipline.
    if (_postFrameCallbacks.isNotEmpty) {
      final batch = _postFrameCallbacks;
      _postFrameCallbacks = <FrameCallback>[];
      final now = _clock.now;
      for (final cb in batch) {
        try {
          cb(now);
        } catch (error, stack) {
          Zone.current.handleUncaughtError(error, stack);
        }
      }
    }
    _callbacks.clear();
    _reassembleCallbacks.clear();
    _postFrameCallbacks.clear();
    onPostFrameCallbackRegistered = null;
  }
}

/// Test variant of [TickerScheduler] that doesn't create a real
/// [Timer.periodic]. Tests drive ticks by:
///
///   1. Advancing the [FakeClock] passed in via the constructor.
///   2. Calling [advanceFrame] to invoke registered callbacks.
///
/// [isActive] reflects whether registrations would have started the
/// real timer — useful for the "zero idle work" structural
/// assertion.
class FakeTickerScheduler extends TickerScheduler {
  FakeTickerScheduler({super.frameInterval, required FakeClock super.clock});

  bool _fakeActive = false;

  @override
  bool get isActive => _fakeActive;

  @override
  void _startTimer() {
    _fakeActive = true;
  }

  @override
  void _stopTimer() {
    _fakeActive = false;
  }

  /// Drives one scheduler tick, calling every registered callback
  /// with the clock's current `now`. No-op when the scheduler is
  /// not active (i.e. no callbacks registered).
  void advanceFrame() {
    if (!_fakeActive) return;
    _fire();
  }

  /// Convenience: advance the fake clock by [delta] and emit one
  /// scheduler tick at the new time. Equivalent to:
  ///
  ///     (scheduler.clock as FakeClock).advance(delta);
  ///     scheduler.advanceFrame();
  void advance(Duration delta) {
    (clock as FakeClock).advance(delta);
    advanceFrame();
  }
}
