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
/// With [softWrap] false, the text lays out on a single row and is
/// clipped horizontally at the right edge.
///
/// The text is sanitized once at construction; later updates re-
/// sanitize. Wide graphemes occupy leading + continuation cells via
/// `CellBuffer`.
class RenderText extends RenderObject
    with ChangeNotifier, SelectionRegistrant, SelectableTextMixin
    implements Selectable {
  RenderText({
    required String text,
    CellStyle style = CellStyle.empty,
    bool softWrap = true,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
    TextAlign textAlign = TextAlign.left,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) : _text = _sanitizePreservingNewlines(text),
       _style = style,
       _softWrap = softWrap,
       _maxLines = maxLines,
       _overflow = overflow,
       _textAlign = textAlign,
       _widthResolver = widthResolver,
       _profile = profile {
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

  String _text;
  CellStyle _style;
  bool _softWrap;
  int? _maxLines;
  TextOverflow _overflow;
  TextAlign _textAlign;
  WidthResolver _widthResolver;
  TerminalProfile _profile;
  int _intrinsicWidth = 0;

  /// Set during layout when [maxLines] cut off real content, so paint
  /// knows the last visible line should be ellipsized.
  bool _moreLinesTruncated = false;

  /// Lines produced by the most recent layout. Empty until [layout]
  /// has been called at least once.
  List<String> _lines = const <String>[];

  /// Memoized layout result, keyed on the constraints that produced
  /// it. The wrap algorithm is the hottest path in the renderer
  /// (see `benchmark/widgets_benchmarks.dart`); reusing a cached
  /// result across frames when neither the text nor the constraints
  /// changed eliminates ~80% of the steady-state layout cost. Any
  /// text / softWrap / width-resolver / profile setter that would
  /// change the wrap output also calls [_invalidateLayoutCache].
  CellConstraints? _cachedConstraints;
  CellSize? _cachedSize;

  void _invalidateLayoutCache() {
    _cachedConstraints = null;
    _cachedSize = null;
  }

  String get text => _text;
  set text(String value) {
    final sanitized = _sanitizePreservingNewlines(value);
    if (sanitized == _text) return;
    _text = sanitized;
    _recomputeIntrinsicWidth();
    _invalidateLayoutCache();
  }

  CellStyle get style => _style;
  set style(CellStyle value) {
    if (_style == value) return;
    _style = value;
    // Style is paint-only; layout result is unaffected.
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
  set overflow(TextOverflow value) => _overflow = value;

  // textAlign also only affects paint — it shifts each line's start
  // column inside the box but doesn't change which graphemes wrap
  // where. Layout cache stays valid across changes.
  // ignore: unnecessary_getters_setters
  TextAlign get textAlign => _textAlign;
  set textAlign(TextAlign value) => _textAlign = value;

  WidthResolver get widthResolver => _widthResolver;
  set widthResolver(WidthResolver value) {
    if (identical(_widthResolver, value)) return;
    _widthResolver = value;
    _recomputeIntrinsicWidth();
    _invalidateLayoutCache();
  }

  TerminalProfile get profile => _profile;
  set profile(TerminalProfile value) {
    if (_profile == value) return;
    _profile = value;
    _recomputeIntrinsicWidth();
    _invalidateLayoutCache();
  }

  /// Display width the text would occupy if given unbounded horizontal
  /// space, ignoring wrapping. Equal to `widthResolver.widthOfText(text)`.
  int get intrinsicWidth => _intrinsicWidth;

  void _recomputeIntrinsicWidth() {
    if (_text.isEmpty) {
      _intrinsicWidth = 0;
      return;
    }
    if (!_text.contains('\n')) {
      _intrinsicWidth = _widthResolver.widthOfText(_text, _profile);
      return;
    }
    var widest = 0;
    for (final line in _text.split('\n')) {
      final w = _widthResolver.widthOfText(line, _profile);
      if (w > widest) widest = w;
    }
    _intrinsicWidth = widest;
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_text.isEmpty) {
      _lines = const <String>[];
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
    for (final line in _lines) {
      final w = _widthResolver.widthOfText(line, _profile);
      if (w > maxLineWidth) maxLineWidth = w;
    }
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
    _selectionPaintRect = CellRect(offset: screenOffset ?? offset, size: size);
    _selectionClipRect = clipRect;
    if (_text.isEmpty || size.isEmpty) return;
    final visibleRows = _lines.length < size.rows ? _lines.length : size.rows;
    var lineStartOffset = 0;
    for (var i = 0; i < visibleRows; i++) {
      final isLastVisible = i == visibleRows - 1;
      final lineWidth = _widthResolver.widthOfText(_lines[i], _profile);
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
    // Reserve one cell for the ellipsis when truncating.
    final contentMaxCol = ellipsize ? maxCol - 1 : maxCol;
    var col = startCol;
    var off = lineStartOffset;
    for (final grapheme in line.characters) {
      final w = _widthResolver.widthOfGrapheme(grapheme, _profile);
      if (col + w > contentMaxCol) break;
      // Cell style is the painting style merged with a selection
      // highlight (inverse) when this grapheme falls inside the
      // current selection range.
      final cellStyle = isOffsetSelected(off)
          ? _style.merge(const CellStyle(inverse: true))
          : _style;
      buffer.writeGrapheme(
        CellOffset(col, row),
        grapheme,
        style: cellStyle,
        widthResolver: _widthResolver,
        profile: _profile,
      );
      col += w;
      off += grapheme.length;
    }
    if (ellipsize && col < maxCol) {
      buffer.writeGrapheme(
        CellOffset(col, row),
        '…',
        style: _style,
        widthResolver: _widthResolver,
        profile: _profile,
      );
    }
  }

  /// Greedy word-wrap. Splits on explicit `\n` first, then within each
  /// paragraph splits on single spaces and greedily packs tokens onto
  /// the current line. Tokens wider than [maxWidth] are broken at
  /// grapheme boundaries. Whitespace that falls at a line break is
  /// dropped rather than carried onto the next line.
  List<String> _wrap(String text, int maxWidth) {
    if (maxWidth <= 0) return <String>[''];
    final lines = <String>[];
    final paragraphs = text.split('\n');
    for (var p = 0; p < paragraphs.length; p++) {
      _wrapParagraph(paragraphs[p], maxWidth, lines);
    }
    return lines;
  }

  void _wrapParagraph(String text, int maxWidth, List<String> out) {
    if (text.isEmpty) {
      out.add('');
      return;
    }
    final tokens = text.split(' ');
    final current = StringBuffer();
    var currentWidth = 0;

    for (final token in tokens) {
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

      final tokenWidth = _widthResolver.widthOfText(token, _profile);
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
      // Long token — hard-break grapheme-by-grapheme. May leave a
      // partial fragment in `current` for the next token to extend.
      for (final g in token.characters) {
        final w = _widthResolver.widthOfGrapheme(g, _profile);
        if (w == 0) {
          current.write(g);
          continue;
        }
        if (currentWidth + w > maxWidth) {
          out.add(current.toString());
          current.clear();
          currentWidth = 0;
          // A single grapheme wider than maxWidth gets its own row;
          // paint clipping will trim what doesn't fit.
          if (w > maxWidth) {
            out.add(g);
            continue;
          }
        }
        current.write(g);
        currentWidth += w;
      }
    }

    out.add(current.toString());
  }

  // ----- Selectable adapters -----------------------------------------
  //
  // The selection algorithm lives in [SelectableTextMixin], which
  // operates on a flat-text view of our wrapped lines. We expose the
  // three required hooks (bounds, lines, width resolution) here.

  CellRect? _selectionPaintRect;
  CellRect? _selectionClipRect;

  @override
  CellRect? get selectionPaintRect => _selectionPaintRect;

  @override
  CellRect? get selectionClipRect => _selectionClipRect;

  @override
  List<String> get selectionLines => _lines;

  @override
  WidthResolver get selectionWidthResolver => _widthResolver;

  @override
  TerminalProfile get selectionProfile => _profile;
}

// ---------------------------------------------------------------------------
// RenderSizedBox
// ---------------------------------------------------------------------------

/// Constrains a child to specific dimensions (or, with a null child,
/// just reports its own preferred size).
///
/// `width == null` means "as wide as the parent allows," and likewise
/// for height. With both null and no child, this collapses to zero.
class RenderSizedBox extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderSizedBox({this.width, this.height, RenderObject? child}) {
    if (child != null) {
      this.child = child;
    }
  }

  int? width;
  int? height;

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
    final w = (width != null && width! >= 0x7fffffff)
        ? constraints.maxCols
        : width;
    final h = (height != null && height! >= 0x7fffffff)
        ? constraints.maxRows
        : height;
    final childConstraints = CellConstraints(
      minCols: w ?? constraints.minCols,
      maxCols: w ?? constraints.maxCols,
      minRows: h ?? constraints.minRows,
      maxRows: h ?? constraints.maxRows,
    );
    final c = _child;
    if (c != null) {
      return c.layout(childConstraints);
    }
    return constraints.constrain(
      CellSize(w ?? constraints.minCols, h ?? constraints.minRows),
    );
  }

  @override
  int computeMaxIntrinsicWidth(int? height) =>
      width ?? (_child?.computeMaxIntrinsicWidth(height) ?? 0);

  @override
  int computeMinIntrinsicWidth(int? height) =>
      width ?? (_child?.computeMinIntrinsicWidth(height) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int? width) =>
      height ?? (_child?.computeMaxIntrinsicHeight(width) ?? 0);

  @override
  int computeMinIntrinsicHeight(int? width) =>
      height ?? (_child?.computeMinIntrinsicHeight(width) ?? 0);

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
    c.paint(
      buffer,
      CellOffset(offset.col + _padding.left, offset.row + _padding.top),
    );
  }
}

// ---------------------------------------------------------------------------
// RenderBorder
// ---------------------------------------------------------------------------

/// Draws a four-sided box around its child using box-drawing
/// graphemes.
///
/// Reserves exactly one cell on each side of the child for the border
/// itself, so a child of size `(w, h)` becomes `(w+2, h+2)` overall.
/// When the assigned size is too small for a meaningful border
/// (`w < 2` or `h < 2`), the border is skipped and the child paints
/// in place — this avoids garbled glyphs when a layout collapses.
class RenderBorder extends RenderObject implements RenderObjectWithSingleChild {
  RenderBorder({required BoxBorder border, RenderObject? child})
    : _border = border {
    if (child != null) this.child = child;
  }

  BoxBorder _border;
  BoxBorder get border => _border;
  set border(BoxBorder value) {
    if (_border == value) return;
    _border = value;
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
    int max0(int v) => v < 0 ? 0 : v;
    final c = _child;
    if (c == null) {
      // Border-only box collapses to its minimum useful size.
      return constraints.constrain(const CellSize(2, 2));
    }
    final maxC = constraints.maxCols;
    final maxR = constraints.maxRows;
    // A meaningful border needs at least 3 cells per axis (one for
    // each edge plus one for content). When the parent gives us less,
    // hand the child the full constraints and skip the frame at paint
    // time — better to show the content than to swallow it.
    final canFrame = (maxC == null || maxC >= 3) && (maxR == null || maxR >= 3);
    if (!canFrame) {
      final childSize = c.layout(constraints);
      return constraints.constrain(childSize);
    }
    final childConstraints = CellConstraints(
      minCols: max0(constraints.minCols - 2),
      maxCols: maxC == null ? null : max0(maxC - 2),
      minRows: max0(constraints.minRows - 2),
      maxRows: maxR == null ? null : max0(maxR - 2),
    );
    final childSize = c.layout(childConstraints);
    return constraints.constrain(
      CellSize(childSize.cols + 2, childSize.rows + 2),
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
    if (w < 2 || h < 2) {
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
    final left = offset.col;
    final top = offset.row;
    final right = offset.col + w - 1;
    final bottom = offset.row + h - 1;

    buffer.writeGrapheme(CellOffset(left, top), g.topLeft, style: cs);
    buffer.writeGrapheme(CellOffset(right, top), g.topRight, style: cs);
    buffer.writeGrapheme(CellOffset(left, bottom), g.bottomLeft, style: cs);
    buffer.writeGrapheme(CellOffset(right, bottom), g.bottomRight, style: cs);

    for (var col = left + 1; col < right; col++) {
      buffer.writeGrapheme(CellOffset(col, top), g.horizontal, style: cs);
      buffer.writeGrapheme(CellOffset(col, bottom), g.horizontal, style: cs);
    }
    for (var row = top + 1; row < bottom; row++) {
      buffer.writeGrapheme(CellOffset(left, row), g.vertical, style: cs);
      buffer.writeGrapheme(CellOffset(right, row), g.vertical, style: cs);
    }

    final innerOffset = CellOffset(offset.col + 1, offset.row + 1);
    c?.paint(
      buffer,
      innerOffset,
      screenOffset: (screenOffset ?? offset) + const CellOffset(1, 1),
      clipRect: clipRect,
    );
  }
}
