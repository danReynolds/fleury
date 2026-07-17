import 'package:fleury/fleury_core.dart';

/// A 2D grid of values, each rendered as a block character whose density
/// represents the cell's intensity within the visible range.
///
/// Common shapes: GitHub-style activity calendars, time-of-day usage
/// matrices, attention heatmaps. The block ladder (`░▒▓█`) is theme-safe
/// and reads crisply on any background; for a stronger accent, supply a
/// [color] and the active cells will take it.
///
/// ```dart
/// Heatmap(
///   values: weeklyActivity,                 // List<List<num>>
///   rowLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
///   colLabels: const ['J', 'F', 'M', 'A', 'M', 'J', ...],
/// )
/// ```
///
/// Semantics: contributes one summary node (chart role, label, and data
/// state) by design. Terminal charts are announced and asserted as
/// summaries; per-element semantic children are intentionally omitted.
class Heatmap extends StatelessWidget {
  const Heatmap({
    super.key,
    required this.values,
    this.min,
    this.max,
    this.cellWidth = 2,
    this.color,
    this.rowLabels,
    this.colLabels,
    this.showLegend = false,
    this.semanticLabel = 'Heatmap',
  });

  /// `values[row][col]` — outer list is rows top→bottom, inner is cols
  /// left→right.
  final List<List<num>> values;

  /// Low end of the color/intensity range. `null` autoscales.
  final num? min;

  /// High end. `null` autoscales.
  final num? max;

  /// Cells per data point (≥ 1). Wider cells make each data point easier
  /// to read; 2 is a nice default.
  final int cellWidth;

  /// Foreground for active cells. Defaults to the theme's primary.
  final Color? color;

  /// Optional labels for the rows (drawn to the left).
  final List<String>? rowLabels;

  /// Optional labels for the columns (drawn above the grid).
  final List<String>? colLabels;

  /// When true, append a `░▒▓█  min – max` scale strip below the grid so the
  /// intensity ladder maps to real values — the encoding is otherwise opaque
  /// (and color/glyph-density-only is an accessibility red flag).
  final bool showLegend;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _heatmapStats(values, min: min, max: max);
    final grid = _RawHeatmap(
      values: values,
      min: min,
      max: max,
      cellWidth: cellWidth < 1 ? 1 : cellWidth,
      color: color ?? theme.colorScheme.primary,
      labelStyle: theme.mutedStyle,
      rowLabels: rowLabels,
      colLabels: colLabels,
    );
    return Semantics(
      role: SemanticRole.chart,
      label: semanticLabel,
      state: SemanticState({
        'chartType': 'heatmap',
        'chartRowCount': stats.rows,
        'chartColumnCount': stats.columns,
        'chartPointCount': stats.pointCount,
        'chartMinValue': stats.min,
        'chartMaxValue': stats.max,
        'rowLabelCount': rowLabels?.length ?? 0,
        'columnLabelCount': colLabels?.length ?? 0,
      }),
      child: showLegend
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                grid,
                Text(
                  '░▒▓█  ${_fmtHeat(stats.min)} – ${_fmtHeat(stats.max)}',
                  style: theme.mutedStyle,
                ),
              ],
            )
          : grid,
    );
  }
}

