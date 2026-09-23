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
      pointer(tester, MouseEventKind.moved, 1, 0);
      expect(tester.render().atColRow(1, 0).style.inverse, isTrue);
      pointer(tester, MouseEventKind.moved, 32, 0);
      expect(tester.exists(text('Row hovered')), isTrue);
      pointer(tester, MouseEventKind.down, 32, 0);
      pointer(tester, MouseEventKind.up, 32, 0);
      expect(tester.exists(text('Pinned to sidebar')), isTrue);
      expect(tester.exists(text('Row hovered')), isTrue);
      pointer(tester, MouseEventKind.leave, 40, 0);
      expect(tester.exists(text('Row not hovered')), isTrue);
      expect(tester.render().atColRow(1, 0).style.inverse, isFalse);
      tester.press(KeySequence.enter);
      expect(tester.exists(text('Not pinned')), isTrue);
    },
  );
}
