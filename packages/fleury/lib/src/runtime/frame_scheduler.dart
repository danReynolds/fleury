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
/// A scheduler must never satisfy a zero delay with a microtask when it can
/// be invoked from inside its own flush — a post-frame callback or a
/// `setState` during the post-frame drain requests the next frame while the
/// render is still on the stack. Dart drains the microtask queue to empty
/// before any timer, I/O, or signal runs, so a frame→frame microtask chain
/// starves the event loop for the chain's whole duration: no input, no
/// Ctrl+C, no signal delivery. The default scheduler takes a microtask only
/// when idle and a `Timer` (a macrotask) when re-entrant; the browser
/// scheduler uses `requestAnimationFrame`, which is a macrotask already.
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
       _onRender = onRender {
    _flushScheduler = flushScheduler ?? _defaultFlush;
  }

  final Clock _clock;
  final FrameRenderCallback _onRender;
  late final FrameFlushScheduler _flushScheduler;

  /// Depth of [_onRender] calls on the stack (a counter, not a bool: a
  /// synchronous test scheduler can nest a flush inside a render). Non-zero
  /// means a request arriving now is re-entrant and must not chain a
  /// microtask — see [_defaultFlush].
  int _renderDepth = 0;

  /// The built-in flush: a microtask when the scheduler is idle (the
  /// historical "as soon as possible"), a `Timer` when a render is on the
  /// stack or a cap defers the flush.
  ///
  /// `Timer(Duration.zero, …)` is a macrotask: the event loop turns once
  /// before the next frame, so input, signals, and timers get their turn
  /// between frames instead of after the whole chain. Without this, a
  /// chunked paste — one post-frame callback per chunk, each scheduling the
  /// next — ran to completion as one unbroken microtask sequence: a 512 KiB
  /// paste held the isolate for ~12 s, and a post-frame callback that
  /// re-registers itself pinned it forever. SIGINT/SIGTERM are event-loop
  /// deliveries too, so the only exit was SIGKILL.
  FrameFlushCancellation? _defaultFlush(Duration delay, void Function() flush) {
    if (delay <= Duration.zero && _renderDepth == 0) {
      scheduleMicrotask(flush);
      return null;
    }
    final timer = Timer(delay, flush);
    return timer.cancel;
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
    _renderDepth++;
    try {
      _onRender(reason);
    } finally {
      _renderDepth--;
    }
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
