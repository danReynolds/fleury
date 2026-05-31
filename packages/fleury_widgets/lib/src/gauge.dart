import 'package:fleury/fleury.dart';

/// A single-value status indicator: a horizontal bar with an optional
/// inline label and a percentage suffix. Sub-cell precision via the
/// horizontal eighth-block glyphs (`▏▎▍▌▋▊▉█`).
///
/// Distinct from `ProgressBar` by intent — `Gauge` is for *status reading*
/// (CPU, memory, disk, signal), with a labeled, prominent presentation;
/// `ProgressBar` is for *task progress*. Use `ProgressBar` when something
/// is happening; use `Gauge` when something *is*.
///
/// ```dart
/// SizedBox(width: 32, child: Gauge(value: 0.78, label: 'CPU'));
/// ```
class Gauge extends StatelessWidget {
  const Gauge({
    super.key,
    required this.value,
    this.label,
    this.showPercentage = true,
    this.color,
    this.trackColor,
  });

  /// Fraction filled, clamped to 0..1.
  final double value;

  /// Optional label shown before the bar.
  final String? label;

  /// Whether to show `nn%` after the bar.
  final bool showPercentage;

  /// Filled-bar color. Defaults to the theme's primary.
  final Color? color;

  /// Empty-track color. Defaults to the theme's muted style.
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = CellStyle(foreground: color ?? theme.colorScheme.primary);
    final track = CellStyle(
      foreground: trackColor ?? theme.mutedStyle.foreground,
      dim: true,
    );
    return _RawGauge(
      value: value,
      label: label,
      showPercentage: showPercentage,
      filledStyle: filled,
      trackStyle: track,
    );
  }
}

class _RawGauge extends LeafRenderObjectWidget {
  const _RawGauge({
    required this.value,
    required this.label,
    required this.showPercentage,
    required this.filledStyle,
    required this.trackStyle,
  });

  final double value;
  final String? label;
  final bool showPercentage;
  final CellStyle filledStyle;
  final CellStyle trackStyle;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGauge(
    value: value,
    label: label,
    showPercentage: showPercentage,
    filledStyle: filledStyle,
    trackStyle: trackStyle,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderGauge renderObject,
  ) {
    renderObject
      ..value = value
      ..label = label
      ..showPercentage = showPercentage
      ..filledStyle = filledStyle
      ..trackStyle = trackStyle;
  }
}

/// Render object behind [Gauge]. See its docs.
class RenderGauge extends RenderObject {
  RenderGauge({
    required double value,
    required String? label,
    required bool showPercentage,
    required CellStyle filledStyle,
    required CellStyle trackStyle,
  }) : _value = value,
       _label = label,
       _showPercentage = showPercentage,
       _filledStyle = filledStyle,
       _trackStyle = trackStyle;

  double _value;
  set value(double v) {
    _value = v;
    markNeedsPaint();
  }

  String? _label;
  set label(String? v) {
    _label = v;
    markNeedsPaint();
  }

  bool _showPercentage;
  set showPercentage(bool v) {
    _showPercentage = v;
    markNeedsPaint();
  }

  CellStyle _filledStyle;
  set filledStyle(CellStyle v) {
    _filledStyle = v;
    markNeedsPaint();
  }

  CellStyle _trackStyle;
  set trackStyle(CellStyle v) {
    _trackStyle = v;
    markNeedsPaint();
  }

  static const _eighths = [' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];
  static const _full = '█';
  static const _track = '░';

  String get _suffix =>
      _showPercentage ? ' ${(_value.clamp(0.0, 1.0) * 100).round()}%' : '';
  String get _prefix => _label == null ? '' : '${_label!}  ';

  @override
  CellSize performLayout(CellConstraints constraints) {
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : 20;
    return constraints.constrain(CellSize(cols, 1));
  }

  @override
  int computeMaxIntrinsicWidth(int? height) {
    // Want at least enough room for the label/percentage chrome plus a
    // visible track. A 10-cell track is a sensible default.
    return _prefix.length + _suffix.length + 10;
  }

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
    if (w == 0 || size.rows == 0) return;

    final prefix = _prefix;
    final suffix = _suffix;
    final trackWidth = w - prefix.length - suffix.length;
    if (trackWidth < 1) {
      // Degraded: too narrow for chrome + bar. Render just the prefix,
      // truncated to fit.
      var col = offset.col;
      for (final ch in prefix.split('')) {
        if (col >= offset.col + w) break;
        buffer.writeGrapheme(CellOffset(col, offset.row), ch);
        col++;
      }
      return;
    }

    var col = offset.col;
    // Prefix (plain).
    for (final ch in prefix.split('')) {
      buffer.writeGrapheme(CellOffset(col, offset.row), ch);
      col++;
    }

    // Track + fill.
    final fillCells = _value.clamp(0.0, 1.0) * trackWidth;
    final full = fillCells.floor();
    final partialIndex = ((fillCells - full) * 8).round();
    for (var t = 0; t < trackWidth; t++) {
      final String glyph;
      final CellStyle style;
      if (t < full) {
        glyph = _full;
        style = _filledStyle;
      } else if (t == full && partialIndex > 0 && partialIndex < 8) {
        glyph = _eighths[partialIndex];
        style = _filledStyle;
      } else {
        glyph = _track;
        style = _trackStyle;
      }
      buffer.writeGrapheme(CellOffset(col, offset.row), glyph, style: style);
      col++;
    }

    // Suffix (plain).
    for (final ch in suffix.split('')) {
      buffer.writeGrapheme(CellOffset(col, offset.row), ch);
      col++;
    }
  }
}
