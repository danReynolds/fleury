import 'package:characters/characters.dart';

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../rendering/render_objects.dart' show TextOverflow;
import '../rendering/selectable_text_mixin.dart';
import '../rendering/text_sanitizer.dart';
import '../rendering/width_resolver.dart';
import 'framework.dart';
import 'selection/selectable.dart';
import 'theme.dart';

/// An inline run of styled text, optionally with [children] that inherit
/// and override this span's [style] — a cascade, like Flutter's TextSpan.
/// Build a tree of these to mix styles on one line.
class TextSpan {
  const TextSpan({this.text, this.style, this.children});

  final String? text;
  final CellStyle? style;
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

  final TextSpan text;
  final bool softWrap;
  final int? maxLines;
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
      ..overflow = overflow;
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
  const _Glyph(this.grapheme, this.width, this.style, {this.isBreak = false});
  final String grapheme;
  final int width;
  final CellStyle style;
  final bool isBreak;
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
    TerminalProfile profile = TerminalProfile.standard,
  }) : _softWrap = softWrap,
       _maxLines = maxLines,
       _overflow = overflow,
       _widthResolver = widthResolver,
       _profile = profile {
    _glyphs = _flatten(span, base);
  }

  bool _softWrap;
  int? _maxLines;
  TextOverflow _overflow;
  final WidthResolver _widthResolver;
  final TerminalProfile _profile;

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
  TerminalProfile get selectionProfile => _profile;

  void _refreshSelectionLines() {
    final out = <String>[];
    for (final line in _lines) {
      final buf = StringBuffer();
      for (final g in line) {
        buf.write(g.grapheme);
      }
      out.add(buf.toString());
    }
    _selectionLines = out;
  }

  void setSpan(TextSpan span, CellStyle base) {
    _glyphs = _flatten(span, base);
  }

  set softWrap(bool value) => _softWrap = value;
  set maxLines(int? value) => _maxLines = value;
  // ignore: unnecessary_getters_setters
  set overflow(TextOverflow value) => _overflow = value;

  List<_Glyph> _flatten(TextSpan span, CellStyle inherited) {
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
              _Glyph(g, _widthResolver.widthOfGrapheme(g, _profile), style),
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
    // Split into words on single spaces (empty words = consecutive spaces).
    final words = <List<_Glyph>>[];
    var word = <_Glyph>[];
    for (final g in para) {
      if (g.grapheme == ' ') {
        words.add(word);
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

    for (final w in words) {
      final isFirst = lineWidth == 0;
      if (w.isEmpty) {
        if (!isFirst &&
            (!_softWrap || maxCols == null || lineWidth + 1 <= maxCols)) {
          line.add(const _Glyph(' ', 1, CellStyle.empty));
          lineWidth += 1;
        }
        continue;
      }
      final ww = widthOf(w);
      final needed = isFirst ? ww : 1 + ww;
      if (!_softWrap || maxCols == null || lineWidth + needed <= maxCols) {
        if (!isFirst) {
          line.add(const _Glyph(' ', 1, CellStyle.empty));
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
    _selectionPaintRect = CellRect(offset: screenOffset ?? offset, size: size);
    _selectionClipRect = clipRect;

    if (_lines.isEmpty || size.isEmpty) return;
    final visibleRows = _lines.length < size.rows ? _lines.length : size.rows;
    var lineStartOffset = 0;
    for (var i = 0; i < visibleRows; i++) {
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
        offset.row + i,
        ellipsize,
        lineStartOffset,
      );
      // +length of the line's flat text, +1 for the implicit newline
      // separator. Matches what `selectionLines.join('\n')` produces.
      lineStartOffset += _selectionLines[i].length + 1;
    }
  }

  void _paintLine(
    CellBuffer buffer,
    List<_Glyph> line,
    int startCol,
    int row,
    bool ellipsize,
    int lineStartOffset,
  ) {
    final maxCol = startCol + size.cols;
    final contentMaxCol = ellipsize ? maxCol - 1 : maxCol;
    var col = startCol;
    var off = lineStartOffset;
    for (final g in line) {
      if (col + g.width > contentMaxCol) break;
      // Per-glyph style merged with inverse-video when this cell
      // falls inside the live selection. Inverse cascades over the
      // span's own foreground/background so styled spans still get
      // the selection highlight.
      final cellStyle = isOffsetSelected(off)
          ? g.style.merge(const CellStyle(inverse: true))
          : g.style;
      buffer.writeGrapheme(
        CellOffset(col, row),
        g.grapheme,
        style: cellStyle,
        widthResolver: _widthResolver,
        profile: _profile,
      );
      col += g.width;
      off += g.grapheme.length;
    }
    if (ellipsize && col < maxCol) {
      buffer.writeGrapheme(
        CellOffset(col, row),
        '…',
        widthResolver: _widthResolver,
        profile: _profile,
      );
    }
  }
}
