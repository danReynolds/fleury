import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';

import 'braille.dart';
import 'half_block_buffer.dart';
import 'octant_buffer.dart';
import 'quadrant_buffer.dart';
import 'sextant_buffer.dart';
import 'pixel_surface.dart';
import 'sub_cell_buffer.dart';

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
  ///
  /// [width] is a stroke thickness in SUB-CELL PIXELS (braille dots / block
  /// sub-pixels), not logical units, so a stroke keeps its visual weight
  /// when the canvas bounds change. `1` is the hairline default — exactly
  /// the pre-width rasterization; larger values stamp a round brush along
  /// the line, so caps and polygon joints come out rounded. A cell still
  /// holds one color: overlapping strokes resolve last-drawn-wins per cell,
  /// which is what makes a two-pass glow work — draw the wide dim halo
  /// first, the narrow bright core second.
  void drawLine(
    double x1,
    double y1,
    double x2,
    double y2, {
    Color? color,
    double width = 1,
  });
}

/// A [Canvas]'s drawing routine.
abstract class CanvasPainter {
  void paint(CanvasContext ctx);
}

/// A braille drawing surface — each terminal cell holds a 2×4 pixel grid,
/// so lines and dots render at sub-cell resolution. Use it to build custom
/// data visualisations; `LineChart` is built on the same primitive.
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

  /// 2×3 pixels per cell using Unicode *sextant* glyphs (`U+1FB00..`,
  /// Symbols for Legacy Computing, Unicode 13). Solid look at higher
  /// vertical resolution than [quadrant], with broad support — kitty and
  /// foot draw them natively and many monospace fonts ship them.
  sextant,

  /// 2×4 pixels per cell using Unicode *octant* glyphs (`U+1CD00..`,
  /// Unicode 16). Braille's resolution with a solid, gap-free look — the
  /// crispest tier — but newer: needs a Unicode-16-aware font (Cascadia
  /// Code, JuliaMono) or a terminal that draws box glyphs natively
  /// (kitty ≥ 0.40, Ghostty). Falls back gracefully elsewhere only if the
  /// caller picks another tier.
  octant,

  /// Real pixels via the terminal's confirmed graphics protocol (RFC 0021):
  /// the painter rasterizes to RGBA — antialiased strokes, per-pixel color,
  /// additive glow — delivered as an inline-image placement over the
  /// canvas's cells. Requires a Kitty-graphics surface; where none is
  /// confirmed the canvas renders [braille] instead (a canvas must never be
  /// blank because the terminal is old). Pick this to pin the pixel look;
  /// pick [auto] to take the best the surface offers.
  pixels,

  /// Resolve at build time from the confirmed surface capabilities: a
  /// Kitty-graphics protocol upgrades to [pixels], everything else renders
  /// [braille]. For content where fidelity is the point (charts, maps).
  /// Content whose glyph texture IS the aesthetic should pin a glyph tier
  /// instead — the framework never silently changes a canvas's look unless
  /// the author opted into exactly that.
  auto,
}

/// Builds the sub-cell buffer for [marker] at the given cell dimensions.
/// Shared by [Canvas] and `LineChart` so both select a tier identically.
SubCellBuffer subCellBufferFor(CanvasMarker marker, int cols, int rows) =>
    switch (marker) {
      CanvasMarker.braille => BrailleBuffer(cols, rows),
      CanvasMarker.halfBlock => HalfBlockBuffer(cols, rows),
      CanvasMarker.quadrant => QuadrantBuffer(cols, rows),
      CanvasMarker.sextant => SextantBuffer(cols, rows),
      CanvasMarker.octant => OctantBuffer(cols, rows),
      // The glyph ladder's callers only: Canvas resolves pixels/auto at
      // build time and never passes them here. A caller that does (LineChart
      // handed `auto` by an app) gets braille — the never-blank floor.
      CanvasMarker.pixels || CanvasMarker.auto => BrailleBuffer(cols, rows),
    };

