import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

/// Per-terminal configuration that affects display-width calculations.
///
/// Unicode UAX #11 leaves the width of "ambiguous" characters up to the
/// emulator. Most modern Unicode terminals render them as narrow (1 cell);
/// CJK terminals and a few legacy emulators render them as wide (2 cells).
/// The renderer probes the terminal where it can and falls back to narrow.
@immutable
final class TerminalProfile {
  const TerminalProfile({
    this.ambiguousIsWide = false,
    this.emojiIsWide = true,
  });

  /// When true, UAX #11 Ambiguous characters render as 2 columns. Default
  /// is false (narrow).
  final bool ambiguousIsWide;

  /// When true, characters in the standard emoji ranges render as 2
  /// columns. Default is true — almost every modern emulator does this.
  final bool emojiIsWide;

  /// Sensible default for modern terminals: narrow ambiguous, wide emoji.
  static const TerminalProfile standard = TerminalProfile();

  /// Profile for legacy CJK terminals where Ambiguous characters should
  /// render as 2 columns.
  static const TerminalProfile cjk = TerminalProfile(ambiguousIsWide: true);

  @override
  bool operator ==(Object other) =>
      other is TerminalProfile &&
      other.ambiguousIsWide == ambiguousIsWide &&
      other.emojiIsWide == emojiIsWide;

  @override
  int get hashCode => Object.hash(ambiguousIsWide, emojiIsWide);
}

/// Returns the number of terminal cells a grapheme cluster occupies.
///
/// Implementations must accept any UTF-16 string. The argument is a single
/// grapheme cluster (per Unicode UAX #29); callers should split with the
/// `characters` package before calling.
abstract interface class WidthResolver {
  /// Width in cells: 0 for empty/combining-only clusters, 1 for narrow,
  /// 2 for wide. The renderer enforces this by writing a leading cell
  /// followed by `width - 1` continuation cells.
  int widthOfGrapheme(String grapheme, TerminalProfile profile);

  /// Sum of widths over all grapheme clusters in [text]. Equivalent to
  /// splitting on grapheme clusters and summing.
  int widthOfText(String text, TerminalProfile profile) {
    var total = 0;
    for (final g in text.characters) {
      total += widthOfGrapheme(g, profile);
    }
    return total;
  }
}

/// Default width resolver based on Unicode East Asian Width (UAX #11) plus
/// emoji-aware adjustments. Pragmatic, not exhaustive: covers the ranges
/// real terminals get wrong if you don't handle them, leaves the long tail
/// as "narrow."
final class DefaultWidthResolver implements WidthResolver {
  const DefaultWidthResolver();

  @override
  int widthOfGrapheme(String grapheme, TerminalProfile profile) {
    if (grapheme.isEmpty) return 0;

    // ASCII fast path: a single printable ASCII code unit is always
    // its own grapheme cluster, always width 1. Skips the runes
    // iterator and the range scans, which add up when called per
    // grapheme inside the wrap algorithm.
    if (grapheme.length == 1) {
      final c = grapheme.codeUnitAt(0);
      if (c >= 0x20 && c <= 0x7E) return 1;
    }

    // For grapheme clusters built from multiple code points (combining marks,
    // ZWJ sequences, regional-indicator pairs), use the first base code point
    // for width and treat the remainder as combining (zero width by default).
    final iterator = grapheme.runes.iterator;
    if (!iterator.moveNext()) return 0;
    final base = iterator.current;

    if (_isZeroWidth(base)) return 0;

    if (profile.emojiIsWide && _isEmojiPresentation(base)) return 2;
    if (_isWide(base)) return 2;
    if (profile.ambiguousIsWide && _isAmbiguous(base)) return 2;

    return 1;
  }

  @override
  int widthOfText(String text, TerminalProfile profile) {
    // Pure-ASCII fast path: every code unit 0x20..0x7E is one
    // single-cell grapheme. Skips the `text.characters` iterator
    // allocation and the per-grapheme range scans entirely. Common
    // for label-style strings like 'Item 12' or 'hello world'.
    final len = text.length;
    var asciiPrefix = 0;
    while (asciiPrefix < len) {
      final c = text.codeUnitAt(asciiPrefix);
      if (c < 0x20 || c > 0x7E) break;
      asciiPrefix++;
    }
    if (asciiPrefix == len) return len;

    // Mixed text: count the ASCII prefix at width 1/char, then fall
    // back to grapheme iteration for the rest.
    var total = asciiPrefix;
    final rest = text.substring(asciiPrefix);
    for (final g in rest.characters) {
      total += widthOfGrapheme(g, profile);
    }
    return total;
  }

  // ---- Width tables ------------------------------------------------------
  //
  // Pragmatic excerpts from UAX #11. Full ranges would be ~300 entries; the
  // sets below cover what real terminal text actually contains. Long-tail
  // ranges can be added when concrete test cases demand them.

