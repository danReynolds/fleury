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
        'programmatic亜',
        reason:
            'with composing cleared, commit inserts at the caret / replaces '
            'selection — it must not rewrite a stale (0,1) range into '
            '`亜rogrammatic`',
      );
    },
  );
}
