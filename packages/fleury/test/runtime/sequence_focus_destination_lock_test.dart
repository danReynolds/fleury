// Lock test: a text-origin step held by a pending sequence must replay into
// the field that was focused when it was typed — not whoever is focused when
// timeoutlen fires. Today `_replayHeld` calls `_deliverText` against the live
// focus chain, so a focus change mid-chord reroutes the held character.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'sequence timeout replays held printable to the field that owned it',
    (tester) async {
      final aNode = FocusNode(debugLabel: 'a');
      final bNode = FocusNode(debugLabel: 'b');
      addTearDown(aNode.dispose);
      addTearDown(bNode.dispose);
      final a = TextEditingController();
      final b = TextEditingController();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      var fired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.x.a.b, onTrigger: (_) => fired++),
          ],
          child: Column(
            children: [
              TextInput(controller: a, focusNode: aNode, autofocus: true),
              TextInput(controller: b, focusNode: bNode),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(40, 3));
      expect(aNode.hasFocus, isTrue);

      // Arm a multi-step chord, then hold a text-origin continuation.
      tester.sendKey(
        const KeyEvent(KeyCode.x, modifiers: {KeyModifier.ctrl}),
      );
      tester.dispatcher.dispatch(const TextInputEvent('a'));
      expect(a.text, isEmpty, reason: 'held while the chord lives');
      expect(tester.dispatcher.hasPendingSequence, isTrue);

      // Focus moves before timeoutlen.
      bNode.requestFocus();
      tester.pump();
      expect(bNode.hasFocus, isTrue);

      // Real Timer — same pattern as input_dispatcher_test 16l.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      tester.pump();

      expect(fired, 0);
      expect(
        a.text,
        'a',
        reason:
            'held printable was typed into A; timeout replay must not '
            'deliver it to B after focus moved',
      );
      expect(
        b.text,
        isEmpty,
        reason: 'newly focused field must not absorb another field\'s held char',
      );
    },
  );
}