  bool _isZeroWidth(int r) {
    // C0 / C1 controls are zero-width (and should already have been replaced
    // by the sanitizer; defending against them in the resolver too).
    if (r < 0x20 || (r >= 0x7F && r <= 0x9F)) return true;

    // Combining marks and modifiers commonly seen at base positions.
    if (r >= 0x0300 && r <= 0x036F) return true; // Combining Diacriticals
    if (r >= 0x1AB0 && r <= 0x1AFF) return true; // Combining Diacriticals Ext.
    if (r >= 0x1DC0 && r <= 0x1DFF) return true; // Combining Diacriticals Sup.
    if (r >= 0x20D0 && r <= 0x20FF) return true; // Combining Marks for Symbols
    // Variation selectors (VS1-VS16) are zero-width modifiers. VS16 (0xFE0F) is
    // the one extend that can immediately follow an ASCII base and NOT already
    // be covered above, so widthOfText's ASCII fast path — which peels the base
    // and re-measures the tail as a fresh cluster — would otherwise count the
    // VS16-based fragment as width 1 (e.g. '1️⃣' measured 2, paints 1).
    if (r >= 0xFE00 && r <= 0xFE0F) return true; // Variation Selectors
    if (r >= 0xFE20 && r <= 0xFE2F) return true; // Combining Half Marks
    if (r == 0x200B || r == 0x200C || r == 0x200D) return true; // ZW{SP,NJ,J}
    if (r == 0xFEFF) return true; // BOM / ZWNBSP

    return false;
  }

  bool _isWide(int r) {
    // Hangul Jamo
    if (r >= 0x1100 && r <= 0x115F) return true;
    // CJK Radicals / Kangxi
    if (r >= 0x2E80 && r <= 0x303E) return true;
    // Hiragana / Katakana / Bopomofo / Hangul Compat / Kanbun / Extended-A
    if (r >= 0x3041 && r <= 0x33FF) return true;
    // CJK Unified Ideographs Extension A
    if (r >= 0x3400 && r <= 0x4DBF) return true;
    // CJK Unified Ideographs
    if (r >= 0x4E00 && r <= 0x9FFF) return true;
    // Yi Syllables / Radicals
    if (r >= 0xA000 && r <= 0xA4CF) return true;
    // Hangul Syllables
    if (r >= 0xAC00 && r <= 0xD7A3) return true;
    // CJK Compatibility Ideographs
    if (r >= 0xF900 && r <= 0xFAFF) return true;
    // CJK Compatibility Forms / Small Forms / Vertical Forms
    if (r >= 0xFE30 && r <= 0xFE6F) return true;
    // Fullwidth Forms (excluding halfwidth shapes)
    if (r >= 0xFF00 && r <= 0xFF60) return true;
    if (r >= 0xFFE0 && r <= 0xFFE6) return true;
    // CJK Unified Ideographs Extension B through F
    if (r >= 0x20000 && r <= 0x2FFFD) return true;
    // CJK Unified Ideographs Extension G
    if (r >= 0x30000 && r <= 0x3FFFD) return true;
    return false;
  }

  bool _isEmojiPresentation(int r) {
    // Common emoji ranges that render as 2-column glyphs by default.
    // Regional indicators (0x1F1E6-0x1F1FF) form flag emoji as pairs; each
    // renders 2 columns wide, and widthOfGrapheme keys the whole cluster off
    // its base rune, so the base must report emoji presentation. Without this a
    // flag was modeled width-1 and every cell after it on the row shifted left.
    if (r >= 0x1F1E6 && r <= 0x1F1FF) return true; // Regional indicators (flags)
    if (r >= 0x1F300 && r <= 0x1F64F) return true; // Misc Symbols & Pictographs
    if (r >= 0x1F680 && r <= 0x1F6FF) return true; // Transport
    if (r >= 0x1F900 && r <= 0x1F9FF) return true; // Supplemental Pictographs
    if (r >= 0x1FA70 && r <= 0x1FAFF) return true; // Symbols & Pictographs Ext.
    // Single high-traffic emoji not in the contiguous ranges above.
    if (r == 0x2600) return true; // ☀
    if (r == 0x2601) return true; // ☁
    if (r == 0x2614) return true; // ☔
    if (r == 0x2615) return true; // ☕
    // Dingbats (U+2700–U+27BF) are a MIX of presentations, not "mostly wide":
    // only the Emoji_Presentation=Yes code points below render as 2-column emoji
    // by default. The rest — ✓ U+2713, ✗ U+2717, ✎/✏ pencils, ✂ scissors,
    // ✈ plane — default to TEXT presentation and are 1 cell wide. Widening the
    // whole block modeled those at 2, so on a terminal that renders them at 1
    // every following cell on the row shifted one column left (garbled diff /
    // scroll). Classify by Unicode presentation, not by the block.
    if (r == 0x2705) return true; // ✅
    if (r >= 0x270A && r <= 0x270B) return true; // ✊ ✋
    if (r == 0x2728) return true; // ✨
    if (r == 0x274C) return true; // ❌
    if (r == 0x274E) return true; // ❎
    if (r >= 0x2753 && r <= 0x2755) return true; // ❓ ❔ ❕
    if (r == 0x2757) return true; // ❗
    if (r >= 0x2795 && r <= 0x2797) return true; // ➕ ➖ ➗
    if (r == 0x27B0) return true; // ➰
    if (r == 0x27BF) return true; // ➿
    return false;
  }

  bool _isAmbiguous(int r) {
    // Pragmatic ambiguous set: the ranges most likely to differ between
    // terminals. CJK-aware terminals render these as 2 columns when
    // `ambiguousIsWide` is true.
    if (r >= 0x00A1 && r <= 0x00BE) return true; // some Latin-1 supplement
    if (r >= 0x2010 && r <= 0x205F) return true; // general punctuation
    if (r >= 0x2160 && r <= 0x217F) return true; // Roman numerals
    if (r >= 0x2500 && r <= 0x25FF) return true; // box drawing & block
    return false;
  }
}