String _fmtHeat(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

bool _labelsEqual(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

({int rows, int columns, int pointCount, num min, num max}) _heatmapStats(
  List<List<num>> values, {
  required num? min,
  required num? max,
}) {
  var columns = 0;
  var pointCount = 0;
  num? autoMin;
  num? autoMax;
  for (final row in values) {
    if (row.length > columns) columns = row.length;
    pointCount += row.length;
    for (final value in row) {
      if (autoMin == null || value < autoMin) autoMin = value;
      if (autoMax == null || value > autoMax) autoMax = value;
    }
  }
  var resolvedMin = min ?? autoMin ?? 0;
  var resolvedMax = max ?? autoMax ?? 1;
  if (resolvedMax == resolvedMin) resolvedMax = resolvedMin + 1;
  return (
    rows: values.length,
    columns: columns,
    pointCount: pointCount,
    min: resolvedMin,
    max: resolvedMax,
  );
}

class _RawHeatmap extends LeafRenderObjectWidget {
  const _RawHeatmap({
    required this.values,
    required this.min,
    required this.max,
    required this.cellWidth,
    required this.color,
    required this.labelStyle,
    required this.rowLabels,
    required this.colLabels,
  });

  final List<List<num>> values;
  final num? min;
  final num? max;
  final int cellWidth;
  final Color color;
  final CellStyle labelStyle;
  final List<String>? rowLabels;
  final List<String>? colLabels;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderHeatmap(
    values: values,
    min: min,
    max: max,
    cellWidth: cellWidth,
    color: color,
    labelStyle: labelStyle,
    rowLabels: rowLabels,
    colLabels: colLabels,
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderHeatmap r) {
    r
      ..values = values
      ..min = min
      ..max = max
      ..cellWidth = cellWidth
      ..color = color
      ..labelStyle = labelStyle
      ..rowLabels = rowLabels
      ..colLabels = colLabels;
  }
}

/// Render object behind [Heatmap]. See its docs.
class RenderHeatmap extends RenderObject {
  RenderHeatmap({
    required List<List<num>> values,
    required num? min,
    required num? max,
    required int cellWidth,
    required Color color,
    required CellStyle labelStyle,
    required List<String>? rowLabels,
    required List<String>? colLabels,
  }) : _values = values,
       _min = min,
       _max = max,
       _cellWidth = cellWidth,
       _color = color,
       _labelStyle = labelStyle,
       _rowLabels = rowLabels,
       _colLabels = colLabels;

  List<List<num>> _values;
  set values(List<List<num>> v) {
    if (identical(_values, v)) return;
    final layoutChanged =
        _values.length != v.length ||
        (_values.isEmpty ? 0 : _values[0].length) !=
            (v.isEmpty ? 0 : v[0].length);
    _values = v;
    if (layoutChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaintOnly();
    }
  }

  num? _min;
  set min(num? v) {
    if (_min == v) return;
    _min = v;
    markNeedsPaintOnly();
  }

  num? _max;
  set max(num? v) {
    if (_max == v) return;
    _max = v;
    markNeedsPaintOnly();
  }

  int _cellWidth;
  set cellWidth(int v) {
    final clamped = v < 1 ? 1 : v;
    if (_cellWidth == clamped) return;
    _cellWidth = clamped;
    markNeedsLayout();
  }

  Color _color;
  set color(Color v) {
    if (_color == v) return;
    _color = v;
    markNeedsPaintOnly();
  }

  CellStyle _labelStyle;
  set labelStyle(CellStyle v) {
    if (_labelStyle == v) return;
    _labelStyle = v;
    markNeedsPaintOnly();
  }

  List<String>? _rowLabels;
  set rowLabels(List<String>? v) {
    if (_labelsEqual(_rowLabels, v)) return;
    _rowLabels = v;
    markNeedsLayout();
  }

  List<String>? _colLabels;
  set colLabels(List<String>? v) {
    if (_labelsEqual(_colLabels, v)) return;
    _colLabels = v;
    markNeedsLayout();
  }

  // Four-level density ladder. Empty cells stay empty (transparent).
  static const _glyphs = ['░', '▒', '▓', '█'];

  int get _rows => _values.length;
  int get _cols => _values.isEmpty ? 0 : _values[0].length;

  int get _rowLabelWidth {
    final labels = _rowLabels;
    if (labels == null || labels.isEmpty) return 0;
    var w = 0;
    for (final l in labels) {
      if (l.length > w) w = l.length;
    }
    return w + 1; // single space between label and grid
  }

  int get _colLabelHeight => _colLabels == null ? 0 : 1;

  @override
  CellSize performLayout(CellConstraints constraints) {
    final desiredW = _rowLabelWidth + _cols * _cellWidth;
    final desiredH = _colLabelHeight + _rows;
    final cols = constraints.hasBoundedWidth
        ? (desiredW < constraints.maxCols! ? desiredW : constraints.maxCols!)
        : desiredW;
    final rows = constraints.hasBoundedHeight
        ? (desiredH < constraints.maxRows! ? desiredH : constraints.maxRows!)
        : desiredH;
    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  int computeMaxIntrinsicWidth(int? height) =>
      _rowLabelWidth + _cols * _cellWidth;
  @override
  int computeMaxIntrinsicHeight(int? width) => _colLabelHeight + _rows;

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.cols == 0 || size.rows == 0 || _values.isEmpty) return;

    // Compute min/max (autoscale fallback) over the finite cells only —
    // one NaN/±Infinity cell must not poison the scale for the grid.
    var lo = _min?.toDouble();
    var hi = _max?.toDouble();
    if (lo == null || hi == null) {
      double? autoLo, autoHi;
      for (final row in _values) {
        for (final v in row) {
          final d = v.toDouble();
          if (!d.isFinite) continue;
          if (autoLo == null || d < autoLo) autoLo = d;
          if (autoHi == null || d > autoHi) autoHi = d;
        }
      }
      lo ??= autoLo ?? 0;
      hi ??= autoHi ?? 1;
    }
    if (hi == lo) hi = lo + 1; // avoid /0

    final gridLeft = offset.col + _rowLabelWidth;
    final gridTop = offset.row + _colLabelHeight;
    final fillStyle = CellStyle(foreground: _color);

    // Column labels (top row, centered above each column).
    final colLabels = _colLabels;
    if (colLabels != null && offset.row < buffer.size.rows) {
      for (var c = 0; c < _cols && c < colLabels.length; c++) {
        final cellLeft = gridLeft + c * _cellWidth;
        final text = colLabels[c];
        final clipped = text.length > _cellWidth
            ? text.substring(0, _cellWidth)
            : text;
        final padLeft = (_cellWidth - clipped.length) ~/ 2;
        for (var i = 0; i < clipped.length; i++) {
          final col = cellLeft + padLeft + i;
          if (col < 0 || col >= buffer.size.cols) continue;
          buffer.writeGrapheme(
            CellOffset(col, offset.row),
            clipped[i],
            style: _labelStyle,
          );
        }
      }
    }

    // Row labels (left gutter, right-aligned).
    final rowLabels = _rowLabels;
    if (rowLabels != null) {
      final w = _rowLabelWidth - 1; // minus the trailing space
      for (var r = 0; r < _rows && r < rowLabels.length; r++) {
        final row = gridTop + r;
        if (row < 0 || row >= buffer.size.rows) continue;
        final text = rowLabels[r];
        final clipped = text.length > w ? text.substring(0, w) : text;
        final startCol = offset.col + (w - clipped.length);
        for (var i = 0; i < clipped.length; i++) {
          final col = startCol + i;
          if (col < 0 || col >= buffer.size.cols) continue;
          buffer.writeGrapheme(
            CellOffset(col, row),
            clipped[i],
            style: _labelStyle,
          );
        }
      }
    }

    // Grid cells.
    for (var r = 0; r < _rows; r++) {
      final row = _values[r];
      for (var c = 0; c < row.length && c < _cols; c++) {
        final v = row[c].toDouble();
        // Non-finite cells render as gaps — ceil() on them would throw.
        if (!v.isFinite) continue;
        var t = (v - lo) / (hi - lo);
        if (t <= 0 || t.isNaN) continue; // leave empty
        if (t > 1) t = 1;
        // Quartile mapping: (0, .25] → ░, (.25, .5] → ▒, (.5, .75] → ▓, (.75, 1] → █.
        final idx = ((t * 4).ceil() - 1).clamp(0, 3);
        final glyph = _glyphs[idx];
        final cellLeft = gridLeft + c * _cellWidth;
        for (var w = 0; w < _cellWidth; w++) {
          final col = cellLeft + w;
          if (col >= buffer.size.cols) break;
          if (gridTop + r >= buffer.size.rows) break;
          buffer.writeGrapheme(
            CellOffset(col, gridTop + r),
            glyph,
            style: fillStyle,
          );
        }
      }
    }
  }
}
