// Locks the named KeySequence constants used with Dart 3.10 dot-shorthand
// in KeyBinding declarations:
//   KeyBinding.event(keys: [.space, .ctrl.s, ...], onEvent: ...)
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
  group('KeySequence named statics — equal escape-hatch long form', () {
    test('space equals KeyCode.char(\' \')', () {
      expect(KeySequence.space, const KeyCode.char(' '));
    });
    test('letter atoms equal KeyCode.char(...)', () {
      expect(KeySequence.a, const KeyCode.char('a'));
      expect(KeySequence.q, const KeyCode.char('q'));
      expect(KeySequence.z, const KeyCode.char('z'));
    });
    test('special chords equal their KeyCode statics', () {
      expect(KeySequence.enter, KeyCode.enter);
      expect(KeySequence.escape, KeyCode.escape);
      expect(KeySequence.tab, KeyCode.tab);
      expect(KeySequence.up, KeyCode.arrowUp);
      expect(KeySequence.down, KeyCode.arrowDown);
      expect(KeySequence.left, KeyCode.arrowLeft);
      expect(KeySequence.right, KeyCode.arrowRight);
      expect(KeySequence.home, KeyCode.home);
      expect(KeySequence.end, KeyCode.end);
      expect(KeySequence.pageUp, KeyCode.pageUp);
      expect(KeySequence.pageDown, KeyCode.pageDown);
      expect(KeySequence.f1, KeyCode.f1);
      expect(KeySequence.f12, KeyCode.f12);
      expect(KeySequence.shiftTab, KeySequence.shift.tab);
    });
  });

  group('KeySequence named statics — match the right events', () {
    test('.space matches a space char event', () {
      expect(
        KeySequence.space.matches(const KeyEvent(KeyCode.char(' '))),
        isTrue,
      );
      expect(
        KeySequence.space.matches(const KeyEvent(KeyCode.char('a'))),
        isFalse,
      );
    });
    test('.enter / .escape / .tab match their keycodes', () {
      expect(KeySequence.enter.matches(_key(KeyCode.enter)), isTrue);
      expect(KeySequence.escape.matches(_key(KeyCode.escape)), isTrue);
      expect(KeySequence.tab.matches(_key(KeyCode.tab)), isTrue);
    });
    test('.shiftTab needs the shift modifier', () {
      expect(
        KeySequence.shiftTab.matches(_key(KeyCode.tab, shift: true)),
        isTrue,
      );
      expect(
        KeySequence.shiftTab.matches(_key(KeyCode.tab)),
        isFalse,
        reason: 'bare Tab should not match Shift+Tab',
      );
    });
    test('arrow chords', () {
      expect(KeySequence.up.matches(_key(KeyCode.arrowUp)), isTrue);
      expect(KeySequence.down.matches(_key(KeyCode.arrowDown)), isTrue);
      expect(KeySequence.left.matches(_key(KeyCode.arrowLeft)), isTrue);
      expect(KeySequence.right.matches(_key(KeyCode.arrowRight)), isTrue);
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
            // Dart resolves `.space` to `KeySequence.space` because the
            // list's element type is `KeySequence`.
            KeyBinding(.space, onTrigger: () => sp++),
            KeyBinding(.enter, onTrigger: () => en++),
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
            KeyBinding(.ctrl.s, onTrigger: () => fired.add('save')),
            KeyBinding(.alt.x, onTrigger: () => fired.add('alt-x')),
            KeyBinding(.ctrl.shift.p, onTrigger: () => fired.add('palette')),
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
          bindings: [KeyBinding(.ctrl.shift.space, onTrigger: () => fired++)],
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
      expect(KeySequence.ctrl.shift.p, KeySequence.shift.ctrl.p);
      expect(KeySequence.ctrl.alt.shift.f5, KeySequence.shift.alt.ctrl.f5);
    });

    test('hint label puts modifiers in canonical Ctrl/Alt/Shift order', () {
      expect(KeySequence.shift.ctrl.p.hintLabel, 'Ctrl+Shift+P');
      expect(
        KeySequence.shift.alt.ctrl.space.hintLabel,
        'Ctrl+Alt+Shift+Space',
      );
      // Bare char keeps its lowercase hint.
      expect(KeySequence.a.hintLabel, 'a');
    });
  });

  group('sequences via the chain', () {
    testWidgets('vim-style .d.d fires after two events within the timeout', (
      tester,
    ) {
      var fired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(.d.d, onTrigger: () => fired++)],
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
          bindings: [KeyBinding(.ctrl.x.ctrl.s, onTrigger: () => fired++)],
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
