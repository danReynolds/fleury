// Concrete render objects used by the first wave of layout widgets:
// RenderText, RenderSizedBox, RenderPadding. Multi-child render objects
// (RenderFlex, RenderStack) land in a later slice.

import 'package:characters/characters.dart';

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../widgets/selection/selectable.dart';
import 'border.dart';
import 'cell.dart';
import 'cell_buffer.dart';
import 'edge_insets.dart';
import 'layout.dart';
import 'render_object.dart';
import 'selectable_text_mixin.dart';
import 'text_projection.dart';
import 'text_sanitizer.dart';
import 'width_resolver.dart';

/// How text that exceeds its line/height budget is shown.
enum TextOverflow {
  /// Cut off at the edge.
  clip,

  /// Cut off with a trailing ellipsis (…) on the last visible line.
  ellipsis,
}

/// Horizontal alignment of each line within the available width.
enum TextAlign {
  /// Pin to the left edge — the natural reading order for English-
  /// like LTR text and the default.
  left,

  /// Center each line in the available width.
  center,

  /// Pin to the right edge — useful for status-line numbers, key
  /// hints in the corner, etc.
  right,
}

// ---------------------------------------------------------------------------
// RenderText
// ---------------------------------------------------------------------------

/// Paints a sanitized, grapheme-aware string into the terminal grid.
///
/// With [softWrap] true (default), the text is broken into lines on
/// word boundaries when it exceeds the available width. Words longer
/// than the available width are broken at grapheme boundaries.
/// With [softWrap] false, automatic reflow is disabled; explicit newlines
/// still create rows, and each long row is clipped horizontally.
///
/// The text is sanitized once at construction; later updates re-
/// sanitize. Wide graphemes occupy leading + continuation cells via
/// `CellBuffer`.
class RenderText extends RenderObject
    with ChangeNotifier, SelectionRegistrant, SelectableTextMixin
    implements Selectable {
  RenderText({
    required String text,
    CellStyle style = CellStyle.none,
    bool softWrap = true,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
    TextAlign textAlign = TextAlign.left,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TextPresentationPolicy textPolicy = TextPresentationPolicy.spec,
  }) : _logicalText = _sanitizePreservingNewlines(text),
       _style = style,
       _softWrap = softWrap,
       _maxLines = maxLines,
       _overflow = overflow,
       _textAlign = textAlign,
       _widthResolver = widthResolver,
       _textPolicy = textPolicy {
    _projection = projectText(_logicalText, policy: _textPolicy);
    _text = _projection.displayText;
    _recomputeIntrinsicWidth();
  }

  /// `\n` is a C0 control that [sanitizeForDisplay] would replace with
  /// U+FFFD, but at the Text-widget layer it's meaningful — it forces
  /// a line break. Split first, sanitize each segment, rejoin so the
  /// downstream cell buffer still never sees a raw newline byte.
  static String _sanitizePreservingNewlines(String value) {
    if (!value.contains('\n')) return sanitizeForDisplay(value);
    return value.split('\n').map(sanitizeForDisplay).join('\n');
  }

  /// Canonical (post-sanitization) text — what [text], copy, and semantics
  /// answer with. Geometry never reads it directly.
  String _logicalText;

  /// The display projection of [_logicalText] under [_textPolicy] — the
  /// per-render-object memo (RFC 0019 §6.4): recomputed only when the logical
  /// text or the operational policy changes, never per frame. Identity (same
  /// string object, zero mappings) unless lowering is authorized AND the text
  /// contains a recognized emoji ZWJ sequence.
  late TextProjection _projection;

  /// What layout measures, wrap breaks, and paint draws:
  /// `_projection.displayText`. Every geometry path in this class operates on
  /// this string, so display offsets (selection hit testing, painting) are
  /// consistent by construction; the projection maps them back to
  /// [_logicalText] where data leaves the geometry world.
  late String _text;

  CellStyle _style;
  bool _softWrap;
  int? _maxLines;
  TextOverflow _overflow;
  TextAlign _textAlign;
  WidthResolver _widthResolver;
  TextPresentationPolicy _textPolicy;
  int _intrinsicWidth = 0;

  /// Width axes of [_textPolicy] — the value every measurement call uses.
  CellWidthPolicy get _policy => _textPolicy.widths;

  /// Set during layout when [maxLines] cut off real content, so paint
  /// knows the last visible line should be ellipsized.
  bool _moreLinesTruncated = false;

  /// Lines produced by the most recent layout. Empty until [layout]
  /// has been called at least once.
  List<String> _lines = const <String>[];

  // Widths measured by the current multi-line layout. A single unwrapped
  // line uses _intrinsicWidth directly, so short labels allocate no list.
  List<int> _lineWidths = const <int>[];

  /// Memoized layout result, keyed on the constraints that produced
  /// it. The wrap algorithm is the hottest path in the renderer
  /// (see `benchmark/widgets_benchmarks.dart`); reusing a cached
  /// result across frames when neither the text nor the constraints
  /// changed eliminates ~80% of the steady-state layout cost. Any
  /// text / softWrap / width-resolver / policy setter that would
  /// change the wrap output also calls [_invalidateLayoutCache].
  CellConstraints? _cachedConstraints;
  CellSize? _cachedSize;

  void _invalidateLayoutCache() {
    _cachedConstraints = null;
    _cachedSize = null;
    markNeedsLayout();
  }

  /// The canonical logical text (RFC 0019 decision 3): what was set, not what
  /// is painted. The display form lives in [_text] via [_projection].
  String get text => _logicalText;
  set text(String value) {
    final sanitized = _sanitizePreservingNewlines(value);
    if (sanitized == _logicalText) return;
    _logicalText = sanitized;
    _projection = projectText(sanitized, policy: _textPolicy);
    final display = _projection.displayText;
    final nextIntrinsicWidth = _measureIntrinsicWidth(display);
    if (_canReuseCurrentSingleLineLayout(display, nextIntrinsicWidth)) {
      _text = display;
      _intrinsicWidth = nextIntrinsicWidth;
      _lines = <String>[display];
      _lineWidths = const <int>[];
      _moreLinesTruncated = false;
      markNeedsPaintOnly();
      return;
    }
    _text = display;
    _intrinsicWidth = nextIntrinsicWidth;
    _invalidateLayoutCache();
  }

  CellStyle get style => _style;
  set style(CellStyle value) {
    if (_style == value) return;
    _style = value;
    // Style is paint-only; layout result is unaffected.
    markNeedsPaintOnly();
  }

  bool get softWrap => _softWrap;
  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    _invalidateLayoutCache();
  }

  int? get maxLines => _maxLines;
  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    _invalidateLayoutCache();
  }

  // Overflow only affects paint (which graphemes/ellipsis show), not the
  // line breaking, so changing it leaves the layout cache valid.
  // ignore: unnecessary_getters_setters
  TextOverflow get overflow => _overflow;
  set overflow(TextOverflow value) {
    if (_overflow == value) return;
    _overflow = value;
    markNeedsPaintOnly();
  }

  // textAlign also only affects paint — it shifts each line's start
  // column inside the box but doesn't change which graphemes wrap
  // where. Layout cache stays valid across changes.
  // ignore: unnecessary_getters_setters
  TextAlign get textAlign => _textAlign;
  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    markNeedsPaintOnly();
  }

  WidthResolver get widthResolver => _widthResolver;
  set widthResolver(WidthResolver value) {
    if (identical(_widthResolver, value)) return;
    _widthResolver = value;
    _recomputeIntrinsicWidth();
    _invalidateLayoutCache();
  }

  TextPresentationPolicy get textPolicy => _textPolicy;
  set textPolicy(TextPresentationPolicy value) {
    // Operational equality only — provenance never reaches this layer, so a
    // re-derived policy with identical geometry is a no-op (RFC 0019
    // decision 17). A real change dirties LAYOUT, not merely paint
    // (property gate 14): both the width axes and the lowering decision
    // change which cells the text occupies.
    if (_textPolicy == value) return;
    _textPolicy = value;
    _projection = projectText(_logicalText, policy: value);
    _text = _projection.displayText;
    _recomputeIntrinsicWidth();
    _invalidateLayoutCache();
  }

  /// Display width the text would occupy if given unbounded horizontal
  /// space, ignoring wrapping. Equal to `widthResolver.widthOfText(text)`.
  int get intrinsicWidth => _intrinsicWidth;

  void _recomputeIntrinsicWidth() {
    _intrinsicWidth = _measureIntrinsicWidth(_text);
  }

  int _measureIntrinsicWidth(String value) {
    if (value.isEmpty) return 0;
    if (!value.contains('\n')) {
      return _widthResolver.widthOfText(value, _policy);
    }
    var widest = 0;
    for (final line in value.split('\n')) {
      final w = _widthResolver.widthOfText(line, _policy);
      if (w > widest) widest = w;
    }
    return widest;
  }

  bool _canReuseCurrentSingleLineLayout(
    String nextText,
    int nextIntrinsicWidth,
  ) {
    if (needsLayout) return false;
    if (_text.isEmpty != nextText.isEmpty) return false;
    if (_text.contains('\n') || nextText.contains('\n')) return false;
    if (_intrinsicWidth != nextIntrinsicWidth) return false;
    if (!_softWrap) return true;
    final maxCols = constraints.maxCols;
    return maxCols == null || nextIntrinsicWidth <= maxCols;
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_text.isEmpty) {
      _lines = const <String>[];
      _lineWidths = const <int>[];
      _moreLinesTruncated = false;
      return constraints.constrain(CellSize.zero);
    }
    final maxCols = constraints.maxCols;
    final hasNewlines = _text.contains('\n');

    // Single-line fast path: no newlines AND either wrapping is off,
    // no width bound, or the text already fits. This is the dominant
    // case for short labels (ListView items, button text). Skip the
    // layout cache here — it's already cheap, and the cache-check
    // overhead would be a net loss.
    if (!hasNewlines &&
        (!_softWrap || maxCols == null || _intrinsicWidth <= maxCols)) {
      _lines = <String>[_text];
      _lineWidths = const <int>[];
      _moreLinesTruncated = false;
      final cols = maxCols == null
          ? _intrinsicWidth
          : (_intrinsicWidth < maxCols ? _intrinsicWidth : maxCols);
      return constraints.constrain(CellSize(cols, 1));
    }

    // Slow paths (real wrap, multi-paragraph): consult the cache.
    // These are the cases where re-running the algorithm every frame
    // dominated the wrap-Text benchmarks.
    final cached = _cachedSize;
    if (cached != null && constraints == _cachedConstraints) {
      return cached;
    }

    if (!_softWrap || maxCols == null) {
      // No-wrap with newlines: split into paragraphs, clip each to
      // maxCols at paint, but don't reflow.
      _lines = _text.split('\n');
    } else {
      // Soft-wrap path (also handles paragraph splitting on \n).
      _lines = _wrap(_text, maxCols);
    }

    // Cap to maxLines; the last kept line gets ellipsized at paint.
    _moreLinesTruncated = false;
    if (_maxLines != null && _lines.length > _maxLines!) {
      _moreLinesTruncated = true;
      _lines = _lines.sublist(0, _maxLines!);
    }

    var maxLineWidth = 0;
    final lineWidths = <int>[];
    for (final line in _lines) {
      final w = _widthResolver.widthOfText(line, _policy);
      lineWidths.add(w);
      if (w > maxLineWidth) maxLineWidth = w;
    }
    _lineWidths = lineWidths;
    final cols = maxCols == null
        ? maxLineWidth
        : (maxLineWidth < maxCols ? maxLineWidth : maxCols);
    final result = constraints.constrain(CellSize(cols, _lines.length));

    _cachedConstraints = constraints;
    _cachedSize = result;
    return result;
  }

  // Intrinsic sizing: the unwrapped natural width, and the line count under
  // soft-wrap at a given width. v1 reports the same value for min/max width
  // (no longest-word break analysis); good enough for `IntrinsicWidth` to
  // size a child to its full text width.
  @override
  int computeMaxIntrinsicWidth(int? height) => _intrinsicWidth;

  @override
  int computeMinIntrinsicWidth(int? height) => _intrinsicWidth;

  @override
  int computeMaxIntrinsicHeight(int? width) => _linesAt(width);

  @override
  int computeMinIntrinsicHeight(int? width) => _linesAt(width);

  int _linesAt(int? width) {
    if (_text.isEmpty) return 0;
    final List<String> lines;
    if (width == null || !_softWrap || width >= _intrinsicWidth) {
      lines = _text.split('\n');
    } else {
      lines = _wrap(_text, width);
    }
    final n = lines.length;
    if (_maxLines != null && n > _maxLines!) return _maxLines!;
    return n;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    // Selection geometry lives in SCREEN coordinates. We track two
    // rectangles:
    //
    //   - paintRect: where this Selectable's content WOULD live on
    //     screen if nothing clipped it (the full bounds, including
    //     scrolled-off rows). The grapheme-walk algorithm walks lines
    //     starting at `paintRect.offset.row`, so this MUST be the
    //     anchor of the full content even when partially off-screen.
    //
    //   - clipRect: the visible window. A click outside the clip is
    //     not a hit; the delegate treats it as before/after.
    //
    // `cellBounds` (the public Selectable interface) reports the
    // INTERSECTION so the delegate's reading-order sort and visible-
    // region checks see only the on-screen portion. Selectables with
    // empty intersections (fully scrolled off) report null and are
    // skipped.
    final selectionBounds = CellRect(
      offset: screenOffset ?? offset,
      size: size,
    );
    _updateRetainedSelectionGeometry(selectionBounds, clipRect);
    if (RetainedPaintGeometryCapture.isActive) {
      RetainedPaintGeometryCapture.record(
        _replaySelectionGeometry,
        selectionBounds,
        clipRect: clipRect,
      );
    }
    if (_text.isEmpty || size.isEmpty) return;
    final visibleRows = _lines.length < size.rows ? _lines.length : size.rows;
    var lineStartOffset = 0;
    for (var i = 0; i < visibleRows; i++) {
      final isLastVisible = i == visibleRows - 1;
      final lineWidth = _lineWidths.isEmpty ? _intrinsicWidth : _lineWidths[i];
      final clipped = lineWidth > size.cols;
      final ellipsize =
          _overflow == TextOverflow.ellipsis &&
          isLastVisible &&
          (clipped || (_moreLinesTruncated && i == _lines.length - 1));
      // Shift each line's start column to honour textAlign. When the
      // line is wider than the box (clipped), alignment has no slack
      // to distribute so we pin at 0.
      final slack = size.cols - lineWidth;
      final dx = (slack <= 0)
          ? 0
          : switch (_textAlign) {
              TextAlign.left => 0,
              TextAlign.center => slack ~/ 2,
              TextAlign.right => slack,
            };
      _paintLine(
        buffer,
        _lines[i],
        offset.col + dx,
        offset.row + i,
        ellipsize,
        offset.col + size.cols,
        lineStartOffset,
      );
      lineStartOffset += _lines[i].length + 1; // implicit newline
    }
  }

  void _paintLine(
    CellBuffer buffer,
    String line,
    int startCol,
    int row,
    bool ellipsize,
    int maxCol,
    int lineStartOffset,
  ) {
    // Reserve what the ellipsis actually measures on this surface. `…` is
    // East Asian Ambiguous, so an ambiguous-wide terminal draws it two cells
    // wide; reserving one there put the ellipsis one column past the box —
    // where it was degraded to `?` at the buffer edge, or overwrote the
    // neighbour otherwise (RFC 0019).
    final ellipsisWidth = ellipsize
        ? _widthResolver.widthOfGrapheme(_ellipsis, _policy)
        : 0;
    final contentMaxCol = maxCol - ellipsisWidth;
    var col = startCol;
    var off = lineStartOffset;
    for (final grapheme in line.characters) {
      final w = _widthResolver.widthOfGrapheme(grapheme, _policy);
      if (col + w > contentMaxCol) break;
      // Cell style is the painting style merged with a selection
      // highlight (reverse) when this grapheme falls inside the
      // current selection range.
      final cellStyle = isOffsetSelected(off)
          ? _style.merge(const CellStyle(inverse: true))
          : _style;
      paintMeasuredGrapheme(buffer, col, row, grapheme, w, cellStyle);
      col += w;
      off += grapheme.length;
    }
    // `col + ellipsisWidth <= maxCol`, not `col < maxCol`: the ellipsis must
    // fit INSIDE the box, never half-in with its continuation cell over the
    // neighbour.
    if (ellipsize && col + ellipsisWidth <= maxCol) {
      paintMeasuredGrapheme(buffer, col, row, _ellipsis, ellipsisWidth, _style);
    }
  }

  /// The overflow marker. `…` is East Asian Ambiguous — one cell under the
  /// spec policy, two on a surface that measured ambiguous glyphs wide.
  static const String _ellipsis = '…';

  /// Greedy word-wrap. Splits on explicit `\n` first, then within each
  /// paragraph splits on single spaces and greedily packs tokens onto
  /// the current line. Tokens wider than [maxWidth] are broken at
  /// grapheme boundaries. Whitespace that falls at a line break is
  /// dropped rather than carried onto the next line.
  List<String> _wrap(String text, int maxWidth) {
    if (maxWidth <= 0) return <String>[''];
    final lines = <String>[];
    final paragraphs = text.split('\n');
    var paragraphStart = 0;
    for (var p = 0; p < paragraphs.length; p++) {
      _wrapParagraph(paragraphs[p], maxWidth, lines, paragraphStart);
      paragraphStart += paragraphs[p].length + 1;
    }
    return lines;
  }

  void _wrapParagraph(
    String text,
    int maxWidth,
    List<String> out,
    int paragraphStart,
  ) {
    if (text.isEmpty) {
      out.add('');
      return;
    }
    final tokens = text.split(' ');
    final current = StringBuffer();
    var currentWidth = 0;
    var tokenStart = paragraphStart;

    for (final token in tokens) {
      final tokenGlobalStart = tokenStart;
      tokenStart += token.length + 1;
      final isFirstOnLine = currentWidth == 0;
      if (token.isEmpty) {
        // Empty token comes from consecutive spaces. Honor it as a
        // single space when there's room; otherwise drop it (don't
        // start a new line with leading whitespace).
        if (!isFirstOnLine && currentWidth + 1 <= maxWidth) {
          current.write(' ');
          currentWidth += 1;
        }
        continue;
      }

      final tokenWidth = _widthResolver.widthOfText(token, _policy);
      final needed = isFirstOnLine ? tokenWidth : 1 + tokenWidth;

      if (currentWidth + needed <= maxWidth) {
        if (!isFirstOnLine) {
          current.write(' ');
          currentWidth += 1;
        }
        current.write(token);
        currentWidth += tokenWidth;
        continue;
      }

      // Token doesn't fit on the current line.
      if (!isFirstOnLine) {
        out.add(current.toString());
        current.clear();
        currentWidth = 0;
      }
      if (tokenWidth <= maxWidth) {
        current.write(token);
        currentWidth = tokenWidth;
        continue;
      }
      // Long token — hard-break at unit boundaries. A unit is one grapheme,
      // or one whole lowered cluster group: the atoms of one source grapheme
      // stay on one line when the group fits, and break apart only when the
      // group alone exceeds the line (RFC 0019 decision 15). May leave a
      // partial fragment in `current` for the next token to extend.
      for (final unit in _breakUnits(token, tokenGlobalStart, maxWidth)) {
        final w = _widthResolver.widthOfText(unit, _policy);
        if (w == 0) {
          current.write(unit);
          continue;
        }
        if (currentWidth + w > maxWidth) {
          out.add(current.toString());
          current.clear();
          currentWidth = 0;
          // A single unit wider than maxWidth gets its own row; paint
          // clipping will trim what doesn't fit.
          if (w > maxWidth) {
            out.add(unit);
            continue;
          }
        }
        current.write(unit);
        currentWidth += w;
      }
    }

    out.add(current.toString());
  }

  /// The hard-break units of [token], whose display offsets start at
  /// [globalStart]: single graphemes, except that a lowered cluster group
  /// travels as one unbreakable unit while it fits [maxWidth] — and as its
  /// individual atoms (each ≤ 2 cells, so each always placeable) when the
  /// group alone exceeds the line.
  ///
  /// Identity projections take the allocation-free grapheme path; this list
  /// materializes only on the already-cold path of an overlong token in
  /// lowered text.
  Iterable<String> _breakUnits(String token, int globalStart, int maxWidth) {
    if (_projection.isIdentity) return token.characters;
    final units = <String>[];
    var i = 0;
    while (i < token.length) {
      final group = _projection.clusterAtDisplay(globalStart + i);
      if (group != null && group.displayRange.start == globalStart + i) {
        final length = group.displayRange.end - group.displayRange.start;
        final groupText = token.substring(i, i + length);
        if (_widthResolver.widthOfText(groupText, _policy) <= maxWidth) {
          units.add(groupText);
        } else {
          for (final atom in group.displayAtomRanges) {
            units.add(
              token.substring(
                i + (atom.start - group.displayRange.start),
                i + (atom.end - group.displayRange.start),
              ),
            );
          }
        }
        i += length;
      } else {
        final grapheme = token.substring(i).characters.first;
        units.add(grapheme);
        i += grapheme.length;
      }
    }
    return units;
  }

  // ----- Selectable adapters -----------------------------------------
  //
  // The selection algorithm lives in [SelectableTextMixin], which
  // operates on a flat-text view of our wrapped lines. We expose the
  // three required hooks (bounds, lines, width resolution) here.

  CellRect? _selectionPaintRect;
  CellRect? _selectionClipRect;

  void _updateRetainedSelectionGeometry(CellRect? bounds, CellRect? clipRect) {
    _selectionPaintRect = bounds;
    _selectionClipRect = bounds == null ? null : clipRect;
  }

  // ignore: prefer_function_declarations_over_variables
  late final RetainedPaintGeometryCallback _replaySelectionGeometry =
      _updateRetainedSelectionGeometry;

  @override
  CellRect? get selectionPaintRect => _selectionPaintRect;

  @override
  CellRect? get selectionClipRect => _selectionClipRect;

  @override
  List<String> get selectionLines => _lines;

  @override
  WidthResolver get selectionWidthResolver => _widthResolver;

  @override
  CellWidthPolicy get selectionPolicy => _policy;

  // Lowered-group flat ranges, cached against the exact _lines instance
  // (performLayout builds a new list each time it reflows). Selection ops
  // are rare; the walk is O(flat text) and only runs for non-identity
  // projections.
  List<({int start, int end, String source})>? _loweredGroupsCache;
  List<String>? _loweredGroupsCacheLines;

  @override
  List<({int start, int end, String source})> get loweredGroups {
    if (_projection.isIdentity) {
      return const <({int start, int end, String source})>[];
    }
    if (identical(_loweredGroupsCacheLines, _lines)) {
      return _loweredGroupsCache!;
    }
    final computed = _computeLoweredGroupsFlat();
    _loweredGroupsCache = computed;
    _loweredGroupsCacheLines = _lines;
    return computed;
  }

  /// Maps each lowered cluster's display range into FLAT-selection space
  /// (the wrapped lines joined by '\n') by walking the two strings in
  /// lockstep. The wrap only ever DROPS spaces (at word breaks) and INSERTS
  /// newlines (word wrap and forced breaks), so alignment is deterministic:
  /// equal characters advance both cursors, a flat '\n' with no matching
  /// display character is an inserted break, and an unmatched display space
  /// was dropped at a wrap.
  List<({int start, int end, String source})> _computeLoweredGroupsFlat() {
    final display = _projection.displayText;
    final flat = selectionLines.join('\n');
    final out = <({int start, int end, String source})>[];
    var d = 0;
    var f = 0;

    // Advances the aligned cursors until the display cursor reaches
    // [target]; returns the flat cursor there, or null when the flat text
    // ended first (maxLines truncation).
    int? flatAt(int target) {
      while (d < target) {
        if (f < flat.length && d < display.length && flat[f] == display[d]) {
          f++;
          d++;
        } else if (f < flat.length &&
            flat[f] == '\n' &&
            (d >= display.length || display[d] != '\n')) {
          f++; // inserted line break
        } else if (d < display.length && display[d] == ' ') {
          d++; // space dropped at a wrap
        } else {
          return null; // flat text ended (truncation) or unexpected shape
        }
      }
      return f;
    }

    for (final cluster in _projection.changedClusters) {
      final start = flatAt(cluster.displayRange.start);
      if (start == null) break;
      final end = flatAt(cluster.displayRange.end);
      if (end == null) break;
      out.add((
        start: start,
        end: end,
        source: _logicalText.substring(
          cluster.sourceRange.start,
          cluster.sourceRange.end,
        ),
      ));
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// RenderSizedBox
// ---------------------------------------------------------------------------

/// Constrains a child to specific dimensions (or, with a null child,
/// just reports its own preferred size).
///
/// A null dimension adds no constraint on that axis: a child chooses within
/// the parent's bounds, while a box without a child uses the parent's minimum.
class RenderSizedBox extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderSizedBox({int? width, int? height, RenderObject? child})
    : _width = width,
      _height = height {
    if (child != null) {
      this.child = child;
    }
  }

  int? _width;
  int? get width => _width;
  set width(int? value) {
    if (_width == value) return;
    _width = value;
    markNeedsLayout();
  }

  int? _height;
  int? get height => _height;
  set height(int? value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    // Resolve the `expandSize` sentinel against the parent's max.
    // Anywhere SizedBox.expand or a hand-set huge width comes through,
    // it caps at what the parent actually offers.
    final width = _width;
    final height = _height;
    final w = (width != null && width >= 0x7fffffff)
        ? constraints.maxCols
        : width;
    final h = (height != null && height >= 0x7fffffff)
        ? constraints.maxRows
        : height;
    final resolvedWidth = w == null ? null : constraints.constrainWidth(w);
    final resolvedHeight = h == null ? null : constraints.constrainHeight(h);
    final childConstraints = CellConstraints(
      minCols: resolvedWidth ?? constraints.minCols,
      maxCols: resolvedWidth ?? constraints.maxCols,
      minRows: resolvedHeight ?? constraints.minRows,
      maxRows: resolvedHeight ?? constraints.maxRows,
    );
    final c = _child;
    if (c != null) {
      return constraints.constrain(c.layout(childConstraints));
    }
    return constraints.constrain(
      CellSize(
        resolvedWidth ?? constraints.minCols,
        resolvedHeight ?? constraints.minRows,
      ),
    );
  }

  @override
  int computeMaxIntrinsicWidth(int? height) =>
      _width ?? (_child?.computeMaxIntrinsicWidth(height) ?? 0);

  @override
  int computeMinIntrinsicWidth(int? height) =>
      _width ?? (_child?.computeMinIntrinsicWidth(height) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int? width) =>
      _height ?? (_child?.computeMaxIntrinsicHeight(width) ?? 0);

  @override
  int computeMinIntrinsicHeight(int? width) =>
      _height ?? (_child?.computeMinIntrinsicHeight(width) ?? 0);

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}

// ---------------------------------------------------------------------------
// RenderPadding
// ---------------------------------------------------------------------------

/// Insets a child by [padding] cells on each side.
class RenderPadding extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderPadding({EdgeInsets padding = EdgeInsets.zero, RenderObject? child})
    : _padding = padding {
    if (child != null) {
      this.child = child;
    }
  }

  EdgeInsets _padding;
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final hInset = _padding.horizontal;
    final vInset = _padding.vertical;

    final c = _child;
    if (c == null) {
      return constraints.constrain(CellSize(hInset, vInset));
    }

    int max0(int v) => v < 0 ? 0 : v;
    // Subtract padding from constraints; clamp at zero so we never pass
    // negative bounds to the child.
    final cMaxCols = constraints.maxCols;
    final cMaxRows = constraints.maxRows;
    final childConstraints = CellConstraints(
      minCols: max0(constraints.minCols - hInset),
      maxCols: cMaxCols == null ? null : max0(cMaxCols - hInset),
      minRows: max0(constraints.minRows - vInset),
      maxRows: cMaxRows == null ? null : max0(cMaxRows - vInset),
    );
    final childSize = c.layout(childConstraints);
    return constraints.constrain(
      CellSize(childSize.cols + hInset, childSize.rows + vInset),
    );
  }

  @override
  int computeMaxIntrinsicWidth(int? height) {
    final inset = _padding.horizontal;
    final vInset = _padding.vertical;
    // Child's intrinsic width depends on the height *available to it* — its
    // own height minus our vertical padding.
    final childHeight = height == null
        ? null
        : (height - vInset).clamp(0, height);
    return (_child?.computeMaxIntrinsicWidth(childHeight) ?? 0) + inset;
  }

  @override
  int computeMinIntrinsicWidth(int? height) {
    final inset = _padding.horizontal;
    final vInset = _padding.vertical;
    final childHeight = height == null
        ? null
        : (height - vInset).clamp(0, height);
    return (_child?.computeMinIntrinsicWidth(childHeight) ?? 0) + inset;
  }

  @override
  int computeMaxIntrinsicHeight(int? width) {
    final inset = _padding.vertical;
    final hInset = _padding.horizontal;
    final childWidth = width == null ? null : (width - hInset).clamp(0, width);
    return (_child?.computeMaxIntrinsicHeight(childWidth) ?? 0) + inset;
  }

  @override
  int computeMinIntrinsicHeight(int? width) {
    final inset = _padding.vertical;
    final hInset = _padding.horizontal;
    final childWidth = width == null ? null : (width - hInset).clamp(0, width);
    return (_child?.computeMinIntrinsicHeight(childWidth) ?? 0) + inset;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final c = _child;
    if (c == null) return;
    final childOffset = CellOffset(
      offset.col + _padding.left,
      offset.row + _padding.top,
    );
    final screen = screenOffset ?? offset;
    c.paint(
      buffer,
      childOffset,
      screenOffset: CellOffset(
        screen.col + _padding.left,
        screen.row + _padding.top,
      ),
      clipRect: clipRect,
    );
  }
}

