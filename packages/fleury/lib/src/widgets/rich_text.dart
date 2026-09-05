import 'package:characters/characters.dart';

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../rendering/render_objects.dart' show TextOverflow;
import '../rendering/emoji_sequence.dart';
import '../rendering/selectable_text_mixin.dart';
import '../rendering/text_sanitizer.dart';
import '../rendering/width_resolver.dart';
import 'framework.dart';
import 'media_query.dart';
import 'selection/selectable.dart';
import 'theme.dart';

/// An inline run of styled text, optionally with [children] that inherit
/// and override this span's [style] — a cascade, like Flutter's TextSpan.
/// Build a tree of these to mix styles on one line.
class TextSpan {
  const TextSpan({this.text, this.style, this.children});

  /// Text contributed by this span before any [children].
  final String? text;

  /// Style merged over the parent span or ambient text style.
  final CellStyle? style;

  /// Nested spans that inherit and may override this span's style.
  final List<TextSpan>? children;
}

/// Renders a [TextSpan] tree: multiple styles on a line, with the same
/// wrapping, [maxLines], and [overflow] behavior as [Text]. The ambient
/// [DefaultTextStyle] is the base the root span merges onto.
///
/// Participates in app-wide text selection: drag, double-click, and
/// Shift+Arrow work across mixed [Text] and `RichText` widgets inside
/// a [SelectionArea]. The selected copy is the plain text of the spans
/// — styles are visual only, never round-tripped to the clipboard.
/// Set `allowSelect: false` to mask a particular RichText off from
/// any ambient SelectionArea.
class RichText extends StatelessWidget {
  const RichText({
    super.key,
    required this.text,
    this.softWrap = true,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.allowSelect = true,
  });

  /// Root of the styled span tree to render.
  final TextSpan text;

  /// Whether content wraps to additional rows at the available width.
  final bool softWrap;

  /// Maximum rendered rows, or null for no explicit line limit.
  final int? maxLines;

  /// How content beyond the width or [maxLines] budget is represented.
  final TextOverflow overflow;

  /// Whether this RichText participates in ambient
  /// [SelectionArea] selection. When false, the widget is invisible
  /// to selection: drags pass over without highlight, Ctrl+A skips
  /// the content. Defaults to true.
  final bool allowSelect;

  @override
  Widget build(BuildContext context) => _RawRichText(
    span: text,
    base: DefaultTextStyle.of(context),
    softWrap: softWrap,
    maxLines: maxLines,
    overflow: overflow,
    allowSelect: allowSelect,
  );
}

class _RawRichText extends LeafRenderObjectWidget {
  const _RawRichText({
    required this.span,
    required this.base,
    required this.softWrap,
    required this.maxLines,
    required this.overflow,
    required this.allowSelect,
  });

  final TextSpan span;
  final CellStyle base;
  final bool softWrap;
  final int? maxLines;
  final TextOverflow overflow;
  final bool allowSelect;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final r = RenderRichText(
      span: span,
      base: base,
      softWrap: softWrap,
      maxLines: maxLines,
      overflow: overflow,
      textPolicy: MediaQuery.textPolicyOf(context),
    );
    r.attachToSelection(allowSelect ? SelectionScope.maybeOf(context) : null);
    return r;
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderRichText r) {
    r
      ..setSpan(span, base)
      ..softWrap = softWrap
      ..maxLines = maxLines
      ..overflow = overflow
      ..textPolicy = MediaQuery.textPolicyOf(context);
    r.attachToSelection(allowSelect ? SelectionScope.maybeOf(context) : null);
  }

  @override
  LeafRenderObjectElement createElement() => _RawRichTextElement(this);
}

/// Mirror of `_RawTextElement`: detach from the ambient registrar
/// on permanent unmount so a stale RenderRichText doesn't linger.
class _RawRichTextElement extends LeafRenderObjectElement {
  _RawRichTextElement(_RawRichText super.widget);

  @override
  void unmount() {
    (renderObject as RenderRichText).detachFromSelection();
    super.unmount();
  }
}

