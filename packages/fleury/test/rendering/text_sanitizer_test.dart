import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('isUnsafeRune', () {
    test('flags C0 controls (0x00..0x1F)', () {
      for (final r in [0x00, 0x07, 0x09, 0x0A, 0x0D, 0x1B, 0x1F]) {
        expect(
          isUnsafeRune(r),
          isTrue,
          reason: 'rune 0x${r.toRadixString(16)}',
        );
      }
    });

    test('flags DEL (0x7F)', () {
      expect(isUnsafeRune(0x7F), isTrue);
    });

    test('flags C1 controls (0x80..0x9F)', () {
      for (final r in [0x80, 0x85, 0x9F]) {
        expect(
          isUnsafeRune(r),
          isTrue,
          reason: 'rune 0x${r.toRadixString(16)}',
        );
      }
    });

    test('passes printable ASCII', () {
      for (final r in [0x20, 0x41, 0x7E]) {
        expect(
          isUnsafeRune(r),
          isFalse,
          reason: 'rune 0x${r.toRadixString(16)}',
        );
      }
    });

    test('passes high Unicode', () {
      // CJK, emoji, Latin Extended — all OK at this layer; width is a
      // separate concern.
      for (final r in [0x4E2D, 0x1F600, 0x00E9, 0xFEFF]) {
        expect(isUnsafeRune(r), isFalse);
      }
    });
  });

  group('sanitizeForDisplay', () {
    test('returns input unchanged when no unsafe runes are present', () {
      expect(sanitizeForDisplay('hello world'), 'hello world');
      expect(sanitizeForDisplay('日本語'), '日本語');
      expect(sanitizeForDisplay('🙂'), '🙂');
    });

    test('replaces a single ESC sequence', () {
      // Classic terminal hijack: clear screen + cursor home.
      const hostile = '\x1b[2J\x1b[H';
      final cleaned = sanitizeForDisplay(hostile);
      expect(cleaned.contains('\x1B'), isFalse);
      expect(cleaned, replacementCharacter * 2);
    });

    test('collapses CSI sequences without leaking parameters', () {
      const hostile = 'a\x1b[31mred\x1b[0mb';
      final cleaned = sanitizeForDisplay(hostile);
      expect(cleaned, 'a${replacementCharacter}red${replacementCharacter}b');
      expect(cleaned, isNot(contains('[31m')));
      expect(cleaned, isNot(contains('[0m')));
    });

    test('redacts OSC 52 clipboard payloads', () {
      final hostile =
          '\x1b]52;c;U0VDUkVUX1RPS0VO${String.fromCharCode(0x07)}after';
      final cleaned = sanitizeForDisplay(hostile);
      expect(cleaned, '${replacementCharacter}after');
      expect(cleaned, isNot(contains('U0VDUkVUX1RPS0VO')));
      expect(cleaned, isNot(contains('\x07')));
    });

    test('redacts OSC 8 hyperlink control payload while preserving label', () {
      final bel = String.fromCharCode(0x07);
      final hostile =
          '\x1b]8;;https://evil.example/secret${bel}CLICK'
          '\x1b]8;;$bel';
      final cleaned = sanitizeForDisplay(hostile);
      expect(cleaned, '${replacementCharacter}CLICK$replacementCharacter');
      expect(cleaned, isNot(contains('https://evil.example/secret')));
    });

    test('redacts DCS/Sixel and APC/Kitty image payloads', () {
      const sixel = '\x1bPq"1;1;1;1#0!~\x1b\\done';
      const kitty = '\x1b_Gf=100,a=T;AAAA\x1b\\done';

      expect(sanitizeForDisplay(sixel), '${replacementCharacter}done');
      expect(sanitizeForDisplay(kitty), '${replacementCharacter}done');
    });

    test('unterminated OSC consumes the rest of the unsafe payload', () {
      const hostile = '\x1b]52;c;SECRET';
      final cleaned = sanitizeForDisplay(hostile);
      expect(cleaned, replacementCharacter);
      expect(cleaned, isNot(contains('SECRET')));
    });

    test('replaces every C0 control with the replacement character', () {
      const input = '\x00ab\x07c\x1Fd';
      final cleaned = sanitizeForDisplay(input);
      expect(
        cleaned,
        '${replacementCharacter}ab${replacementCharacter}c'
        '${replacementCharacter}d',
      );
    });

    test('replaces C1 controls', () {
      final input = String.fromCharCodes([0x41, 0x85, 0x42]); // A, NEL, B
      final cleaned = sanitizeForDisplay(input);
      expect(cleaned, 'A${replacementCharacter}B');
    });

    test('replaces DEL', () {
      final input = String.fromCharCodes([0x41, 0x7F, 0x42]);
      final cleaned = sanitizeForDisplay(input);
      expect(cleaned, 'A${replacementCharacter}B');
    });

    test('preserves Unicode characters across the unsafe range', () {
      // U+00A0 (NBSP) sits right after the C1 range and must be preserved.
      final input = String.fromCharCodes([0x41, 0xA0, 0x42]);
      final cleaned = sanitizeForDisplay(input);
      expect(cleaned, String.fromCharCodes([0x41, 0xA0, 0x42]));
    });

    test('preserves emoji and CJK characters intact', () {
      const input = 'hello 🙂 中文';
      expect(sanitizeForDisplay(input), input);
    });
  });

  group('sanitizeSingleLine', () {
    test('collapses newlines, CR, and tabs to a single space (not U+FFFD)', () {
      // Regression: sanitizeForDisplay treats \r\n\t as C0 controls and rewrites
      // them to U+FFFD, so a caller that sanitized THEN stripped breaks showed
      // the replacement glyph where a space belonged. sanitizeSingleLine strips
      // the breaks FIRST, so each becomes a real space.
      expect(sanitizeSingleLine('a\tb\nc\rd'), 'a b c d');
      expect(sanitizeSingleLine('line1\nline2'), 'line1 line2');
      expect(
        sanitizeSingleLine('has\ttab'),
        isNot(contains(replacementCharacter)),
        reason: 'a tab must become a space, not the replacement glyph',
      );
    });

    test('still sanitizes other unsafe controls to U+FFFD', () {
      // A break is spaced out, but a genuine escape sequence is still collapsed.
      expect(
        sanitizeSingleLine('a\nb\x1B[31mc'),
        'a b${replacementCharacter}c',
      );
    });

    test('leaves clean single-line text untouched', () {
      expect(sanitizeSingleLine('already clean'), 'already clean');
    });
  });
}
