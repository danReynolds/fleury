import 'package:fleury/fleury.dart' show MouseCursor;
import 'package:fleury/src/terminal/pointer_shapes.dart';
import 'package:test/test.dart';

void main() {
  test('OSC 22 support requires the complete affirmative shape set', () {
    for (final ending in ['\x1b\\', '\x07']) {
      expect(
        parsePointerShapesReply('\x1b]22;1,1,1,1,1$ending\x1b[?1;2c'.codeUnits),
        isTrue,
      );
    }
    for (final reply in [
      '',
      '\x1b[?1;2c',
      '\x1b]22;1,1,0,1,1\x1b\\',
      '\x1b]22;1,1,1,1,1',
      '\x1b]22;1,1,1,1,1,1\x1b\\',
      '\x1b]22;pointer\x1b\\',
    ]) {
      expect(parsePointerShapesReply(reply.codeUnits), isFalse);
    }
  });
  test('cursor encoding is a fixed allowlist and restores the shape stack', () {
    final names = ['default', 'pointer', 'text', 'ew-resize', 'ns-resize'];
    for (var i = 0; i < names.length; i++) {
      expect(
        pointerShapeSequence(MouseCursor.values[i]),
        '\x1b]22;${names[i]}\x1b\\',
      );
    }
    expect(pushPointerShape, '\x1b]22;>default\x1b\\');
    expect(popPointerShape, '\x1b]22;<\x1b\\');
  });
}
