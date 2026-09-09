// Lock test (audit 2.c): a multi-step sequence declared ON a modal
// KeyBindings scope must be able to arm. Today `_dispatchPlain` returns at
// the modal boundary before `_startPending` runs, so sequenceCandidates
// collected on the modal itself are discarded and the chord never starts.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'a multi-step sequence on a modal KeyBindings scope can arm and complete',
    (tester) {
      var fired = 0;
      var appSaw = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(KeyCode.x, onTrigger: (_) => appSaw++)],
          child: KeyBindings(
            modal: true,
            bindings: [
              KeyBinding(KeySequence.ctrl.x.a, onTrigger: (_) => fired++),
            ],
            child: const Focus(autofocus: true, child: Text('dialog')),
          ),
        ),
      );
      tester.render(size: const CellSize(40, 3));

      tester.sendKey(const KeyEvent(KeyCode.x, modifiers: {KeyModifier.ctrl}));
      expect(
        tester.dispatcher.hasPendingSequence,
        isTrue,
        reason:
            'modal boundary must not discard sequence-start candidates that '
            'were collected on the modal scope itself',
      );
      expect(fired, 0);
      expect(appSaw, 0, reason: 'modal must still suppress the app behind');

      tester.sendKey(const KeyEvent(KeyCode.a));
      expect(fired, 1);
      expect(tester.dispatcher.hasPendingSequence, isFalse);
      expect(appSaw, 0);
    },
  );
}
