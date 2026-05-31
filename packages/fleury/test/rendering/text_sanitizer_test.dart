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
      // 6 unsafe runes (2 x ESC, plus four printable that ride along but
      // are themselves printable — but the test only asserts the ESCs are
      // replaced).
      expect(cleaned.contains('\x1B'), isFalse);
      expect(cleaned.contains(replacementCharacter), isTrue);
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
}
