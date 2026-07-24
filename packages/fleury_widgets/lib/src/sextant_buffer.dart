import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';

import 'glyphs.dart';
import 'sub_cell_buffer.dart';

/// A 2×3-pixel-per-cell drawing surface rendering as Unicode **sextant** block
/// glyphs (`U+1FB00..U+1FB3B`, "Symbols for Legacy Computing", Unicode 13.0).
/// A **solid, gap-free** tier that sits between `QuadrantBuffer` (2×2) and
/// `OctantBuffer` (2×4): more vertical resolution than quadrants with much
/// wider support than octants (five-plus years of adoption; drawn natively by
/// kitty and foot, and shipped by many monospace fonts). A good default
/// "solid" tier when octants can't be assumed.
///
/// Bit layout per cell (`bit = row * 2 + col`):
///
///     b0 b1
///     b2 b3
///     b4 b5
class SextantBuffer implements SubCellBuffer {
  SextantBuffer(this.cols, this.rows)
    : _bits = Uint8List(cols * rows),
      _colors = List<Color?>.filled(cols * rows, null);

  final int cols;
  final int rows;
  final Uint8List _bits;
  final List<Color?> _colors;

  @override
  int get pixelWidth => cols * 2;
  @override
  int get pixelHeight => rows * 3;

  @override
  void setPixel(int px, int py, [Color? color]) {
    if (px < 0 || px >= pixelWidth || py < 0 || py >= pixelHeight) return;
    final cellCol = px >> 1;
    final cellRow = py ~/ 3;
    final bit = (py - cellRow * 3) * 2 + (px - (cellCol << 1));
    final idx = cellRow * cols + cellCol;
    _bits[idx] |= 1 << bit;
    if (color != null) _colors[idx] = color;
  }

  @override
  void drawLine(int x0, int y0, int x1, int y1, [Color? color]) {
    var x = x0;
    var y = y0;
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx - dy;
    while (true) {
      setPixel(x, y, color);
      if (x == x1 && y == y1) break;
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

  @override
  void writeTo(
    CellBuffer target,
    CellOffset offset,
    CellStyle defaultStyle, {
    GlyphTier glyphTier = GlyphTier.unicode,
  }) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final bits = _bits[idx];
        if (bits == 0) continue;
        final color = _colors[idx];
        final style = color == null
            ? defaultStyle
            : defaultStyle.merge(CellStyle(foreground: color));
        target.writeGrapheme(
          CellOffset(offset.col + c, offset.row + r),
          glyphTier == GlyphTier.ascii
              ? densityGlyph(glyphTier, subCellBitCount(bits), 6)
              : String.fromCharCode(_sextantGlyphs[bits]),
          style: style,
        );
      }
    }
  }
}

// Maps a 6-bit sextant cell mask to a codepoint. The 60 assigned sextants
// (U+1FB00..U+1FB3B) plus the reused space / left-half / right-half / full
// block glyphs cover all 64 patterns exactly. Generated from the Unicode 13
// NamesList (BLOCK SEXTANT-… position naming).
const List<int> _sextantGlyphs = <int>[
  0x0020, 0x1FB00, 0x1FB01, 0x1FB02, 0x1FB03, 0x1FB04, 0x1FB05, 0x1FB06, //
  0x1FB07, 0x1FB08, 0x1FB09, 0x1FB0A, 0x1FB0B, 0x1FB0C, 0x1FB0D, 0x1FB0E, //
  0x1FB0F, 0x1FB10, 0x1FB11, 0x1FB12, 0x1FB13, 0x258C, 0x1FB14, 0x1FB15, //
  0x1FB16, 0x1FB17, 0x1FB18, 0x1FB19, 0x1FB1A, 0x1FB1B, 0x1FB1C, 0x1FB1D, //
  0x1FB1E, 0x1FB1F, 0x1FB20, 0x1FB21, 0x1FB22, 0x1FB23, 0x1FB24, 0x1FB25, //
  0x1FB26, 0x1FB27, 0x2590, 0x1FB28, 0x1FB29, 0x1FB2A, 0x1FB2B, 0x1FB2C, //
  0x1FB2D, 0x1FB2E, 0x1FB2F, 0x1FB30, 0x1FB31, 0x1FB32, 0x1FB33, 0x1FB34, //
  0x1FB35, 0x1FB36, 0x1FB37, 0x1FB38, 0x1FB39, 0x1FB3A, 0x1FB3B, 0x2588, //
];
