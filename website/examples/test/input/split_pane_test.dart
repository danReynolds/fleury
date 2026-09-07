import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/split_pane.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets('one movement resizes; release outside ends the drag', (tester) {
    tester.pumpWidget(const SizedBox(width: 36, child: SplitPane()));
    pointer(tester, MouseEventKind.down, 14, 2);
    pointer(tester, MouseEventKind.drag, 18, 2);
    expect(tester.exists(text('Resizing…')), isTrue);
    pointer(tester, MouseEventKind.up, 40, 8);
    expect(tester.exists(text('Width: 18 · ← → resize')), isTrue);
    tester.press(KeySequence.left);
    expect(tester.exists(text('Width: 17 · ← → resize')), isTrue);
  });
}
