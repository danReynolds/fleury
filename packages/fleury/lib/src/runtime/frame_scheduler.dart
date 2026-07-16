import 'dart:async';

import '../animation/clock.dart';

/// Render callback the scheduler drives, given the merged frame reason.
typedef FrameRenderCallback = void Function(String reason);

/// Schedules [flush] to run after [delay]. `Duration.zero` means "as soon as
/// possible" (a microtask). Returns an optional cancellation callback so a
/// disposed runtime can release delayed timers / browser frame callbacks
/// instead of retaining the whole session until they fire. Injectable so
/// tests drive timing deterministically.
typedef FrameFlushCancellation = void Function();
typedef FrameFlushScheduler =
    FrameFlushCancellation? Function(Duration delay, void Function() flush);

FrameFlushCancellation? _defaultFlushScheduler(
  Duration delay,
  void Function() flush,
) {
  if (delay <= Duration.zero) {
    scheduleMicrotask(flush);
    return null;
  }
  final timer = Timer(delay, flush);
  return timer.cancel;
}

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
       _flushScheduler = flushScheduler ?? _defaultFlushScheduler;

  final Clock _clock;
  final FrameRenderCallback _onRender;
  final FrameFlushScheduler _flushScheduler;

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
    _onRender(reason);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending = false;
    _scheduleToken += 1;
    _cancelScheduledFlush?.call();
    _cancelScheduledFlush = null;
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
