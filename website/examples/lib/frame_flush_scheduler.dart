import 'dart:async';

/// Browser-independent core of the docs examples' rAF + Timer scheduler.
///
/// The injected adapters keep the race deterministic in tests. Production
/// passes `window.requestAnimationFrame` / `cancelAnimationFrame` wrappers.
void Function() scheduleDocsFrameFlush(
  Duration delay,
  void Function() flush, {
  required int Function(void Function() callback) requestAnimationFrame,
  required void Function(int frameId) cancelAnimationFrame,
  Duration fallbackDelay = const Duration(milliseconds: 120),
}) {
  var canceled = false;
  var completed = false;
  Timer? delayTimer;
  Timer? fallbackTimer;
  int? animationFrameId;

  void run() {
    if (completed || canceled) return;
    completed = true;
    fallbackTimer?.cancel();

    // The Timer can win while rAF is paused in a backgrounded tab. Release
    // that losing browser callback now; the outer FrameScheduler clears its
    // cancellation handle before invoking [flush].
    final frameId = animationFrameId;
    animationFrameId = null;
    if (frameId != null) {
      try {
        cancelAnimationFrame(frameId);
      } catch (_) {}
    }
    flush();
  }

  void arm() {
    if (canceled) return;
    var ranSynchronously = false;
    try {
      final frameId = requestAnimationFrame(() {
        ranSynchronously = true;
        animationFrameId = null;
        run();
      });
      if (!ranSynchronously && !completed && !canceled) {
        animationFrameId = frameId;
      }
    } catch (_) {
      // A partial browser API can throw; the Timer remains the progress path.
    }
    if (!completed && !canceled) fallbackTimer = Timer(fallbackDelay, run);
  }

  if (delay <= Duration.zero) {
    arm();
  } else {
    delayTimer = Timer(delay, arm);
  }

  return () {
    if (canceled || completed) return;
    canceled = true;
    delayTimer?.cancel();
    fallbackTimer?.cancel();
    final frameId = animationFrameId;
    animationFrameId = null;
    if (frameId != null) {
      try {
        cancelAnimationFrame(frameId);
      } catch (_) {}
    }
  };
}
