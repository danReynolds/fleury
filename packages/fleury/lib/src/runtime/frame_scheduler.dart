import 'dart:async';

import '../animation/clock.dart';

/// Render callback the scheduler drives, given the merged frame reason.
typedef FrameRenderCallback = void Function(String reason);

/// Cancels a pending frame flush.
typedef FrameFlushCancellation = void Function();

/// Schedules [flush] to run after [delay]. `Duration.zero` means "as soon as
/// possible". Returns an optional cancellation callback so a disposed runtime
/// can release delayed timers / browser frame callbacks instead of retaining
/// the whole session until they fire. Injectable so tests drive timing
/// deterministically.
///
/// A scheduler must never satisfy a zero delay with a microtask when the
/// request comes from a frame's own microtask drain — a post-frame callback,
/// or a `setState` from a microtask the frame queued. Dart drains the
/// microtask queue to empty before any timer, I/O, or signal runs, so a
/// frame→frame microtask chain starves the event loop for the chain's whole
/// duration: no input, no Ctrl+C, no signal delivery. The default scheduler
/// runs a frame that a frame caused when the turn ends; the browser scheduler
/// uses `requestAnimationFrame`, which is a macrotask already.
typedef FrameFlushScheduler =
    FrameFlushCancellation? Function(Duration delay, void Function() flush);

/// Coalesces frame requests and optionally caps the render rate.
///
/// Without a cap ([minFrameInterval] == [Duration.zero]) this preserves the
/// historical behaviour exactly: the first request in an event-loop turn
/// schedules a microtask flush, and every further request before it runs
/// coalesces into it (merging reasons).
///
/// With a cap, a request arriving sooner than [minFrameInterval] after the last
/// render is deferred to the trailing edge of the interval, so a burst of N
/// updates (e.g. a high-rate token/log stream, or rapid `setState`s) produces
/// one render per interval instead of N. This matters most on round-trip-bound
/// transports (WAN SSH) and streaming agent workloads, where frame COUNT — not
/// frame size — drives perceived latency. Updates are never dropped, only
/// merged: the deferred render reflects the latest state.
class FrameScheduler {
  FrameScheduler({
    required Clock clock,
    required FrameRenderCallback onRender,
    this.minFrameInterval = Duration.zero,
    FrameFlushScheduler? flushScheduler,
  }) : _clock = clock,
       _onRender = onRender,
       _zone = Zone.current {
    _frameZone = _zone.fork(zoneValues: {_frameZoneKey: this});
    _flushScheduler = flushScheduler ?? _defaultFlush;
  }

  final Clock _clock;
  final FrameRenderCallback _onRender;
  late final FrameFlushScheduler _flushScheduler;

  /// The zone this scheduler was built in: the runtime's guarded zone. Every
  /// flush runs here, whoever requested the frame. A request from a listener
  /// registered in `main()` would otherwise run the frame — and every timer
  /// it starts — outside the guard that restores the terminal.
  final Zone _zone;

  static final _frameZoneKey = Object();

  /// Where frames render: a child of [_zone] that marks the code a frame
  /// runs, and every callback that code registers — a microtask, a `.then`, a
  /// timer — as caused by a frame.
  late final Zone _frameZone;

  /// Pending from the moment a frame renders until the event loop turns: a
  /// zero-delay timer, which cannot fire while microtasks are queued, so its
  /// firing marks the end of the frame's microtask drain.
  Timer? _turnEnd;

  /// A zero-delay flush requested while [_turnEnd] was pending. It runs when
  /// [_turnEnd] fires, not as a microtask.
  void Function()? _flushAtTurnEnd;

  /// Microtask flushes since the turn last ended.
  int _microtaskFlushes = 0;

  /// The most microtask frames one turn renders, whatever caused them. A
  /// frame that causes another through a zone this scheduler cannot see (it
  /// completes a future awaited by a loop started outside every frame) still
  /// yields after this many.
  static const _maxMicrotaskFlushesPerTurn = 8;

  /// Whether the running code is a frame, or a callback a frame registered.
  bool get _inFrameCode => identical(Zone.current[_frameZoneKey], this);

