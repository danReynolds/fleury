import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/selectable_note.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets('selects across text widgets and copies only the note', (
    tester,
  ) async {
    tester.pumpWidget(const SizedBox(width: 40, child: SelectableNote()));
    expect(tester.field('Reply'), isFocused);
    tester.type('Looks good.');
    pointer(tester, MouseEventKind.down, 0, 0);
    pointer(tester, MouseEventKind.drag, 4, 1);
    pointer(tester, MouseEventKind.up, 4, 1);
    tester.press(KeySequence.ctrl.c);
    await tester.settle();
    expect(
      (tester.clipboard as InProcessClipboard).lastWritten,
      'Planning notes\nShip',
    );
    expect(tester.field('Reply'), isNot(isFocused));
    expect(tester.field('Reply'), hasValue('Looks good.'));
    tester.press(KeySequence.ctrl.a);
    tester.press(KeySequence.ctrl.c);
    await tester.settle();
    expect(
      (tester.clipboard as InProcessClipboard).lastWritten,
      'Planning notes\nShip the guide.\nReview the gestures.',
    );
    tester.press(KeySequence.escape);
    expect(tester.exists(text('Drag across the note')), isTrue);
  });
}
