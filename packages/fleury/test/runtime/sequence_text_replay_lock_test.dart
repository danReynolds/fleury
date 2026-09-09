// Lock tests for the two ways a held text step can go wrong on replay.
//
// A bare printable arrives as a TextInputEvent, so on the terminal surface it
// is BOTH a possible text insertion and a possible key binding. When it arms a
// prefix, the direct binding on the same key is deferred — and replay owes it
// to the key lane even when no field wanted the text.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  test(
    'an unclaimed held printable still fires its deferred binding',
    () async {
      var short = 0;
      var long = 0;
      final manager = FocusManager();
      final dispatcher = InputDispatcher(
        focusManager: manager,
        sequenceTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(dispatcher.dispose);
      final owner = BuildOwner();
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyBindings(
            bindings: [
              KeyBinding(KeySequence.char('d'), onTrigger: (_) => short++),
              KeyBinding(
                KeySequence.char('d').char('k'),
                onTrigger: (_) => long++,
              ),
            ],
            child: const Text('no text field here'),
          ),
        ),
      );

      dispatcher.dispatch(const TextInputEvent('d'));
      expect(short, 0, reason: 'ambiguous prefix defers the direct binding');

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        short,
        1,
        reason:
            'nothing claimed the text, so the key lane owes it the deferred '
            'binding — vim gg/g',
      );
      expect(long, 0);
      expect(
        dispatcher.hasPendingSequence,
        isFalse,
        reason: 'and the prefix closes, so the which-key popup goes away',
      );
    },
  );
}