// ---------------------------------------------------------------------------
// RenderBorder
// ---------------------------------------------------------------------------

/// Draws a four-sided box around its child using box-drawing
/// graphemes.
///
/// Reserves one glyph-width of frame on each side of the child, so a child
/// of size `(w, h)` becomes `(w + 2·edge, h + 2)` overall. [edgeWidth] is
/// what the frame's own glyphs measure on this surface (RFC 0019): box
/// drawing is East Asian Ambiguous, so a terminal whose probe measured
/// ambiguous glyphs wide draws `│` two columns wide and the frame really
/// does cost two columns a side. Reserving one there would leave the right
/// half of every edge glyph overlapping the child.
///
/// When the assigned size is too small for a meaningful border
/// (`w < 2·edge` or `h < 2`), the border is skipped and the child paints
/// in place — this avoids garbled glyphs when a layout collapses.
class RenderBorder extends RenderObject implements RenderObjectWithSingleChild {
  RenderBorder({
    required BoxBorder border,
    TextPresentationPolicy textPolicy = TextPresentationPolicy.spec,
    RenderObject? child,
  }) : _border = border,
       _textPolicy = textPolicy {
    _edgeWidth = _measureEdge();
    if (child != null) this.child = child;
  }

  static const WidthResolver _widthResolver = DefaultWidthResolver();

