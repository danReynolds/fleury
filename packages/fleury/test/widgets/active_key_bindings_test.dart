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
          bindings: [next],
          child: KeyBindings(
            bindings: [scroll],
            child: const Focus(autofocus: true, child: Text('Body')),
          ),
        ),
      );

      final active = resolveActiveKeyBindings(
        tester.focusManager,
        globalBindings: [quit],
      );

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
}