/// A sub-cell drawing surface for custom plots, diagrams, and markers.
///
/// The [painter] draws in the logical coordinate space described by [bounds];
/// [marker] selects how those points map onto terminal cells. Provide semantic
/// metadata when the drawing communicates information that is not otherwise
/// represented by an enclosing widget.
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

  /// Drawing routine invoked with logical [bounds] during canvas painting.
  ///
  /// Replace the painter instance when its drawing inputs change so the render
  /// object schedules a repaint.
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
      // pixels/auto resolve HERE, against the confirmed surface (RFC 0021
      // §2.1): the render object only ever sees a concrete tier, and the
      // decision is rebuilt when capabilities change (MediaQuery dependency).
      marker: switch (marker) {
        CanvasMarker.pixels || CanvasMarker.auto =>
          MediaQuery.capabilitiesOf(context).liveRasters
              ? CanvasMarker.pixels
              : CanvasMarker.braille,
        final m => m,
      },
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
    if (_marker == CanvasMarker.pixels) {
      _paintPixels(buffer, offset);
      return;
    }
    final buf = subCellBufferFor(_marker, size.cols, size.rows);
    _painter.paint(_SubCellCtx(buf, _bounds));
    buf.writeTo(buffer, offset, _defaultStyle, glyphTier: _glyphTier);
  }

  /// RFC 0021 §2.3: the v1 raster density. ≈4× braille, matching the
  /// typical 1:2 cell aspect.
  static const int _pxPerCellX = 8;
  static const int _pxPerCellY = 16;

  /// Raster identity: images are content-addressed by string id and Kitty
  /// caches by id, so a canvas that redraws must present each frame as a
  /// NEW id — the encoder then transmits the fresh raster and deletes the
  /// old one (its normal placement-diff lifecycle). Instance-unique so two
  /// pixel canvases never collide.
  static int _nextRasterInstance = 1;
  late final int _rasterInstance = _nextRasterInstance++;
  int _rasterRevision = 0;
  PixelSurface? _pixelSurface;
  static final Uint8List _noBytes = Uint8List(0);

  void _paintPixels(CellBuffer buffer, CellOffset offset) {
    final w = size.cols * _pxPerCellX;
    final h = size.rows * _pxPerCellY;
    var surface = _pixelSurface;
    if (surface == null || surface.width != w || surface.height != h) {
      surface = _pixelSurface = PixelSurface(w, h);
    } else {
      surface.clear();
    }
    final captured = surface;
    _painter.paint(_PixelCtx(captured, _bounds));
    _rasterRevision++;
    buffer.writeImageWithId(
      offset,
      // STABLE id + bumped revision (RFC 0021 §2.5 revised): presenters
      // replace the image's data in place instead of transmit-place-delete
      // churn — the churn opened a deleted-old/undecoded-new gap that
      // flickered on terminals with asynchronous graphics decode (Warp).
      'canvas-$_rasterInstance',
      _noBytes,
      width: size.cols,
      height: size.rows,
      fit: InlineImageFit.fill,
      sourceWidth: w,
      sourceHeight: h,
      // Consumed by the presenter within this frame; the surface is reused
      // (cleared, redrawn) only on the NEXT paint, after presentation.
      pixels: () => captured.rgba,
      revision: _rasterRevision,
    );
  }
}

/// Maps a painter's logical calls onto the pixel raster (RFC 0021). The
/// same to-fraction math as [_SubCellCtx], but unrounded — fractional
/// coordinates are the antialiaser's input, not an error to snap away.
class _PixelCtx implements CanvasContext {
  _PixelCtx(this._surface, this._bounds);
  final PixelSurface _surface;
  final CanvasBounds _bounds;

  /// §2.2: stroke width is canonical in braille-dot units; this tier is 4×
  /// braille's vertical density.
  static const double _widthScale = _pxPerCellYd / 4;
  static const double _pxPerCellYd = 16;

  double _mapX(double x) =>
      (x - _bounds.minX) / (_bounds.maxX - _bounds.minX) * (_surface.width - 1);

  double _mapY(double y) =>
      (1 - (y - _bounds.minY) / (_bounds.maxY - _bounds.minY)) *
      (_surface.height - 1);

  (int, int, int) _rgb(Color? color) {
    // Painters overwhelmingly draw RgbColor; palette-indexed colors have no
    // portable RGB without the terminal's palette, so they render as the
    // canvas's hot white rather than guessing.
    if (color is RgbColor) return (color.r, color.g, color.b);
    return (242, 252, 255);
  }

