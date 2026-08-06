// Pins the RFC 0020 §8.7 specification table: the Kitty functional-key PUA
// mapping (verbatim against the protocol spec's "Functional key definitions"
// ranges), the KeyPosition row invariants, the KeySelector id grammar, and
// KeyEvent's identity matching (§13.3).

import 'package:fleury/fleury_core.dart';
import 'package:fleury/src/input/key_tables.dart';
import 'package:test/test.dart';

void main() {
  group('kitty functional-key table', () {
    test('locks and system keys occupy 57358–57363 in spec order', () {
      const expected = [
        SpecialKey.capsLock,
        SpecialKey.scrollLock,
        SpecialKey.numLock,
        SpecialKey.printScreen,
        SpecialKey.pause,
        SpecialKey.menu,
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(kittyFunctionalKeys[57358 + i], expected[i]);
      }
    });

    test('F13–F35 are sequential from 57376', () {
      final extendedF = [
        SpecialKey.f13, SpecialKey.f14, SpecialKey.f15, SpecialKey.f16, //
        SpecialKey.f17, SpecialKey.f18, SpecialKey.f19, SpecialKey.f20, //
        SpecialKey.f21, SpecialKey.f22, SpecialKey.f23, SpecialKey.f24, //
        SpecialKey.f25, SpecialKey.f26, SpecialKey.f27, SpecialKey.f28, //
        SpecialKey.f29, SpecialKey.f30, SpecialKey.f31, SpecialKey.f32, //
        SpecialKey.f33, SpecialKey.f34, SpecialKey.f35,
      ];
      for (var i = 0; i < extendedF.length; i++) {
        expect(
          kittyFunctionalKeys[57376 + i],
          extendedF[i],
          reason: 'F${13 + i}',
        );
      }
    });

    test('keypad block occupies 57399–57427 in spec order', () {
      const expected = [
        SpecialKey.keypad0, SpecialKey.keypad1, SpecialKey.keypad2, //
        SpecialKey.keypad3, SpecialKey.keypad4, SpecialKey.keypad5, //
        SpecialKey.keypad6, SpecialKey.keypad7, SpecialKey.keypad8, //
        SpecialKey.keypad9, SpecialKey.keypadDecimal, //
        SpecialKey.keypadDivide, SpecialKey.keypadMultiply, //
        SpecialKey.keypadSubtract, SpecialKey.keypadAdd, //
        SpecialKey.keypadEnter, SpecialKey.keypadEqual, //
        SpecialKey.keypadSeparator, SpecialKey.keypadLeft, //
        SpecialKey.keypadRight, SpecialKey.keypadUp, SpecialKey.keypadDown, //
        SpecialKey.keypadPageUp, SpecialKey.keypadPageDown, //
        SpecialKey.keypadHome, SpecialKey.keypadEnd, //
        SpecialKey.keypadInsert, SpecialKey.keypadDelete, //
        SpecialKey.keypadBegin,
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(kittyFunctionalKeys[57399 + i], expected[i]);
      }
    });

    test('media, volume, and sided modifiers occupy 57428–57454', () {
      const expected = [
        SpecialKey.mediaPlay, SpecialKey.mediaPause, //
        SpecialKey.mediaPlayPause, SpecialKey.mediaReverse, //
        SpecialKey.mediaStop, SpecialKey.mediaFastForward, //
        SpecialKey.mediaRewind, SpecialKey.mediaTrackNext, //
        SpecialKey.mediaTrackPrevious, SpecialKey.mediaRecord, //
        SpecialKey.volumeDown, SpecialKey.volumeUp, SpecialKey.volumeMute, //
        SpecialKey.leftShift, SpecialKey.leftControl, SpecialKey.leftAlt, //
        SpecialKey.leftSuper, SpecialKey.leftHyper, SpecialKey.leftMeta, //
        SpecialKey.rightShift, SpecialKey.rightControl, SpecialKey.rightAlt, //
        SpecialKey.rightSuper, SpecialKey.rightHyper, SpecialKey.rightMeta, //
        SpecialKey.isoLevel3Shift, SpecialKey.isoLevel5Shift,
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(kittyFunctionalKeys[57428 + i], expected[i]);
      }
    });

    test('the mapping is a bijection with no strays', () {
      expect(kittyFunctionalKeys.length, 6 + 23 + 29 + 27);
      expect(
        kittyFunctionalKeys.values.toSet().length,
        kittyFunctionalKeys.length,
        reason: 'no SpecialKey may claim two codepoints',
      );
      expect(kittyCodepointOf.length, kittyFunctionalKeys.length);
      for (final MapEntry(:key, :value) in kittyFunctionalKeys.entries) {
        expect(kittyCodepointOf[value], key);
      }
      // Every PUA-range special is covered; legacy-encoded specials are not.
      for (final key in SpecialKey.values.skip(SpecialKey.f13.index)) {
        expect(kittyCodepointOf.containsKey(key), isTrue, reason: '$key');
      }
      expect(kittyCodepointOf.containsKey(SpecialKey.enter), isFalse);
      expect(kittyCodepointOf.containsKey(SpecialKey.f12), isFalse);
    });

    test('forSpecial canonical table covers the extended vocabulary', () {
      for (final key in SpecialKey.values) {
        expect(KeyCode.forSpecial(key).special, key);
      }
    });
  });

  group('KeyPosition rows', () {
    test('DOM codes are unique and total', () {
      expect(
        positionByDomCode.length,
        KeyPosition.values.length,
        reason: 'duplicate DOM code strings',
      );
    });

    test('US characters are unique where present', () {
      final chars = [
        for (final p in KeyPosition.values)
          if (p.usCharacter != null) p.usCharacter!,
      ];
      expect(chars.toSet().length, chars.length);
      expect(positionByUsCodepoint.length, chars.length);
    });

    test('usTwin is total except the ISO extra key', () {
      for (final p in KeyPosition.values) {
        if (p == KeyPosition.intlBackslash) {
          expect(p.usTwin, isNull);
        } else {
          expect(p.usTwin, isNotNull, reason: '$p');
        }
      }
    });

    test('character positions twin to their character codes', () {
      expect(KeyPosition.w.usTwin, KeyCode.w);
      expect(KeyPosition.digit1.usTwin, const KeyCode.char('1'));
      expect(KeyPosition.comma.usTwin, const KeyCode.char(','));
      expect(KeyPosition.space.usTwin, KeyCode.space);
    });

    test('functional positions twin to their specials, keypad distinctly', () {
      expect(KeyPosition.enter.usTwin, KeyCode.enter);
      expect(KeyPosition.numpadEnter.usTwin, KeyCode.keypadEnter);
      expect(KeyPosition.f24.usTwin, KeyCode.f24);
      expect(KeyPosition.metaLeft.usTwin, KeyCode.leftSuper);
      expect(positionBySpecial[SpecialKey.arrowUp], KeyPosition.arrowUp);
      expect(positionBySpecial[SpecialKey.leftShift], KeyPosition.shiftLeft);
    });

    test('base-layout codepoints resolve AZERTY-style reports', () {
      // An AZERTY terminal reporting base 0x77 ('w') means QWERTY-W's spot;
      // base 0x31 ('1') means the first number-row key (unshifted '&' cap).
      expect(positionByUsCodepoint[0x77], KeyPosition.w);
      expect(positionByUsCodepoint[0x31], KeyPosition.digit1);
      expect(positionByUsCodepoint[0x60], KeyPosition.backquote);
    });
  });

  group('KeySelector id grammar', () {
    test('round-trips every position', () {
      for (final p in KeyPosition.values) {
        expect(KeySelector.parse(p.selectorId), same(p));
      }
    });

    test('round-trips special and character codes', () {
      for (final key in SpecialKey.values) {
        final code = KeyCode.forSpecial(key);
        expect(KeySelector.parse(code.selectorId), code);
      }
      for (final char in ['a', ' ', ':', 'é', '@', r'\']) {
        final code = KeyCode.char(char);
        expect(KeySelector.parse(code.selectorId), code);
        expect(code.selectorId, 'chr:$char');
      }
    });

    test('rejects unknown kinds and names', () {
      expect(() => KeySelector.parse('pos:nope'), throwsFormatException);
      expect(() => KeySelector.parse('key:nope'), throwsFormatException);
      expect(() => KeySelector.parse('chr:'), throwsFormatException);
      expect(() => KeySelector.parse('wat:w'), throwsFormatException);
      expect(() => KeySelector.parse('w'), throwsFormatException);
    });
  });

  group('KeyEvent.matches — RFC 0020 §13.3', () {
    test('logical selectors match by code, never by position', () {
      const event = KeyEvent(KeyCode.char('z'), position: KeyPosition.w);
      expect(event.matches(const KeyCode.char('z')), isTrue);
      expect(event.matches(const KeyCode.char('w')), isFalse);
    });

    test('positional selectors match a known position exactly', () {
      // AZERTY: the physical key at QWERTY-W types 'z'.
      const event = KeyEvent(KeyCode.char('z'), position: KeyPosition.w);
      expect(event.matches(KeyPosition.w), isTrue);
      expect(event.matches(KeyPosition.z), isFalse);
    });

    test('a known position never falls back to the US twin', () {
      // Physical key known and it is NOT the selector's spot — no match,
      // even though the produced character equals the twin.
      const event = KeyEvent(KeyCode.char('w'), position: KeyPosition.z);
      expect(event.matches(KeyPosition.w), isFalse);
    });

    test('an unknown position degrades one-way to the US twin', () {
      const event = KeyEvent(KeyCode.char('w'));
      expect(event.matches(KeyPosition.w), isTrue);
      expect(event.matches(KeyPosition.a), isFalse);
      // No twin (ISO extra key) → never matches without positional data.
      expect(event.matches(KeyPosition.intlBackslash), isFalse);
    });

    test('modifiers are ignored — identity, not gesture', () {
      const event = KeyEvent(
        KeyCode.char('w'),
        modifiers: {KeyModifier.ctrl},
        position: KeyPosition.w,
      );
      expect(event.matches(const KeyCode.char('w')), isTrue);
      expect(event.matches(KeyPosition.w), isTrue);
    });
  });

  group('KeyEvent extended fields', () {
    test('defaults keep pre-0020 equality semantics', () {
      expect(const KeyEvent(KeyCode.enter), const KeyEvent(KeyCode.enter));
      expect(
        const KeyEvent(KeyCode.enter),
        isNot(const KeyEvent(KeyCode.enter, position: KeyPosition.enter)),
      );
      expect(
        const KeyEvent(KeyCode.enter),
        isNot(const KeyEvent(KeyCode.enter, synthesized: true)),
      );
    });

    test('toString names position and synthesis', () {
      expect(
        const KeyEvent(
          KeyCode.char('z'),
          position: KeyPosition.w,
          synthesized: true,
        ).toString(),
        'KeyEvent(z @w synth)',
      );
    });
  });

  group('InputBatch equality is payload-only', () {
    test('timing differences never break equality or hashing', () {
      const a = InputBatch(
        key: KeyEvent(KeyCode.char('a')),
        committedText: 'a',
        timeStamp: Duration(seconds: 1),
        sequence: 7,
      );
      const b = InputBatch(
        key: KeyEvent(KeyCode.char('a')),
        committedText: 'a',
        timeStamp: Duration(hours: 2),
        sequence: 900,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('payload differences do break equality', () {
      const a = InputBatch(key: KeyEvent(KeyCode.char('a')));
      const b = InputBatch(key: KeyEvent(KeyCode.char('b')));
      const c = InputBatch(
        key: KeyEvent(KeyCode.char('a')),
        committedText: 'a',
      );
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });
}
