// Lock test: segmented paste must not split across fields when focus moves
// mid-transaction. The terminal emits one pasteId; the app that accepted
// `start` owns that paste until `end`, or the paste is finished/discarded on
// the original field — never silently continued into whoever is focused next.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'segmented paste continues on the field that accepted start after focus moves',
    (tester) {
      final firstNode = FocusNode(debugLabel: 'first');
      addTearDown(firstNode.dispose);
      final secondNode = FocusNode(debugLabel: 'second');
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
              // Force chunking so the start segment stays active while we
              // move focus before the continuation/end arrive.
              pastePolicy: const TextPastePolicy(
                largePasteThreshold: 0,
                chunkSize: 4,
              ),
            ),
            TextInput(
              controller: second,
              focusNode: secondNode,
              pastePolicy: const TextPastePolicy(
                largePasteThreshold: 0,
                chunkSize: 4,
              ),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(40, 3));
      expect(firstNode.hasFocus, isTrue);

      const pasteId = 42;
      tester.dispatcher.dispatch(
        const PasteEvent.segment(
          'AAAA',
          pasteId: pasteId,
          phase: PasteEventPhase.start,
        ),
      );
      // Start has been accepted by the focused field.
      expect(first.text, 'AAAA');
      expect(second.text, isEmpty);

      // User tabs / clicks away while the bracketed paste is still streaming.
      secondNode.requestFocus();
      tester.pump();
      expect(secondNode.hasFocus, isTrue);

      tester.dispatcher.dispatch(
        const PasteEvent.segment(
          'BBBB',
          pasteId: pasteId,
          phase: PasteEventPhase.continuation,
        ),
      );
      tester.dispatcher.dispatch(
        const PasteEvent.segment(
          'CCCC',
          pasteId: pasteId,
          phase: PasteEventPhase.end,
        ),
      );
      for (var i = 0; i < 20; i++) {
        tester.pump();
      }

      // Correctness: the whole paste lands on the original destination.
      // Current bug: continuations follow focus into `second`, leaving
      // `first` with a truncated paste and `second` with orphan mid/end
      // segments treated as a fresh paste.
      expect(
        first.text,
        'AAAABBBBCCCC',
        reason:
            'pasteId $pasteId was accepted by first; focus change must not '
            'reroute its remaining segments',
      );
      expect(
        second.text,
        isEmpty,
        reason:
            'the newly focused field must not absorb orphan continuation/'
            'end segments of another field\'s paste',
      );
    },
  );

  testWidgets(
    'IME composition commit stays on the field that owned the composition',
    (tester) {
      final firstNode = FocusNode(debugLabel: 'ime-first');
      addTearDown(firstNode.dispose);
      final secondNode = FocusNode(debugLabel: 'ime-second');
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

      tester.dispatcher.dispatch(const TextCompositionEvent.update('に'));
      expect(first.hasComposingRange, isTrue);
      expect(
        first.text.substring(first.composing.start, first.composing.end),
        'に',
      );

      secondNode.requestFocus();
      tester.pump();
      expect(secondNode.hasFocus, isTrue);

      tester.dispatcher.dispatch(const TextCompositionEvent.commit('日本'));
      tester.pump();

      // Commit must resolve on the field that held the composition, not the
      // newly focused empty field — otherwise the composing underline sticks
      // on first forever and second receives a commit with no prior update.
      expect(
        first.text,
        '日本',
        reason: 'commit belongs to the composition owner',
      );
      expect(first.hasComposingRange, isFalse);
      expect(second.text, isEmpty);
    },
  );
}
