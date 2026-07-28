// RFC 0019 §6.4 — the intra-cluster emoji ZWJ sequence parser.
//
// Property gates 10 and 11 live here: non-emoji ZWJ text is never parsed as a
// sequence (Arabic/Indic joiners are shaping-significant), and modifiers and
// selectors never detach from their base. Unrecognized means null, and null
// means the caller preserves the source bytes — strictness is the safety.

import 'package:fleury/src/rendering/emoji_sequence.dart';
import 'package:test/test.dart';

void main() {
  group('splitEmojiZwjSequence — recognized sequences', () {
    test('family: three bare components', () {
      expect(
        splitEmojiZwjSequence('\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}'),
        ['\u{1F468}', '\u{1F469}', '\u{1F466}'], // 👨 👩 👦
      );
    });

    test('profession: the VS16 selector rides with its base', () {
      expect(
        splitEmojiZwjSequence('\u{1F469}\u{200D}\u{2695}\u{FE0F}'),
        ['\u{1F469}', '\u{2695}\u{FE0F}'], // 👩, ⚕️ — never ⚕ + loose FE0F
      );
    });

    test('modifier integrity: the skin tone travels with its base', () {
      // 👩🏽‍⚕️ → 👩🏽 + ⚕️, never 👩 🏽 ⚕ FE0F (RFC 0019 decision 12).
      expect(
        splitEmojiZwjSequence(
          '\u{1F469}\u{1F3FD}\u{200D}\u{2695}\u{FE0F}',
        ),
        ['\u{1F469}\u{1F3FD}', '\u{2695}\u{FE0F}'],
      );
    });

    test('rainbow flag: VS16 base component + pictograph', () {
      expect(
        splitEmojiZwjSequence('\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}'),
        ['\u{1F3F3}\u{FE0F}', '\u{1F308}'], // 🏳️, 🌈
      );
    });

    test('four-component kiss sequence', () {
      expect(
        splitEmojiZwjSequence(
          '\u{1F469}\u{200D}\u{2764}\u{FE0F}\u{200D}\u{1F48B}\u{200D}\u{1F468}',
        ),
        ['\u{1F469}', '\u{2764}\u{FE0F}', '\u{1F48B}', '\u{1F468}'],
      );
    });

    test('gender-sign components parse (they are Extended_Pictographic)', () {
      // 🧟‍♂️ zombie + male sign with selector.
      expect(
        splitEmojiZwjSequence('\u{1F9DF}\u{200D}\u{2642}\u{FE0F}'),
        ['\u{1F9DF}', '\u{2642}\u{FE0F}'],
      );
    });
  });

  group('splitEmojiZwjSequence — unrecognized (null → preserve)', () {
    test('no joiner at all: the common case, cheapest reject', () {
      expect(splitEmojiZwjSequence('a'), isNull);
      expect(splitEmojiZwjSequence('中'), isNull);
      expect(splitEmojiZwjSequence('🙂'), isNull);
    });

    test('modifier sequence without a joiner is not a ZWJ sequence', () {
      // 👍🏽 is base + modifier — one component, nothing to split.
      expect(splitEmojiZwjSequence('\u{1F44D}\u{1F3FD}'), isNull);
    });

    test('non-emoji safety: shaping joiners never parse as sequences', () {
      // Arabic lam + ZWJ + alef: the ZWJ is shaping-significant and the
      // segment bases are letters, not pictographs (property gate 10).
      expect(splitEmojiZwjSequence('\u{0644}\u{200D}\u{0627}'), isNull);
      // Devanagari conjunct with ZWJ.
      expect(
        splitEmojiZwjSequence('\u{0915}\u{094D}\u{200D}\u{0937}'),
        isNull,
      );
    });

    test('a mixed sequence with one non-pictographic base is rejected whole', () {
      expect(splitEmojiZwjSequence('\u{1F468}\u{200D}a'), isNull);
    });

    test('malformed joiner placement is rejected', () {
      expect(splitEmojiZwjSequence('\u{200D}\u{1F468}'), isNull, reason: 'leading');
      expect(splitEmojiZwjSequence('\u{1F468}\u{200D}'), isNull, reason: 'trailing');
      expect(
        splitEmojiZwjSequence('\u{1F468}\u{200D}\u{200D}\u{1F469}'),
        isNull,
        reason: 'doubled',
      );
      expect(splitEmojiZwjSequence('\u{200D}'), isNull, reason: 'bare joiner');
    });

    test('an unexpected code point inside a segment rejects the cluster', () {
      // A keycap enclosing mark after a pictographic base is not an emoji ZWJ
      // sequence shape we lower.
      expect(
        splitEmojiZwjSequence('\u{1F468}\u{20E3}\u{200D}\u{1F469}'),
        isNull,
      );
    });

    test('empty input', () {
      expect(splitEmojiZwjSequence(''), isNull);
    });
  });
}
