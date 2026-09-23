import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/nested_row.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets(
    'a child action keeps the row hovered and keyboard access intact',
    (tester) {
      tester.pumpFleuryHome(const SizedBox(width: 36, child: NestedRow()));
      for (final col in [0, 3, 10, 14, 25]) {
        pointer(tester, MouseEventKind.moved, col, 1);
        expect(tester.render().atColRow(0, 0).style.foreground, Colors.cyan);
        expect(tester.exists(text('Inside file row')), isTrue);
      }
      pointer(tester, MouseEventKind.down, 14, 1);
      pointer(tester, MouseEventKind.up, 14, 1);
      expect(tester.exists(text('Pinned to sidebar')), isTrue);
      expect(tester.exists(text('Inside file row')), isTrue);
      pointer(tester, MouseEventKind.moved, 28, 1);
      expect(tester.exists(text('Outside file row')), isTrue);
      expect(
        tester.render().atColRow(0, 0).style.foreground,
        isNot(Colors.cyan),
      );
      expect(tester.exists(text('Pinned to sidebar')), isTrue);
      tester.press(KeySequence.enter);
      expect(tester.exists(text('Not pinned')), isTrue);
    },
  );
}
