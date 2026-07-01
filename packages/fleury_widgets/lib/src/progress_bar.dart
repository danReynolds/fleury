import 'package:fleury/fleury_core.dart';

import 'component_theme.dart';
import 'glyphs.dart';

/// A horizontal determinate progress bar that fills proportionally to
/// [value] (0..1). It fills the available width — bound it with a
/// `SizedBox` for a fixed length — and renders sub-cell precision with
/// eighth-block glyphs, so a 4.5-cell fill shows four full blocks plus a
/// half block rather than rounding.
///
/// ```dart
/// SizedBox(width: 20, child: ProgressBar(value: downloaded / total));
/// ```
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.filledStyle,
    this.trackStyle,
    this.semanticLabel = 'Progress',
  });

  /// Fraction filled, clamped to 0..1. Pass `null` for an *indeterminate* bar
  /// — a block sweeps across the track for work of unknown duration (the
  /// convention is to never show a determinate shape when progress is unknown).
  final double? value;

  /// Style for the filled portion (the blocks).
  final CellStyle? filledStyle;

  /// Style for the unfilled track.
  final CellStyle? trackStyle;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  // Frames for one full sweep of the indeterminate marquee.
  static const _sweepPeriod = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final resolvedFilledStyle =
        filledStyle ?? widgetTheme.resolveProgressFilled(theme);
    final resolvedTrackStyle =
        trackStyle ?? widgetTheme.resolveProgressTrack(theme);

    final value = this.value;
    if (value == null) {
      return Semantics(
        role: SemanticRole.progress,
        label: semanticLabel,
        state: const SemanticState({'indeterminate': true}),
        child: FrameBuilder(
          interval: const Duration(milliseconds: 90),
          builder: (ctx, frame, elapsed, delta) => _RawProgressBar(
            value: 0,
            indeterminatePhase: (frame % _sweepPeriod) / _sweepPeriod,
            filledStyle: resolvedFilledStyle,
            trackStyle: resolvedTrackStyle,
            glyphTier: MediaQuery.glyphTierOf(ctx),
          ),
        ),
      );
    }

    final clamped = value.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();
    return Semantics(
      role: SemanticRole.progress,
      label: semanticLabel,
      value: clamped,
      state: SemanticState({
        'progressCurrent': clamped,
        'progressTotal': 1.0,
        'progressLabel': '$percent%',
      }),
      child: _RawProgressBar(
        value: value,
        filledStyle: resolvedFilledStyle,
        trackStyle: resolvedTrackStyle,
        glyphTier: MediaQuery.glyphTierOf(context),
      ),
    );
  }
}

final class _RawProgressBar extends LeafRenderObjectWidget {
  const _RawProgressBar({
    required this.value,
    required this.filledStyle,
    required this.trackStyle,
    required this.glyphTier,
    this.indeterminatePhase,
  });

  final double value;
  final CellStyle filledStyle;
  final CellStyle trackStyle;
  final GlyphTier glyphTier;
  final double? indeterminatePhase;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderProgressBar(
    value: value,
    filledStyle: filledStyle,
    trackStyle: trackStyle,
    glyphTier: glyphTier,
    indeterminatePhase: indeterminatePhase,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProgressBar renderObject,
  ) {
    renderObject
      ..value = value
      ..filledStyle = filledStyle
      ..trackStyle = trackStyle
      ..glyphTier = glyphTier
      ..indeterminatePhase = indeterminatePhase;
  }
}

/// Renders a one-row proportional bar; see [ProgressBar].
class RenderProgressBar extends RenderObject {
  RenderProgressBar({
    required double value,
    required CellStyle filledStyle,
    required CellStyle trackStyle,
    required GlyphTier glyphTier,
    double? indeterminatePhase,
  }) : _value = value,
       _filledStyle = filledStyle,
       _trackStyle = trackStyle,
       _glyphTier = glyphTier,
       _indeterminatePhase = indeterminatePhase;

  double _value;
  set value(double v) {
    if (_value == v) return;
    _value = v;
    markNeedsPaintOnly();
  }

  double? _indeterminatePhase;
  set indeterminatePhase(double? v) {
    if (_indeterminatePhase == v) return;
    _indeterminatePhase = v;
    markNeedsPaintOnly();
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
    if (offset.row < 0 || offset.row >= buffer.size.rows) return;

    final phase = _indeterminatePhase;
    if (phase != null) {
      // A lit block (~1/3 of the track) marquees across, wrapping at the ends.
      final seg = w < 6 ? (w < 2 ? 1 : 2) : (w / 3).round();
      final start = (phase * w).floor() % w;
      for (var col = 0; col < w; col++) {
        final tgtCol = offset.col + col;
        if (tgtCol < 0 || tgtCol >= buffer.size.cols) continue;
        final lit = ((col - start) % w + w) % w < seg;
        buffer.writeGrapheme(
          CellOffset(tgtCol, offset.row),
          lit
              ? horizontalFillGlyph(_glyphTier, 8)
              : horizontalTrackGlyph(_glyphTier),
          style: lit ? _filledStyle : _trackStyle,
        );
      }
      return;
    }

    final fillCells = _value.clamp(0.0, 1.0) * w;
    final full = fillCells.floor();
    final partialIndex = ((fillCells - full) * 8).round();

    for (var col = 0; col < w; col++) {
      final tgtCol = offset.col + col;
      if (tgtCol < 0 || tgtCol >= buffer.size.cols) continue;
      final String glyph;
      final CellStyle style;
      if (col < full) {
        glyph = horizontalFillGlyph(_glyphTier, 8);
        style = _filledStyle;
      } else if (col == full && partialIndex > 0 && partialIndex < 8) {
        glyph = horizontalFillGlyph(_glyphTier, partialIndex);
        style = _filledStyle;
      } else {
        glyph = horizontalTrackGlyph(_glyphTier);
        style = _trackStyle;
      }
      buffer.writeGrapheme(CellOffset(tgtCol, offset.row), glyph, style: style);
    }
  }
}
