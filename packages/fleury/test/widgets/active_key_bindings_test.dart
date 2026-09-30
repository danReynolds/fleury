import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void main() {
  testWidgets(
    'resolves live unshadowed aliases in dispatch order as immutable values',
    (tester) {
      final down = KeyCode.arrowDown;
      final next = KeyBinding(
        KeyCode.char('j'),
        aliases: [down],
        label: 'Next',
        onTrigger: (_) {},
      );
      final scroll = KeyBinding(down, label: 'Scroll', onTrigger: (_) {});
      final quit = KeyBinding(
        KeyCode.char('q'),
        label: 'Quit',
        onTrigger: (_) {},
      );

      tester.pumpWidget(
        KeyBindings(
          bindings: [quit],
          child: KeyBindings(
            bindings: [next],
            child: KeyBindings(
              bindings: [scroll],
              child: const Focus(autofocus: true, child: Text('Body')),
            ),
          ),
        ),
      );

      final active = resolveActiveKeyBindings(tester.focusManager);

      expect(active.map((entry) => entry.binding), [scroll, next, quit]);
      expect(active.map((entry) => entry.sequenceLabel), ['↓', 'j', 'q']);
      expect(active[1].sequences, [KeyCode.char('j')]);
      expect(() => active.add(active.first), throwsUnsupportedError);
      expect(
        () => active.first.sequences.add(KeySequence.escape),
        throwsUnsupportedError,
      );
    },
  );

  testWidgets('omits printable aliases claimed by focused text input', (
    tester,
  ) {
    final mixed = KeyBinding(
      KeyCode.char('j'),
      aliases: [KeyCode.arrowDown],
      label: 'Next',
      onTrigger: (_) {},
    );
    final printable = KeyBinding(
      KeyCode.char('?'),
      label: 'Help',
      onTrigger: (_) {},
    );

    tester.pumpWidget(
      KeyBindings(
        bindings: [mixed, printable],
        child: TextInput(autofocus: true),
      ),
    );

    final active = resolveActiveKeyBindings(tester.focusManager);

    expect(active.map((entry) => entry.binding), [mixed]);
    expect(active.single.sequenceLabel, '↓');
  });

  group('a modal scope', () {
    testWidgets('ends resolution where it ends dispatch', (tester) {
      var quits = 0;
      final quit = KeyBinding(
        KeyCode.char('q'),
        label: 'Quit',
        onTrigger: (_) => quits++,
      );
      final confirm = KeyBinding(
        KeyCode.char('y'),
        label: 'Confirm',
        onTrigger: (_) {},
      );
      final next = KeyBinding(
        KeyCode.arrowDown,
        label: 'Next',
        onTrigger: (_) {},
      );

      tester.pumpWidget(
        KeyBindings(
          bindings: [quit],
          child: KeyBindings(
            modal: true,
            bindings: [confirm],
            child: KeyBindings(
              bindings: [next],
              child: const Focus(autofocus: true, child: Text('Dialog')),
            ),
          ),
        ),
      );

      expect(
        resolveActiveKeyBindings(tester.focusManager).map((e) => e.binding),
        [next, confirm],
        reason: 'the modal scope and what is inside it, nothing beyond',
      );
      tester.sendKey(const KeyEvent(KeyCode.q));
      expect(quits, 0, reason: 'dispatch never reaches the binding either');
    });

    testWidgets('lists a passthrough by the binding that lets it through', (
      tester,
    ) {
      // The documented way to let one key out of a modal scope: bind it
      // there and bubble. Whether a handler bubbles is decided when it runs,
      // so resolution lists the binding at the scope, under its own label.
      var quits = 0;
      final quit = KeyBinding(
        KeySequence.ctrl.q,
        label: 'Quit',
        onTrigger: (_) => quits++,
      );
      final letOut = KeyBinding(
        KeySequence.ctrl.q,
        label: 'Quit app',
        onTrigger: (event) => event.bubble(),
      );

      tester.pumpWidget(
        KeyBindings(
          bindings: [quit],
          child: KeyBindings(
            modal: true,
            bindings: [letOut],
            child: const Focus(autofocus: true, child: Text('Dialog')),
          ),
        ),
      );

      expect(
        resolveActiveKeyBindings(tester.focusManager).map((e) => e.binding),
        [letOut],
      );
      tester.sendKey(const KeyEvent(KeyCode.q, modifiers: {KeyModifier.ctrl}));
      expect(quits, 1, reason: 'the bubbled key does reach the app binding');
    });
  });
}
