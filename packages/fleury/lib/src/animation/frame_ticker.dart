// FrameTicker: discrete-lane primitive for frame-indexed
// animations (spinners, cursor blink, typing indicators, marquee).
//
// Differences from Ticker:
//   - FrameTicker has its own logical interval (e.g. 80 ms for a
//     spinner, 500 ms for a cursor blink). It registers with the
//     same TickerScheduler so there's still one underlying timer
//     for the whole app, but only advances its frame counter when
//     enough time has elapsed since its last emit.
//   - FrameTicker exposes a `frame` integer counter (plus elapsed
//     and delta) and uses a Listenable model so multiple widgets
//     can subscribe.
//
// Most apps don't touch FrameTicker directly — they use
// `FrameBuilder` (the consumption widget) or pre-built widgets
// like `Spinner` and `BlinkingCursor`.

import '../foundation/change_notifier.dart';
import 'ticker_scheduler.dart';

/// Frame-indexed ticker driven by a [TickerScheduler]. Notifies its
/// listeners each time enough time has elapsed since the last
/// notification to advance the frame counter.
///
/// Sharing the scheduler with [Ticker]s in the continuous lane
/// means N concurrent [FrameTicker]s still produce only one
/// underlying [Timer.periodic] in the runtime.
class FrameTicker extends ChangeNotifier {
  FrameTicker({required this.interval, required TickerScheduler scheduler})
    : _scheduler = scheduler,
      assert(
        interval > Duration.zero,
        'FrameTicker.interval must be positive.',
      ) {
    // Register for hot-reload reset. After reassemble we restart the
    // frame counter at 0 so widgets keying off `frame` (spinner
    // glyph index, blink phase) jump to a deterministic position
    // rather than continuing from whatever phase they were in.
    _scheduler.registerReassembleCallback(_onReassemble);
  }

  /// How much time must elapse before the next frame advance.
  /// Typical values: 80 ms (spinner), 500 ms (cursor blink),
  /// 400 ms (typing indicator).
  final Duration interval;

  final TickerScheduler _scheduler;

  /// Cached tear-off so register / unregister see identical
  /// callbacks (the scheduler's set is identity-based).
  late final SchedulerTickCallback _schedulerCallback = _handleSchedulerTick;

  /// Cached tear-off for the reassemble registry.
  late final void Function() _onReassemble = _handleReassemble;

  bool _active = false;
  bool _disposed = false;
  bool _muted = false;

  Duration? _startTime;
  Duration _elapsed = Duration.zero;
  Duration _lastEmitElapsed = Duration.zero;
  Duration _delta = Duration.zero;
  int _frame = 0;

  /// Monotonically-increasing frame counter. Increments by one each
  /// time the ticker advances. Resets to zero on [start].
  int get frame => _frame;

  /// Total elapsed time since the most recent [start], updated on
  /// every scheduler tick (not only on frame advances). Reads
  /// 0 before the first scheduler tick.
  Duration get elapsed => _elapsed;

  /// Elapsed time between the previous frame advance and the most
  /// recent one. Useful for builders that animate against actual
  /// elapsed time (which may exceed [interval] under stall).
  Duration get delta => _delta;

  /// Whether this ticker is currently registered with the
  /// scheduler.
  bool get isActive => _active;

  /// When true, the ticker continues to advance internal state but
  /// suppresses notifications. Re-enabling resumes notifications at
  /// the next scheduler tick that crosses an interval boundary.
  bool get muted => _muted;
  set muted(bool value) {
    if (_disposed) {
      throw StateError(
        'FrameTicker.muted set after dispose. Create a new FrameTicker '
        'instead of reusing this one.',
      );
    }
    if (_muted == value) return;
    _muted = value;
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Starts the ticker. Captures the scheduler's clock value as the
  /// start anchor; resets [frame] / [elapsed] / [delta] to zero.
  /// No-op when already active or disposed.
  void start() {
    if (_disposed) {
      throw StateError(
        'FrameTicker.start() called after dispose. Create a new '
        'FrameTicker instead of reusing this one.',
      );
    }
    if (_active) return;
    _active = true;
    _startTime = _scheduler.clock.now;
    _frame = 0;
    _elapsed = Duration.zero;
    _lastEmitElapsed = Duration.zero;
    _delta = Duration.zero;
    _scheduler.register(_schedulerCallback);
  }

  /// Stops the ticker. Pauses scheduler callbacks; the next [start]
  /// resets the start anchor.
  void stop() {
    if (_disposed) {
      throw StateError('FrameTicker.stop() called after dispose.');
    }
    if (!_active) return;
    _active = false;
    _startTime = null;
    _scheduler.unregister(_schedulerCallback);
  }

  /// Releases resources. Idempotent. Subsequent [start] / [stop]
  /// calls throw.
  @override
  void dispose() {
    if (_disposed) return;
    if (_active) {
      _scheduler.unregister(_schedulerCallback);
    }
    _scheduler.unregisterReassembleCallback(_onReassemble);
    _disposed = true;
    _active = false;
    _startTime = null;
    super.dispose();
  }

  void _handleReassemble() {
    if (_disposed) return;
    // Reset frame phase. If the ticker was active, re-anchor its
    // start time to "now" so elapsed begins from zero again — this
    // keeps the next frame advance one full interval away rather
    // than firing immediately.
    _frame = 0;
    _elapsed = Duration.zero;
    _lastEmitElapsed = Duration.zero;
    _delta = Duration.zero;
    if (_active) {
      _startTime = _scheduler.clock.now;
    }
    notifyListeners();
  }

  void _handleSchedulerTick(Duration clockNow) {
    if (!_active) return;
    _elapsed = clockNow - _startTime!;
    if (_elapsed - _lastEmitElapsed < interval) return;
    _delta = _elapsed - _lastEmitElapsed;
    _lastEmitElapsed = _elapsed;
    _frame += 1;
    if (_muted) return;
    notifyListeners();
  }
}
