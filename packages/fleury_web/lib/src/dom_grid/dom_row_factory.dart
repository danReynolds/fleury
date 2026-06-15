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

    span.textContent = run.text;

    switch (run.kind) {
      case CellRunKind.text:
      case CellRunKind.emptyText:
      case CellRunKind.boxDrawing:
        break;
      case CellRunKind.wideText:
        span.className = 'w2';
      case CellRunKind.protocolPlaceholder:
        span.className = 'proto';
        span.setAttribute('title', protocolPlaceholderTitle);
        span.setAttribute(
          protocolPlaceholderKindAttribute,
          protocolPlaceholderKind,
        );
        span.setAttribute(
          protocolPlaceholderUnsupportedAttribute,
          protocolPlaceholderUnsupported,
        );
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
