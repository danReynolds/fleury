// SelectableTextMixin — shared text-selection algorithm.
//
// The selection algorithm is style-agnostic: it operates on flat text
// (the concatenation of every line's graphemes with `\n` separators),
// the painted bounds captured at paint time, and the width resolver.
// `RenderText` and `RenderRichText` differ only in how they STYLE the
// painted cells, so both can mix in this implementation and feed their
// flat lines in through three small abstract members.
//
// The mixin owns:
//   - the live selection edges (`_selStart`, `_selEnd`)
//   - the published [SelectionGeometry]
//   - every Selectable interface method
//   - the per-cell `isOffsetSelected` hook used by paint code to flip
//     the highlight on for selected cells
//
// The host provides:
//   - [selectionBounds]   — paint-time CellRect (null when unpainted)
//   - [selectionLines]    — flat text per visually-laid-out line
//   - [selectionWidthResolver] / [selectionProfile] — for grapheme widths
//
// Concrete classes still need `with ChangeNotifier, SelectionRegistrant`
// to get the registration machinery; the mixin only handles the
// algorithm.

import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import '../widgets/selection/selectable.dart';
import '../widgets/selection/selection.dart';
import '../widgets/selection/selection_event.dart';
import 'render_object.dart';
import 'width_resolver.dart';

/// Edge-relation between a screen-space point and a Selectable's
/// painted rect. `before` and `after` propagate up to the
/// [SelectionContainerDelegate] so it can walk to the previous/next
/// Selectable; `inside` carries a character offset within this
/// leaf's flat content.
enum TextEdgeKind { none, before, inside, after }

/// One edge (start or end) of the selection as it relates to a
/// single Selectable. The mixin keeps two of these alive at all
/// times — one for the anchor, one for the moving cursor.
class TextEdgeRelation {
  const TextEdgeRelation.none() : kind = TextEdgeKind.none, offset = -1;
  const TextEdgeRelation.before() : kind = TextEdgeKind.before, offset = -1;
  const TextEdgeRelation.after() : kind = TextEdgeKind.after, offset = -1;
  const TextEdgeRelation.inside(this.offset) : kind = TextEdgeKind.inside;

  final TextEdgeKind kind;
  final int offset;

  SelectionResult asSelectionResult() => switch (kind) {
    TextEdgeKind.before => SelectionResult.previous,
    TextEdgeKind.after => SelectionResult.next,
    TextEdgeKind.inside => SelectionResult.end,
    TextEdgeKind.none => SelectionResult.none,
  };
}

