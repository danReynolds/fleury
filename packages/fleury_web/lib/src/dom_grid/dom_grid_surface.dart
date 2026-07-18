import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import '../frame_presentation.dart';
import '../metrics/cell_metrics.dart';
import 'dom_row_factory.dart';

/// Retained DOM grid implementation of [FrameSurface].
///
/// The surface owns only visual DOM. It retains one row element per visible row
/// and updates dirty rows by replacing that row's children with spans generated
/// from the shared [RowSpanModel] pipeline.
final class DomGridSurface implements FrameSurface {
  DomGridSurface({
    required web.Element root,
    required CellSize size,
    DomRowFactory? rowFactory,
    web.Document? document,
  }) : _root = root,
       _document = document ?? web.document,
       _rowFactory = rowFactory ?? DomRowFactory(document: document) {
    _configureRoot();
    resize(size);
  }

  final web.Element _root;
  final web.Document _document;
  final DomRowFactory _rowFactory;
  final List<web.Element> _rows = [];
  var _size = CellSize.zero;
  MeasuredCellBox? _metrics;
  var _presentCount = 0;
  var _rowReplaceCount = 0;

  web.Element get rootElement => _root;

  List<web.Element> get rowElements => List.unmodifiable(_rows);

  int get presentCount => _presentCount;

  int get rowReplaceCount => _rowReplaceCount;

  @override
  CellSize get size => _size;

  @override
  WebSurfaceCapabilities get capabilities => const WebSurfaceCapabilities(
    supportsTrueColor: true,
    supportsSemanticLinks: false,
    supportsGlyphOverlay: false,
  );

  @override
  FrameSurfacePresentationStats present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  ) {
    _presentCount += 1;
    if (plan.size != _size) resize(plan.size);
    final scrollUpRows = plan.scrollUpRows;
    if (scrollUpRows != null &&
        scrollUpRows > 0 &&
        scrollUpRows < _rows.length &&
        !plan.fullRepaint) {
      _scrollUp(scrollUpRows);
    }
    var rowsReplaced = 0;
    var domNodesCreated = 0;
    var styleCacheHits = 0;
    var styleCacheMisses = 0;
    var widthCacheHits = 0;
    var widthCacheMisses = 0;
    for (final rowModel in plan.dirtyRowModels) {
      if (rowModel.row < 0 || rowModel.row >= _rows.length) continue;
      final rowStats = _rowFactory.replaceChildren(
        _rows[rowModel.row],
        rowModel,
        _metrics,
      );
      domNodesCreated += rowStats.nodesCreated;
      styleCacheHits += rowStats.styleCacheHits;
      styleCacheMisses += rowStats.styleCacheMisses;
      widthCacheHits += rowStats.widthCacheHits;
      widthCacheMisses += rowStats.widthCacheMisses;
      rowsReplaced += 1;
      _rowReplaceCount += 1;
    }
    return FrameSurfacePresentationStats(
      rowsReplaced: rowsReplaced,
      domNodesCreated: domNodesCreated,
      styleCacheHits: styleCacheHits,
      styleCacheMisses: styleCacheMisses,
      widthCacheHits: widthCacheHits,
      widthCacheMisses: widthCacheMisses,
    );
  }

  @override
  void resize(CellSize size, {MeasuredCellBox? metrics}) {
    final sizeChanged = size != _size || _rows.length != size.rows;
    _metrics = metrics ?? _metrics;
    if (!sizeChanged) {
      _applyMetricsToRows();
      return;
    }
    _size = size;
    // Preserve the overlapping retained rows across a resize instead of
    // discarding every row's content. A served session drives resize() straight
    // from the ResizeObserver the instant the browser window changes size — a
    // full network round trip before the server's full-repaint-at-new-size plan
    // can arrive — and an in-flight old-size plan resizes the surface again on
    // the way. Blanking every row here would flash the mirrored content away for
    // that whole RTT on every resize tick (a blank the length of a window drag).
    // Rows [0, min(old, new)) keep their spans; only the row-count delta is
    // created (grow) or dropped (shrink). A column-only change keeps the same
    // rows — their reflowed content is clipped/padded by the root width until the
    // next repaint (which resize always precipitates), never blanked.
    if (_rows.length > size.rows) {
      _rows.removeRange(size.rows, _rows.length);
    } else {
      for (var row = _rows.length; row < size.rows; row++) {
        _rows.add(_createRowElement(row));
      }
    }
    _root.callMethodVarArgs<JSAny?>('replaceChildren'.toJS, [
      for (final row in _rows) row,
    ]);
    _applyMetricsToRows();
  }

  @override
  Future<void> dispose() async {
    _rows.clear();
    _root.callMethodVarArgs<JSAny?>('replaceChildren'.toJS, const <JSAny?>[]);
  }

  /// Moves the first [count] retained row elements to the bottom of the
  /// grid (document order defines visual position), renumbering `data-row`.
  /// The moved elements carry stale spans; the plan's residual dirty rows
  /// cover them.
  void _scrollUp(int count) {
    for (var i = 0; i < count; i++) {
      final element = _rows.removeAt(0);
      _rows.add(element);
      _root.appendChild(element);
    }
    for (var row = 0; row < _rows.length; row++) {
      _rows[row].setAttribute('data-row', '$row');
    }
  }

  void _configureRoot() {
    _root.className = 'fleury-screen';
    _root.ariaHidden = 'true';
    _root.setAttribute('role', 'presentation');
    _root.setAttribute('style', _rootStyle());
  }

  web.Element _createRowElement(int row) {
    final element = _document.createElement('div');
    element.className = 'fleury-row';
    element.setAttribute('data-row', '$row');
    final metrics = _metrics;
    if (metrics != null) {
      element.setAttribute('style', _rowStyle(metrics));
    }
    return element;
  }

  void _applyMetricsToRows() {
    _root.setAttribute('style', _rootStyle());
    final metrics = _metrics;
    if (metrics == null) return;
    final rowStyle = _rowStyle(metrics);
    for (final row in _rows) {
      row.setAttribute('style', rowStyle);
    }
  }

  String _rootStyle() {
    final base = StringBuffer(
      'user-select:none;white-space:pre;tab-size:1;'
      'font-kerning:none;font-variant-ligatures:none;'
      'font-feature-settings:"liga" 0,"clig" 0',
    );
    final metrics = _metrics;
    if (metrics != null) {
      // Cells are sized to the device-pixel-snapped `cssCellWidth`, but
      // `white-space:pre` advances text by the font's natural glyph width
      // (`layoutCellWidth`). When the two disagree, every column lands a hair
      // off the snapped grid and the box-drawing borders — painted as 1px
      // gradient lines — fall on sub-pixel boundaries, so they anti-alias into
      // soft, dashed, jagged edges. A sub-pixel letter-spacing closes the gap so
      // the flow matches the snapped grid: borders stay crisp and glyphs (bars,
      // sparklines) tile seamlessly into their snapped cells.
      base
        ..write(
          ';letter-spacing:${metrics.cssCellWidth - metrics.layoutCellWidth}px',
        )
        ..write(';line-height:${metrics.cssCellHeight}px')
        ..write(';width:${metrics.cssCanvasWidth}px')
        ..write(';height:${metrics.cssCanvasHeight}px');
    } else {
      base.write(';letter-spacing:0');
    }
    return base.toString();
  }

  String _rowStyle(MeasuredCellBox metrics) =>
      'height:${metrics.cssCellHeight}px;line-height:${metrics.cssCellHeight}px';
}
