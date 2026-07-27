import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import 'width_tables.dart';

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

  /// When true, `Emoji_Presentation` characters render as 2 columns, and a
  /// VS16 selector promotes its base to 2. Default is true.
  ///
  /// Narrower in effect than it sounds: UAX #11 ED4 (amended in Unicode 9)
  /// folds `Emoji_Presentation=Yes` into East Asian *Wide*, so most emoji are
  /// already 2 by [DefaultWidthResolver]'s wide table and this flag cannot
  /// narrow them. What it does govern is the set ED4 explicitly excludes —
  /// `Regional_Indicator` (flags) — plus the VS16 promotion of an otherwise
  /// narrow base.
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

/// Default width resolver: East Asian Width (UAX #11) and emoji presentation
/// (UTS #51), from tables generated over the full Unicode Character Database —
/// see width_tables.dart. Complete rather than excerpted, so a code point
/// nobody anticipated still gets the width the standard assigns it instead of
/// falling through to a guess.
///
/// Two things it does NOT get from a table, because neither is a per-code-point
/// property: presentation selectors (VS15/VS16 act on the whole cluster) and
/// the cap at 2 cells, which is where the terminal ecosystem converged
/// regardless of what the data says.
///
/// Width is a *model* of what the terminal will draw, never a guarantee — no
/// protocol exists to ask. Where the model is least certain,
/// [hasUncertainWidth] tells the renderer to contain the disagreement.
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

    // A presentation selector (UTS #51) switches the base between text and
    // emoji presentation, which changes how wide the terminal draws it. This is
    // a RULE over the cluster, not a table row per code point — it holds for
    // every emoji-capable base, so it covers the whole VS16 family a
    // block-by-block table keeps missing: ⭐️ ❤️ ☑️ ⚠️ each measured 1 before
    // this while every terminal draws them at 2.
    //
    // Scanned on the same iterator that produced the base, so there is no
    // second pass; for the common single-rune cluster the loop exits at once.
    while (iterator.moveNext()) {
      final r = iterator.current;
      if (r == 0xFE0F) {
        // VS16 — emoji presentation.
        if (profile.emojiIsWide) return 2;
        break; // Emoji disabled: fall back to the base's own rules.
      }
      if (r == 0xFE0E) return 1; // VS15 — text presentation is always narrow.
    }

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

    // The code unit that ended the run may be an Extend belonging to the LAST
    // ASCII character's cluster — '1' + VS16 + U+20E3 (1️⃣) is a single cluster
    // with an ASCII base. Peeling that base off measures the two halves
    // separately and loses the cluster's real width, so hand the last ASCII
    // character back to the grapheme path. (The fast path's premise — one ASCII
    // code unit is one width-1 cluster — is only true when nothing combines
    // onto it.)
    if (asciiPrefix > 0 && _isExtender(text.codeUnitAt(asciiPrefix))) {
      asciiPrefix--;
    }

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
  // GENERATED from the Unicode Character Database — see width_tables.dart and
  // tool/ucd_width_tables.dart. These used to be hand-written "pragmatic
  // excerpts", which is the one approach no mature width library takes: the
  // excerpts were wrong for a third of the box-drawing block and classified the
  // whole Dingbats range as emoji, which desynced entire frames. Deliberate
  // deviations from the raw UCD live in the generator's `_curate`, documented
  // there. Do not add ranges here.

  /// Code units that attach to a preceding base instead of starting their own
  /// cluster. Only the ranges that can follow an ASCII base matter here — this
  /// guards [widthOfText]'s fast path, nothing else. Not UCD-derived: it is a
  /// cluster-boundary question, not a width one.
  bool _isExtender(int c) =>
      (c >= 0x0300 && c <= 0x036F) || // combining diacriticals
      (c >= 0x20D0 && c <= 0x20FF) || // marks for symbols (incl. keycap U+20E3)
      (c >= 0xFE00 && c <= 0xFE0F) || // variation selectors
      (c >= 0xFE20 && c <= 0xFE2F) || // combining half marks
      c == 0x200D; // ZWJ

  bool _isZeroWidth(int r) => _inRanges(zeroWidthRanges, r);

  bool _isWide(int r) => _inRanges(wideRanges, r);

  bool _isEmojiPresentation(int r) => _inRanges(emojiPresentationRanges, r);

  bool _isAmbiguous(int r) => _inRanges(ambiguousRanges, r);
}

/// Binary search over a flat, sorted list of INCLUSIVE `[start, end]` pairs.
///
/// Allocation-free and called per non-ASCII grapheme on the layout hot path;
/// the ASCII fast paths in [DefaultWidthResolver] short-circuit before reaching
/// any of this, so the common case never pays for it.
bool _inRanges(List<int> ranges, int r) {
  var lo = 0;
  var hi = (ranges.length >> 1) - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final i = mid << 1;
    if (r < ranges[i]) {
      hi = mid - 1;
    } else if (r > ranges[i + 1]) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Whether a terminal's *rendered* width for [grapheme] is genuinely likely to
/// disagree with the width model — i.e. whether getting this glyph wrong is a
/// live risk rather than a theoretical one.
///
/// True for the emoji-capable clusters, where terminals and fonts really do
/// differ: an explicit presentation selector or ZWJ, the emoji planes, and the
/// Misc-Symbols/Dingbats block (where ✓ ✗ ☀ live — the block whose
/// misclassification desynced whole frames). False for ASCII and CJK, where
/// every implementation agrees, and false for box drawing, blocks, geometric
/// shapes and arrows: those are UAX #11 Ambiguous, answered by the startup
/// probe, and they appear in long runs where pinning would cost real bytes.
///
/// The renderer uses this to decide whether to pin each following cell to an
/// absolute column. That containment is what keeps a width disagreement a local
/// cosmetic artifact instead of shifting every subsequent cell on the row —
/// the difference between a smudged glyph and a garbled frame.
bool hasUncertainWidth(String grapheme) {
  if (grapheme.isEmpty) return false;
  // Single-code-unit fast path, allocation-free: this is called per dirty
  // non-ASCII cell, and box-drawing runs would otherwise pay a runes iterator
  // per cell to be told what a range check answers. Only true clusters
  // (surrogate pairs, ZWJ sequences, selectors) need the walk below.
  if (grapheme.length == 1) {
    final c = grapheme.codeUnitAt(0);
    if (c >= 0x20 && c <= 0x7E) return false; // ASCII is certain
    return c >= 0x2600 && c <= 0x27BF; // misc symbols & dingbats
  }
  final iterator = grapheme.runes.iterator;
  if (!iterator.moveNext()) return false;
  final base = iterator.current;
  if (base >= 0x2600 && base <= 0x27BF) return true; // misc symbols, dingbats
  if (base >= 0x1F000 && base <= 0x1FAFF) return true; // emoji planes
  if (base >= 0x1F1E6 && base <= 0x1F1FF) return true; // regional indicators
  while (iterator.moveNext()) {
    final r = iterator.current;
    // A presentation selector or ZWJ means the cluster's rendering is
    // font-negotiated, which is exactly where implementations diverge.
    if (r == 0xFE0E || r == 0xFE0F || r == 0x200D) return true;
  }
  return false;
}
