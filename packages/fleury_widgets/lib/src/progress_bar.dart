import 'package:fleury/fleury.dart';

/// A horizontal determinate progress bar that fills proportionally to
/// [value] (0..1). It fills the available width — bound it with a
/// `SizedBox` for a fixed length — and renders sub-cell precision with
/// eighth-block glyphs, so a 4.5-cell fill shows four full blocks plus a
/// half block rather than rounding.
///
/// ```dart
/// SizedBox(width: 20, child: ProgressBar(value: downloaded / total));
/// ```
class ProgressBar extends LeafRenderObjectWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.filledStyle = CellStyle.empty,
    this.trackStyle = const CellStyle(dim: true),
  });

  /// Fraction filled, clamped to 0..1.
  final double value;

  /// Style for the filled portion (the blocks).
  final CellStyle filledStyle;

  /// Style for the unfilled track.
  final CellStyle trackStyle;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderProgressBar(
    value: value,
    filledStyle: filledStyle,
    trackStyle: trackStyle,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProgressBar renderObject,
  ) {
    renderObject
      ..value = value
      ..filledStyle = filledStyle
      ..trackStyle = trackStyle;
  }
}

/// Renders a one-row proportional bar; see [ProgressBar].
class RenderProgressBar extends RenderObject {
  RenderProgressBar({
    required double value,
    required CellStyle filledStyle,
    required CellStyle trackStyle,
  }) : _value = value,
       _filledStyle = filledStyle,
       _trackStyle = trackStyle;

  double _value;
  set value(double v) => _value = v;

  CellStyle _filledStyle;
  set filledStyle(CellStyle v) => _filledStyle = v;

  CellStyle _trackStyle;
  set trackStyle(CellStyle v) => _trackStyle = v;

  // 1/8..7/8 partial blocks; index 0 is unused (no partial).
  static const _eighths = [' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];
  static const _full = '█';
  static const _track = '░';

  @override
  CellSize performLayout(CellConstraints constraints) {
    // Fill the available width (fall back to a small default when
    // unbounded); always one row tall.
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : 10;
    return constraints.constrain(CellSize(cols, 1));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final w = size.cols;
    if (w == 0 || size.rows == 0) return;
    final fillCells = _value.clamp(0.0, 1.0) * w;
    final full = fillCells.floor();
    final partialIndex = ((fillCells - full) * 8).round();

    if (offset.row < 0 || offset.row >= buffer.size.rows) return;
    for (var col = 0; col < w; col++) {
      final tgtCol = offset.col + col;
      if (tgtCol < 0 || tgtCol >= buffer.size.cols) continue;
      final String glyph;
      final CellStyle style;
      if (col < full) {
        glyph = _full;
        style = _filledStyle;
      } else if (col == full && partialIndex > 0 && partialIndex < 8) {
        glyph = _eighths[partialIndex];
        style = _filledStyle;
      } else {
        glyph = _track;
        style = _trackStyle;
      }
      buffer.writeGrapheme(CellOffset(tgtCol, offset.row), glyph, style: style);
    }
  }
}
