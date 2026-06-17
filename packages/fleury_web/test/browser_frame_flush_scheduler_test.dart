@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury_web/src/browser_frame_flush_scheduler.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser frame scheduler falls back when rAF is unavailable', () async {
    final originalRequestAnimationFrame = web.window.getProperty<JSAny?>(
      'requestAnimationFrame'.toJS,
    );
    web.window.setProperty('requestAnimationFrame'.toJS, null);
    addTearDown(() {
      web.window.setProperty(
        'requestAnimationFrame'.toJS,
        originalRequestAnimationFrame,
      );
    });

    final flushed = Completer<void>();
    browserFrameFlushScheduler(Duration.zero, flushed.complete);

    await flushed.future.timeout(const Duration(seconds: 1));
  });
}
