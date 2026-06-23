// Direct unit tests for the internal BrailleBuffer — covers the pixel
// mapping, dot-bit math, line drawing, color tracking, and writeTo. These
// are exercised indirectly via Canvas/LineChart, but a bad mapping there
// could pass integration tests with the wrong internal values, so the
// primitive deserves its own coverage.

import 'package:fleury/fleury.dart';
// ignore: implementation_imports
import 'package:fleury_widgets/src/braille.dart';
import 'package:test/test.dart';

void main() {
  group('BrailleBuffer', () {
    test('pixelWidth/pixelHeight are 2 × cols, 4 × rows', () {
      final b = BrailleBuffer(3, 5);
      expect(b.pixelWidth, 6);
      expect(b.pixelHeight, 20);
    });

    test('setPixel(0, 0) sets dot 1 (bit 0)', () {
      final b = BrailleBuffer(1, 1);
      b.setPixel(0, 0);
      // Render and read the codepoint of cell (0, 0).
      final buffer = CellBuffer(const CellSize(1, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      expect(buffer.atColRow(0, 0).grapheme!.codeUnitAt(0), 0x2800 + (1 << 0));
    });

    test('ASCII glyph tier writes density glyphs', () {
      final b = BrailleBuffer(1, 1);
      b.setPixel(0, 0);
      final buffer = CellBuffer(const CellSize(1, 1));
      b.writeTo(
        buffer,
        CellOffset.zero,
        CellStyle.empty,
        glyphTier: GlyphTier.ascii,
      );
      expect(buffer.atColRow(0, 0).grapheme, '.');
    });

    test('setPixel(1, 3) sets dot 8 (bit 7)', () {
      final b = BrailleBuffer(1, 1);
      b.setPixel(1, 3);
      final buffer = CellBuffer(const CellSize(1, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      expect(buffer.atColRow(0, 0).grapheme!.codeUnitAt(0), 0x2800 + (1 << 7));
    });

    test('every dot position maps to a unique bit', () {
      // Map each of the 8 dot positions (px, py) to its bit and check no
      // overlap: setting all 8 should produce 0xFF → glyph U+28FF (the
      // "all dots" braille pattern).
      final b = BrailleBuffer(1, 1);
      const positions = [
        (0, 0),
        (0, 1),
        (0, 2),
        (0, 3),
        (1, 0),
        (1, 1),
        (1, 2),
        (1, 3),
      ];
      for (final (px, py) in positions) {
        b.setPixel(px, py);
      }
      final buffer = CellBuffer(const CellSize(1, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      expect(buffer.atColRow(0, 0).grapheme!.codeUnitAt(0), 0x28FF);
    });

    test('out-of-bounds setPixel is silently clipped', () {
      final b = BrailleBuffer(1, 1);
      // Should not throw.
      b.setPixel(-1, 0);
      b.setPixel(0, -1);
      b.setPixel(99, 99);
      // Buffer remains empty.
      final buffer = CellBuffer(const CellSize(1, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      expect(buffer.atColRow(0, 0).grapheme, isNull);
    });

    test('drawLine lights both endpoints', () {
      final b = BrailleBuffer(2, 2); // 4×8 pixels
      b.drawLine(0, 0, 3, 7);
      final buffer = CellBuffer(const CellSize(2, 2));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      // (0,0) lands in cell (0,0); (3,7) lands in cell (1,1).
      expect(buffer.atColRow(0, 0).grapheme, isNotNull);
      expect(buffer.atColRow(1, 1).grapheme, isNotNull);
    });

    test('horizontal line stays in a single cell row', () {
      // Pixel row 1 (within cell row 0) all the way across.
      final b = BrailleBuffer(3, 1); // 6×4 pixels
      for (var x = 0; x < 6; x++) {
        b.setPixel(x, 1);
      }
      final buffer = CellBuffer(const CellSize(3, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      // All three cells in row 0 should have braille; nothing else exists.
      for (var c = 0; c < 3; c++) {
        expect(buffer.atColRow(c, 0).grapheme, isNotNull);
      }
    });

    test('setPixel with a color stores it on the cell', () {
      final b = BrailleBuffer(1, 1);
      b.setPixel(0, 0, const AnsiColor(3));
      final buffer = CellBuffer(const CellSize(1, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      expect(buffer.atColRow(0, 0).style.foreground, const AnsiColor(3));
    });

    test('most-recently-set color on a cell wins', () {
      final b = BrailleBuffer(1, 1);
      b.setPixel(0, 0, const AnsiColor(1));
      b.setPixel(1, 0, const AnsiColor(2));
      final buffer = CellBuffer(const CellSize(1, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      expect(buffer.atColRow(0, 0).style.foreground, const AnsiColor(2));
    });

    test('writeTo respects the destination offset', () {
      final b = BrailleBuffer(1, 1);
      b.setPixel(0, 0);
      final buffer = CellBuffer(const CellSize(3, 3));
      b.writeTo(buffer, const CellOffset(2, 1), CellStyle.empty);
      // Only the destination cell should have a braille glyph.
      expect(buffer.atColRow(2, 1).grapheme, isNotNull);
      expect(buffer.atColRow(0, 0).grapheme, isNull);
    });

    test('writeTo skips empty cells', () {
      final b = BrailleBuffer(2, 1);
      b.setPixel(0, 0); // light only the left cell
      final buffer = CellBuffer(const CellSize(2, 1));
      b.writeTo(buffer, CellOffset.zero, CellStyle.empty);
      expect(buffer.atColRow(0, 0).grapheme, isNotNull);
      expect(
        buffer.atColRow(1, 0).grapheme,
        isNull,
        reason: 'untouched cells should not be written',
      );
    });
  });
}
