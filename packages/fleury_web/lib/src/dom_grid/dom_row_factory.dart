import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import '../metrics/cell_metrics.dart';
import 'cell_style_css.dart';

/// Creates live DOM nodes from [RowSpanModel]s.
///
/// This class is the browser counterpart to the static HTML adapter. It never
/// uses `innerHTML`; text content is assigned through `Node.textContent`, and
/// a row is applied through the browser's real `replaceChildren(...nodes)` API.
final class DomRowFactory {
  DomRowFactory({web.Document? document})
    : _document = document ?? web.document;

  final web.Document _document;
  final Map<CellStyle, String> _styleCssCache = {};
  final Map<_WidthCorrectionCacheKey, String> _widthCssCache = {};

  /// Builds span nodes for [row].
  List<web.Node> createNodes(
    RowSpanModel row, {
    DomRowReplacementStats? stats,
    MeasuredCellBox? metrics,
  }) {
    return [
      for (final run in row.runs) _createSpan(run, stats, metrics: metrics),
    ];
  }

  /// Replaces [rowElement]'s children with nodes for [row].
  ///
  /// Returns count data for the replacement.
  DomRowReplacementStats replaceChildren(
    web.Element rowElement,
    RowSpanModel row,
    MeasuredCellBox? metrics,
  ) {
    final stats = DomRowReplacementStats();
    final nodes = createNodes(row, stats: stats, metrics: metrics);
    rowElement.callMethodVarArgs<JSAny?>('replaceChildren'.toJS, [
      for (final node in nodes) node,
    ]);
    stats.nodesCreated = nodes.length;
    return stats;
  }

  web.Element _createSpan(
    CellSpanRun run,
    DomRowReplacementStats? stats, {
    required MeasuredCellBox? metrics,
  }) {
    final span = _document.createElement('span');

    if (run.kind == CellRunKind.boxDrawing) {
      final mask = boxDrawingMask(run.text);
      if (mask != null) {
        // Spaces hold the cells; the line is painted with CSS gradients.
        span.textContent = ''.padRight(run.widthCols, ' ');
        span.setAttribute('style', boxDrawingCss(run.style, mask));
        return span;
      }
    }

    // Block-element glyphs (half / quarter / sextant blocks, shades, braille)
    // carry image pixels. Rendered as inline text the cell background paints
    // only the font's content box, so the line-box leading leaves a sliver of
    // page background at every row boundary — visible as horizontal "scan
    // lines" across an image. When such a glyph carries a background, lay the
    // cell out as a full-height inline-block so the background fills the whole
    // cell and neighbours meet with no gap (the same tiling fix box-drawing
    // glyphs get). Gating on a background keeps baseline-aligned block glyphs
    // without one — sparkline / progress bars — on the normal text path.
    if (metrics != null &&
        run.style.background != null &&
        _isBlockElementText(run.text)) {
      span.textContent = run.text;
      span.setAttribute('style', _blockFillCss(run, stats, metrics));
      return span;
    }

    span.textContent = run.text;

    switch (run.kind) {
      case CellRunKind.text:
      case CellRunKind.emptyText:
      case CellRunKind.boxDrawing:
        break;
      case CellRunKind.wideText:
        span.className = 'w2';
    }

    final css = _cssFor(run, stats, metrics);
    if (css.isNotEmpty) span.setAttribute('style', css);
    return span;
  }

  String _cssFor(
    CellSpanRun run,
    DomRowReplacementStats? stats,
    MeasuredCellBox? metrics,
  ) {
    final parts = <String>[
      _widthCssFor(run, stats, metrics),
      _styleCssFor(run.style, stats),
    ].where((part) => part.isNotEmpty);
    return parts.join(';');
  }

  String _widthCssFor(
    CellSpanRun run,
    DomRowReplacementStats? stats,
    MeasuredCellBox? metrics,
  ) {
    if (run.correction != WidthCorrection.pinToCellWidth) return '';
    if (metrics == null) {
      return 'display:inline-block;width:${run.widthCols}ch;overflow:hidden';
    }
    final key = _WidthCorrectionCacheKey(
      widthCols: run.widthCols,
      cssCellWidth: metrics.cssCellWidth,
    );
    if (_widthCssCache.containsKey(key)) {
      stats?.widthCacheHits += 1;
      return _widthCssCache[key]!;
    }
    stats?.widthCacheMisses += 1;
    final css =
        'display:inline-block;width:${_cssPx(run.widthCols * metrics.cssCellWidth)};overflow:hidden';
    _widthCssCache[key] = css;
    return css;
  }

  /// Whether every grapheme in [text] is a block-element glyph — half / quarter
  /// blocks, shades and the full block (U+2580–U+259F), legacy-computing
  /// sextants (U+1FB00–U+1FB3B), or braille (U+2800–U+28FF). These are the
  /// glyphs the image renderer paints pixels with.
  static bool _isBlockElementText(String text) {
    if (text.isEmpty) return false;
    for (final rune in text.runes) {
      final isBlock =
          (rune >= 0x2580 && rune <= 0x259F) ||
          (rune >= 0x1FB00 && rune <= 0x1FB3B) ||
          (rune >= 0x2800 && rune <= 0x28FF);
      if (!isBlock) return false;
    }
    return true;
  }

  /// CSS that lays a block-element cell out as a full-cell inline-block so its
  /// background fills the entire cell box (no row-boundary gap), while the glyph
  /// still paints the sub-cell pixels over it.
  String _blockFillCss(
    CellSpanRun run,
    DomRowReplacementStats? stats,
    MeasuredCellBox metrics,
  ) =>
      'display:inline-block'
      ';width:${_cssPx(run.widthCols * metrics.cssCellWidth)}'
      ';height:100%'
      ';vertical-align:top'
      ';overflow:hidden'
      ';${_styleCssFor(run.style, stats)}';

  String _styleCssFor(CellStyle style, DomRowReplacementStats? stats) {
    if (_styleCssCache.containsKey(style)) {
      stats?.styleCacheHits += 1;
      return _styleCssCache[style]!;
    }
    stats?.styleCacheMisses += 1;
    final css = cellStyleToCss(style);
    _styleCssCache[style] = css;
    return css;
  }
}

final class DomRowReplacementStats {
  var nodesCreated = 0;
  var styleCacheHits = 0;
  var styleCacheMisses = 0;
  var widthCacheHits = 0;
  var widthCacheMisses = 0;
}

final class _WidthCorrectionCacheKey {
  const _WidthCorrectionCacheKey({
    required this.widthCols,
    required this.cssCellWidth,
  });

  final int widthCols;
  final double cssCellWidth;

  @override
  bool operator ==(Object other) =>
      other is _WidthCorrectionCacheKey &&
      other.widthCols == widthCols &&
      other.cssCellWidth == cssCellWidth;

  @override
  int get hashCode => Object.hash(widthCols, cssCellWidth);
}

String _cssPx(double value) {
  if (value == value.roundToDouble()) return '${value.toInt()}px';
  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  text = text.replaceFirst(RegExp(r'\.$'), '');
  return '${text}px';
}
