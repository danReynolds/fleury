// Lock test (audit 2.f): after a mid-session demotion to press-only, a
// KeyBinding.hold must stay inert. Demotion correctly synthesizes ends for
// in-flight holds, but KeyBindings never re-runs `_syncHoldObserver` on the
// capability flip — the observation-lane registration survives, so the next
// press re-latches a hold that can never receive a real release.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'after held-state demotion, the next press does not re-latch a hold',
    (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final log = <String>[];
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding.hold(
              KeyCode.space,
              onHoldStart: (_) => log.add('start'),
              onHoldEnd: (_) => log.add('end'),
            ),
          ],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.render(size: const CellSize(20, 3));

      // Prove the hold works under full capabilities.
      tester.sendKey(const KeyEvent(KeyCode.space, type: KeyEventType.down));
      expect(log, ['start']);
      tester.sendKey(const KeyEvent(KeyCode.space, type: KeyEventType.up));
      expect(log, ['start', 'end']);
      log.clear();

      // Mid-session loss of held-state (demotion / renegotiation downgrade).
      // Closes any open hold via observation-lane releases, but today leaves
      // the KeyBindings observer registered.
      tester.keyboardCapabilities = KeyboardCapabilities.legacy;

      tester.sendKey(const KeyEvent(KeyCode.space, type: KeyEventType.down));
      expect(
        log,
        isEmpty,
        reason:
            'after demotion the hold must be inert — same contract as a '
            'surface that never reported held state. Re-latching here starts '
            'a hold that can never end',
      );

      // Even a synthesized/legacy "up" must not invent an end for a start
      // that should never have fired.
      tester.sendKey(const KeyEvent(KeyCode.space, type: KeyEventType.up));
      expect(log, isEmpty);
    },
  );
}
