import 'dart:async';

/// Schedules deferred semantic flushes for the retained DOM host.
///
/// The visual frame ends at present/commit; semantic presentation runs in a
/// later task so it never spends the rAF budget. The host calls [schedule]
/// at most once per outstanding flush — implementations run [flush] exactly
/// once per accepted schedule, outside the current task.
///
/// Frames that arrive while a flush is outstanding simply accumulate dirty
/// state; the eventual flush reads the latest element tree and committed
/// buffer, which is how several visual frames coalesce into one semantic
/// pass under load.
abstract interface class SemanticFlushScheduler {
  /// Requests that [flush] run in a later task.
  void schedule(void Function() flush);

  /// Cancels any outstanding flush.
  void dispose();
}

/// Default scheduler: a macrotask ([Timer.run]) with an optional minimum
/// interval between flush starts.
///
/// A macrotask posted from a rAF callback runs after the browser finishes the
/// current rendering update, so the flush shares no frame budget with the
/// visual pipeline. [minInterval] adds explicit coalescing on top of the
/// natural backpressure (a slow flush already delays the next schedule);
/// zero keeps semantic latency minimal and is the default.
final class TimerSemanticFlushScheduler implements SemanticFlushScheduler {
  TimerSemanticFlushScheduler({this.minInterval = Duration.zero});

  final Duration minInterval;

  final Stopwatch _sinceLastFlush = Stopwatch();
  Timer? _pending;
  var _disposed = false;

  @override
  void schedule(void Function() flush) {
    if (_disposed || _pending != null) return;
    var delay = Duration.zero;
    if (minInterval > Duration.zero && _sinceLastFlush.isRunning) {
      final remaining = minInterval - _sinceLastFlush.elapsed;
      if (remaining > Duration.zero) delay = remaining;
    }
    _pending = Timer(delay, () {
      _pending = null;
      _sinceLastFlush
        ..reset()
        ..start();
      flush();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _pending = null;
  }
}

/// Same-task scheduler: the flush runs as a microtask, after the visual
/// frame's synchronous work but within the same event-loop task. The wire
/// presenter's default — semantics for a rendered frame reach the peer in
/// the same task as its plan, so "semantics for the just-rendered frame"
/// stays literally true for agents and MCP settle windows don't lengthen.
final class MicrotaskSemanticFlushScheduler implements SemanticFlushScheduler {
  var _pending = false;
  var _disposed = false;

  @override
  void schedule(void Function() flush) {
    if (_disposed || _pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      if (_disposed) return;
      flush();
    });
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
