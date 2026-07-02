import 'package:fleury/fleury_core.dart';

import 'braille.dart';
import 'half_block_buffer.dart';
import 'quadrant_buffer.dart';

/// Logical drawing extents for a [Canvas]. Logical Y increases upward,
/// like a math plot; the canvas flips it when mapping to terminal pixels.
class CanvasBounds {
  const CanvasBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  }) : assert(maxX > minX, 'maxX must exceed minX'),
       assert(maxY > minY, 'maxY must exceed minY');

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  /// Convenience `(0..1, 0..1)` bounds — useful for "fraction of the box"
  /// style drawing.
  static const unit = CanvasBounds(minX: 0, maxX: 1, minY: 0, maxY: 1);
}

/// Receives drawing calls from a [CanvasPainter]. Coordinates are in the
/// canvas's logical space; the implementation maps them to braille pixels.
abstract class CanvasContext {
  /// Lights a single pixel at logical `(x, y)`.
  void drawDot(double x, double y, {Color? color});

  /// Draws a line segment in logical space (Bresenham at pixel resolution).
  void drawLine(double x1, double y1, double x2, double y2, {Color? color});
}

/// A [Canvas]'s drawing routine.
abstract class CanvasPainter {
  void paint(CanvasContext ctx);
}

/// A braille drawing surface — each terminal cell holds a 2×4 pixel grid,
/// so lines and dots render at sub-cell resolution. Use it to build custom
/// data visualisations; [LineChart] is built on the same primitive.
///
/// ```dart
/// Canvas(
///   bounds: const CanvasBounds(minX: 0, maxX: 100, minY: -10, maxY: 10),
///   painter: _SinePainter(),
/// )
/// ```
/// Sub-cell rendering style for [Canvas]. Different markers trade
/// vertical/horizontal resolution against font coverage and aesthetic.
enum CanvasMarker {
  /// 2×4 pixels per cell using Unicode braille (`U+2800..U+28FF`).
  /// Highest resolution; reads as a stippled curve. Universal modern
  /// font support.
  braille,

  /// 1×2 pixels per cell using ` `/`▀`/`▄`/`█`. Lowest resolution but
  /// reads as solid blocks rather than dots. Works on every monospace
  /// font (the glyphs are decades old).
  halfBlock,

  /// 2×2 pixels per cell using the 16 quadrant glyphs from the Block
  /// Elements range. Middle ground — solid-block look at 2× the
  /// horizontal resolution of [halfBlock].
  quadrant,
}

class Canvas extends StatelessWidget {
  const Canvas({
    super.key,
    required this.painter,
    this.bounds,
    this.marker = CanvasMarker.braille,
    this.semanticRole = SemanticRole.image,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.semanticState = SemanticState.empty,
  });

  final CanvasPainter painter;

  /// Logical coordinate range. Defaults to [CanvasBounds.unit].
  final CanvasBounds? bounds;

  /// Sub-cell rendering style. See [CanvasMarker] for the tradeoffs.
  final CanvasMarker marker;

  /// Semantic role used when this canvas opts into semantics.
  ///
  /// Defaults to [SemanticRole.image]. Custom plots can use
  /// [SemanticRole.chart] and provide chart-specific [semanticState].
  final SemanticRole semanticRole;

  /// Optional label that exposes the canvas to the semantic app graph.
  ///
  /// Plain canvases do not contribute semantics because higher-level widgets
  /// such as charts wrap their drawing surface with richer meaning.
  final String? semanticLabel;

  /// Optional semantic value for the drawn content.
  final Object? semanticValue;

  /// Optional semantic hint for the drawn content.
  final String? semanticHint;

  /// Additional semantic state for custom canvas surfaces.
  final SemanticState semanticState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedBounds = bounds ?? CanvasBounds.unit;
    final raw = _RawCanvas(
      painter: painter,
      bounds: resolvedBounds,
      marker: marker,
      defaultStyle: CellStyle(foreground: theme.colorScheme.primary),
      glyphTier: MediaQuery.glyphTierOf(context),
    );
    if (!_hasSemantics) return raw;
    return Semantics(
      role: semanticRole,
      label: semanticLabel,
      value: semanticValue,
      hint: semanticHint,
      state: semanticState.merge(<String, Object?>{
        'canvasMarker': marker.name,
        'canvasMinX': resolvedBounds.minX,
        'canvasMaxX': resolvedBounds.maxX,
        'canvasMinY': resolvedBounds.minY,
        'canvasMaxY': resolvedBounds.maxY,
      }),
      child: raw,
    );
  }

  bool get _hasSemantics =>
      semanticLabel != null ||
      semanticValue != null ||
      semanticHint != null ||
      semanticState.values.isNotEmpty ||
      semanticRole != SemanticRole.image;
}

class _RawCanvas extends LeafRenderObjectWidget {
  const _RawCanvas({
    required this.painter,
    required this.bounds,
    required this.marker,
    required this.defaultStyle,
    required this.glyphTier,
  });

  final CanvasPainter painter;
  final CanvasBounds bounds;
  final CanvasMarker marker;
  final CellStyle defaultStyle;
  final GlyphTier glyphTier;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCanvas(
    painter: painter,
    bounds: bounds,
    marker: marker,
    defaultStyle: defaultStyle,
    glyphTier: glyphTier,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderCanvas renderObject,
  ) {
    renderObject
      ..painter = painter
      ..bounds = bounds
      ..marker = marker
      ..defaultStyle = defaultStyle
      ..glyphTier = glyphTier;
  }
}

