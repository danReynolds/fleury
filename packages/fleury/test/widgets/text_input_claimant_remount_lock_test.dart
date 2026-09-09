// Lock test: when a TextInput that owns a FocusNode's claimants is disposed
// during a tree replace, its dispose must not clobber claimants already
// installed by a newly mounted TextInput on the same FocusNode. Today dispose
// unconditionally nulls the claimants, and Column→single-field rebuild mounts
// the survivor before the departing sibling's dispose runs — leaving a
// focused field that silently drops typed text / IME / paste.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'replacing a Column of fields with one field keeps the survivor claiming',
    (tester) {
      final firstNode = FocusNode(debugLabel: 'first');
      final secondNode = FocusNode(debugLabel: 'second');
      addTearDown(firstNode.dispose);
      addTearDown(secondNode.dispose);
      final first = TextEditingController();
      final second = TextEditingController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      tester.pumpWidget(
        Column(
          children: [
            TextInput(controller: first, focusNode: firstNode, autofocus: true),
            TextInput(controller: second, focusNode: secondNode),
          ],
        ),
      );
      tester.render(size: const CellSize(40, 3));
      expect(secondNode.textInputClaimant, isNotNull);

      tester.pumpWidget(
        TextInput(controller: second, focusNode: secondNode, autofocus: true),
      );
      tester.pump();

      expect(secondNode.hasFocus, isTrue);
      expect(
        secondNode.textInputClaimant,
        isNotNull,
        reason:
            'survivor TextInput must still claim text after sibling unmount '
            'rebuild; departing State.dispose nulled the claimants after the '
            'new State attached them',
      );
      expect(secondNode.textCompositionClaimant, isNotNull);
      tester.dispatcher.dispatch(const TextInputEvent('z'));
      expect(
        second.text,
        'z',
        reason: 'typed text must reach the remounted survivor field',
      );
    },
  );
}
