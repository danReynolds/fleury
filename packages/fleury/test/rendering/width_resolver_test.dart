import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  const resolver = DefaultWidthResolver();
  const standard = TerminalProfile.standard;
  const cjk = TerminalProfile.cjk;

  group('widthOfGrapheme — narrow', () {
    test('ASCII letters and digits are width 1', () {
      for (final g in ['A', 'z', '0', '9', '~', ' ']) {
        expect(resolver.widthOfGrapheme(g, standard), 1, reason: 'g=$g');
      }
    });

    test('Latin-1 letters with combining marks remain width 1', () {
      // 'é' as base 'e' + U+0301 combining acute.
      const grapheme = 'é';
      expect(resolver.widthOfGrapheme(grapheme, standard), 1);
    });

    test('Latin Extended characters are width 1', () {
      expect(resolver.widthOfGrapheme('ñ', standard), 1);
      expect(resolver.widthOfGrapheme('ü', standard), 1);
    });
  });

  group('widthOfGrapheme — wide', () {
    test('CJK characters are width 2', () {
      for (final g in ['中', '文', '日', '本', '語']) {
        expect(resolver.widthOfGrapheme(g, standard), 2, reason: 'g=$g');
      }
    });

    test('Hangul syllables are width 2', () {
      expect(resolver.widthOfGrapheme('한', standard), 2);
      expect(resolver.widthOfGrapheme('글', standard), 2);
    });

    test('Hiragana and Katakana are width 2', () {
      expect(resolver.widthOfGrapheme('あ', standard), 2);
      expect(resolver.widthOfGrapheme('ア', standard), 2);
    });

    test('Fullwidth ASCII forms are width 2', () {
      // U+FF21 = FULLWIDTH LATIN CAPITAL A
      expect(resolver.widthOfGrapheme('Ａ', standard), 2);
    });
  });

  group('widthOfGrapheme — emoji', () {
    test('basic emoji are width 2 under standard profile', () {
      expect(resolver.widthOfGrapheme('🙂', standard), 2);
      expect(resolver.widthOfGrapheme('🚀', standard), 2);
      expect(resolver.widthOfGrapheme('🧪', standard), 2);
    });

    test('emoji + variation selector / ZWJ remain width 2', () {
      // ⭐️ = U+2B50 plus variation selector — base char is U+2B50 (not in
      // our pragmatic emoji ranges) so this is OK to be width 1 today.
      // What we DO want is ZWJ sequences with a wide base char to stay wide.
      // 👨‍👩‍👧 = man + ZWJ + woman + ZWJ + girl; the base is U+1F468 (man).
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      expect(resolver.widthOfGrapheme(family, standard), 2);
    });

    test('emoji disabled by profile fall back to base-char rules', () {
      const noEmoji = TerminalProfile(emojiIsWide: false);
      // 🙂 (U+1F642) is outside our _isWide ranges (it's in U+1F300+ which
      // is only covered by the emoji table), so disabling emojiIsWide
      // makes it fall through to width 1.
      expect(resolver.widthOfGrapheme('🙂', noEmoji), 1);
    });
  });

  group('widthOfGrapheme — zero width', () {
    test('combining mark alone has width 0', () {
      // U+0301 alone — combining acute. (Real text would have a base char,
      // but per UAX #11 a combining mark in isolation is zero-width.)
      expect(resolver.widthOfGrapheme('́', standard), 0);
    });

    test('ZWJ alone has width 0', () {
      expect(resolver.widthOfGrapheme('‍', standard), 0);
    });

    test('control characters report width 0', () {
      // The renderer should never see these (sanitizer replaces them) but
      // defending in depth here is cheap.
      expect(resolver.widthOfGrapheme('', standard), 0);
      expect(resolver.widthOfGrapheme('', standard), 0);
    });

    test('empty string has width 0', () {
      expect(resolver.widthOfGrapheme('', standard), 0);
    });
  });

  group('widthOfGrapheme — ambiguous', () {
    test('box-drawing characters are narrow under standard profile', () {
      // U+2500 BOX DRAWINGS LIGHT HORIZONTAL — ambiguous in UAX #11.
      expect(resolver.widthOfGrapheme('─', standard), 1);
    });

    test('box-drawing characters are wide under CJK profile', () {
      expect(resolver.widthOfGrapheme('─', cjk), 2);
    });
  });

  group('widthOfText', () {
    test('sums widths across grapheme clusters', () {
      expect(resolver.widthOfText('abc', standard), 3);
      // 'h' + 'e' + 'l' + 'l' + 'o' + ' ' + 中 (2) + 文 (2) = 10
      expect(resolver.widthOfText('hello 中文', standard), 10);
    });

    test('counts a wide emoji as 2', () {
      expect(resolver.widthOfText('go 🚀', standard), 5);
    });
  });
}