  @override
  void drawDot(double x, double y, {Color? color}) {
    final (r, g, b) = _rgb(color);
    final px = _mapX(x);
    final py = _mapY(y);
    // One braille dot's visual weight at this density.
    _surface.addLine(px, py, px, py, r: r, g: g, b: b, width: _widthScale);
  }

  @override
  void drawLine(
    double x1,
    double y1,
    double x2,
    double y2, {
    Color? color,
    double width = 1,
  }) {
    final (r, g, b) = _rgb(color);
    _surface.addLine(
      _mapX(x1),
      _mapY(y1),
      _mapX(x2),
      _mapY(y2),
      r: r,
      g: g,
      b: b,
      width: width * _widthScale,
    );
  }
}

(int, int) _toPixel(CanvasBounds b, double x, double y, int pw, int ph) {
  final tx = (x - b.minX) / (b.maxX - b.minX);
  final ty = (y - b.minY) / (b.maxY - b.minY);
  return ((tx * (pw - 1)).round(), ((1 - ty) * (ph - 1)).round());
}

/// Maps a painter's logical draw calls onto any [SubCellBuffer] tier. The
/// to-pixel math is identical across tiers — only the buffer's
/// pixelWidth/Height differ — so one context serves all markers.
class _SubCellCtx implements CanvasContext {
  _SubCellCtx(this._buf, this._bounds);
  final SubCellBuffer _buf;
  final CanvasBounds _bounds;
  @override
  void drawDot(double x, double y, {Color? color}) {
    final (px, py) = _toPixel(_bounds, x, y, _buf.pixelWidth, _buf.pixelHeight);
    _buf.setPixel(px, py, color);
  }

  @override
  void drawLine(
    double x1,
    double y1,
    double x2,
    double y2, {
    Color? color,
    double width = 1,
  }) {
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
    if (width <= 1) {
      _buf.drawLine(px1, py1, px2, py2, color);
      return;
    }
    // Thick stroke: walk the same Bresenham the buffers use, stamping a
    // round brush at every step instead of one pixel. Stamping (vs N offset
    // parallel lines) keeps diagonals gap-free and rounds caps and joints,
    // which is what vector outlines want. Over-stamping neighbouring steps
    // is harmless — setPixel ORs dots — and the brush is cached per width.
    final brush = _brushFor(width);
    var x = px1;
    var y = py1;
    final dx = (px2 - px1).abs();
    final dy = (py2 - py1).abs();
    final sx = px1 < px2 ? 1 : -1;
    final sy = py1 < py2 ? 1 : -1;
    var err = dx - dy;
    while (true) {
      for (var i = 0; i < brush.length; i += 2) {
        _buf.setPixel(x + brush[i], y + brush[i + 1], color);
      }
      if (x == px2 && y == py2) break;
      final e2 = err * 2;
      if (e2 > -dy) {
        err -= dy;
        x += sx;
      }
      if (e2 < dx) {
        err += dx;
        y += sy;
      }
    }
  }

  /// Brush offsets for a rounded stamp of [width] pixels, packed as
  /// `[dx0, dy0, dx1, dy1, ...]` and cached — painters redraw every frame,
  /// and the brush for a given width never changes.
  static final Map<int, List<int>> _brushes = {};

  static List<int> _brushFor(double width) {
    final w = width.round().clamp(2, 64);
    return _brushes[w] ??= _buildBrush(w);
  }

  static List<int> _buildBrush(int w) {
    // Offsets span the w-pixel box centred as symmetrically as an integer
    // grid allows (even widths bias half a pixel down-right). Corners are
    // trimmed to a disc for w >= 4; at 2-3 pixels a full square IS the
    // roundest shape the grid can express.
    final lo = -((w - 1) >> 1);
    final hi = w >> 1;
    final centre = (lo + hi) / 2;
    final r2 = (w * w) / 4 + 0.6;
    final out = <int>[];
    for (var dy = lo; dy <= hi; dy++) {
      for (var dx = lo; dx <= hi; dx++) {
        if (w <= 3 ||
            (dx - centre) * (dx - centre) + (dy - centre) * (dy - centre) <=
                r2) {
          out
            ..add(dx)
            ..add(dy);
        }
      }
    }
    return out;
  }
}
