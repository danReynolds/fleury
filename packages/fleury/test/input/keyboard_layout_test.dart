// RFC 0020 §9 — the hint bar must not tell an AZERTY user to press "W".

import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/keyboard_state.dart';
import 'package:test/test.dart';

void main() {
  group('labelFor', () {
    test('a logical key IS its own label — no layout needed', () {
      final layout = KeyboardLayout.learning();
      expect(layout.labelFor(KeyCode.char('j'))?.text, 'J');
    });

    test('an unknown position resolves to nothing, never a guess', () {
      // The whole point: silence beats a confident lie. A caller that gets
      // null renders the position honestly instead.
      expect(KeyboardLayout.learning().labelFor(KeyPosition.w), isNull);
    });

    test('a bundled table names the cap that is really there', () {
      final azerty = KeyboardLayout.named('fr-azerty');
      expect(azerty.labelFor(KeyPosition.w)?.text, 'Z');
      expect(azerty.labelFor(KeyPosition.a)?.text, 'Q');
      expect(azerty.labelFor(KeyPosition.w)?.source, KeyLabelSource.table);
    });

    test('a position the table does not move keeps its US cap', () {
      // Tables are deliberately partial — absent means "same as US".
      expect(KeyboardLayout.named('de-qwertz').labelFor(KeyPosition.j), isNull);
    });

    test('an unknown table name degrades to learning, never throws', () {
      expect(KeyboardLayout.named('klingon').labelFor(KeyPosition.w), isNull);
    });
  });

  group('learning from the terminal (§9, kitty flag 4)', () {
    test('an unmodified press with a position teaches one cap', () {
      final layout = KeyboardLayout.learning();
      // On a Dvorak keyboard the key at QWERTY-W produces a comma.
      layout.observe(
        const KeyEvent(KeyCode.char(','), position: KeyPosition.w),
      );
      final label = layout.labelFor(KeyPosition.w);
      expect(label?.text, ',');
      expect(label?.source, KeyLabelSource.learned);
    });

    test('what the terminal reports beats the table', () {
      // The table is an assumption about which layout is in use; a report is
      // this keyboard, right now.
      final layout = KeyboardLayout.named('fr-azerty');
      expect(layout.labelFor(KeyPosition.w)?.text, 'Z');
      layout.observe(
        const KeyEvent(KeyCode.char('!'), position: KeyPosition.w),
      );
      expect(layout.labelFor(KeyPosition.w)?.text, '!');
    });

    test('a chord teaches nothing — it reports the BASE key', () {
      // Ctrl+С on Cyrillic reports base 'c' with the position: that pair
      // describes the fallback matching rule, not the physical cap.
      final layout = KeyboardLayout.learning();
      layout.observe(
        const KeyEvent(
          KeyCode.char('c'),
          modifiers: {KeyModifier.ctrl},
          position: KeyPosition.c,
        ),
      );
      expect(layout.labelFor(KeyPosition.c), isNull);
    });

    test('a positionless press teaches nothing', () {
      final layout = KeyboardLayout.learning();
      layout.observe(const KeyEvent(KeyCode.char('w')));
      expect(layout.labelFor(KeyPosition.w), isNull);
    });

    test('a special key teaches nothing (its identity is layout-free)', () {
      final layout = KeyboardLayout.learning();
      layout.observe(
        const KeyEvent(KeyCode.enter, position: KeyPosition.enter),
      );
      expect(layout.labelFor(KeyPosition.enter), isNull);
    });
  });

  group('labelForSequence', () {
    test('an all-logical sequence is untouched', () {
      final layout = KeyboardLayout.named('fr-azerty');
      final ctrlS = KeySequence.ctrl.s;
      expect(layout.labelForSequence(ctrlS), ctrlS.hintLabel);
    });

    test('a positional step is substituted', () {
      final layout = KeyboardLayout.named('fr-azerty');
      expect(layout.labelForSequence(KeyPosition.w), 'Z');
    });

    test('an unknown position falls back to the US twin, not a blank', () {
      // Degraded, but still actionable: the US name is what the position is
      // documented as, and a blank hint helps nobody.
      final layout = KeyboardLayout.learning();
      expect(layout.labelForSequence(KeyPosition.w), KeyPosition.w.hintLabel);
    });

    test('substitution preserves the modifier prefix', () {
      final layout = KeyboardLayout.named('fr-azerty');
      final chord = KeySequence.ctrl.code(KeyPosition.w);
      expect(layout.labelForSequence(chord), 'Ctrl+Z');
    });
  });

  group('the session learns as it dispatches', () {
    test('a press through the session reaches the layout', () {
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      session.ingest(
        const KeyEvent(KeyCode.char(';'), position: KeyPosition.z),
      );
      expect(session.layout.labelFor(KeyPosition.z)?.text, ';');
    });

    test('a legacy surface still learns what it can', () {
      // Position reporting and release reporting are independent
      // capabilities: a surface can have one without the other.
      final session = KeyboardSession();
      session.ingest(
        const KeyEvent(KeyCode.char('a'), position: KeyPosition.q),
      );
      expect(session.layout.labelFor(KeyPosition.q)?.text, 'A');
    });
  });
}