class _Glyph {
  const _Glyph(
    this.grapheme,
    this.width,
    this.style, {
    this.isBreak = false,
    this.groupId,
    this.groupSource,
  });
  final String grapheme;
  final int width;
  final CellStyle style;
  final bool isBreak;

  /// Non-null when this glyph is one atom of a lowered cluster group; equal
  /// ids mark atoms of the same source cluster.
  final int? groupId;

  /// The canonical source cluster, carried on the group's FIRST atom only.
  final String? groupSource;
}

/// Lays out and paints a flattened [TextSpan] tree as styled cells, with
/// word wrap, maxLines, and ellipsis/clip overflow. One style per glyph,
/// resolved by cascading each span's style onto its parent's.
///
/// Implements [Selectable] via [SelectableTextMixin], so RichText
/// participates in any ancestor [SelectionArea] alongside plain Text.
/// Styles are visual only — the clipboard copy is the plain text of
/// the spans.
class RenderRichText extends RenderObject
    with ChangeNotifier, SelectionRegistrant, SelectableTextMixin
    implements Selectable {
  RenderRichText({
    required TextSpan span,
    required CellStyle base,
    bool softWrap = true,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TextPresentationPolicy textPolicy = TextPresentationPolicy.spec,
  }) : _softWrap = softWrap,
       _maxLines = maxLines,
       _overflow = overflow,
       _widthResolver = widthResolver,
       _textPolicy = textPolicy {
    _span = span;
    _base = base;
    _glyphs = _flatten(span, base);
  }

  bool _softWrap;
  int? _maxLines;
  TextOverflow _overflow;
  final WidthResolver _widthResolver;
  TextPresentationPolicy _textPolicy;

  /// Kept so a policy change can re-run flattening (lowering happens there).
  late TextSpan _span;
  late CellStyle _base;

  /// Width axes of [_textPolicy] — what every measurement call uses.
  CellWidthPolicy get _policy => _textPolicy.widths;

  late List<_Glyph> _glyphs;
  List<List<_Glyph>> _lines = const [];
  bool _moreLinesTruncated = false;
  CellRect? _selectionPaintRect;
  CellRect? _selectionClipRect;
  // Cached flat-text view per line — recomputed whenever _lines is
  // rebuilt (which happens on layout, not paint). The mixin reads
  // this on every event.
  List<String> _selectionLines = const [];

  // ----- SelectableTextMixin hooks -----------------------------------

  @override
  CellRect? get selectionPaintRect => _selectionPaintRect;

  @override
  CellRect? get selectionClipRect => _selectionClipRect;

  @override
  List<String> get selectionLines => _selectionLines;

  @override
  WidthResolver get selectionWidthResolver => _widthResolver;

  @override
  CellWidthPolicy get selectionPolicy => _policy;

  int _nextGroupId = 0;
  List<({int start, int end, String source})> _loweredGroups =
      const <({int start, int end, String source})>[];

  @override
  List<({int start, int end, String source})> get loweredGroups =>
      _loweredGroups;

  void _refreshSelectionLines() {
    final out = <String>[];
    final groups = <({int start, int end, String source})>[];
    int? openGroupId;
    var openStart = 0;
    String openSource = '';
    var flatOffset = 0;

    void closeGroup() {
      if (openGroupId == null) return;
      groups.add((start: openStart, end: flatOffset, source: openSource));
      openGroupId = null;
    }

    for (var lineIndex = 0; lineIndex < _lines.length; lineIndex++) {
      if (lineIndex > 0) flatOffset++; // the implicit '\n' between lines
      final buf = StringBuffer();
      for (final g in _lines[lineIndex]) {
        if (g.groupId != openGroupId) {
          closeGroup();
          if (g.groupId != null) {
            openGroupId = g.groupId;
            openStart = flatOffset;
            openSource = g.groupSource ?? g.grapheme;
          }
        }
        buf.write(g.grapheme);
        flatOffset += g.grapheme.length;
      }
      out.add(buf.toString());
    }
    closeGroup();
    _selectionLines = out;
    _loweredGroups = groups;
  }

  set textPolicy(TextPresentationPolicy value) {
    // Operational equality only (provenance never reaches this layer). Both
    // axes change geometry, and the lowering decision changes the glyph list
    // itself, so re-flatten and dirty LAYOUT (property gate 14).
    if (_textPolicy == value) return;
    _textPolicy = value;
    _glyphs = _flatten(_span, _base);
    markNeedsLayout();
  }

  void setSpan(TextSpan span, CellStyle base) {
    _span = span;
    _base = base;
    _glyphs = _flatten(span, base);
    markNeedsLayout();
  }

  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    markNeedsLayout();
  }

  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    markNeedsLayout();
  }

  // ignore: unnecessary_getters_setters
  set overflow(TextOverflow value) {
    if (_overflow == value) return;
    _overflow = value;
    markNeedsPaintOnly();
  }

  List<_Glyph> _flatten(TextSpan span, CellStyle inherited) {
    return _textPolicy.lowering == ClusterLowering.split
        ? _flattenLowered(span, inherited)
        : _flattenPreserved(span, inherited);
  }

  /// The byte-identical legacy path: per-span grapheme walk, no detection.
  /// Every unprobed/preserve surface goes through here unchanged (property
  /// gate 2).
  List<_Glyph> _flattenPreserved(TextSpan span, CellStyle inherited) {
    final out = <_Glyph>[];
    void visit(TextSpan s, CellStyle parent) {
      final style = s.style == null ? parent : parent.merge(s.style!);
      final text = s.text;
      if (text != null && text.isNotEmpty) {
        for (final paragraph in _splitKeepingBreaks(text)) {
          if (paragraph == '\n') {
            out.add(_Glyph('\n', 0, style, isBreak: true));
            continue;
          }
          for (final g in sanitizeForDisplay(paragraph).characters) {
            out.add(
              _Glyph(g, _widthResolver.widthOfGrapheme(g, _policy), style),
            );
          }
        }
      }
      final children = s.children;
      if (children != null) {
        for (final child in children) {
          visit(child, style);
        }
      }
    }

    visit(span, inherited);
    return out;
  }

  /// The lowering path: sequence detection runs across the FLATTENED
  /// paragraph text, so splitting a logical sequence across compatible
  /// styled spans changes neither detection nor the result (property gate
  /// 12) — per-span walking would misparse a cluster that crosses a span
  /// boundary. Each cluster takes the style in effect at its base; a lowered
  /// component inherits the style covering that component's own base
  /// (RFC 0019 §6.4).
  List<_Glyph> _flattenLowered(TextSpan span, CellStyle inherited) {
    final out = <_Glyph>[];
    final paragraphText = StringBuffer();
    // Style per code unit of paragraphText. Rebuilt at flatten time only —
    // never per frame — and cleared per paragraph, so the cost is one byte
    // of style reference per code unit of the longest paragraph.
    final unitStyles = <CellStyle>[];

    void flushParagraph() {
      if (paragraphText.isEmpty) return;
      final text = paragraphText.toString();
      var offset = 0;
      for (final cluster in text.characters) {
        final components = splitEmojiZwjSequence(cluster);
        if (components == null) {
          out.add(
            _Glyph(
              cluster,
              _widthResolver.widthOfGrapheme(cluster, _policy),
              unitStyles[offset],
            ),
          );
        } else {
          final groupId = _nextGroupId++;
          var componentOffset = offset;
          for (var c = 0; c < components.length; c++) {
            final component = components[c];
            out.add(
              _Glyph(
                component,
                _widthResolver.widthOfGrapheme(component, _policy),
                unitStyles[componentOffset],
                groupId: groupId,
                groupSource: c == 0 ? cluster : null,
              ),
            );
            // +1 skips the dropped joiner between components.
            componentOffset += component.length + 1;
          }
        }
        offset += cluster.length;
      }
      paragraphText.clear();
      unitStyles.clear();
    }

    void visit(TextSpan s, CellStyle parent) {
      final style = s.style == null ? parent : parent.merge(s.style!);
      final text = s.text;
      if (text != null && text.isNotEmpty) {
        for (final paragraph in _splitKeepingBreaks(text)) {
          if (paragraph == '\n') {
            flushParagraph();
            out.add(_Glyph('\n', 0, style, isBreak: true));
            continue;
          }
          final sanitized = sanitizeForDisplay(paragraph);
          paragraphText.write(sanitized);
          for (var i = 0; i < sanitized.length; i++) {
            unitStyles.add(style);
          }
        }
      }
      final children = s.children;
      if (children != null) {
        for (final child in children) {
          visit(child, style);
        }
      }
    }

    visit(span, inherited);
    flushParagraph();
    return out;
  }

  // Splits on '\n', yielding the segments and a '\n' marker between them.
  static Iterable<String> _splitKeepingBreaks(String text) sync* {
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) yield '\n';
      if (parts[i].isNotEmpty) yield parts[i];
    }
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_glyphs.isEmpty) {
      _lines = const [];
      _moreLinesTruncated = false;
      _refreshSelectionLines();
      return constraints.constrain(CellSize.zero);
    }
    final maxCols = constraints.maxCols;
    _lines = _wrap(maxCols);

    _moreLinesTruncated = false;
    if (_maxLines != null && _lines.length > _maxLines!) {
      _moreLinesTruncated = true;
      _lines = _lines.sublist(0, _maxLines!);
    }

    var widest = 0;
    for (final line in _lines) {
      var w = 0;
      for (final g in line) {
        w += g.width;
      }
      if (w > widest) widest = w;
    }
    final cols = maxCols == null
        ? widest
        : (widest < maxCols ? widest : maxCols);
    _refreshSelectionLines();
    return constraints.constrain(CellSize(cols, _lines.length));
  }

  List<List<_Glyph>> _wrap(int? maxCols) {
    final lines = <List<_Glyph>>[];
    var para = <_Glyph>[];
    void flushPara() {
      _wrapParagraph(para, maxCols, lines);
      para = <_Glyph>[];
    }

    for (final g in _glyphs) {
      if (g.isBreak) {
        flushPara();
      } else {
        para.add(g);
      }
    }
    flushPara();
    return lines;
  }

  void _wrapParagraph(List<_Glyph> para, int? maxCols, List<List<_Glyph>> out) {
    if (para.isEmpty) {
      out.add(const <_Glyph>[]);
      return;
    }
    // Split into words on single spaces (empty words = consecutive spaces),
    // remembering the ACTUAL space glyph that separated each pair so a LINK's
    // internal spaces can keep the link. Without this, the whitespace inside a
    // multi-word link is re-emitted unstyled and the link fractures into one
    // `<a>` (and one underline segment) per word.
    final words = <List<_Glyph>>[];
    final separators = <_Glyph>[];
    var word = <_Glyph>[];
    for (final g in para) {
      if (g.grapheme == ' ') {
        words.add(word);
        separators.add(g);
        word = <_Glyph>[];
      } else {
        word.add(g);
      }
    }
    words.add(word);

    var line = <_Glyph>[];
    var lineWidth = 0;
    int widthOf(List<_Glyph> ws) {
      var w = 0;
      for (final g in ws) {
        w += g.width;
      }
      return w;
    }

    const emptySpace = _Glyph(' ', 1, CellStyle.none);
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      // The space preceding this word. Re-emit the ORIGINAL space glyph (with
      // its style) only when it carries a link, so a multi-word link stays ONE
      // contiguous run — one `<a>`, one unbroken underline — rather than
      // splitting at every space. A non-link separator stays a bare unstyled
      // space, so every non-link run is byte-identical to before (no wire or
      // paint drift). Whitespace at a wrap boundary is still dropped.
      final separator = i > 0 && separators[i - 1].style.linkUri != null
          ? separators[i - 1]
          : emptySpace;
      final isFirst = lineWidth == 0;
      if (w.isEmpty) {
        if (!isFirst &&
            (!_softWrap || maxCols == null || lineWidth + 1 <= maxCols)) {
          line.add(separator);
          lineWidth += 1;
        }
        continue;
      }
      final ww = widthOf(w);
      final needed = isFirst ? ww : 1 + ww;
      if (!_softWrap || maxCols == null || lineWidth + needed <= maxCols) {
        if (!isFirst) {
          line.add(separator);
          lineWidth += 1;
        }
        line.addAll(w);
        lineWidth += ww;
      } else {
        if (!isFirst) {
          out.add(line);
          line = <_Glyph>[];
          lineWidth = 0;
        }
        if (ww > maxCols) {
          for (final g in w) {
            if (lineWidth > 0 && lineWidth + g.width > maxCols) {
              out.add(line);
              line = <_Glyph>[];
              lineWidth = 0;
            }
            line.add(g);
            lineWidth += g.width;
          }
        } else {
          line.addAll(w);
          lineWidth = ww;
        }
      }
    }
    out.add(line);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    // Selection geometry lives in screen coordinates. paintRect is
    // the full content rect (including any portion scrolled off);
    // clipRect is the visible window. Together they let the mixin
    // route hit-tests correctly even inside a ScrollView. See
    // SelectableTextMixin for the contract.
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

    if (_lines.isEmpty || size.isEmpty) return;
    // Resolve after recording current geometry, once for this paint rather
    // than scanning the document's line lengths again for every glyph.
    final selection = getSelectionRange();
    final visibleRows = _lines.length < size.rows ? _lines.length : size.rows;
    var lineStartOffset = 0;
    for (var i = 0; i < visibleRows; i++) {
      final row = offset.row + i;
      if (row >= buffer.size.rows) break;
      if (row < 0) {
        // Keep flat selection offsets without traversing hidden glyphs.
        // Selection and retained geometry were recorded before culling.
        lineStartOffset += _selectionLines[i].length + 1;
        continue;
      }
      final line = _lines[i];
      final isLastVisible = i == visibleRows - 1;
      var lineWidth = 0;
      for (final g in line) {
        lineWidth += g.width;
      }
      final ellipsize =
          _overflow == TextOverflow.ellipsis &&
          isLastVisible &&
          (lineWidth > size.cols ||
              (_moreLinesTruncated && i == _lines.length - 1));
      _paintLine(
        buffer,
        line,
        offset.col,
        row,
        ellipsize,
        lineStartOffset,
        selection,
      );
      // +length of the line's flat text, +1 for the implicit newline
      // separator. Matches what `selectionLines.join('\n')` produces.
      lineStartOffset += _selectionLines[i].length + 1;
    }
  }

  void _updateRetainedSelectionGeometry(CellRect? bounds, CellRect? clipRect) {
    _selectionPaintRect = bounds;
    _selectionClipRect = bounds == null ? null : clipRect;
  }

  // ignore: prefer_function_declarations_over_variables
  late final RetainedPaintGeometryCallback _replaySelectionGeometry =
      _updateRetainedSelectionGeometry;

  void _paintLine(
    CellBuffer buffer,
    List<_Glyph> line,
    int startCol,
    int row,
    bool ellipsize,
    int lineStartOffset,
    ({int start, int end})? selection,
  ) {
    final maxCol = startCol + size.cols;
    final contentMaxCol = ellipsize ? maxCol - 1 : maxCol;
    var col = startCol;
    var off = lineStartOffset;
    for (final g in line) {
      if (col + g.width > contentMaxCol) break;
      // Per-glyph style merged with reverse-video when this cell
      // falls inside the live selection. Inverse cascades over the
      // span's own foreground/background so styled spans still get
      // the selection highlight.
      final cellStyle =
          selection != null && off >= selection.start && off < selection.end
          ? g.style.merge(const CellStyle(inverse: true))
          : g.style;
      buffer.writeGrapheme(
        CellOffset(col, row),
        g.grapheme,
        style: cellStyle,
        widthResolver: _widthResolver,
        policy: _policy,
      );
      col += g.width;
      off += g.grapheme.length;
    }
    if (ellipsize && col < maxCol) {
      buffer.writeGrapheme(
        CellOffset(col, row),
        '…',
        widthResolver: _widthResolver,
        policy: _policy,
      );
    }
  }
}