  BoxBorder _border;
  BoxBorder get border => _border;
  set border(BoxBorder value) {
    if (_border == value) return;
    _border = value;
    _updateEdgeWidth();
    markNeedsPaintOnly();
  }

  TextPresentationPolicy _textPolicy;
  TextPresentationPolicy get textPolicy => _textPolicy;
  set textPolicy(TextPresentationPolicy value) {
    if (_textPolicy == value) return;
    _textPolicy = value;
    _updateEdgeWidth();
    markNeedsPaintOnly();
  }

  /// Columns one vertical/corner glyph occupies on this surface: the frame's
  /// thickness, in both the reserved geometry and the paint.
  late int _edgeWidth;
  int get edgeWidth => _edgeWidth;

  /// The widest glyph in the set decides the frame thickness. Every built-in
  /// set is uniform (all six glyphs share a width class), but taking the max
  /// keeps a mixed set from writing past the columns reserved for it.
  int _measureEdge() {
    final g = BorderGlyphs.forStyle(_border.style);
    final widths = _textPolicy.widths;
    var edge = 1;
    for (final glyph in <String>[
      g.topLeft,
      g.topRight,
      g.bottomLeft,
      g.bottomRight,
      g.horizontal,
      g.vertical,
    ]) {
      final w = _widthResolver.widthOfGrapheme(glyph, widths);
      if (w > edge) edge = w;
    }
    return edge;
  }

