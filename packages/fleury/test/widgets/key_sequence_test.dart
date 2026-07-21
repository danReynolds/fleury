import 'package:fleury/fleury.dart';
// Direct src imports: KeySequenceMatch / KeyBindingEvent (key_bindings) and
// the framework-internal $KeySequenceInternal step hooks (events).
import 'package:fleury/src/input/events.dart';
import 'package:fleury/src/widgets/key_bindings.dart';
import 'package:test/test.dart';

KeyEvent _char(
  String c, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
  bool superKey = false,
  bool meta = false,
  KeyEventType type = KeyEventType.down,
}) => KeyEvent(
  KeyCode.char(c),
  type: type,
  modifiers: {
    if (ctrl) KeyModifier.ctrl,
    if (alt) KeyModifier.alt,
    if (shift) KeyModifier.shift,
    if (superKey) KeyModifier.superKey,
    if (meta) KeyModifier.meta,
  },
);

KeyEvent _code(
  KeyCode kc, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
  bool superKey = false,
}) => KeyEvent(
  kc,
  modifiers: {
    if (ctrl) KeyModifier.ctrl,
    if (alt) KeyModifier.alt,
    if (shift) KeyModifier.shift,
    if (superKey) KeyModifier.superKey,
  },
);

KeyBindingEvent _bindingEvent(KeySequence sequence, KeyEvent event) =>
    KeyBindingEvent(KeySequenceMatch(sequence, [event]));

