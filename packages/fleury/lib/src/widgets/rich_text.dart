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
  const _Glyph(this.grapheme, this.width, this.style);
  final String grapheme;
  final int width;
  final CellStyle style;
  bool get isBreak => grapheme == '\n';

  // Ordinary glyphs carry only paint data. Lowering metadata is needed only
  // by atoms of split clusters; keeping it there avoids two null fields on
  // every ordinary glyph in the document.
  int? get groupId => null;
  String? get groupSource => null;
}

class _LoweredGlyph extends _Glyph {
  const _LoweredGlyph(
    super.grapheme,
    super.width,
    super.style, {
    required this.groupId,
    this.groupSource,
  });

  /// Non-null when this glyph is one atom of a lowered cluster group; equal
  /// ids mark atoms of the same source cluster.
  @override
  final int groupId;

  /// The canonical source cluster, carried on the group's FIRST atom only.
  @override
  final String? groupSource;
}

// One bounded index per flattening operation. Sharing is safe only when both
// the grapheme and its immutable style match; lowered atoms are never pooled
// because their group identity belongs to a particular source position.
class _GlyphFactory {
  _GlyphFactory(this.resolver, this.policy);
  final WidthResolver resolver;
  final CellWidthPolicy policy;
  final _ascii = List<_Glyph?>.filled(95, null);

  _Glyph glyph(String text, CellStyle style) {
    final code = text.length == 1 ? text.codeUnitAt(0) : -1;
    if (code >= 0x20 && code <= 0x7e) {
      final previous = _ascii[code - 0x20];
      if (previous != null && identical(previous.style, style)) return previous;
      return _ascii[code - 0x20] = _Glyph(
        text,
        resolver.widthOfGrapheme(text, policy),
        style,
      );
    }
    return _Glyph(text, resolver.widthOfGrapheme(text, policy), style);
  }
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
    _runs = _project(span, base);
    _glyphs = _flatten(_runs);
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

  // A value snapshot of source runs, including span boundaries. Re-projecting
  // on update observes changes even when callers reuse a mutable children list.
  late List<({String text, CellStyle style})> _runs;
  late List<_Glyph> _glyphs;
  List<List<_Glyph>> _lines = const [];
  int _laidOutWidth = 0;
  bool _moreLinesTruncated = false;
  // Cached flat-text view per line — recomputed whenever _lines is
  // rebuilt (which happens on layout, not paint). The mixin reads
  // this on every event.
  List<String> _selectionLines = const [];

  // ----- SelectableTextMixin hooks -----------------------------------

  @override
  CellRect? get selectionPaintRect => screenGeometry()?.bounds;