/// The shared selection algorithm. Mix this in to a [RenderObject]
/// that also mixes in `ChangeNotifier` (for listener machinery) and
/// `SelectionRegistrant` (for ambient-area attach/detach).
///
/// ```dart
/// class RenderText extends RenderObject
///     with ChangeNotifier, SelectionRegistrant, SelectableTextMixin
///     implements Selectable { ... }
/// ```
mixin SelectableTextMixin on RenderObject implements Selectable {
  // ----- Required from the host -------------------------------------

  /// The painted rect of this Selectable in SCREEN coordinates,
  /// including any portion currently scrolled off (or otherwise
  /// clipped). The grapheme-walk algorithm anchors at
  /// `selectionPaintRect.offset` and walks line-by-line from there,
  /// so this must reflect the full content's position even when only
  /// a slice is visible. Null before the first paint.
  CellRect? get selectionPaintRect;

  /// The visible clip applied to this Selectable in screen
  /// coordinates, or null when no clip is active (the legacy case
  /// where everything painted IS on-screen). Hit-tests reject
  /// points outside `selectionPaintRect ∩ selectionClipRect`.
  CellRect? get selectionClipRect;

  /// The flat text of each visually-laid-out line (post-wrap). The
  /// concatenation `selectionLines.join('\n')` is the flat content
  /// the selection algorithm operates on.
  List<String> get selectionLines;

  /// Width resolver used to compute grapheme widths when mapping
  /// screen columns to character offsets.
  WidthResolver get selectionWidthResolver;

  /// Terminal profile passed to [selectionWidthResolver].
  TerminalProfile get selectionProfile;

  /// Subclass hook: notify the framework that listener-attached
  /// observers should run. Hosts mixing in `ChangeNotifier` already
  /// provide a matching `notifyListeners()`.
  void notifyListeners();

  // ----- Mixin state -------------------------------------------------

  SelectionGeometry _selectionGeometry = SelectionGeometry.empty;
  TextEdgeRelation _selStart = const TextEdgeRelation.none();
  TextEdgeRelation _selEnd = const TextEdgeRelation.none();

  /// The full painted rect of this Selectable in SCREEN coordinates,
  /// including any portion currently scrolled off-screen. Returned to
  /// the delegate as `cellBounds` for reading-order purposes — a
  /// Selectable that scrolled off the top of a viewport still belongs
  /// BEFORE the visible content in the joined selection text, not
  /// after it. Null only before the first paint.
  @override
  CellRect? get cellBounds => selectionPaintRect;

  /// The currently-visible portion of [cellBounds] after applying
  /// the inherited clipRect. Null when the Selectable is fully
  /// off-screen, OR when it hasn't painted yet. Used by visibility
  /// queries (e.g. SelectionArea's auto-scroll, which only counts
  /// visible Selectables toward the edge-detection region).
  @override
  CellRect? get visibleBounds {
    final paint = selectionPaintRect;
    if (paint == null) return null;
    final clip = selectionClipRect;
    if (clip == null) return paint;
    return clip.intersect(paint);
  }

  @override
  SelectionGeometry get geometry => _selectionGeometry;

  @override
  int get contentLength {
    final lines = selectionLines;
    var total = 0;
    for (final line in lines) {
      total += line.length;
    }
    return total + (lines.isEmpty ? 0 : lines.length - 1);
  }

  /// Hook for paint code. Returns true if the character at the given
  /// flat-text offset falls inside the current selection range.
  bool isOffsetSelected(int off) {
    final range = getSelectionRange();
    if (range == null) return false;
    return off >= range.start && off < range.end;
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event) {
      case SelectionEdgeUpdateEvent(:final globalPosition, :final isStart):
        final rel = _relateScreenPoint(globalPosition);
        if (isStart) {
          _selStart = rel;
        } else {
          _selEnd = rel;
        }
        _recomputeGeometry();
        return rel.asSelectionResult();
      case SelectionClearEvent():
        _selStart = const TextEdgeRelation.none();
        _selEnd = const TextEdgeRelation.none();
        _recomputeGeometry();
        return SelectionResult.none;
      case SelectionGranularEvent(:final granularity, :final globalPosition):
        switch (granularity) {
          case SelectionGranularity.all:
            _selStart = const TextEdgeRelation.inside(0);
            _selEnd = TextEdgeRelation.inside(contentLength);
            _recomputeGeometry();
            return SelectionResult.end;
          case SelectionGranularity.word:
            final off = globalPosition == null
                ? null
                : _offsetAtScreenPoint(globalPosition);
            // A click past the last character of the text (on the
            // empty trailing cells of a SizedBox wrapper, say) maps
            // to `contentLength` — that's a position between words,
            // not a word. Skip rather than back-walking to the
            // previous word.
            if (off == null || off >= contentLength) {
              return SelectionResult.none;
            }
            final (start, end) = _wordBoundariesAt(off);
            if (start == end) return SelectionResult.none;
            _selStart = TextEdgeRelation.inside(start);
            _selEnd = TextEdgeRelation.inside(end);
            _recomputeGeometry();
            return SelectionResult.end;
          case SelectionGranularity.line:
            final off = globalPosition == null
                ? null
                : _offsetAtScreenPoint(globalPosition);
            if (off == null) return SelectionResult.none;
            final (start, end) = _lineBoundariesAt(off);
            if (start == end) return SelectionResult.none;
            _selStart = TextEdgeRelation.inside(start);
            _selEnd = TextEdgeRelation.inside(end);
            _recomputeGeometry();
            return SelectionResult.end;
        }
    }
  }

  int? _offsetAtScreenPoint(CellOffset point) {
    final rel = _relateScreenPoint(point);
    return rel.kind == TextEdgeKind.inside ? rel.offset : null;
  }

  @override
  CellOffset? nextGraphemeBoundary(CellOffset from, int dCol, int dRow) {
    // Grapheme stepping uses the FULL paint rect — the cursor may
    // extend into rows that are currently scrolled off-screen.
    // (A future "scroll to keep cursor visible" feature would lift
    // that boundary back into the visible window.)
    final bounds = selectionPaintRect;
    if (bounds == null) return null;
    final lines = selectionLines;

    // Vertical motion: only the DESTINATION row needs to live inside
    // our bounds. The source position can be in a different
    // Selectable — that's how Shift+Up/Down hops across widget
    // boundaries (the delegate walks Selectables in reading order;
    // the one that contains the destination row claims the step).
    if (dRow != 0) {
      final newRow = from.row + dRow;
      if (newRow < bounds.offset.row ||
          newRow >= bounds.offset.row + bounds.size.rows) {
        return null;
      }
      final localRow = newRow - bounds.offset.row;
      if (localRow >= lines.length) return null;
      final targetCol = from.col.clamp(
        bounds.offset.col,
        bounds.offset.col + bounds.size.cols - 1,
      );
      var col = bounds.offset.col;
      for (final grapheme in lines[localRow].characters) {
        final w = selectionWidthResolver.widthOfGrapheme(
          grapheme,
          selectionProfile,
        );
        if (targetCol < col + w) {
          return CellOffset(col, newRow);
        }
        col += w;
      }
      return CellOffset(col, newRow);
    }

    // Horizontal motion: the source must be inside our bounds.
    if (from.row < bounds.offset.row ||
        from.row >= bounds.offset.row + bounds.size.rows) {
      return null;
    }
    if (from.col < bounds.offset.col ||
        from.col >= bounds.offset.col + bounds.size.cols) {
      return null;
    }
    final localRow = from.row - bounds.offset.row;
    if (localRow >= lines.length) return null;
    final line = lines[localRow];

    if (dCol > 0) {
      var col = bounds.offset.col;
      for (final grapheme in line.characters) {
        final w = selectionWidthResolver.widthOfGrapheme(
          grapheme,
          selectionProfile,
        );
        if (from.col < col + w) {
          final nextCol = col + w;
          if (nextCol >= bounds.offset.col + bounds.size.cols) {
            if (localRow + 1 < lines.length) {
              return CellOffset(bounds.offset.col, from.row + 1);
            }
            return null;
          }
          return CellOffset(nextCol, from.row);
        }
        col += w;
      }
      if (localRow + 1 < lines.length) {
        return CellOffset(bounds.offset.col, from.row + 1);
      }
      return null;
    } else if (dCol < 0) {
      var col = bounds.offset.col;
      int? previousStart;
      for (final grapheme in line.characters) {
        final w = selectionWidthResolver.widthOfGrapheme(
          grapheme,
          selectionProfile,
        );
        if (from.col < col + w) {
          if (previousStart != null) {
            return CellOffset(previousStart, from.row);
          }
          if (localRow > 0) {
            return _lastBoundaryOnRow(localRow - 1);
          }
          return null;
        }
        previousStart = col;
        col += w;
      }
      if (previousStart != null) {
        return CellOffset(previousStart, from.row);
      }
      if (localRow > 0) return _lastBoundaryOnRow(localRow - 1);
      return null;
    }

    return null;
  }

  CellOffset? _lastBoundaryOnRow(int localRow) {
    // Same as nextGraphemeBoundary: anchor against the full paint
    // rect, since this is grapheme-stepping geometry.
    final bounds = selectionPaintRect;
    if (bounds == null) return null;
    final lines = selectionLines;
    if (localRow < 0 || localRow >= lines.length) return null;
    var col = bounds.offset.col;
    int? lastStart;
    for (final grapheme in lines[localRow].characters) {
      lastStart = col;
      col += selectionWidthResolver.widthOfGrapheme(grapheme, selectionProfile);
    }
    return lastStart == null
        ? CellOffset(bounds.offset.col, bounds.offset.row + localRow)
        : CellOffset(lastStart, bounds.offset.row + localRow);
  }

  /// Returns `(start, end)` of the word surrounding [offset]. Four
  /// rules in priority order:
  ///
  ///   1. CJK / Hangul / Hiragana / Katakana characters each form
  ///      their own word.
  ///   2. Latin/ASCII word characters (alphanumerics + underscore +
  ///      every non-ASCII letter) expand into the contiguous run.
  ///   3. Apostrophes / right single quotes between two word
  ///      characters extend the run (UAX #29 MidLetter).
  ///   4. Anything else selects just the single character.
  (int, int) _wordBoundariesAt(int offset) {
    final text = _flatText();
    if (text.isEmpty) return (0, 0);
    final clamped = offset.clamp(0, text.length - 1);
    final codeUnit = text.codeUnitAt(clamped);

    if (_isCjkChar(codeUnit)) {
      return (clamped, clamped + 1);
    }
    if (!_isWordChar(codeUnit)) {
      return (clamped, clamped + 1);
    }

    var start = clamped;
    while (start > 0) {
      final prev = text.codeUnitAt(start - 1);
      if (_isWordChar(prev) && !_isCjkChar(prev)) {
        start--;
        continue;
      }
      if (_isMidLetter(prev) && start - 2 >= 0) {
        final prevPrev = text.codeUnitAt(start - 2);
        if (_isWordChar(prevPrev) && !_isCjkChar(prevPrev)) {
          start -= 2;
          continue;
        }
      }
      break;
    }

    var end = clamped;
    while (end < text.length) {
      final cur = text.codeUnitAt(end);
      if (_isWordChar(cur) && !_isCjkChar(cur)) {
        end++;
        continue;
      }
      if (_isMidLetter(cur) && end + 1 < text.length) {
        final next = text.codeUnitAt(end + 1);
        if (_isWordChar(next) && !_isCjkChar(next)) {
          end += 2;
          continue;
        }
      }
      break;
    }
    return (start, end);
  }

  static bool _isMidLetter(int codeUnit) {
    return codeUnit == 0x27 || codeUnit == 0x2019;
  }

  static bool _isCjkChar(int codeUnit) {
    return (codeUnit >= 0x3040 && codeUnit <= 0x30FF) || // Hiragana + Katakana
        (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) || // CJK Unified Ideographs
        (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF) || // Hangul Syllables
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) || // CJK Ext A
        (codeUnit >= 0xF900 && codeUnit <= 0xFAFF); // CJK Compatibility
  }

  (int, int) _lineBoundariesAt(int offset) {
    final lines = selectionLines;
    var lineStart = 0;
    for (var i = 0; i < lines.length; i++) {
      final lineEnd = lineStart + lines[i].length;
      if (offset <= lineEnd) return (lineStart, lineEnd);
      lineStart = lineEnd + 1; // +1 for implicit newline
    }
    return (0, contentLength);
  }

  static bool _isWordChar(int codeUnit) {
    if (codeUnit == 0x5F) return true; // '_'
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return true; // 0-9
    if (codeUnit >= 0x41 && codeUnit <= 0x5A) return true; // A-Z
    if (codeUnit >= 0x61 && codeUnit <= 0x7A) return true; // a-z
    return codeUnit > 0x7F;
  }

  @override
  SelectedContent? getSelectedContent() {
    final range = getSelectionRange();
    if (range == null || range.start == range.end) return null;
    return SelectedContent(
      plainText: _flatText().substring(range.start, range.end),
    );
  }

  @override
  ({int end, int start})? getSelectionRange() {
    final s = _selStart;
    final e = _selEnd;
    if (s.kind == TextEdgeKind.none && e.kind == TextEdgeKind.none) {
      return null;
    }
    final length = contentLength;
    int resolve(TextEdgeRelation here, TextEdgeRelation other) {
      switch (here.kind) {
        case TextEdgeKind.inside:
          return here.offset;
        case TextEdgeKind.before:
          return 0;
        case TextEdgeKind.after:
          return length;
        case TextEdgeKind.none:
          return resolve(other, here);
      }
    }

    final sOff = resolve(s, e);
    final eOff = resolve(e, s);
    if (sOff == eOff) return null;
    return sOff < eOff ? (start: sOff, end: eOff) : (start: eOff, end: sOff);
  }

  TextEdgeRelation _relateScreenPoint(CellOffset point) {
    final paintRect = selectionPaintRect;
    if (paintRect == null) return const TextEdgeRelation.none();

    // "Before / after" is determined by paint rect, NOT by the clip.
    // This is critical for drag-extension across a scrolled boundary:
    // a Selectable whose content is currently scrolled off-screen
    // still has a defined position relative to a cursor inside the
    // visible viewport. If we used the clipped rect instead, the
    // off-screen Selectable would report `none` and the dispatch
    // would erase its in-flight edge state — silently breaking
    // selections that span the scroll boundary.
    //
    // We only check ROW for before/after — a click past the right
    // edge of a short line should land at end-of-line on THAT row,
    // not "after the whole Selectable" (which would mean past the
    // last row). The grapheme walk below handles past-end-of-row by
    // returning inside(end-of-line-offset).
    if (point.row < paintRect.offset.row) {
      return const TextEdgeRelation.before();
    }
    if (point.row >= paintRect.offset.row + paintRect.size.rows) {
      return const TextEdgeRelation.after();
    }
    if (point.col < paintRect.offset.col) {
      return const TextEdgeRelation.before();
    }

    // The point sits inside our paint rect vertically. Check the
    // clip — if our row is scrolled off-screen, this is not a real
    // hit; resolve to before/after based on which clip edge we fell.
    //
    // We only check the VERTICAL clip dimension here. The framework
    // currently only has vertical scroll (`ScrollView`); when a
    // horizontal-scroll widget lands, the clip's column range needs
    // an analogous check (and the grapheme walk needs to start at
    // `paintRect.offset.col + horizontalScroll` instead of
    // `paintRect.offset.col`). Left as a single-axis-only design
    // note so it's not silently extended without thinking.
    final clip = selectionClipRect;
    if (clip != null) {
      if (point.row < clip.offset.row) return const TextEdgeRelation.before();
      if (point.row >= clip.offset.row + clip.size.rows) {
        return const TextEdgeRelation.after();
      }
    }

    // Inside paint rect AND inside the visible clip. Walk graphemes
    // anchored at the full paint rect to find the content offset.
    final lines = selectionLines;
    final localRow = point.row - paintRect.offset.row;
    if (localRow < 0 || localRow >= lines.length) {
      return localRow < 0
          ? const TextEdgeRelation.before()
          : const TextEdgeRelation.after();
    }
    var col = paintRect.offset.col;
    var off = _offsetOfLineStart(localRow);
    for (final grapheme in lines[localRow].characters) {
      final w = selectionWidthResolver.widthOfGrapheme(
        grapheme,
        selectionProfile,
      );
      if (point.col < col + w) return TextEdgeRelation.inside(off);
      col += w;
      off += grapheme.length;
    }
    return TextEdgeRelation.inside(off);
  }

  int _offsetOfLineStart(int lineIndex) {
    final lines = selectionLines;
    var off = 0;
    for (var i = 0; i < lineIndex; i++) {
      off += lines[i].length + 1; // +1 for implicit newline
    }
    return off;
  }

  String _flatText() => selectionLines.join('\n');

  void _recomputeGeometry() {
    final range = getSelectionRange();
    final next = range == null
        ? SelectionGeometry.empty
        : SelectionGeometry(
            status: SelectionStatus.collapsed,
            startEdgeOffsetInContent: range.start,
            endEdgeOffsetInContent: range.end,
          );
    if (_selectionGeometry == next) return;
    _selectionGeometry = next;
    notifyListeners();
    // Paint-only: a selection-range change moves which cells are
    // highlighted, never the text's size or wrap. `performLayout` produces
    // the line structure that selection maps onto (layout -> selection), not
    // the reverse, so the cached layout stays valid. cellBounds for
    // reading-order selection are refreshed during paint, which
    // [markNeedsPaintOnly] still triggers via the nearest repaint boundary.
    markNeedsPaintOnly();
  }
}
