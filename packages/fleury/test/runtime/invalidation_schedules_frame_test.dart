// A render-object invalidation raised outside a build schedules a frame.
//
// A paint-only setter driven by a timer — a blink, a spinner, a progress
// glyph — only set a flag that frames consult; nothing asked for the frame,
// so the change showed on the next unrelated frame, or never in an idle app.
// Layout invalidation had the same hole. Both now go through the frame
// driver's one scheduling primitive.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_events.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

class _Dot extends LeafRenderObjectWidget {
  const _Dot();

  static _RenderDot? last;

  @override
  RenderObject createRenderObject(BuildContext context) => last = _RenderDot();
}

class _RenderDot extends RenderObject {
  var _on = false;
  set on(bool value) {
    if (value == _on) return;
    _on = value;
    markNeedsPaintOnly();
  }

  int _cols = 1;
  set cols(int value) {
    if (value == _cols) return;
    _cols = value;
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(CellSize(_cols, 1));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    for (var c = 0; c < _cols; c++) {
      buffer.writeGrapheme(
        offset + CellOffset(c, 0),
        _on ? '●' : '○',
        style: CellStyle.none,
      );
    }
  }
}

void main() {
  test('a timer-driven paint-only setter gets its own frame', () async {
    final driver = FakeTerminalDriver(size: const CellSize(10, 2));
    final frames = <String>[];
    final sub = DebugEvents.stream.listen((event) {
      if (event is FrameDebugEvent) frames.add(event.frame.reason);
    });
    final future = runApp(const _Dot(), driver: driver, enableHotReload: false);
    try {
      await _settle();
      await _settle();
      final before = frames.length;
      expect(driver.output, contains('○'));

      Timer.run(() => _Dot.last!.on = true);
      await _settle();
      await _settle();
      expect(
        frames.length,
        greaterThan(before),
        reason:
            'no build, no input, no post-frame: the setter alone must '
            'schedule the frame',
      );
      expect(driver.output, contains('●'));

      final beforeLayout = frames.length;
      Timer.run(() => _Dot.last!.cols = 3);
      await _settle();
      await _settle();
      expect(frames.length, greaterThan(beforeLayout));
      // The diff writes each new cell with its own cursor move.
      expect('●'.allMatches(driver.output).length, greaterThanOrEqualTo(3));
    } finally {
      await sub.cancel();
      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await future.timeout(const Duration(seconds: 2));
      await driver.dispose();
    }
  });
}
