import 'package:fleury/fleury_host.dart';

import 'glyphs.dart';

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
///
/// Semantics: contributes one summary node (chart role, label, and data
/// state) by design. Terminal charts are announced and asserted as
/// summaries; per-element semantic children are intentionally omitted.
class Gauge extends StatelessWidget {
  const Gauge({
    super.key,
    required this.value,
    this.label,
    this.showPercentage = true,
    this.color,
    this.thresholds = const <(double, Color)>[],
    this.trackColor,
    this.semanticLabel,
  });

  /// Fraction filled, clamped to 0..1.
  final double value;

  /// Optional label shown before the bar.
  final String? label;

  /// Whether to show `nn%` after the bar.
  final bool showPercentage;

  /// Filled-bar color. Defaults to the theme's primary.
  final Color? color;

  /// Optional `(fraction, color)` breakpoints, ascending. The fill takes the
  /// color of the highest breakpoint whose fraction the value has reached — the
  /// system-monitor convention (e.g. `[(0.8, warning), (0.95, error)]` turns
  /// the bar amber then red) so "high" reads without parsing the number.
  final List<(double, Color)> thresholds;

  /// Empty-track color. Defaults to the theme's muted style.
  final Color? trackColor;

  /// Label exposed through the semantic app graph.
  ///
  /// Defaults to [label] when present, otherwise `Gauge`.
  final String? semanticLabel;

  Color _fillColor(ThemeData theme) {
    var resolved = color ?? theme.colorScheme.primary;
    final clamped = value.clamp(0.0, 1.0);
    for (final (fraction, zoneColor) in thresholds) {
      if (clamped >= fraction) resolved = zoneColor;
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = CellStyle(foreground: _fillColor(theme));
    final track = CellStyle(
      foreground: trackColor ?? theme.mutedStyle.foreground,
      dim: true,
    );
    final clamped = value.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();
    return Semantics(
      role: SemanticRole.chart,
      label: semanticLabel ?? label ?? 'Gauge',
      value: '$percent%',
      state: SemanticState({
        'chartType': 'gauge',
        'chartMinValue': 0,
        'chartMaxValue': 1,
        'chartLatestValue': clamped,
        'progressCurrent': percent,
        'progressTotal': 100,
        if (label != null) 'progressLabel': label,
      }),
      child: _RawGauge(
        value: value,
        label: label,
        showPercentage: showPercentage,
        filledStyle: filled,
        trackStyle: track,
        glyphTier: MediaQuery.glyphTierOf(context),
      ),
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
    required this.glyphTier,
  });

  final double value;
  final String? label;
  final bool showPercentage;
  final CellStyle filledStyle;
  final CellStyle trackStyle;
  final GlyphTier glyphTier;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGauge(
    value: value,
    label: label,
    showPercentage: showPercentage,
    filledStyle: filledStyle,
    trackStyle: trackStyle,
    glyphTier: glyphTier,
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
      ..trackStyle = trackStyle
      ..glyphTier = glyphTier;
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
    required GlyphTier glyphTier,
  }) : _value = value,
       _label = label,
       _showPercentage = showPercentage,
       _filledStyle = filledStyle,
       _trackStyle = trackStyle,
       _glyphTier = glyphTier;

  double _value;
  set value(double v) {
    if (_value == v) return;
    _value = v;
    markNeedsPaintOnly();
  }

  String? _label;
  set label(String? v) {
    if (_label == v) return;
    _label = v;
    markNeedsLayout();
  }

  bool _showPercentage;
  set showPercentage(bool v) {
    if (_showPercentage == v) return;
    _showPercentage = v;
    markNeedsLayout();
  }

  CellStyle _filledStyle;
  set filledStyle(CellStyle v) {
    if (_filledStyle == v) return;
    _filledStyle = v;
    markNeedsPaintOnly();
  }

  CellStyle _trackStyle;
  set trackStyle(CellStyle v) {
    if (_trackStyle == v) return;
    _trackStyle = v;
    markNeedsPaintOnly();
  }

  GlyphTier _glyphTier;
  set glyphTier(GlyphTier v) {
    if (_glyphTier == v) return;
    _glyphTier = v;
    markNeedsPaintOnly();
  }

  String get _suffix =>
      _showPercentage ? ' ${(_value.clamp(0.0, 1.0) * 100).round()}%' : '';
  String get _maxSuffix => _showPercentage ? ' 100%' : '';
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
    return _prefix.length + _maxSuffix.length + 10;
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
        glyph = horizontalFillGlyph(_glyphTier, 8);
        style = _filledStyle;
      } else if (t == full && partialIndex > 0 && partialIndex < 8) {
        glyph = horizontalFillGlyph(_glyphTier, partialIndex);
        style = _filledStyle;
      } else {
        glyph = horizontalTrackGlyph(_glyphTier);
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