void main() {
  group('KeyCode is a one-step KeySequence', () {
    test('a bare KeyCode matches its char', () {
      expect(KeyCode.q.matches(_char('q')), isTrue);
    });

    test('KeyCode.a and KeyCode.char("a") are one value', () {
      expect(KeyCode.a, KeyCode.char('a'));
      expect(KeyCode.a.hashCode, KeyCode.char('a').hashCode);
    });

    test('a bare letter does not match its uppercase (implicit shift)', () {
      expect(KeyCode.q.matches(_char('Q')), isFalse);
    });

    test('a bare letter rejects ctrl/alt/super/meta-modified events', () {
      expect(KeyCode.q.matches(_char('q', ctrl: true)), isFalse);
      expect(KeyCode.x.matches(_char('x', alt: true)), isFalse);
      expect(KeyCode.s.matches(_char('s', superKey: true)), isFalse);
      expect(KeyCode.s.matches(_char('s', meta: true)), isFalse);
    });

    test('char() escape hatch matches, is const-eligible', () {
      const seq = KeyCode.char('?');
      expect(seq.matches(_char('?')), isTrue);
      expect(seq.hintLabel, '?');
    });

    test('bare letter / space hints', () {
      expect(KeyCode.q.hintLabel, 'q');
      expect(KeyCode.space.hintLabel, 'Space');
    });
  });

  group('modifier chain — .ctrl.s etc.', () {
    test('Ctrl+S matches; rejects without Ctrl or with extra Shift', () {
      expect(KeySequence.ctrl.s.matches(_char('s', ctrl: true)), isTrue);
      expect(KeySequence.ctrl.s.matches(_char('s')), isFalse);
      expect(
        KeySequence.ctrl.s.matches(_char('s', ctrl: true, shift: true)),
        isFalse,
        reason: 'strict: Ctrl+Shift+S must not match Ctrl+S',
      );
    });

    test('Ctrl+Shift+P is order-agnostic and matches', () {
      final a = KeySequence.ctrl.shift.p;
      final b = KeySequence.shift.ctrl.p;
      expect(a, b, reason: 'modifier order should not matter');
      expect(a.matches(_char('p', ctrl: true, shift: true)), isTrue);
    });

    test('modifier stacking is idempotent', () {
      expect(KeySequence.ctrl.ctrl.s, KeySequence.ctrl.s);
      expect(KeySequence.ctrl.alt.ctrl.s, KeySequence.ctrl.alt.s);
    });

    test('hint labels', () {
      expect(KeySequence.ctrl.s.hintLabel, 'Ctrl+S');
      expect(KeySequence.ctrl.shift.p.hintLabel, 'Ctrl+Shift+P');
    });

    test('dynamic atoms via char()/code()', () {
      expect(KeySequence.alt.char('1').matches(_char('1', alt: true)), isTrue);
      expect(
        KeySequence.ctrl
            .code(KeyCode.f5)
            .matches(_code(KeyCode.f5, ctrl: true)),
        isTrue,
      );
    });
  });

  group('super / meta are first-class and strict', () {
    test('Super+K matches only Super+K', () {
      final k = KeySequence.superKey.k;
      expect(k.matches(_char('k', superKey: true)), isTrue);
      expect(k.matches(_char('k')), isFalse);
      expect(k.matches(_char('k', ctrl: true)), isFalse);
    });

    test('Meta+X matches only Meta+X', () {
      final x = KeySequence.meta.x;
      expect(x.matches(_char('x', meta: true)), isTrue);
      expect(x.matches(_char('x')), isFalse);
    });

    test(
      'REGRESSION: a bare binding does not fire on a Super/Meta-modified event',
      () {
        // The pre-RFC-0018 matcher ignored Super/Meta, so ⌘S (which the
        // browser surface reports as Super+s) wrongly fired a bare `.s`.
        expect(KeySequence.s.matches(_char('s', superKey: true)), isFalse);
        expect(KeySequence.s.matches(_char('s', meta: true)), isFalse);
      },
    );

    test('Super/Meta chords are NOT text-shadowed', () {
      // A bare printable is shadowed by a focused editable; a Super/Meta
      // chord arrives as a key event, so it stays firable.
      expect(KeySequence.s.isShadowedByTextInput, isTrue);
      expect(KeySequence.superKey.s.isShadowedByTextInput, isFalse);
      expect(KeySequence.meta.s.isShadowedByTextInput, isFalse);
    });

    test('hint labels render Super/Meta', () {
      expect(KeySequence.superKey.k.hintLabel, 'Super+K');
      expect(KeySequence.meta.enter.hintLabel, 'Meta+Enter');
    });
  });

  group('Shift+letter canonicalisation', () {
    test('.shift.d matches shift+d, uppercase D, and D+shift', () {
      final shiftD = KeySequence.shift.d;
      expect(shiftD.matches(_char('d', shift: true)), isTrue);
      expect(
        shiftD.matches(_char('D')),
        isTrue,
        reason: 'a terminal reporting bare uppercase D still matches',
      );
      expect(shiftD.matches(_char('D', shift: true)), isTrue);
    });

    test('bare .d does not match uppercase D', () {
      expect(KeySequence.d.matches(_char('D')), isFalse);
    });

    test('.shift.g and KeyCode.char("G") are one value', () {
      expect(KeySequence.shift.g, KeyCode.char('G'));
      expect(KeySequence.shift.g.hashCode, KeyCode.char('G').hashCode);
    });

    test('uppercase letter collides with .shift.<letter> as a map key', () {
      final m = <KeySequence, String>{};
      m[KeyCode.char('S')] = 'first';
      m[KeySequence.shift.s] = 'second';
      expect(m.length, 1, reason: 'same canonical sequence → single entry');
      expect(m.values.first, 'second');
    });
  });

  group('special keys', () {
    test('escape / arrows match; arrows reject modifier mismatch', () {
      expect(KeySequence.escape.matches(_code(KeyCode.escape)), isTrue);
      expect(
        KeySequence.up.matches(_code(KeyCode.arrowUp, ctrl: true)),
        isFalse,
      );
      expect(
        KeySequence.ctrl.up.matches(_code(KeyCode.arrowUp, ctrl: true)),
        isTrue,
      );
    });

    test('arrow hints use direction symbols', () {
      expect(KeySequence.up.hintLabel, '↑');
      expect(KeySequence.ctrl.up.hintLabel, 'Ctrl+↑');
    });

    test('shiftTab matches Shift+Tab only', () {
      expect(
        KeySequence.shiftTab.matches(_code(KeyCode.tab, shift: true)),
        isTrue,
      );
      expect(KeySequence.shiftTab.matches(_code(KeyCode.tab)), isFalse);
    });
  });

  group('multi-step sequences', () {
    test('.d.d has two steps; matches() checks step 0 only', () {
      final seq = KeySequence.d.d;
      expect(seq.isSequence, isTrue);
      expect(seq.stepCount, 2);
      expect(seq.matches(_char('d')), isTrue);
    });

    test('.space.q — matchesStepAt walks the steps', () {
      final seq = KeySequence.space.q;
      expect(seq.matchesStepAt(0, _char(' ')), isTrue);
      expect(seq.matchesStepAt(1, _char('q')), isTrue);
      expect(seq.matchesStepAt(2, _char('x')), isFalse);
    });

    test('emacs-style Ctrl+X Ctrl+S has 2 steps', () {
      final seq = KeySequence.ctrl.x.ctrl.s;
      expect(seq.stepCount, 2);
      expect(seq.matchesStepAt(0, _char('x', ctrl: true)), isTrue);
      expect(seq.matchesStepAt(1, _char('s', ctrl: true)), isTrue);
      expect(seq.hintLabel, 'Ctrl+X Ctrl+S');
    });

    test('canonicalisation holds inside sequences', () {
      expect(KeySequence.shift.g.g, KeyCode.char('G').g);
      expect((KeySequence.shift.g.g).hashCode, (KeyCode.char('G').g).hashCode);
    });

    test('equality compares step-by-step', () {
      expect(KeySequence.d.d, KeySequence.d.d);
      expect(KeySequence.d.d == KeySequence.d.k, isFalse);
    });
  });

  group('isPrefixOf', () {
    test('a leader is a prefix of the sequences it delays', () {
      expect(KeySequence.g.isPrefixOf(KeySequence.g.g), isTrue);
      expect(KeySequence.ctrl.x.isPrefixOf(KeySequence.ctrl.x.ctrl.s), isTrue);
    });

    test('a non-prefix, and a longer sequence, are not prefixes', () {
      expect(KeySequence.g.g.isPrefixOf(KeySequence.g), isFalse);
      expect(KeySequence.d.isPrefixOf(KeySequence.g.g), isFalse);
    });

    test('a sequence is a prefix of itself', () {
      expect(KeySequence.ctrl.s.isPrefixOf(KeySequence.ctrl.s), isTrue);
    });
  });

  group('parse / hintLabel round-trip', () {
    final samples = <KeySequence>[
      KeyCode.q,
      KeyCode.char('?'),
      KeySequence.ctrl.s,
      KeySequence.ctrl.shift.p,
      KeySequence.superKey.k,
      KeySequence.meta.enter,
      KeySequence.shift.g,
      KeySequence.up,
      KeySequence.ctrl.up,
      KeySequence.shiftTab,
      KeySequence.g.g,
      KeySequence.ctrl.x.ctrl.s,
      KeySequence.space.f,
      KeySequence.alt.char('1'),
      // The '+' key: bare and modified (Ctrl+Plus zoom). '+' doubles as the
      // modifier separator, so this pins that the grammar stays unambiguous.
      KeyCode.char('+'),
      KeySequence.ctrl.char('+'),
      KeySequence.shift.char('='),
    ];

    test('parse(x.hintLabel) == x for every sample', () {
      for (final seq in samples) {
        expect(
          KeySequence.parse(seq.hintLabel),
          seq,
          reason: 'round-trip failed for "${seq.hintLabel}"',
        );
      }
    });

    test('parse accepts aliases and is case-insensitive', () {
      expect(KeySequence.parse('control+s'), KeySequence.ctrl.s);
      expect(KeySequence.parse('CMD+k'), KeySequence.superKey.k);
      expect(KeySequence.parse('esc'), KeySequence.escape);
      expect(KeySequence.parse('g g'), KeySequence.g.g);
    });

    test('tryParse returns null on garbage; parse throws', () {
      expect(KeySequence.tryParse('ctrl+'), isNull);
      expect(KeySequence.tryParse('boguskey'), isNull);
      expect(KeySequence.tryParse(''), isNull);
      expect(() => KeySequence.parse('ctrl+'), throwsFormatException);
    });
  });

  group('KeyEvent.toSequence', () {
    test('captures code + modifiers as a bindable sequence', () {
      expect(_char('c', ctrl: true).toSequence(), KeySequence.ctrl.c);
      expect(_code(KeyCode.enter).toSequence(), KeyCode.enter);
      expect(_char('g', shift: true).toSequence(), KeyCode.char('G'));
    });
  });

  group('non-ASCII', () {
    test('accented chars match themselves; uppercase folds to shift', () {
      expect(KeyCode.char('é').matches(_char('é')), isTrue);
      expect(KeyCode.char('é').matches(_char('e')), isFalse);
      expect(KeyCode.char('É'), KeySequence.shift.char('é'));
    });

    test('digits and punctuation do not shift-fold', () {
      expect(KeyCode.char('5').matches(_char('5')), isTrue);
      expect(
        KeyCode.char('/').matches(_char('?')),
        isFalse,
        reason: 'no implicit fold across distinct codepoints',
      );
    });
  });

  group('KeyBinding', () {
    test('onTrigger fires and consumes (no bubble)', () {
      var fired = 0;
      final binding = KeyBinding(KeySequence.a, onTrigger: () => fired += 1);
      final event = _bindingEvent(KeySequence.a, _char('a'));
      binding.onEvent(event);
      expect(fired, 1);
      expect(event.isBubbling, isFalse);
    });

    test('KeyBinding.event can bubble', () {
      var fired = 0;
      final binding = KeyBinding.event(
        KeySequence.a,
        onEvent: (e) {
          fired += 1;
          e.bubble();
        },
      );
      final event = _bindingEvent(KeySequence.a, _char('a'));
      binding.onEvent(event);
      expect(fired, 1);
      expect(event.isBubbling, isTrue);
    });

    test('KeyBinding.any binds several aliases, one action', () {
      final binding = KeyBinding.any([
        KeySequence.j,
        KeySequence.down,
      ], onTrigger: () {});
      expect(binding.sequences.length, 2);
      expect(binding.sequences.first.matches(_char('j')), isTrue);
      expect(binding.sequences[1].matches(_code(KeyCode.arrowDown)), isTrue);
    });

    test('KeyBinding.any exposes which alias fired via the match', () {
      KeySequence? firedAlias;
      final binding = KeyBinding.any([
        KeySequence.j,
        KeySequence.down,
      ], onEvent: (e) => firedAlias = e.match.sequence);
      binding.onEvent(
        _bindingEvent(KeySequence.down, _code(KeyCode.arrowDown)),
      );
      expect(firedAlias, KeySequence.down);
    });

    test('KeyBinding.any requires exactly one handler', () {
      expect(
        () =>
            KeyBinding.any([KeySequence.j], onTrigger: () {}, onEvent: (_) {}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('displayLabel falls back to the canonical sequence label', () {
      expect(KeyBinding(KeySequence.q, onTrigger: () {}).displayLabel, 'q');
      expect(
        KeyBinding.any(
          [KeySequence.j, KeySequence.down],
          onTrigger: () {},
          label: 'j/↓',
        ).displayLabel,
        'j/↓',
      );
    });
  });
}