/// Render object behind [Canvas]. See its docs.
class RenderCanvas extends RenderObject {
  RenderCanvas({
    required CanvasPainter painter,
    required CanvasBounds bounds,
    required CanvasMarker marker,
    required CellStyle defaultStyle,
    required GlyphTier glyphTier,
  }) : _painter = painter,
       _bounds = bounds,
       _marker = marker,
       _defaultStyle = defaultStyle,
       _glyphTier = glyphTier;

  CanvasPainter _painter;
  set painter(CanvasPainter v) {
    if (identical(_painter, v)) return;
    _painter = v;
    markNeedsPaintOnly();
  }

  CanvasBounds _bounds;
  set bounds(CanvasBounds v) {
    if (_bounds == v) return;
    _bounds = v;
    markNeedsPaintOnly();
  }

  CanvasMarker _marker;
  set marker(CanvasMarker v) {
    if (_marker == v) return;
    _marker = v;
    markNeedsPaintOnly();
  }

  CellStyle _defaultStyle;
  set defaultStyle(CellStyle v) {
    if (_defaultStyle == v) return;
    _defaultStyle = v;
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
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : 20;
    final rows = constraints.hasBoundedHeight ? constraints.maxRows! : 10;
    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.cols == 0 || size.rows == 0) return;
    switch (_marker) {
      case CanvasMarker.braille:
        final buf = BrailleBuffer(size.cols, size.rows);
        _painter.paint(_BrailleCtx(buf, _bounds));
        buf.writeTo(buffer, offset, _defaultStyle, glyphTier: _glyphTier);
      case CanvasMarker.halfBlock:
        final buf = HalfBlockBuffer(size.cols, size.rows);
        _painter.paint(_HalfBlockCtx(buf, _bounds));
        buf.writeTo(buffer, offset, _defaultStyle, glyphTier: _glyphTier);
      case CanvasMarker.quadrant:
        final buf = QuadrantBuffer(size.cols, size.rows);
        _painter.paint(_QuadrantCtx(buf, _bounds));
        buf.writeTo(buffer, offset, _defaultStyle, glyphTier: _glyphTier);
    }
  }
}

// Per-marker contexts. Each carries its own buffer instance so type
// stays specific (no shared interface needed across packages). The
// to-pixel math is identical apart from the pixelWidth/Height source.

(int, int) _toPixel(CanvasBounds b, double x, double y, int pw, int ph) {
  final tx = (x - b.minX) / (b.maxX - b.minX);
  final ty = (y - b.minY) / (b.maxY - b.minY);
  return ((tx * (pw - 1)).round(), ((1 - ty) * (ph - 1)).round());
}

class _BrailleCtx implements CanvasContext {
  _BrailleCtx(this._buf, this._bounds);
  final BrailleBuffer _buf;
  final CanvasBounds _bounds;
  @override
  void drawDot(double x, double y, {Color? color}) {
    final (px, py) = _toPixel(_bounds, x, y, _buf.pixelWidth, _buf.pixelHeight);
    _buf.setPixel(px, py, color);
  }

  @override
  void drawLine(double x1, double y1, double x2, double y2, {Color? color}) {
    final (px1, py1) = _toPixel(
      _bounds,
      x1,
      y1,
      _buf.pixelWidth,
      _buf.pixelHeight,
    );
    final (px2, py2) = _toPixel(
      _bounds,
      x2,
      y2,
      _buf.pixelWidth,
      _buf.pixelHeight,
    );
    _buf.drawLine(px1, py1, px2, py2, color);
  }
}

class _HalfBlockCtx implements CanvasContext {
  _HalfBlockCtx(this._buf, this._bounds);
  final HalfBlockBuffer _buf;
  final CanvasBounds _bounds;
  @override
  void drawDot(double x, double y, {Color? color}) {
    final (px, py) = _toPixel(_bounds, x, y, _buf.pixelWidth, _buf.pixelHeight);
    _buf.setPixel(px, py, color);
  }

  @override
  void drawLine(double x1, double y1, double x2, double y2, {Color? color}) {
    final (px1, py1) = _toPixel(
      _bounds,
      x1,
      y1,
      _buf.pixelWidth,
      _buf.pixelHeight,
    );
    final (px2, py2) = _toPixel(
      _bounds,
      x2,
      y2,
      _buf.pixelWidth,
      _buf.pixelHeight,
    );
    _buf.drawLine(px1, py1, px2, py2, color);
  }
}

class _QuadrantCtx implements CanvasContext {
  _QuadrantCtx(this._buf, this._bounds);
  final QuadrantBuffer _buf;
  final CanvasBounds _bounds;
  @override
  void drawDot(double x, double y, {Color? color}) {
    final (px, py) = _toPixel(_bounds, x, y, _buf.pixelWidth, _buf.pixelHeight);
    _buf.setPixel(px, py, color);
  }

  @override
  void drawLine(double x1, double y1, double x2, double y2, {Color? color}) {
    final (px1, py1) = _toPixel(
      _bounds,
      x1,
      y1,
      _buf.pixelWidth,
      _buf.pixelHeight,
    );
    final (px2, py2) = _toPixel(
      _bounds,
      x2,
      y2,
      _buf.pixelWidth,
      _buf.pixelHeight,
    );
    _buf.drawLine(px1, py1, px2, py2, color);
  }
}
