import 'package:fleury_widgets/src/pixel_surface.dart';
import 'package:test/test.dart';

int _r(PixelSurface s, int x, int y) => s.rgba[(y * s.width + x) * 4];
int _g(PixelSurface s, int x, int y) => s.rgba[(y * s.width + x) * 4 + 1];
int _b(PixelSurface s, int x, int y) => s.rgba[(y * s.width + x) * 4 + 2];
int _a(PixelSurface s, int x, int y) => s.rgba[(y * s.width + x) * 4 + 3];

void main() {
  group('PixelSurface', () {
    test('starts transparent and clear() returns it there', () {
      final s = PixelSurface(8, 8);
      expect(_a(s, 3, 3), 0);
      s.addLine(0, 3, 7, 3, r: 255, g: 0, b: 0, width: 1);
      expect(_a(s, 3, 3), greaterThan(0));
      s.clear();
      expect(_a(s, 3, 3), 0);
      expect(_r(s, 3, 3), 0);
    });

    test('a horizontal stroke covers its width fully at the centerline', () {
      final s = PixelSurface(32, 16);
      s.addLine(4, 8, 27, 8, r: 0, g: 255, b: 0, width: 3);
      // Center of the stroke: full coverage.
      expect(_g(s, 16, 8), greaterThanOrEqualTo(250));
      // One row off-center on a 3-wide stroke: still solidly inside.
      expect(_g(s, 16, 7), greaterThan(200));
      // Well outside the stroke: nothing.
      expect(_a(s, 16, 12), 0);
    });

    test('edges are antialiased: coverage falls off, not steps off', () {
      // Drawn off the pixel grid (y=8.3) so the rows land at distinct
      // depths in the 1px coverage ramp: row 8 deep inside, row 7 partial,
      // row 6 outside. Pixel centers sample at y+0.5.
      final s = PixelSurface(32, 16);
      s.addLine(4, 8.3, 27, 8.3, r: 255, g: 255, b: 255, width: 2);
      final centre = _r(s, 16, 8);
      final edge = _r(s, 16, 7);
      final outside = _r(s, 16, 6);
      expect(centre, greaterThan(edge));
      expect(edge, greaterThan(outside));
      expect(edge, greaterThan(60));
      expect(edge, lessThan(230));
      expect(outside, 0);
    });

    test('overlapping strokes blend additively and saturate', () {
      final s = PixelSurface(16, 16);
      // Two half-intensity red strokes on the same path.
      s.addLine(2, 8, 13, 8, r: 140, g: 0, b: 0, width: 2);
      final once = _r(s, 8, 8);
      s.addLine(2, 8, 13, 8, r: 140, g: 0, b: 0, width: 2);
      final twice = _r(s, 8, 8);
      expect(twice, greaterThan(once));
      // And a third pass cannot exceed the channel ceiling.
      s.addLine(2, 8, 13, 8, r: 140, g: 0, b: 0, width: 2);
      expect(_r(s, 8, 8), lessThanOrEqualTo(255));
      expect(_a(s, 8, 8), lessThanOrEqualTo(255));
    });

    test('a zero-length stroke stamps a round dot of the stroke width', () {
      // Stamped at a pixel CENTER (8.5, 8.5) so distances to neighbouring
      // pixel centers are exact integers.
      final s = PixelSurface(16, 16);
      s.addLine(8.5, 8.5, 8.5, 8.5, r: 0, g: 0, b: 255, width: 4);
      expect(_b(s, 8, 8), greaterThan(250));
      // Radius 2: two pixels out sits on the AA rim, four is outside.
      expect(_b(s, 10, 8), greaterThan(0));
      expect(_a(s, 13, 8), 0);
      expect(_a(s, 8, 13), 0);
      // Round, not square: the diagonal corner at (11,11) is sqrt(18) ≈ 4.2
      // out — far outside the radius-2 disc a square stamp would fill.
      expect(_a(s, 11, 11), 0);
    });

    test('a diagonal stroke is continuous — no dropped pixels along it', () {
      final s = PixelSurface(32, 32);
      s.addLine(2, 2, 29, 29, r: 255, g: 255, b: 255, width: 2);
      for (var i = 4; i <= 27; i++) {
        expect(_a(s, i, i), greaterThan(0), reason: 'gap at ($i,$i)');
      }
    });

    test('strokes clip at the surface bounds without throwing', () {
      final s = PixelSurface(8, 8);
      s.addLine(-10, -10, 20, 20, r: 255, g: 0, b: 0, width: 6);
      s.addLine(4, -50, 4, 50, r: 255, g: 0, b: 0, width: 3);
      expect(_a(s, 4, 4), greaterThan(0));
    });

    test('sub-pixel endpoints shift coverage smoothly (no snap)', () {
      // Pixel centers sample at y+0.5, so y=8.5 sits dead-center in row 8
      // (all weight there) and y=9.0 straddles rows 8 and 9 equally. The
      // half-step must REDISTRIBUTE weight, not snap — this is what keeps
      // slow movement from strobing between pixel rows.
      final a = PixelSurface(16, 16)
        ..addLine(2, 8.5, 13, 8.5, r: 255, g: 255, b: 255, width: 1);
      final b = PixelSurface(16, 16)
        ..addLine(2, 9.0, 13, 9.0, r: 255, g: 255, b: 255, width: 1);
      expect(_r(a, 8, 8), greaterThan(250));
      expect(_r(a, 8, 9), 0);
      expect(_r(b, 8, 9), greaterThan(60));
      expect(_r(b, 8, 8), lessThan(_r(a, 8, 8)));
    });
  });
}
