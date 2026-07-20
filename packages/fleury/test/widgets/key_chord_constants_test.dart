// Locks the named KeyChord constants used with Dart 3.10 dot-shorthand
// in KeyBinding declarations:
//   KeyBinding(keys: [.space, .ctrl.s, ...], onEvent: ...)
//
// Each constant should equal the same chord built via the escape-hatch
// constructor, match the corresponding KeyEvent, and (for non-special
// chords) carry the right hint label.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

KeyEvent _key(
  KeyCode k, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
}) => KeyEvent(
  k,
  modifiers: {
    if (ctrl) KeyModifier.ctrl,
    if (alt) KeyModifier.alt,
    if (shift) KeyModifier.shift,
  },
);

void main() {
  group('KeyChord named statics — equal escape-hatch long form', () {
    test('space equals KeyChord.char(\' \')', () {
      expect(KeyChord.space, const KeyChord.char(' '));
    });
    test('letter atoms equal KeyChord.char(...)', () {
      expect(KeyChord.a, const KeyChord.char('a'));
      expect(KeyChord.q, const KeyChord.char('q'));
      expect(KeyChord.z, const KeyChord.char('z'));
    });
    test('special chords equal KeyChord.key(...)', () {
      expect(KeyChord.enter, const KeyChord.key(KeyCode.enter));
      expect(KeyChord.escape, const KeyChord.key(KeyCode.escape));
      expect(KeyChord.tab, const KeyChord.key(KeyCode.tab));
      expect(KeyChord.up, const KeyChord.key(KeyCode.arrowUp));
      expect(KeyChord.down, const KeyChord.key(KeyCode.arrowDown));
      expect(KeyChord.left, const KeyChord.key(KeyCode.arrowLeft));
      expect(KeyChord.right, const KeyChord.key(KeyCode.arrowRight));
      expect(KeyChord.home, const KeyChord.key(KeyCode.home));
      expect(KeyChord.end, const KeyChord.key(KeyCode.end));
      expect(KeyChord.pageUp, const KeyChord.key(KeyCode.pageUp));
      expect(KeyChord.pageDown, const KeyChord.key(KeyCode.pageDown));
      expect(KeyChord.f1, const KeyChord.key(KeyCode.f1));
      expect(KeyChord.f12, const KeyChord.key(KeyCode.f12));
      expect(KeyChord.shiftTab, const KeyChord.key(KeyCode.tab, shift: true));
    });
  });

  group('KeyChord named statics — match the right events', () {
    test('.space matches a space char event', () {
      expect(KeyChord.space.matches(const KeyEvent(KeyCode.char(' '))), isTrue);
      expect(
        KeyChord.space.matches(const KeyEvent(KeyCode.char('a'))),
        isFalse,
      );
    });
    test('.enter / .escape / .tab match their keycodes', () {
      expect(KeyChord.enter.matches(_key(KeyCode.enter)), isTrue);
      expect(KeyChord.escape.matches(_key(KeyCode.escape)), isTrue);
      expect(KeyChord.tab.matches(_key(KeyCode.tab)), isTrue);
    });
    test('.shiftTab needs the shift modifier', () {
      expect(KeyChord.shiftTab.matches(_key(KeyCode.tab, shift: true)), isTrue);
      expect(
        KeyChord.shiftTab.matches(_key(KeyCode.tab)),
        isFalse,
        reason: 'bare Tab should not match Shift+Tab',
      );
    });
    test('arrow chords', () {
      expect(KeyChord.up.matches(_key(KeyCode.arrowUp)), isTrue);
      expect(KeyChord.down.matches(_key(KeyCode.arrowDown)), isTrue);
      expect(KeyChord.left.matches(_key(KeyCode.arrowLeft)), isTrue);
      expect(KeyChord.right.matches(_key(KeyCode.arrowRight)), isTrue);
    });
  });

  group('KeyBinding with dot-shorthand inside keys: list', () {
    testWidgets('typed list literal resolves .space / .enter to the statics', (
      tester,
    ) {
      var sp = 0;
      var en = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            // Dart resolves `.space` to `KeyChord.space` because the
            // list's element type is `KeyChord`.
            KeyBinding(.space, onEvent: (_) => sp++),
            KeyBinding(.enter, onEvent: (_) => en++),
          ],
          child: const Text('app'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(const KeyEvent(KeyCode.char(' ')));
      tester.pump();
      expect(sp, 1);

      tester.sendKey(_key(KeyCode.enter));
      tester.pump();
      expect(en, 1);
    });

    testWidgets('modifier chains: .ctrl.s, .alt.x, .ctrl.shift.p', (tester) {
      final fired = <String>[];
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(.ctrl.s, onEvent: (_) => fired.add('save')),
            KeyBinding(.alt.x, onEvent: (_) => fired.add('alt-x')),
            KeyBinding(.ctrl.shift.p, onEvent: (_) => fired.add('palette')),
          ],
          child: const Text('app'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(
        const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
      );
      tester.pump();
      tester.sendKey(
        const KeyEvent(KeyCode.char('x'), modifiers: {KeyModifier.alt}),
      );
      tester.pump();
      tester.sendKey(
        const KeyEvent(
          KeyCode.char('p'),
          modifiers: {KeyModifier.ctrl, KeyModifier.shift},
        ),
      );
      tester.pump();

      expect(fired, ['save', 'alt-x', 'palette']);
    });
  });

  group('strict modifier matching via the chain', () {
    testWidgets('Ctrl+Shift+Space fires only on the exact combo', (tester) {
      var fired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(.ctrl.shift.space, onEvent: (_) => fired++)],
          child: const Text('app'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      // Strict match: fires only on Ctrl+Shift+Space.
      tester.sendKey(
        const KeyEvent(
          KeyCode.char(' '),
          modifiers: {KeyModifier.ctrl, KeyModifier.shift},
        ),
      );
      tester.pump();
      expect(fired, 1);

      // Bare Ctrl+Space → no match.
      tester.sendKey(
        const KeyEvent(KeyCode.char(' '), modifiers: {KeyModifier.ctrl}),
      );
      tester.pump();
      expect(fired, 1);

      // Bare Space → no match.
      tester.sendKey(const KeyEvent(KeyCode.char(' ')));
      tester.pump();
      expect(fired, 1);
    });

    test('modifier order does not matter', () {
      expect(KeyChord.ctrl.shift.p, KeyChord.shift.ctrl.p);
      expect(KeyChord.ctrl.alt.shift.f5, KeyChord.shift.alt.ctrl.f5);
    });

    test('hint label puts modifiers in canonical Ctrl/Alt/Shift order', () {
      expect(KeyChord.shift.ctrl.p.hintLabel, 'Ctrl+Shift+P');
      expect(KeyChord.shift.alt.ctrl.space.hintLabel, 'Ctrl+Alt+Shift+Space');
      // Bare char keeps its lowercase hint.
      expect(KeyChord.a.hintLabel, 'a');
    });
  });

  group('sequences via the chain', () {
    testWidgets('vim-style .d.d fires after two events within the timeout', (
      tester,
    ) {
      var fired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(.d.d, onEvent: (_) => fired++)],
          child: const Text('app'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(const KeyEvent(KeyCode.char('d')));
      tester.pump();
      tester.sendKey(const KeyEvent(KeyCode.char('d')));
      tester.pump();
      expect(fired, 1);
    });

    testWidgets('Emacs-style .ctrl.x.ctrl.s fires through a 4-atom chain', (
      tester,
    ) {
      var fired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(.ctrl.x.ctrl.s, onEvent: (_) => fired++)],
          child: const Text('app'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(
        const KeyEvent(KeyCode.char('x'), modifiers: {KeyModifier.ctrl}),
      );
      tester.pump();
      tester.sendKey(
        const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
      );
      tester.pump();
      expect(fired, 1);
    });
  });
}
