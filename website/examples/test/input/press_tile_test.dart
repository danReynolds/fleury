import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/press_tile.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets(
    'release outside cancels; primary and secondary clicks stay distinct',
    (tester) {
      tester.pumpWidget(const PressTile());
      pointer(tester, MouseEventKind.down, 3, 0);
      expect(tester.exists(text('Pressed…')), isTrue);
      pointer(tester, MouseEventKind.up, 30, 4);
      expect(tester.exists(text('Cancelled')), isTrue);
      pointer(tester, MouseEventKind.down, 3, 0);
      pointer(tester, MouseEventKind.up, 3, 0);
      expect(tester.exists(text('Opened notes.md')), isTrue);
      pointer(tester, MouseEventKind.down, 3, 0, button: MouseButton.right);
      pointer(tester, MouseEventKind.up, 3, 0, button: MouseButton.right);
      expect(tester.exists(text('notes.md · Markdown · 2 KB')), isTrue);
    },
  );
}