  /// The built-in flush: a microtask (the historical "as soon as
  /// possible"), except for a frame caused by a frame, which runs when the
  /// event-loop turn ends, and a `Timer` when a cap defers the flush.
  ///
  /// A frame that requests the next frame from its own microtask drain is a
  /// chain — a post-frame callback per paste chunk, or a `setState` from a
  /// microtask the frame itself queued — and a chain never yields: a 512 KiB
  /// paste held the isolate for ~12 s, and a self-renewing chain pinned it
  /// forever. SIGINT/SIGTERM are event-loop deliveries too, so the only exit
  /// was SIGKILL. Waiting for the turn to end lets input, signals, and timers
  /// run between frames. A frame that other code requests after a frame, such
  /// as an error report mounting its banner or an event handler resuming
  /// after an `await`, still renders in the same drain.
  ///
  /// The chained frame rides the turn-end timer and does not get a new
  /// `Timer` of its own. Timers fire in deadline order, so a new zero-delay
  /// timer runs after every timer already due, including ones that fell due
  /// while the request's own handler ran. The turn-end timer dates from the
  /// turn's first frame, so the chained frame runs before any timer created
  /// after the request.
  FrameFlushCancellation? _defaultFlush(Duration delay, void Function() flush) {
    final guarded = _zone.bindCallbackGuarded(() {
      if (!_disposed) {
        _turnEnd ??= _zone.createTimer(
          Duration.zero,
          _zone.bindCallbackGuarded(_endTurn),
        );
      }
      flush();
    });
    if (delay > Duration.zero) return _zone.createTimer(delay, guarded).cancel;
    final chained =
        _turnEnd != null &&
        (_inFrameCode || _microtaskFlushes >= _maxMicrotaskFlushesPerTurn);
    if (!chained) {
      _microtaskFlushes++;
      _zone.scheduleMicrotask(guarded);
      return null;
    }
    _flushAtTurnEnd = guarded;
    return () {
      if (identical(_flushAtTurnEnd, guarded)) _flushAtTurnEnd = null;
    };
  }

  void _endTurn() {
    _turnEnd = null;
    _microtaskFlushes = 0;
    final flush = _flushAtTurnEnd;
    _flushAtTurnEnd = null;
    flush?.call();
  }

  /// Minimum time between rendered frames. [Duration.zero] disables the cap.
  final Duration minFrameInterval;

  Duration? _lastRenderAt;
  bool _pending = false;
  bool _disposed = false;
  String _reason = 'scheduled';
  FrameFlushCancellation? _cancelScheduledFlush;
  var _scheduleToken = 0;

  /// Whether a flush is scheduled but has not yet run.
  bool get hasPendingFrame => _pending;

  /// Requests a frame. Coalesces with any already-pending flush.
  void requestFrame([String reason = 'scheduled']) {
    if (_disposed) return;
    if (_pending) {
      _reason = _mergeReasons(_reason, reason);
      return;
    }
    _pending = true;
    _reason = reason;
    _schedule(_waitBeforeFlush());
  }

  void _schedule(Duration delay) {
    final token = ++_scheduleToken;
    var ranSynchronously = false;
    void flush() {
      ranSynchronously = true;
      if (token != _scheduleToken) return;
      _cancelScheduledFlush = null;
      _flush();
    }

    final cancel = _flushScheduler(delay, flush);
    // A custom test scheduler may invoke flush synchronously. onRender can
    // then request another frame before this outer scheduler call returns;
    // never overwrite that newer request's cancellation handle with the old
    // one. Cancel any stale handle the custom scheduler returned.
    if (!ranSynchronously && token == _scheduleToken && _pending) {
      _cancelScheduledFlush = cancel;
    } else {
      cancel?.call();
    }
  }

  Duration _waitBeforeFlush() {
    if (minFrameInterval <= Duration.zero) return Duration.zero;
    final last = _lastRenderAt;
    if (last == null) return Duration.zero;
    final since = _clock.now - last;
    if (since >= minFrameInterval) return Duration.zero;
    return minFrameInterval - since;
  }

  void _flush() {
    if (_disposed || !_pending) return;
    _pending = false;
    _lastRenderAt = _clock.now;
    final reason = _reason;
    _reason = 'scheduled';
    _frameZone.run(() => _onRender(reason));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending = false;
    _scheduleToken += 1;
    _cancelScheduledFlush?.call();
    _cancelScheduledFlush = null;
    _turnEnd?.cancel();
    _turnEnd = null;
  }
}

/// Merge two frame reasons into a stable, deduped `a+b` label.
String _mergeReasons(String current, String next) {
  if (current == next) return current;
  if (current.isEmpty || current == 'scheduled') return next;
  if (next.isEmpty || next == 'scheduled') return current;
  final parts = current.split('+');
  if (parts.contains(next)) return current;
  return '$current+$next';
}
