// Lock test: sticky pasteId / IME ownership must not keep delivering into a
// field that is still enabled+mounted but covered by ExcludeFocus (hidden tab,
// occluded route). Today sticky routing gates only on FocusNode.acceptsInput,
// which ignores ExcludeFocus — acceptsInput is the paint-error exclusion bit,
// not the focus-exclusion marker. Covered-but-enabled fields keep receiving
// mid-flight paste/composition after the pane is hidden.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'segmented paste does not continue into an ExcludeFocus-covered start owner',
    (tester) {
      final visibleNode = FocusNode(debugLabel: 'sticky-paste-visible');
      final hiddenNode = FocusNode(debugLabel: 'sticky-paste-hidden');
      addTearDown(visibleNode.dispose);
      addTearDown(hiddenNode.dispose);
      final visible = TextEditingController();
      final hidden = TextEditingController();
      addTearDown(visible.dispose);
      addTearDown(hidden.dispose);

      const policy = TextPastePolicy(largePasteThreshold: 0, chunkSize: 4);

      tester.pumpWidget(
        Column(
          children: [
            ExcludeFocus(
              excluding: false,
              child: TextInput(
                controller: hidden,
                focusNode: hiddenNode,
                autofocus: true,
                pastePolicy: policy,
              ),
            ),
            TextInput(
              controller: visible,
              focusNode: visibleNode,
              pastePolicy: policy,
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(40, 3));
      expect(hiddenNode.hasFocus, isTrue);

      const pasteId = 91;
      tester.dispatcher.dispatch(
        const PasteEvent.segment(
          'AAAA',
          pasteId: pasteId,
          phase: PasteEventPhase.start,
        ),
      );
      expect(hidden.text, 'AAAA');

      // Hide the start owner the way Tabs / Navigator do — ExcludeFocus on,
      // focus cleared from the covered pane, another field takes focus.
      tester.pumpWidget(
        Column(
          children: [
            ExcludeFocus(
              excluding: true,
              child: TextInput(
                controller: hidden,
                focusNode: hiddenNode,
                pastePolicy: policy,
              ),
            ),
            TextInput(
              controller: visible,
              focusNode: visibleNode,
              pastePolicy: policy,
            ),
          ],
        ),
      );
      tester.pump();
      visibleNode.requestFocus();
      tester.pump();
      expect(hiddenNode.hasFocus, isFalse);
      expect(visibleNode.hasFocus, isTrue);

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
      tester.pump();

      expect(
        hidden.text,
        'AAAA',
        reason:
            'ExcludeFocus promises the keyboard cannot stay in a hidden pane; '
            'sticky paste must not keep writing into a covered-but-enabled '
            'start owner (acceptsInput alone is the wrong gate)',
      );
      expect(
        visible.text,
        isEmpty,
        reason:
            'orphan sticky continuations must not fall through to the newly '
            'focused field either — same sticky-orphan contract as disable',
      );
    },
  );

  testWidgets(
    'IME commit does not land on an ExcludeFocus-covered composition owner',
    (tester) {
      final visibleNode = FocusNode(debugLabel: 'sticky-ime-visible');
      final hiddenNode = FocusNode(debugLabel: 'sticky-ime-hidden');
      addTearDown(visibleNode.dispose);
      addTearDown(hiddenNode.dispose);
      final visible = TextEditingController();
      final hidden = TextEditingController();
      addTearDown(visible.dispose);
      addTearDown(hidden.dispose);

      tester.pumpWidget(
        Column(
          children: [
            ExcludeFocus(
              excluding: false,
              child: TextInput(
                controller: hidden,
                focusNode: hiddenNode,
                autofocus: true,
              ),
            ),
            TextInput(controller: visible, focusNode: visibleNode),
          ],
        ),
      );
      tester.render(size: const CellSize(40, 3));

      tester.dispatcher.dispatch(const TextCompositionEvent.update('に'));
      expect(hidden.hasComposingRange, isTrue);
      expect(hidden.text, 'に');

      tester.pumpWidget(
        Column(
          children: [
            ExcludeFocus(
              excluding: true,
              child: TextInput(controller: hidden, focusNode: hiddenNode),
            ),
            TextInput(controller: visible, focusNode: visibleNode),
          ],
        ),
      );
      tester.pump();
      visibleNode.requestFocus();
      tester.pump();
      expect(visibleNode.hasFocus, isTrue);

      tester.dispatcher.dispatch(const TextCompositionEvent.commit('日本'));
      tester.pump();

      expect(
        hidden.text,
        isNot(equals('日本')),
        reason:
            'commit must not apply into a pane ExcludeFocus has covered; the '
            'sticky owner is still acceptsInput-true and still claims IME',
      );
      expect(
        visible.text,
        isEmpty,
        reason: 'orphan commit must not fall through to the live chain',
      );
    },
  );
}