  void _updateEdgeWidth() {
    final next = _measureEdge();
    if (next == _edgeWidth) return;
    _edgeWidth = next;
    markNeedsLayout();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  // A framed box is its child plus one frame glyph on every side. The
  // horizontal budget loses two glyph WIDTHS; rows are unaffected by width,
  // so the vertical budget always loses two.
  static int? _less(int? extent, int n) =>
      extent == null ? null : (extent > n ? extent - n : 0);

  int get _frameCols => 2 * _edgeWidth;

  @override
  int computeMaxIntrinsicWidth(int? height) =>
      (child?.computeMaxIntrinsicWidth(_less(height, 2)) ?? 0) + _frameCols;

  @override
  int computeMinIntrinsicWidth(int? height) =>
      (child?.computeMinIntrinsicWidth(_less(height, 2)) ?? 0) + _frameCols;

  @override
  int computeMaxIntrinsicHeight(int? width) =>
      (child?.computeMaxIntrinsicHeight(_less(width, _frameCols)) ?? 0) + 2;

  @override
  int computeMinIntrinsicHeight(int? width) =>
      (child?.computeMinIntrinsicHeight(_less(width, _frameCols)) ?? 0) + 2;

  /// Whether the last layout reserved room for the frame; paint follows it.
  var _framed = false;

  @override
  CellSize performLayout(CellConstraints constraints) {
    int max0(int v) => v < 0 ? 0 : v;
    final c = _child;
    final frameCols = _frameCols;
    if (c == null) {
      // Border-only box collapses to its minimum useful size.
      return constraints.constrain(CellSize(frameCols, 2));
    }
    final maxC = constraints.maxCols;
    final maxR = constraints.maxRows;
    // A meaningful border needs room for both edges plus one cell of
    // content. When the parent gives us less, hand the child the full
    // constraints and skip the frame at paint time — better to show the
    // content than to swallow it.
    final canFrame =
        (maxC == null || maxC >= frameCols + 1) && (maxR == null || maxR >= 3);
    _framed = canFrame;
    if (!canFrame) {
      final childSize = c.layout(constraints);
      return constraints.constrain(childSize);
    }
    final childConstraints = CellConstraints(
      minCols: max0(constraints.minCols - frameCols),
      maxCols: maxC == null ? null : max0(maxC - frameCols),
      minRows: max0(constraints.minRows - 2),
      maxRows: maxR == null ? null : max0(maxR - 2),
    );
    final childSize = c.layout(childConstraints);
    return constraints.constrain(
      CellSize(childSize.cols + frameCols, childSize.rows + 2),
    );
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final w = size.cols;
    final h = size.rows;
    final c = _child;
    final edge = _edgeWidth;
    // The layout decision, not a re-derivation from the painted size: the two
    // thresholds disagreed by one cell (two on an ambiguous-wide surface), so
    // a box laid out unframed at full width could still get a frame painted
    // over its content.
    if (!_framed) {
      // Too small for a real border — paint the child in place if
      // any, skip the frame entirely.
      c?.paint(
        buffer,
        offset,
        screenOffset: screenOffset ?? offset,
        clipRect: clipRect,
      );
      return;
    }
    final g = BorderGlyphs.forStyle(_border.style);
    final cs = _border.cellStyle;
    final widths = _textPolicy.widths;
    final left = offset.col;
    final top = offset.row;
    // Leading column of the RIGHT edge: its glyph runs to the box's last
    // column, so it starts one glyph width in from there.
    final right = offset.col + w - edge;
    final bottom = offset.row + h - 1;

    void write(int col, int row, String glyph) => buffer.writeGrapheme(
      CellOffset(col, row),
      glyph,
      style: cs,
      policy: widths,
    );

    write(left, top, g.topLeft);
    write(right, top, g.topRight);
    write(left, bottom, g.bottomLeft);
    write(right, bottom, g.bottomRight);

    // The horizontal runs tile the span between the corners. A span that is
    // not a whole number of glyphs (possible only when a glyph is wider than
    // one cell) keeps its remainder blank in the border's own style rather
    // than letting a glyph overhang a corner — an overhang would evict the
    // corner's leading cell and punch a hole in the frame.
    var col = left + edge;
    for (; col + edge <= right; col += edge) {
      write(col, top, g.horizontal);
      write(col, bottom, g.horizontal);
    }
    for (; col < right; col++) {
      write(col, top, ' ');
      write(col, bottom, ' ');
    }
    for (var row = top + 1; row < bottom; row++) {
      write(left, row, g.vertical);
      write(right, row, g.vertical);
    }

    final innerOffset = CellOffset(offset.col + edge, offset.row + 1);
    c?.paint(
      buffer,
      innerOffset,
      screenOffset: (screenOffset ?? offset) + CellOffset(edge, 1),
      clipRect: clipRect,
    );
  }
}
