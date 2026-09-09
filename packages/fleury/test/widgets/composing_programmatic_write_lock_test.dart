// Lock test (audit 10.f): a programmatic controller write must clear any
// active IME composing range. Leaving it intact lets a later commit replace
// a stale range against the new text and corrupt the document
// (`あ` + write `programmatic` + commit `亜` → `亜rogrammatic`).
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'programmatic text write clears composing so a later commit cannot clobber',
    (tester) {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));
      tester.render(size: const CellSize(20, 2));

      tester.dispatcher.dispatch(const TextCompositionEvent.update('あ'));
      expect(controller.hasComposingRange, isTrue);
      expect(controller.text, 'あ');

      controller.text = 'programmatic';
      expect(
        controller.hasComposingRange,
        isFalse,
        reason:
            'programmatic write must clear composing; stale range against '
            'the new string is what lets the next commit corrupt it',
      );

      tester.dispatcher.dispatch(const TextCompositionEvent.commit('亜'));
      expect(
        controller.text,
        isNot('亜rogrammatic'),
        reason: 'the stale (0,1) range must not be rewritten — audit 10.f',
      );
      expect(
        controller.text,
        'p亜rogrammatic',
        reason:
            'with composing cleared the commit inserts at the caret, and the '
            'write left the caret where it was. Forcing it to the end here '
            'would read `programmatic亜`, but that is the same line that '
            'sends the cursor to the end of an as-you-type formatter on '
            'every keystroke — see the caret test below',
      );
    },
  );

  test('a programmatic write leaves the caret alone', () {
    final c = TextEditingController(text: '5551234');
    addTearDown(c.dispose);
    c.selection = const TextSelection.collapsed(offset: 3);

    // What `onChanged: (v) => controller.text = format(v)` does every
    // keystroke. Collapsing to the end here makes it impossible to edit
    // anywhere but the end of the field.
    c.text = '555-1234';

    expect(c.selection.baseOffset, 3);
    expect(c.composing, TextRange.empty);
  });
}
