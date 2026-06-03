import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/key_bindings.dart';
import 'package:test/test.dart';

KeyEvent _char(
  String c, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
}) {
  return KeyEvent(
    char: c,
    modifiers: {
      if (ctrl) KeyModifier.ctrl,
      if (alt) KeyModifier.alt,
      if (shift) KeyModifier.shift,
    },
  );
}

KeyEvent _code(
  KeyCode kc, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
}) {
  return KeyEvent(
    keyCode: kc,
    modifiers: {
      if (ctrl) KeyModifier.ctrl,
      if (alt) KeyModifier.alt,
      if (shift) KeyModifier.shift,
    },
  );
}

void main() {
  group('bare character atoms', () {
    test('letter static matches its char', () {
      expect(KeyChord.q.matches(_char('q')), isTrue);
    });

    test(
      'letter static does not match uppercase event (which carries implicit shift)',
      () {
        expect(KeyChord.q.matches(_char('Q')), isFalse);
      },
    );

    test('letter static rejects ctrl-modified events', () {
      expect(KeyChord.q.matches(_char('q', ctrl: true)), isFalse);
    });

    test('letter static rejects alt-modified events', () {
      expect(KeyChord.x.matches(_char('x', alt: true)), isFalse);
    });

    test('space has hint "Space"', () {
      expect(KeyChord.space.hintLabel, 'Space');
    });

    test('bare letter hint is lowercase', () {
      expect(KeyChord.q.hintLabel, 'q');
    });
  });

  group('escape-hatch char/key constructors are const', () {
    test('const KeyChord.char compiles and matches', () {
      const chord = KeyChord.char('q');
      expect(chord.matches(_char('q')), isTrue);
    });

    test('const KeyChord.char with strict modifiers matches exact combo', () {
      const chord = KeyChord.char('p', ctrl: true, shift: true);
      expect(chord.matches(_char('p', ctrl: true, shift: true)), isTrue);
      expect(
        chord.matches(_char('p', ctrl: true)),
        isFalse,
        reason: 'strict shift: ctrl+P should NOT match ctrl+shift+P',
      );
    });

    test('const KeyChord.key with modifiers', () {
      const chord = KeyChord.key(KeyCode.arrowUp, ctrl: true);
      expect(chord.matches(_code(KeyCode.arrowUp, ctrl: true)), isTrue);
      expect(chord.matches(_code(KeyCode.arrowUp)), isFalse);
    });
  });

  group('modifier chain — KeyChord.ctrl.x', () {
    test('Ctrl+S matches', () {
      expect(KeyChord.ctrl.s.matches(_char('s', ctrl: true)), isTrue);
    });

    test('Ctrl+S rejects without Ctrl', () {
      expect(KeyChord.ctrl.s.matches(_char('s')), isFalse);
    });

    test('Ctrl+S rejects with extra Shift (strict)', () {
      expect(
        KeyChord.ctrl.s.matches(_char('s', ctrl: true, shift: true)),
        isFalse,
      );
    });

    test('Ctrl+Shift+P matches in either chain order', () {
      final a = KeyChord.ctrl.shift.p;
      final b = KeyChord.shift.ctrl.p;
      expect(a == b, isTrue, reason: 'modifier order should not matter');
      expect(a.matches(_char('p', ctrl: true, shift: true)), isTrue);
    });

    test('Alt+X matches', () {
      expect(KeyChord.alt.x.matches(_char('x', alt: true)), isTrue);
    });

    test('hint label is "Ctrl+S" (uppercase letter)', () {
      expect(KeyChord.ctrl.s.hintLabel, 'Ctrl+S');
    });

    test('hint label for triple-modifier', () {
      expect(KeyChord.ctrl.shift.p.hintLabel, 'Ctrl+Shift+P');
    });

    test(
      'escape-hatch char on PendingKeyChord supports digits / punctuation',
      () {
        final altOne = KeyChord.alt.char('1');
        expect(altOne.matches(_char('1', alt: true)), isTrue);
      },
    );

    test(
      'escape-hatch key on PendingKeyChord supports KeyCode-valued atoms',
      () {
        final chord = KeyChord.ctrl.key(KeyCode.f5);
        expect(chord.matches(_code(KeyCode.f5, ctrl: true)), isTrue);
      },
    );
  });

  group('Shift+letter canonicalization', () {
    test('.shift.d matches event with shift modifier set + lowercase char', () {
      expect(KeyChord.shift.d.matches(_char('d', shift: true)), isTrue);
    });

    test(
      '.shift.d matches uppercase char without modifier flag (implicit shift)',
      () {
        expect(
          KeyChord.shift.d.matches(_char('D')),
          isTrue,
          reason:
              'terminals reporting D without explicit shift should still match shift.d',
        );
      },
    );

    test('.shift.d matches uppercase char WITH modifier flag', () {
      expect(KeyChord.shift.d.matches(_char('D', shift: true)), isTrue);
    });

    test(
      '.d does NOT match uppercase D (implicit shift breaks bare letter)',
      () {
        expect(KeyChord.d.matches(_char('D')), isFalse);
      },
    );
  });

  group('special-key statics', () {
    test('escape matches', () {
      expect(KeyChord.escape.matches(_code(KeyCode.escape)), isTrue);
    });

    test('arrows reject modifier mismatch', () {
      expect(KeyChord.up.matches(_code(KeyCode.arrowUp, ctrl: true)), isFalse);
    });

    test('Ctrl+arrow chain matches', () {
      expect(
        KeyChord.ctrl.up.matches(_code(KeyCode.arrowUp, ctrl: true)),
        isTrue,
      );
    });

    test('arrow hint uses direction symbol', () {
      expect(KeyChord.up.hintLabel, '↑');
      expect(KeyChord.ctrl.up.hintLabel, 'Ctrl+↑');
    });

    test('shiftTab static', () {
      expect(
        KeyChord.shiftTab.matches(_code(KeyCode.tab, shift: true)),
        isTrue,
      );
      expect(KeyChord.shiftTab.matches(_code(KeyCode.tab)), isFalse);
    });
  });

  group('sequences (multi-step chords)', () {
    test('.d.d (vim-style) has two steps', () {
      final seq = KeyChord.d.d;
      expect(seq.isSequence, isTrue);
      expect(seq.stepCount, 2);
    });

    test('matches() returns true for first step only', () {
      final seq = KeyChord.space.q;
      expect(seq.matches(_char(' ')), isTrue);
      expect(
        seq.matches(_char('q')),
        isFalse,
        reason:
            'matches() checks step 0 only; dispatcher walks subsequent steps',
      );
    });

    test('matchesStepAt walks the steps', () {
      final seq = KeyChord.space.q;
      expect(seq.matchesStepAt(0, _char(' ')), isTrue);
      expect(seq.matchesStepAt(1, _char('q')), isTrue);
      expect(
        seq.matchesStepAt(2, _char('x')),
        isFalse,
        reason: 'out-of-bound step index returns false',
      );
    });

    test('Emacs-style C-x C-s has four atoms but two steps', () {
      final seq = KeyChord.ctrl.x.ctrl.s;
      expect(seq.stepCount, 2);
      expect(seq.matchesStepAt(0, _char('x', ctrl: true)), isTrue);
      expect(seq.matchesStepAt(1, _char('s', ctrl: true)), isTrue);
    });

    test('hint label joins steps with spaces', () {
      expect(KeyChord.space.p.hintLabel, 'Space p');
      expect(KeyChord.ctrl.x.ctrl.s.hintLabel, 'Ctrl+X Ctrl+S');
    });

    test('equality compares step-by-step', () {
      expect(KeyChord.d.d == KeyChord.d.d, isTrue);
      expect(KeyChord.d.d == KeyChord.d.k, isFalse);
      expect(KeyChord.ctrl.x.ctrl.s == KeyChord.ctrl.x.ctrl.s, isTrue);
    });

    test('chain across mods+seq: shift.g.g (Shift+G then G)', () {
      final seq = KeyChord.shift.g.g;
      expect(seq.stepCount, 2);
      expect(seq.matchesStepAt(0, _char('G')), isTrue);
      expect(seq.matchesStepAt(1, _char('g')), isTrue);
    });
  });

  group('idempotency and escape-hatch parity', () {
    test('.ctrl.ctrl.s equals .ctrl.s (modifier idempotent)', () {
      expect(KeyChord.ctrl.ctrl.s, KeyChord.ctrl.s);
    });

    test('.shift.shift.d equals .shift.d', () {
      expect(KeyChord.shift.shift.d, KeyChord.shift.d);
    });

    test('.ctrl.alt.ctrl.s equals .ctrl.alt.s', () {
      expect(KeyChord.ctrl.alt.ctrl.s, KeyChord.ctrl.alt.s);
    });

    test('uppercase escape hatch behaves like .shift.<letter>', () {
      // KeyChord.char('A') canonicalizes uppercase → shift-asserted.
      // It should match the same events as KeyChord.shift.a.
      const upper = KeyChord.char('A');
      final chain = KeyChord.shift.a;
      expect(upper.matches(_char('A')), isTrue);
      expect(upper.matches(_char('a', shift: true)), isTrue);
      expect(upper.matches(_char('a')), isFalse);
      // Match parity with the chain form on the same events.
      expect(chain.matches(_char('A')), isTrue);
      expect(chain.matches(_char('a', shift: true)), isTrue);
      expect(chain.matches(_char('a')), isFalse);
    });
  });

  group('equality / hashCode', () {
    test('two equal chords have equal hashCodes', () {
      final a = KeyChord.ctrl.s;
      final b = KeyChord.ctrl.s;
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('chords with same atom but different modifier mask differ', () {
      expect(KeyChord.ctrl.s == KeyChord.alt.s, isFalse);
    });

    test('escape-hatch and chain produce equal chords', () {
      expect(KeyChord.ctrl.s == const KeyChord.char('s', ctrl: true), isTrue);
    });

    test('canonical equality: uppercase letter equals .shift.<letter>', () {
      // Both fire on the same events, so they must hash and compare
      // equal — otherwise they'd collide as distinct map chords.
      const upper = KeyChord.char('S');
      final chain = KeyChord.shift.s;
      const explicit = KeyChord.char('s', shift: true);
      expect(upper, chain);
      expect(upper.hashCode, chain.hashCode);
      expect(upper, explicit);
      expect(explicit, chain);
    });

    test('canonical equality holds inside sequences', () {
      expect(KeyChord.shift.g.g, const KeyChord.char('G').g);
      expect(
        (KeyChord.shift.g.g).hashCode,
        (const KeyChord.char('G').g).hashCode,
      );
    });

    test('uppercase letter as a Map key collides with .shift.<letter>', () {
      final m = <KeyChord, String>{};
      m[const KeyChord.char('S')] = 'first';
      m[KeyChord.shift.s] = 'second';
      // Same canonical chord → single entry, last write wins.
      expect(m.length, 1);
      expect(m.values.first, 'second');
    });
  });

  group('non-ASCII characters', () {
    test('lowercase accented char matches itself', () {
      const chord = KeyChord.char('é');
      expect(chord.matches(_char('é')), isTrue);
      expect(chord.matches(_char('e')), isFalse);
    });

    test('uppercase accented char canonicalises to shift', () {
      // 'É' → toLowerCase = 'é', differs, so shift is implicit.
      expect(
        const KeyChord.char('É'),
        equals(const KeyChord.char('é', shift: true)),
      );
    });

    test('digits via the escape hatch', () {
      const five = KeyChord.char('5');
      expect(five.matches(_char('5')), isTrue);
      expect(five.matches(_char('6')), isFalse);
      // Digits aren't case-bearing; explicit shift stays distinct.
      expect(five == const KeyChord.char('5', shift: true), isFalse);
    });

    test('punctuation via the escape hatch', () {
      const slash = KeyChord.char('/');
      expect(slash.matches(_char('/')), isTrue);
      expect(
        slash.matches(_char('?')),
        isFalse,
        reason: 'no implicit shift fold across distinct unicode codepoints',
      );
    });

    test('chained with modifiers: .ctrl.char(\'/\')', () {
      final chord = KeyChord.ctrl.char('/');
      expect(chord.matches(_char('/', ctrl: true)), isTrue);
      expect(chord.matches(_char('/')), isFalse);
    });

    // Known limitation: Dart's String.toLowerCase() does not apply
    // locale-specific rules (Turkish dotted-I, etc.). Bindings to
    // characters in those scripts may not canonicalise as expected;
    // users should bind the explicit form (KeyChord.char('İ') /
    // KeyChord.char('i', shift: true)) and not mix them.
  });

  group('KeyBinding', () {
    test('matches when any of its chords matches', () {
      final binding = KeyBinding.list([
        KeyChord.j,
        KeyChord.down,
      ], onEvent: (_) {});
      expect(binding.chords.length, 2);
      expect(binding.chords.first.matches(_char('j')), isTrue);
      expect(binding.chords[1].matches(_code(KeyCode.arrowDown)), isTrue);
    });

    test('handler fires when invoked', () {
      var fired = 0;
      final binding = KeyBinding(KeyChord.a, onEvent: (_) => fired += 1);
      binding.onEvent(KeyBindingEvent(_char('a')));
      expect(fired, 1);
    });

    test('displayLabel falls back to first chord hintLabel', () {
      final binding = KeyBinding(KeyChord.q, onEvent: (_) {});
      expect(binding.displayLabel, 'q');
    });

    test('explicit label overrides the chord default', () {
      final binding = KeyBinding.list(
        [KeyChord.j, KeyChord.down],
        onEvent: (_) {},
        label: 'j/↓',
      );
      expect(binding.displayLabel, 'j/↓');
    });

    test('event.bubble() flips a handler from absorb to passthrough', () {
      // Handler runs unconditionally; calling bubble() declares
      // intent to let the event continue propagating.
      var fired = 0;
      final absorbing = KeyBinding(KeyChord.a, onEvent: (_) => fired += 1);
      final absorbEvent = KeyBindingEvent(_char('a'));
      absorbing.onEvent(absorbEvent);
      expect(fired, 1);
      expect(absorbEvent.isBubbling, isFalse);

      final bubbling = KeyBinding(
        KeyChord.a,
        onEvent: (event) {
          fired += 1;
          event.bubble();
        },
      );
      final bubbleEvent = KeyBindingEvent(_char('a'));
      bubbling.onEvent(bubbleEvent);
      expect(fired, 2);
      expect(bubbleEvent.isBubbling, isTrue);
    });
  });
}
