// DefaultWidthResolver under RFC 0019's precedence ladder: width axes bind to
// cluster KINDS, so a policy answer can only reach the class it was measured
// on. The load-bearing cases here are the leak-prevention ones — a FE0F inside
// a ZWJ sequence or keycap must never take the simple-variation-sequence
// width, and the emoji veto must never touch CJK.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  const resolver = DefaultWidthResolver();
  const spec = CellWidthPolicy.spec;
  const cjk = CellWidthPolicy.cjk;

  /// Terminal-A-shaped policy: every emoji class measured narrow.
  const narrowEmoji = CellWidthPolicy(
    emojiPresentation: CellWidth.one,
    emojiVariationSequence: CellWidth.one,
  );

  /// VS-Code-family policy: bare emoji wide, the VS16 sequence inert.
  const inertVs16 = CellWidthPolicy(emojiVariationSequence: CellWidth.one);

  group('widthOfGrapheme — narrow', () {
    test('ASCII letters and digits are width 1', () {
      for (final g in ['A', 'z', '0', '9', '~', ' ']) {
        expect(resolver.widthOfGrapheme(g, spec), 1, reason: 'g=$g');
      }
    });

    test('Latin-1 letters with combining marks remain width 1', () {
      // 'é' as base 'e' + U+0301 combining acute.
      const grapheme = 'é';
      expect(resolver.widthOfGrapheme(grapheme, spec), 1);
    });

    test('Latin Extended characters are width 1', () {
      expect(resolver.widthOfGrapheme('ñ', spec), 1);
      expect(resolver.widthOfGrapheme('ü', spec), 1);
    });
  });

  group('widthOfGrapheme — wide', () {
    test('CJK characters are width 2', () {
      for (final g in ['中', '文', '日', '本', '語']) {
        expect(resolver.widthOfGrapheme(g, spec), 2, reason: 'g=$g');
      }
    });

    test('Hangul syllables are width 2', () {
      expect(resolver.widthOfGrapheme('한', spec), 2);
      expect(resolver.widthOfGrapheme('글', spec), 2);
    });

    test('Hiragana and Katakana are width 2', () {
      expect(resolver.widthOfGrapheme('あ', spec), 2);
      expect(resolver.widthOfGrapheme('ア', spec), 2);
    });

    test('Fullwidth ASCII forms are width 2', () {
      // U+FF21 = FULLWIDTH LATIN CAPITAL A
      expect(resolver.widthOfGrapheme('Ａ', spec), 2);
    });
  });

  group('widthOfGrapheme — the emoji-presentation axis', () {
    test('basic emoji are width 2 under the spec policy', () {
      expect(resolver.widthOfGrapheme('🙂', spec), 2);
      expect(resolver.widthOfGrapheme('🚀', spec), 2);
      expect(resolver.widthOfGrapheme('🧪', spec), 2);
    });

    test('emojiPresentation: one has real veto power (RFC 0019 §6.3)', () {
      // UAX #11 ED4 folds Emoji_Presentation=Yes into East Asian Wide, so the
      // wide table alone would keep these at 2. On a terminal MEASURED to draw
      // emoji in one cell (terminal A, live-probed 2026-07-27), modelling 2 is
      // simply wrong — the emoji class resolves 1.
      expect(resolver.widthOfGrapheme('🙂', narrowEmoji), 1);
      expect(resolver.widthOfGrapheme('🚀', narrowEmoji), 1);
      expect(resolver.widthOfGrapheme('✅', narrowEmoji), 1);
    });

    test('the veto never touches CJK or other non-emoji Wide classes', () {
      // CJK ideographs are wide WITHOUT being emoji — the classes are
      // distinct generated tables, and no emoji axis may affect them.
      for (final g in ['中', '한', 'あ', 'Ａ']) {
        expect(resolver.widthOfGrapheme(g, narrowEmoji), 2, reason: 'g=$g');
      }
    });

    test('emoji-presentation dingbats follow the axis; text ones never do', () {
      expect(resolver.widthOfGrapheme('✅', spec), 2);
      expect(resolver.widthOfGrapheme('✓', spec), 1);
      expect(resolver.widthOfGrapheme('✓', narrowEmoji), 1);
      expect(resolver.widthOfGrapheme('✗', spec), 1);
    });
  });

  group('widthOfGrapheme — the variation-sequence axis', () {
    test('VS16 promotes a text-default base under the spec policy', () {
      for (final g in [
        '\u{2764}\u{FE0F}', // ❤️ heart
        '\u{2611}\u{FE0F}', // ☑️ ballot box with check
        '\u{26A0}\u{FE0F}', // ⚠️ warning
        '\u{2708}\u{FE0F}', // ✈️ airplane
        '\u{270C}\u{FE0F}', // ✌️ victory hand
      ]) {
        expect(resolver.widthOfGrapheme(g, spec), 2, reason: 'g=$g');
      }
    });

    test('an inert selector leaves the base its OWN width, not 1', () {
      // emojiVariationSequence: one means "the selector does not promote on
      // this surface" — the 19-of-30 camp. A text-default base falls to its
      // own 1, but a base that is Wide in its own right keeps its 2: an
      // ignoring terminal still draws bare ⭐ wide.
      expect(resolver.widthOfGrapheme('\u{2764}\u{FE0F}', inertVs16), 1);
      expect(resolver.widthOfGrapheme('\u{26A0}\u{FE0F}', inertVs16), 1);
      expect(resolver.widthOfGrapheme('\u{2B50}\u{FE0F}', inertVs16), 2); // ⭐️
    });

    test('the axes compose: narrow emoji + inert selector', () {
      // Terminal A: ⭐️ falls back to scalar ⭐ (emoji class) which the emoji
      // axis narrows — the fallback path consults the OTHER axis correctly.
      expect(resolver.widthOfGrapheme('\u{2B50}\u{FE0F}', narrowEmoji), 1);
    });

    test('VS15 pins text presentation (width 1) under every policy', () {
      expect(resolver.widthOfGrapheme('\u{2757}\u{FE0E}', spec), 1); // ❗︎
      expect(resolver.widthOfGrapheme('\u{2714}\u{FE0E}', spec), 1); // ✔︎
      expect(resolver.widthOfGrapheme('\u{2714}\u{FE0E}', inertVs16), 1);
    });

    test('the bare base without a selector keeps its own width', () {
      expect(resolver.widthOfGrapheme('\u{2764}', spec), 1); // ❤ EAW=N
      expect(resolver.widthOfGrapheme('\u{26A0}', spec), 1); // ⚠ EAW=N
      expect(resolver.widthOfGrapheme('\u{2B50}', spec), 2); // ⭐ EAW=W (ED4)
    });
  });

  group('widthOfGrapheme — precedence ladder (leak prevention)', () {
    test('a FE0F inside a ZWJ sequence never takes the sequence axis', () {
      // 👩‍⚕️ contains FE0F, but it is a ZWJ sequence — branch 1, base-keyed.
      // An inert-VS16 policy must NOT narrow it to 1.
      const healthWorker = '\u{1F469}\u{200D}\u{2695}\u{FE0F}';
      expect(resolver.widthOfGrapheme(healthWorker, spec), 2);
      expect(
        resolver.widthOfGrapheme(healthWorker, inertVs16),
        2,
        reason: 'the selector belongs to a component, not the cluster',
      );
      // The base-keyed composite rule does follow the emoji axis (branch 1 is
      // policy-aware; the pin covers the residual disagreement until P2).
      expect(resolver.widthOfGrapheme(healthWorker, narrowEmoji), 1);
    });

    test('ZWJ family sequences stay base-keyed and capped at 2', () {
      const family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}';
      expect(resolver.widthOfGrapheme(family, spec), 2);
      expect(resolver.widthOfGrapheme(family, inertVs16), 2);
    });

    test('keycaps are their own kind: never the sequence axis', () {
      // 1️⃣ contains FE0F but is a keycap — branch 2, spec-fixed 2 under
      // every policy, pinned.
      const keycap = '1\u{FE0F}\u{20E3}';
      expect(resolver.widthOfGrapheme(keycap, spec), 2);
      expect(resolver.widthOfGrapheme(keycap, inertVs16), 2);
      expect(resolver.widthOfGrapheme(keycap, narrowEmoji), 2);
    });

    test('modifier sequences are spec-fixed 2', () {
      const thumbsUp = '\u{1F44D}\u{1F3FD}'; // 👍🏽 — base + Fitzpatrick
      expect(resolver.widthOfGrapheme(thumbsUp, spec), 2);
      expect(resolver.widthOfGrapheme(thumbsUp, narrowEmoji), 2);
    });

    test('regional-indicator flag pairs are spec-fixed 2', () {
      expect(resolver.widthOfGrapheme('\u{1F1FA}\u{1F1F8}', spec), 2); // 🇺🇸
      expect(resolver.widthOfGrapheme('\u{1F1EF}\u{1F1F5}', spec), 2); // 🇯🇵
      // Composite kinds are deliberately not governed by the measured axes —
      // nothing probes them; the pin covers them (RFC 0019 §6.3 branch 2).
      expect(resolver.widthOfGrapheme('\u{1F1FA}\u{1F1F8}', narrowEmoji), 2);
    });

    test('a LONE regional indicator is a bare scalar (branch 4)', () {
      // Not a pair — no companion — so the emoji-presentation axis applies.
      expect(resolver.widthOfGrapheme('\u{1F1FA}', spec), 2);
      expect(resolver.widthOfGrapheme('\u{1F1FA}', narrowEmoji), 1);
    });

    test('tag sequences are spec-fixed 2', () {
      // 🏴󠁧󠁢󠁥󠁮󠁧󠁿 England: black flag + tag characters.
      const england =
          '\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}';
      expect(resolver.widthOfGrapheme(england, spec), 2);
    });
  });

  group('widthOfGrapheme — zero width', () {
    test('combining mark alone has width 0', () {
      expect(resolver.widthOfGrapheme('́', spec), 0);
    });

    test('ZWJ alone has width 0', () {
      expect(resolver.widthOfGrapheme('‍', spec), 0);
    });

    test('control characters report width 0', () {
      expect(resolver.widthOfGrapheme('', spec), 0);
      expect(resolver.widthOfGrapheme('', spec), 0);
    });

    test('empty string has width 0', () {
      expect(resolver.widthOfGrapheme('', spec), 0);
    });
  });

  group('widthOfGrapheme — the ambiguous axis', () {
    test('box-drawing characters are narrow under the spec policy', () {
      expect(resolver.widthOfGrapheme('─', spec), 1);
    });

    test('box-drawing characters are wide under the CJK policy', () {
      expect(resolver.widthOfGrapheme('─', cjk), 2);
    });

    test('Greek and Latin-1 punctuation follow the axis too', () {
      expect(resolver.widthOfGrapheme('α', spec), 1);
      expect(resolver.widthOfGrapheme('α', cjk), 2);
      expect(resolver.widthOfGrapheme('°', cjk), 2);
    });
  });

  group('hasUncertainWidth', () {
    test('ASCII and CJK are certain', () {
      for (final g in ['A', ' ', '~', '中', '한', 'あ']) {
        expect(hasUncertainWidth(g), isFalse, reason: 'g=$g');
      }
    });

    test('TUI chrome stays certain so long runs are not pinned', () {
      for (final g in ['─', '│', '╭', '█', '▉', '▁', '●', '→', '←']) {
        expect(hasUncertainWidth(g), isFalse, reason: 'g=$g');
      }
    });

    test('emoji-capable clusters are uncertain', () {
      for (final g in [
        '✓',
        '✗',
        '✅',
        '⚠',
        '\u{26A0}\u{FE0F}',
        '\u{2B50}\u{FE0F}',
        '🙂',
        '🚀',
        '\u{1F1FA}\u{1F1F8}',
        '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}',
      ]) {
        expect(hasUncertainWidth(g), isTrue, reason: 'g=$g');
      }
    });

    test('empty input is certain', () {
      expect(hasUncertainWidth(''), isFalse);
    });
  });

  group('widthOfText', () {
    test('sums widths across grapheme clusters', () {
      expect(resolver.widthOfText('abc', spec), 3);
      expect(resolver.widthOfText('hello 中文', spec), 10);
    });

    test('counts a wide emoji as 2', () {
      expect(resolver.widthOfText('go 🚀', spec), 5);
    });

    test('ASCII base + VS16 keycap measures as one composite cluster', () {
      // One grapheme with an ASCII base; the fast path must not peel the '1'
      // off its cluster or the halves get measured separately.
      const keycap = '1\u{FE0F}\u{20E3}'; // 1️⃣
      expect(
        resolver.widthOfText(keycap, spec),
        resolver.widthOfGrapheme(keycap, spec),
        reason: 'widthOfText must equal the summed grapheme width',
      );
      expect(resolver.widthOfText(keycap, spec), 2);
      expect(resolver.widthOfText('a${keycap}b', spec), 4);
    });

    test('a flag emoji in mixed text counts as 2', () {
      expect(resolver.widthOfText('go \u{1F1FA}\u{1F1F8}', spec), 5);
    });

    test('a VS16 cluster in mixed text follows the axis', () {
      expect(resolver.widthOfText('ok \u{26A0}\u{FE0F}', spec), 5);
      expect(resolver.widthOfText('ok \u{26A0}\u{FE0F}', inertVs16), 4);
    });
  });
}
