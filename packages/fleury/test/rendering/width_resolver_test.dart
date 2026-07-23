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

    test('regional-indicator flag emoji are width 2', () {
      // A flag is a pair of regional indicators forming one grapheme; the base
      // rune (0x1F1E6-0x1F1FF) must report emoji presentation, else the flag is
      // modeled width-1 and every cell after it on the row shifts one left.
      expect(resolver.widthOfGrapheme('\u{1F1FA}\u{1F1F8}', standard), 2); // 🇺🇸
      expect(resolver.widthOfGrapheme('\u{1F1EF}\u{1F1F5}', standard), 2); // 🇯🇵
      expect(
        resolver.widthOfGrapheme(
          '\u{1F1FA}\u{1F1F8}',
          const TerminalProfile(emojiIsWide: false),
        ),
        1,
        reason: 'emoji disabled falls back to base-char rules',
      );
    });

    test('emoji disabled by profile fall back to base-char rules', () {
      const noEmoji = TerminalProfile(emojiIsWide: false);
      // 🙂 (U+1F642) is outside our _isWide ranges (it's in U+1F300+ which
      // is only covered by the emoji table), so disabling emojiIsWide
      // makes it fall through to width 1.
      expect(resolver.widthOfGrapheme('🙂', noEmoji), 1);
    });
  });

  group('widthOfGrapheme — dingbats (U+2700–U+27BF presentation split)', () {
    test('text-presentation dingbats are width 1', () {
      // Emoji_Presentation=No: default to text, so 1 cell. ✓/✗ are the most
      // common TUI status glyphs; widening them desynced the cell diff against
      // terminals that render them at 1 (garbled scrolling in the storybook).
      for (final g in ['✓', '✗', '✎', '✏', '✂', '✈', '✉', '✒', '✍', '✁']) {
        expect(resolver.widthOfGrapheme(g, standard), 1, reason: 'g=$g');
      }
    });

    test('emoji-presentation dingbats stay width 2', () {
      // Emoji_Presentation=Yes: render as 2-column emoji by default, so the
      // narrowing above must not catch them.
      for (final g in [
        '✅',
        '✊',
        '✋',
        '✨',
        '❌',
        '❎',
        '❓',
        '❔',
        '❕',
        '❗',
        '➕',
        '➖',
        '➗',
        '➰',
        '➿',
      ]) {
        expect(resolver.widthOfGrapheme(g, standard), 2, reason: 'g=$g');
      }
    });

    test('emoji disabled by profile narrows even wide dingbats', () {
      const noEmoji = TerminalProfile(emojiIsWide: false);
      expect(resolver.widthOfGrapheme('✅', noEmoji), 1);
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

    test('ASCII base + VS16 keycap is not double-counted (fast-path split)', () {
      // '1' + VS16 + enclosing keycap is one grapheme. widthOfText's ASCII fast
      // path peels the '1' and re-measures the tail as a fresh cluster whose
      // base is VS16 (0xFE0F) — which must be zero-width, or the total exceeds
      // the summed grapheme width by one (measured 2 before the fix).
      const keycap = '1\u{FE0F}\u{20E3}'; // 1️⃣
      expect(
        resolver.widthOfText(keycap, standard),
        resolver.widthOfGrapheme(keycap, standard),
        reason: 'widthOfText must equal the summed grapheme width',
      );
      expect(resolver.widthOfText(keycap, standard), 1);
    });

    test('a flag emoji in mixed text counts as 2', () {
      // 'go ' peels as the ASCII prefix, then the flag grapheme adds 2.
      expect(resolver.widthOfText('go \u{1F1FA}\u{1F1F8}', standard), 5);
    });
  });
}
