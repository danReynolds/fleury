import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Browser flush adapter for Fleury's shared [FrameScheduler].
void browserFrameFlushScheduler(Duration delay, void Function() flush) {
  void requestBrowserFrameFlush() {
    if (_hasRequestAnimationFrame()) {
      try {
        web.window.requestAnimationFrame(
          ((JSNumber _) {
            flush();
          }).toJS,
        );
        return;
      } catch (_) {
        // Some embedded browser surfaces expose a partial window API. Falling
        // back keeps the first retained DOM frame from getting stranded.
      }
    }
    Timer.run(flush);
  }

  if (delay <= Duration.zero) {
    requestBrowserFrameFlush();
  } else {
    Timer(delay, requestBrowserFrameFlush);
  }
}

bool _hasRequestAnimationFrame() {
  final requestAnimationFrame = web.window.getProperty<JSAny?>(
    'requestAnimationFrame'.toJS,
  );
  return requestAnimationFrame != null &&
      requestAnimationFrame.typeofEquals('function');
}
