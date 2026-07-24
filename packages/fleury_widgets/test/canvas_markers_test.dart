// Tests for the CanvasMarker variants beyond braille — HalfBlock and
// Quadrant. The existing canvas_test.dart covers the braille default
// path; this file covers the new markers and their pixel→glyph maps.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
// ignore: implementation_imports
import 'package:fleury_widgets/src/half_block_buffer.dart';
// ignore: implementation_imports
import 'package:fleury_widgets/src/octant_buffer.dart';
// ignore: implementation_imports
import 'package:fleury_widgets/src/quadrant_buffer.dart';
// ignore: implementation_imports
import 'package:fleury_widgets/src/sextant_buffer.dart';
import 'package:test/test.dart';

class _DotAt implements CanvasPainter {
  const _DotAt(this.x, this.y);
  final double x;
  final double y;
  @override
  void paint(CanvasContext ctx) => ctx.drawDot(x, y);
}

void main() {
  group('HalfBlockBuffer', () {
    test('pixelWidth/pixelHeight: 1×2 per cell', () {
      final b = HalfBlockBuffer(3, 4);
      expect(b.pixelWidth, 3);
      expect(b.pixelHeight, 8);
    });

    test('top pixel only → ▀', () {
      final b = HalfBlockBuffer(1, 1);
      b.setPixel(0, 0);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, '▀');
    });

    test('ASCII glyph tier writes density glyphs', () {
      final b = HalfBlockBuffer(1, 1);
      b.setPixel(0, 0);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(
        buf,
        CellOffset.zero,
        CellStyle.empty,
        glyphTier: GlyphTier.ascii,
      );
      expect(buf.atColRow(0, 0).grapheme, ':');
    });

    test('bottom pixel only → ▄', () {
      final b = HalfBlockBuffer(1, 1);
      b.setPixel(0, 1);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, '▄');
    });

    test('both pixels → █', () {
      final b = HalfBlockBuffer(1, 1);
      b.setPixel(0, 0);
      b.setPixel(0, 1);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, '█');
    });

    test('out-of-bounds setPixel is silently clipped', () {
      final b = HalfBlockBuffer(1, 1);
      b.setPixel(-1, 0);
      b.setPixel(0, -1);
      b.setPixel(99, 99);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, isNull);
    });
  });

  group('QuadrantBuffer', () {
    test('pixelWidth/pixelHeight: 2×2 per cell', () {
      final b = QuadrantBuffer(3, 4);
      expect(b.pixelWidth, 6);
      expect(b.pixelHeight, 8);
    });

    test('upper-left pixel → ▘', () {
      final b = QuadrantBuffer(1, 1);
      b.setPixel(0, 0);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, '▘');
    });

    test('ASCII glyph tier writes density glyphs', () {
      final b = QuadrantBuffer(1, 1);
      b.setPixel(0, 0);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(
        buf,
        CellOffset.zero,
        CellStyle.empty,
        glyphTier: GlyphTier.ascii,
      );
      expect(buf.atColRow(0, 0).grapheme, '.');
    });

    test('upper-right pixel → ▝', () {
      final b = QuadrantBuffer(1, 1);
      b.setPixel(1, 0);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, '▝');
    });

    test('diagonal pixels (UL+LR) → ▚', () {
      final b = QuadrantBuffer(1, 1);
      b.setPixel(0, 0);
      b.setPixel(1, 1);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, '▚');
    });

    test('all four quadrants → █', () {
      final b = QuadrantBuffer(1, 1);
      b.setPixel(0, 0);
      b.setPixel(1, 0);
      b.setPixel(0, 1);
      b.setPixel(1, 1);
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).grapheme, '█');
    });

    test('color carries from setPixel to writeTo', () {
      final b = QuadrantBuffer(1, 1);
      b.setPixel(0, 0, const AnsiColor(2));
      final buf = CellBuffer(const CellSize(1, 1));
      b.writeTo(buf, CellOffset.zero, CellStyle.empty);
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(2));
    });
  });

  group('Canvas marker dispatch', () {
    testWidgets('default marker is braille (renders a braille codepoint)', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: Canvas(painter: _DotAt(0, 0)),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 1));
      final code = buf.atColRow(0, 0).grapheme!.codeUnitAt(0);
      expect(
        code >= 0x2800 && code <= 0x28FF,
        isTrue,
        reason: 'expected a braille codepoint',
      );
    });

    testWidgets(
      'ASCII tier renders canvas dots as ASCII density glyphs',
      (tester) {
        tester.pumpWidget(
          const SizedBox(
            width: 1,
            height: 1,
            child: Canvas(painter: _DotAt(0, 0)),
          ),
        );
        final buf = tester.render(size: const CellSize(1, 1));
        expect(buf.atColRow(0, 0).grapheme, '.');
      },
      glyphTier: GlyphTier.ascii,
    );

    testWidgets('marker: halfBlock renders ▀/▄/█ glyphs', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: Canvas(painter: _DotAt(0, 1), marker: CanvasMarker.halfBlock),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 1));
      // (0, 1) is upper-left logically (Y up); halfBlock pixel (0, 0)
      // top half → ▀.
      expect(buf.atColRow(0, 0).grapheme, '▀');
    });

    testWidgets('marker: quadrant renders ▘ etc.', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: Canvas(painter: _DotAt(0, 1), marker: CanvasMarker.quadrant),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 1));
      // (0, 1) → upper-left quadrant → ▘.
      expect(buf.atColRow(0, 0).grapheme, '▘');
    });
  });

  group('SextantBuffer', () {
    test('pixelWidth/pixelHeight: 2×3 per cell', () {
      final b = SextantBuffer(3, 4);
      expect(b.pixelWidth, 6);
      expect(b.pixelHeight, 12);
    });

    test('full cell → █; a single pixel → a sextant glyph', () {
      final full = SextantBuffer(1, 1);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 2; x++) {
          full.setPixel(x, y);
        }
      }
      final fb = CellBuffer(const CellSize(1, 1));
      full.writeTo(fb, CellOffset.zero, CellStyle.empty);
      expect(fb.atColRow(0, 0).grapheme, '█');

      final one = SextantBuffer(1, 1)..setPixel(0, 0); // top-left → SEXTANT-1
      final ob = CellBuffer(const CellSize(1, 1));
      one.writeTo(ob, CellOffset.zero, CellStyle.empty);
      expect(ob.atColRow(0, 0).grapheme, String.fromCharCode(0x1FB00));
    });
  });

  group('OctantBuffer', () {
    test('pixelWidth/pixelHeight: 2×4 per cell', () {
      final b = OctantBuffer(3, 4);
      expect(b.pixelWidth, 6);
      expect(b.pixelHeight, 16);
    });

    test('full cell → █; a mid-left pixel → an octant glyph', () {
      final full = OctantBuffer(1, 1);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 2; x++) {
          full.setPixel(x, y);
        }
      }
      final fb = CellBuffer(const CellSize(1, 1));
      full.writeTo(fb, CellOffset.zero, CellStyle.empty);
      expect(fb.atColRow(0, 0).grapheme, '█');

      // (px=0, py=1) → bit 2 → BLOCK OCTANT-3 (U+1CD00).
      final one = OctantBuffer(1, 1)..setPixel(0, 1);
      final ob = CellBuffer(const CellSize(1, 1));
      one.writeTo(ob, CellOffset.zero, CellStyle.empty);
      expect(ob.atColRow(0, 0).grapheme, String.fromCharCode(0x1CD00));
    });

    test('no lit cell ever renders as blank', () {
      // Every non-empty mask must map to a non-space glyph (superset fallback).
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 2; x++) {
          final b = OctantBuffer(1, 1)..setPixel(x, y);
          final buf = CellBuffer(const CellSize(1, 1));
          b.writeTo(buf, CellOffset.zero, CellStyle.empty);
          expect(
            buf.atColRow(0, 0).grapheme,
            isNot(' '),
            reason: 'pixel ($x,$y) must light a visible glyph',
          );
        }
      }
    });
  });
}
