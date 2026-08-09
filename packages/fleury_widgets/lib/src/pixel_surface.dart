import 'dart:math' as math;
import 'dart:typed_data';

/// An RGBA raster the pixel canvas tier draws into (RFC 0021 §2.4).
///
/// This is the pixel-space sibling of the glyph-tier `SubCellBuffer`s, with
/// the two properties glyph cells cannot offer and neon needs:
///
/// - **Antialiasing.** Strokes are signed-distance capsules — every pixel's
///   coverage is how deep it sits inside the capsule, so edges ramp instead
///   of stepping, caps and joints come out round, and sub-pixel endpoint
///   movement shifts weight smoothly between rows (no strobing during slow
///   motion).
/// - **Additive blending.** Overlapping strokes SUM their light and clamp,
///   the physics of glow: a halo pass under a core pass brightens where
///   they cross instead of the last write winning. (Per-cell glyph tiers
///   resolve color last-drawn-wins; this tier has no cells to fight over.)
///
/// Deliberately not a general 2D library: two primitives (capsule stroke,
/// which doubles as a dot at zero length) are exactly what `CanvasPainter`s
/// emit. The buffer is row-major RGBA, transparent black when cleared, and
/// sized once — the render object recreates it on resize, not per frame.
final class PixelSurface {
  PixelSurface(this.width, this.height)
    : assert(width > 0),
      assert(height > 0),
      rgba = Uint8List(width * height * 4);

  final int width;
  final int height;

  /// Row-major RGBA8888, premultiplied by nothing — alpha is coverage.
  final Uint8List rgba;

  /// Resets every pixel to transparent black. One memset, called per frame.
  void clear() => rgba.fillRange(0, rgba.length, 0);

  /// Draws an antialiased capsule stroke from `(x0, y0)` to `(x1, y1)`,
  /// [width] pixels thick, adding `r/g/b` scaled by coverage into the
  /// buffer. Zero length stamps a round dot. Coordinates are pixel-space
  /// doubles; fractional positions land as partial coverage.
  void addLine(
    double x0,
    double y0,
    double x1,
    double y1, {
    required int r,
    required int g,
    required int b,
    double width = 1,
  }) {
    // Capsule geometry: radius from stroke width, half a pixel of AA apron.
    final radius = width <= 1 ? 0.5 : width / 2;
    final apron = radius + 0.75;

    // Bounding box, clipped to the surface.
    final minX = _clampInt((_min(x0, x1) - apron).floor(), 0, this.width - 1);
    final maxX = _clampInt((_max(x0, x1) + apron).ceil(), 0, this.width - 1);
    final minY = _clampInt((_min(y0, y1) - apron).floor(), 0, height - 1);
    final maxY = _clampInt((_max(y0, y1) + apron).ceil(), 0, height - 1);
    if (minX > maxX || minY > maxY) return;

    final dx = x1 - x0;
    final dy = y1 - y0;
    final lengthSq = dx * dx + dy * dy;

    for (var py = minY; py <= maxY; py++) {
      // Sample at pixel centers.
      final sy = py + 0.5;
      var rowBase = (py * this.width + minX) * 4;
      for (var px = minX; px <= maxX; px++, rowBase += 4) {
        final sx = px + 0.5;
        // Distance from the sample to the segment (capsule SDF).
        double ex;
        double ey;
        if (lengthSq == 0) {
          ex = sx - x0;
          ey = sy - y0;
        } else {
          var t = ((sx - x0) * dx + (sy - y0) * dy) / lengthSq;
          if (t < 0) {
            t = 0;
          } else if (t > 1) {
            t = 1;
          }
          ex = sx - (x0 + dx * t);
          ey = sy - (y0 + dy * t);
        }
        final dist = math.sqrt(ex * ex + ey * ey);
        // Coverage: 1 inside the radius, ramping to 0 over one pixel.
        final coverage = _clampDouble(radius + 0.5 - dist, 0, 1);
        if (coverage <= 0) continue;

        // Additive, saturating.
        final addR = (r * coverage).round();
        final addG = (g * coverage).round();
        final addB = (b * coverage).round();
        final addA = (255 * coverage).round();
        final cr = rgba[rowBase] + addR;
        final cg = rgba[rowBase + 1] + addG;
        final cb = rgba[rowBase + 2] + addB;
        final ca = rgba[rowBase + 3] + addA;
        rgba[rowBase] = cr > 255 ? 255 : cr;
        rgba[rowBase + 1] = cg > 255 ? 255 : cg;
        rgba[rowBase + 2] = cb > 255 ? 255 : cb;
        rgba[rowBase + 3] = ca > 255 ? 255 : ca;
      }
    }
  }
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

double _clampDouble(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);
