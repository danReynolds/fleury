import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Browser flush adapter for Fleury's shared [FrameScheduler].
void Function() browserFrameFlushScheduler(
  Duration delay,
  void Function() flush,
) {
  var canceled = false;
  var completed = false;
  Timer? delayTimer;
  Timer? fallbackTimer;
  int? animationFrameId;

  void run() {
    if (canceled || completed) return;
    completed = true;
    flush();
  }

  void requestBrowserFrameFlush() {
    if (canceled) return;
    if (_hasRequestAnimationFrame()) {
      try {
        animationFrameId = web.window.requestAnimationFrame(
          ((JSNumber _) {
            animationFrameId = null;
            run();
          }).toJS,
        );
        return;
      } catch (_) {
        // Some embedded browser surfaces expose a partial window API. Falling
        // back keeps the first retained DOM frame from getting stranded.
      }
    }
    fallbackTimer = Timer(Duration.zero, run);
  }

  if (delay <= Duration.zero) {
    requestBrowserFrameFlush();
  } else {
    delayTimer = Timer(delay, requestBrowserFrameFlush);
  }

  return () {
    if (canceled || completed) return;
    canceled = true;
    delayTimer?.cancel();
    fallbackTimer?.cancel();
    final frameId = animationFrameId;
    if (frameId != null) {
      try {
        web.window.cancelAnimationFrame(frameId);
      } catch (_) {
        // A partial window API may expose rAF without cancellation. The
        // callback still observes [canceled] and releases our references.
      }
      animationFrameId = null;
    }
  };
}

bool _hasRequestAnimationFrame() {
  final requestAnimationFrame = web.window.getProperty<JSAny?>(
    'requestAnimationFrame'.toJS,
  );
  return requestAnimationFrame != null &&
      requestAnimationFrame.typeofEquals('function');
}
