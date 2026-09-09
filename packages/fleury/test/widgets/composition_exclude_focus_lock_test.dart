// Lock test: sticky IME ownership must not fall through to the live focus
// chain when the composition owner stops claiming (disabled → claimants
// cleared via `_syncClaimants`). Today `_deliverComposition` retries the
// live chain after the sticky owner declines, so a commit lands on whoever
// is newly focused.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'IME commit does not fall through after the composition owner is disabled',
    (tester) {
      final firstNode = FocusNode(debugLabel: 'ime-excl-first');
      final secondNode = FocusNode(debugLabel: 'ime-excl-second');
      addTearDown(firstNode.dispose);
      addTearDown(secondNode.dispose);
      final first = TextEditingController();
      final second = TextEditingController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      tester.pumpWidget(
        Column(
          children: [
            TextInput(
              controller: first,
              focusNode: firstNode,
              autofocus: true,
            ),
            TextInput(controller: second, focusNode: secondNode),
          ],
        ),
      );
      tester.render(size: const CellSize(40, 3));

      tester.dispatcher.dispatch(const TextCompositionEvent.update('に'));
      expect(first.hasComposingRange, isTrue);
      expect(first.text, 'に');

      // Disable clears textCompositionClaimant via _syncClaimants while the
      // dispatcher still holds this node as sticky composition owner.
      tester.pumpWidget(
        Column(
          children: [
            TextInput(
              controller: first,
              focusNode: firstNode,
              enabled: false,
            ),
            TextInput(controller: second, focusNode: secondNode),
          ],
        ),
      );
      tester.pump();
      secondNode.requestFocus();
      tester.pump();
      expect(secondNode.hasFocus, isTrue);

      tester.dispatcher.dispatch(const TextCompositionEvent.commit('日本'));
      tester.pump();

      expect(
        second.text,
        isEmpty,
        reason:
            'commit must not fall through to the live chain after the sticky '
            'owner declines; that is how an orphan commit lands on second',
      );
      expect(second.hasComposingRange, isFalse);
    },
  );
}
