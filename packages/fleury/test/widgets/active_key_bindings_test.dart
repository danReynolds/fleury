import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void main() {
  testWidgets(
    'resolves live unshadowed aliases in dispatch order as immutable values',
    (tester) {
      final down = KeyChord.key(KeyCode.arrowDown);
      final next = KeyBinding.list(
        [KeyChord.char('j'), down],
        label: 'Next',
        onEvent: (_) {},
      );
      final scroll = KeyBinding(down, label: 'Scroll', onEvent: (_) {});
      final quit = KeyBinding(
        KeyChord.char('q'),
        label: 'Quit',
        onEvent: (_) {},
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
      expect(active.map((entry) => entry.chordLabel), ['↓', 'j', 'q']);
      expect(active[1].chords, [KeyChord.char('j')]);
      expect(() => active.add(active.first), throwsUnsupportedError);
      expect(
        () => active.first.chords.add(KeyChord.escape),
        throwsUnsupportedError,
      );
    },
  );

  testWidgets('omits printable aliases claimed by focused text input', (
    tester,
  ) {
    final mixed = KeyBinding.list(
      [KeyChord.char('j'), KeyChord.key(KeyCode.arrowDown)],
      label: 'Next',
      onEvent: (_) {},
    );
    final printable = KeyBinding(
      KeyChord.char('?'),
      label: 'Help',
      onEvent: (_) {},
    );

    tester.pumpWidget(
      KeyBindings(
        bindings: [mixed, printable],
        child: TextInput(autofocus: true),
      ),
    );

    final active = resolveActiveKeyBindings(tester.focusManager);

    expect(active.map((entry) => entry.binding), [mixed]);
    expect(active.single.chordLabel, '↓');
  });
}
