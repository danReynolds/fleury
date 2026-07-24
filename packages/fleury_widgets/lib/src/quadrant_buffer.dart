import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';

import 'glyphs.dart';
import 'sub_cell_buffer.dart';

/// A 2×2-pixel-per-cell drawing surface that renders as Unicode block-
/// element quadrants. Sits between `HalfBlockBuffer` (1×2) and
/// `BrailleBuffer` (2×4) in resolution, with the visual character of
/// solid blocks. Wide font coverage (the quadrant glyphs are part of
/// the Block Elements range that's existed for decades).
///
/// Bit layout per cell:
///
///     UL  UR    bit 0  bit 1
///     LL  LR    bit 2  bit 3
///
/// All 16 combinations have a dedicated Unicode glyph.
class QuadrantBuffer implements SubCellBuffer {
  QuadrantBuffer(this.cols, this.rows)
    : _bits = Uint8List(cols * rows),
      _colors = List<Color?>.filled(cols * rows, null);

  final int cols;
  final int rows;
  final Uint8List _bits;
  final List<Color?> _colors;

  @override
  int get pixelWidth => cols * 2;
  @override
  int get pixelHeight => rows * 2;

  // Index = (UL << 0) | (UR << 1) | (LL << 2) | (LR << 3).
  static const _glyphs = [
    ' ', // 0000
    '▘', // 0001 UL
    '▝', // 0010 UR
    '▀', // 0011 UL+UR (upper half)
    '▖', // 0100 LL
    '▌', // 0101 UL+LL (left half)
    '▞', // 0110 UR+LL (diagonal /)
    '▛', // 0111 UL+UR+LL
    '▗', // 1000 LR
    '▚', // 1001 UL+LR (diagonal \)
    '▐', // 1010 UR+LR (right half)
    '▜', // 1011 UL+UR+LR
    '▄', // 1100 LL+LR (lower half)
    '▙', // 1101 UL+LL+LR
    '▟', // 1110 UR+LL+LR
    '█', // 1111 all
  ];

  /// Lights a single pixel at `(px, py)`. Pixels outside the grid are
  /// silently clipped. Most-recently-set color on a cell wins.
  @override
  void setPixel(int px, int py, [Color? color]) {
    if (px < 0 || px >= pixelWidth || py < 0 || py >= pixelHeight) return;
    final cellCol = px >> 1;
    final cellRow = py >> 1;
    final dotPx = px - (cellCol << 1);
    final dotPy = py - (cellRow << 1);
    final bit = dotPx + (dotPy << 1); // 0:UL 1:UR 2:LL 3:LR
    final idx = cellRow * cols + cellCol;
    _bits[idx] |= 1 << bit;
    if (color != null) _colors[idx] = color;
  }

  /// Bresenham line in pixel space.
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

  /// Writes the populated cells of this buffer into [target] at [offset].
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
              ? densityGlyph(glyphTier, _bitCount(bits), 4)
              : _glyphs[bits],
          style: style,
        );
      }
    }
  }
}

int _bitCount(int value) {
  var count = 0;
  var remaining = value;
  while (remaining != 0) {
    count += remaining & 1;
    remaining >>= 1;
  }
  return count;
}
