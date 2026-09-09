// Lock test: sticky pasteId routing must not silently truncate when the
// start owner becomes disabled mid-paste. Today `_offerPasteTo` still aims
// at the sticky owner, but TextInput.onPasteEvent returns ignored when
// disabled — continuations/end are dropped and the paste is truncated.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'segmented paste is not truncated when the start owner is disabled mid-flight',
    (tester) {
      final firstNode = FocusNode(debugLabel: 'paste-excl-first');
      final secondNode = FocusNode(debugLabel: 'paste-excl-second');
      addTearDown(firstNode.dispose);
      addTearDown(secondNode.dispose);
      final first = TextEditingController();
      final second = TextEditingController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      const policy = TextPastePolicy(largePasteThreshold: 0, chunkSize: 4);

      tester.pumpWidget(
        Column(
          children: [
            TextInput(
              controller: first,
              focusNode: firstNode,
              autofocus: true,
              pastePolicy: policy,
            ),
            TextInput(
              controller: second,
              focusNode: secondNode,
              pastePolicy: policy,
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(40, 3));

      const pasteId = 77;
      tester.dispatcher.dispatch(
        const PasteEvent.segment(
          'AAAA',
          pasteId: pasteId,
          phase: PasteEventPhase.start,
        ),
      );
      expect(first.text, 'AAAA');

      tester.pumpWidget(
        Column(
          children: [
            TextInput(
              controller: first,
              focusNode: firstNode,
              enabled: false,
              pastePolicy: policy,
            ),
            TextInput(
              controller: second,
              focusNode: secondNode,
              pastePolicy: policy,
            ),
          ],
        ),
      );
      tester.pump();
      secondNode.requestFocus();
      tester.pump();

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

      expect(
        second.text,
        isEmpty,
        reason:
            'disabled-owner paste must not spill into the newly focused field',
      );
      expect(
        first.text,
        'AAAABBBBCCCC',
        reason:
            'preferred: keep applying sticky segments on the start owner. '
            'Acceptable alternate: discard the in-flight paste cleanly. '
            'Truncating to AAAA while ignoring BBBBCCCC is the bug.',
      );
    },
  );
}