  @override
  CellRect? get selectionClipRect => screenGeometry()?.clip;

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
      if (lineIndex > 0) {
        // A newline belongs to a lowered group only when that same group
        // continues on the next row. Otherwise copy must preserve it.
        if (openGroupId != null &&
            (_lines[lineIndex].isEmpty ||
                _lines[lineIndex].first.groupId != openGroupId)) {
          closeGroup();
        }
        flatOffset++; // the implicit '\n' between lines
      }
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
        // Keep single code units in StringBuffer's character buffer instead
        // of making each glyph a separate string fragment to concatenate.
        if (g.grapheme.length == 1) {
          buf.writeCharCode(g.grapheme.codeUnitAt(0));
        } else {
          buf.write(g.grapheme);
        }
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
    _runs = _project(_span, _base);
    _glyphs = _flatten(_runs);
    markNeedsLayout();
  }

  void setSpan(TextSpan span, CellStyle base) {
    _span = span;
    _base = base;
    final runs = _project(span, base);
    if (_sameRuns(runs, _runs)) return;
    _runs = runs;
    _glyphs = _flatten(runs);
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

  static List<({String text, CellStyle style})> _project(
    TextSpan span,
    CellStyle inherited,
  ) {
    final runs = <({String text, CellStyle style})>[];
    void visit(TextSpan s, CellStyle parent) {
      final style = s.style == null ? parent : parent.merge(s.style!);
      final text = s.text;
      if (text != null && text.isNotEmpty) runs.add((text: text, style: style));
      final children = s.children;
      if (children != null) {
        for (final child in children) {
          visit(child, style);
        }
      }
    }

    visit(span, inherited);
    return runs;
  }

  static bool _sameRuns(
    List<({String text, CellStyle style})> a,
    List<({String text, CellStyle style})> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<_Glyph> _flatten(List<({String text, CellStyle style})> runs) {
    final factory = _GlyphFactory(_widthResolver, _policy);
    return _textPolicy.lowering == ClusterLowering.split
        ? _flattenLowered(runs, factory)
        : _flattenPreserved(runs, factory);
  }

  /// The byte-identical legacy path: per-span grapheme walk, no detection.
  /// Every unprobed/preserve surface goes through here unchanged (property
  /// gate 2).
  List<_Glyph> _flattenPreserved(
    List<({String text, CellStyle style})> runs,
    _GlyphFactory factory,
  ) {
    final out = <_Glyph>[];
    for (final run in runs) {
      for (final paragraph in _splitKeepingBreaks(run.text)) {
        if (paragraph == '\n') {
          out.add(_Glyph('\n', 0, run.style));
          continue;
        }
        for (final g in sanitizeForDisplay(paragraph).characters) {
          out.add(factory.glyph(g, run.style));
        }
      }
    }
    return out;
  }

  /// The lowering path: sequence detection runs across the FLATTENED
  /// paragraph text, so splitting a logical sequence across compatible
  /// styled spans changes neither detection nor the result (property gate
  /// 12) — per-span walking would misparse a cluster that crosses a span
  /// boundary. Each cluster takes the style in effect at its base; a lowered
  /// component inherits the style covering that component's own base
  /// (RFC 0019 §6.4).
  List<_Glyph> _flattenLowered(
    List<({String text, CellStyle style})> runs,
    _GlyphFactory factory,
  ) {
    final out = <_Glyph>[];
    final paragraphText = StringBuffer();
    // Style per code unit of paragraphText. Rebuilt at flatten time only —
    // never per frame — and cleared per paragraph: one style reference per
    // code unit of the longest paragraph.
    final unitStyles = <CellStyle>[];

    void flushParagraph() {
      if (paragraphText.isEmpty) return;
      final text = paragraphText.toString();
      var offset = 0;
      for (final cluster in text.characters) {
        final components = splitEmojiZwjSequence(cluster);
        if (components == null) {
          out.add(factory.glyph(cluster, unitStyles[offset]));
        } else {
          final groupId = _nextGroupId++;
          var componentOffset = offset;
          for (var c = 0; c < components.length; c++) {
            final component = components[c];
            out.add(
              _LoweredGlyph(
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

    for (final run in runs) {
      for (final paragraph in _splitKeepingBreaks(run.text)) {
        if (paragraph == '\n') {
          flushParagraph();
          out.add(_Glyph('\n', 0, run.style));
          continue;
        }
        final sanitized = sanitizeForDisplay(paragraph);
        paragraphText.write(sanitized);
        for (var i = 0; i < sanitized.length; i++) {
          unitStyles.add(run.style);
        }
      }
    }
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
    if (!_softWrap && !needsLayout) {
      // A constraint-only resize cannot change unwrapped lines. Keep their
      // glyphs and source groups, but refresh selection identity so screen
      // points are resolved against the new paint geometry.
      _selectionLines = List<String>.of(_selectionLines);
      return constraints.constrain(CellSize(_laidOutWidth, _lines.length));
    }
    if (_glyphs.isEmpty) {
      _lines = const [];
      _laidOutWidth = 0;
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
    _laidOutWidth = widest;
    final cols = maxCols == null
        ? widest
        : (widest < maxCols ? widest : maxCols);
    _refreshSelectionLines();
    return constraints.constrain(CellSize(cols, _lines.length));
  }

  List<List<_Glyph>> _wrap(int? maxCols) {
    final lines = <List<_Glyph>>[];
    var start = 0;
    for (var i = 0; i < _glyphs.length; i++) {
      if (_glyphs[i].isBreak) {
        _wrapParagraph(start, i, maxCols, lines);
        start = i + 1;
      }
    }
    _wrapParagraph(start, _glyphs.length, maxCols, lines);
    return lines;
  }

  void _wrapParagraph(
    int start,
    int end,
    int? maxCols,
    List<List<_Glyph>> out,
  ) {
    if (start == end) {
      out.add(const <_Glyph>[]);
      return;
    }
    // Walk word ranges in the existing glyph list. Paragraphs, words and
    // separators need no intermediate copies; only the resulting lines own
    // new lists. Empty words still represent consecutive/trailing spaces.
    var line = <_Glyph>[];
    var lineWidth = 0;
    var wordEnd = start;
    const emptySpace = _Glyph(' ', 1, CellStyle.none);
    for (var wordStart = start; wordStart <= end; wordStart = wordEnd + 1) {
      wordEnd = wordStart;
      var ww = 0;
      while (wordEnd < end && _glyphs[wordEnd].grapheme != ' ') {
        ww += _glyphs[wordEnd].width;
        wordEnd++;
      }
      // A separator belongs to its source span, including ordinary spaces.
      // Only whitespace at an actual wrap boundary is dropped below.
      final separator = wordStart > start ? _glyphs[wordStart - 1] : emptySpace;
      final isFirst = lineWidth == 0;
      if (wordStart == wordEnd) {
        if (!isFirst &&
            (!_softWrap || maxCols == null || lineWidth + 1 <= maxCols)) {
          line.add(separator);
          lineWidth += 1;
        }
        continue;
      }
      final needed = isFirst ? ww : 1 + ww;
      if (!_softWrap || maxCols == null || lineWidth + needed <= maxCols) {
        if (!isFirst) {
          line.add(separator);
          lineWidth += 1;
        }
        for (var i = wordStart; i < wordEnd; i++) {
          line.add(_glyphs[i]);
        }
        lineWidth += ww;
      } else {
        if (!isFirst) {
          out.add(line);
          line = <_Glyph>[];
          lineWidth = 0;
        }
        if (ww > maxCols) {
          for (var i = wordStart; i < wordEnd; i++) {
            final g = _glyphs[i];
            if (lineWidth > 0 && lineWidth + g.width > maxCols) {
              out.add(line);
              line = <_Glyph>[];
              lineWidth = 0;
            }
            line.add(g);
            lineWidth += g.width;
          }
        } else {
          for (var i = wordStart; i < wordEnd; i++) {
            line.add(_glyphs[i]);
          }
          lineWidth = ww;
        }
      }
    }
    out.add(line);
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    // Resolve once for this paint rather than scanning the document's line
    // lengths again for every glyph.
    final selection = getSelectionRange();
    // Refresh even an empty paint so selection drops obsolete line snapshots.
    if (_lines.isEmpty || size.isEmpty) return;
    final visibleRows = _lines.length < size.rows ? _lines.length : size.rows;
    if (offset.row >= buffer.size.rows || offset.row + visibleRows <= 0) return;
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
    CellStyle? previousStyle;
    CellStyle? previousSelectedStyle;
    for (final g in line) {
      if (col + g.width > contentMaxCol) break;
      // Per-glyph style merged with reverse-video when this cell
      // falls inside the live selection. Inverse cascades over the
      // span's own foreground/background so styled spans still get
      // the selection highlight.
      var cellStyle = g.style;
      if (selection != null && off >= selection.start && off < selection.end) {
        // Glyphs in a span share their immutable paint style. Keep the
        // highlighted value shared too, with no cache retained after this line.
        if (!identical(previousStyle, cellStyle)) {
          previousStyle = cellStyle;
          previousSelectedStyle = cellStyle.merge(
            const CellStyle(inverse: true),
          );
        }
        cellStyle = previousSelectedStyle!;
      }
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
