import 'package:fleury/fleury.dart';

/// A compact, single-row history graph of recent numeric values, rendered
/// with the eight vertical block elements (`▁▂▃▄▅▆▇█`).
///
/// Right-aligned (newest value on the right, like `htop`/`bashtop`); values
/// older than the available width are dropped from the left. Sized by the
/// parent — a row that fills its width by default, or wrap in `SizedBox`
/// for an explicit width.
///
/// ```dart
/// SizedBox(width: 20, child: Sparkline(data: cpuHistory));
/// ```
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.data,
    this.max,
    this.min = 0,
    this.color,
    this.style,
  });

  /// The series of values to plot. The newest value goes on the right.
  final List<num> data;

  /// Top of the visible range. `null` autoscales to the data window.
  final num? max;

  /// Baseline value. Defaults to 0.
  final num min;

  /// Foreground color override; defaults to the theme's primary.
  final Color? color;

  /// Full style override; takes precedence over [color].
  final CellStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved =
        style ?? CellStyle(foreground: color ?? theme.colorScheme.primary);
    return _RawSparkline(data: data, max: max, min: min, style: resolved);
  }
}

class _RawSparkline extends LeafRenderObjectWidget {
  const _RawSparkline({
    required this.data,
    required this.max,
    required this.min,
    required this.style,
  });

  final List<num> data;
  final num? max;
  final num min;
  final CellStyle style;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSparkline(data: data, max: max, min: min, style: style);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSparkline renderObject,
  ) {
    renderObject
      ..data = data
      ..max = max
      ..min = min
      ..style = style;
  }
}

/// Render object behind [Sparkline]. See its docs.
class RenderSparkline extends RenderObject {
  RenderSparkline({
    required List<num> data,
    required num? max,
    required num min,
    required CellStyle style,
  }) : _data = data,
       _max = max,
       _min = min,
       _style = style;

  List<num> _data;
  set data(List<num> v) {
    _data = v;
    markNeedsPaint();
  }

  num? _max;
  set max(num? v) {
    _max = v;
    markNeedsPaint();
  }

  num _min;
  set min(num v) {
    _min = v;
    markNeedsPaint();
  }

  CellStyle _style;
  set style(CellStyle v) {
    _style = v;
    markNeedsPaint();
  }

  // Index 0 ('') means "below baseline — write nothing"; 1..8 are the
  // eight visible levels.
  static const _bars = ['', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

  @override
  CellSize performLayout(CellConstraints constraints) {
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : 10;
    return constraints.constrain(CellSize(cols, 1));
  }

  @override
  int computeMaxIntrinsicWidth(int? height) => _data.length;
  @override
  int computeMaxIntrinsicHeight(int? width) => 1;

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final w = size.cols;
    if (w == 0 || size.rows == 0 || _data.isEmpty) return;

    // Take only the last `w` points so the newest value sits on the right.
    final start = _data.length > w ? _data.length - w : 0;
    final window = _data.sublist(start);
    // Left-pad the row so the window stays right-aligned in `w` columns.
    final leftPad = w - window.length;

    final minD = _min.toDouble();
    var maxD = _max?.toDouble();
    if (maxD == null) {
      var hi = window.first.toDouble();
      for (final v in window) {
        if (v > hi) hi = v.toDouble();
      }
      maxD = hi;
    }
    final range = maxD - minD;

    for (var i = 0; i < window.length; i++) {
      final col = offset.col + leftPad + i;
      final v = window[i].toDouble();
      int level;
      if (range <= 0) {
        // Degenerate range: render baseline cells when at-or-above min,
        // empty otherwise.
        level = v >= minD ? 1 : 0;
      } else {
        var t = (v - minD) / range;
        if (t <= 0) {
          level = 0;
        } else if (t >= 1) {
          level = 8;
        } else {
          // 1..8 — at least one block once we cross the baseline.
          level = (t * 8).ceil();
        }
      }
      if (level == 0) continue;
      buffer.writeGrapheme(
        CellOffset(col, offset.row),
        _bars[level],
        style: _style,
      );
    }
  }
}
