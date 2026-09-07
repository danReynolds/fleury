import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/hover_notes.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets('a child button keeps its row hovered', (tester) {
    tester.pumpWidget(const SizedBox(width: 36, child: HoverNotes()));
    pointer(tester, MouseEventKind.moved, 1, 0);
    expect(tester.exists(text('Over the row · pins: 0')), isTrue);
    pointer(tester, MouseEventKind.down, 32, 0);
    pointer(tester, MouseEventKind.up, 32, 0);
    expect(tester.exists(text('Over the row · pins: 1')), isTrue);
    pointer(tester, MouseEventKind.leave, 40, 0);
    expect(tester.exists(text('Move over the row or Pin')), isTrue);
  });
}
