import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';

import 'glyphs.dart';
import 'sub_cell_buffer.dart';

/// A 1×2-pixel-per-cell drawing surface that renders as Unicode block
/// elements (` ` / `▀` / `▄` / `█`). Lower sub-cell resolution than
/// braille but with much wider font support — every monospace font that
/// supports the Block Elements range can render these — and a "solid"
/// look that reads as a filled chart rather than a stippled one.
///
/// Bit layout per cell:
///
///     top    bit 0
///     bot    bit 1
///
/// Glyph table: 0 → ` `, 1 → `▀`, 2 → `▄`, 3 → `█`.
class HalfBlockBuffer implements SubCellBuffer {
  HalfBlockBuffer(this.cols, this.rows)
    : _bits = Uint8List(cols * rows),
      _colors = List<Color?>.filled(cols * rows, null);

  final int cols;
  final int rows;
  final Uint8List _bits;
  final List<Color?> _colors;

  @override
  int get pixelWidth => cols;
  @override
  int get pixelHeight => rows * 2;
  @override
  bool get isStippled => false;

  static const _glyphs = [' ', '▀', '▄', '█'];

  /// Lights a single pixel at `(px, py)`. Pixels outside the grid are
  /// silently clipped. The most-recently-set color on a cell wins when
  /// multiple lines cross it (matching `BrailleBuffer`'s behaviour).
  @override
  void setPixel(int px, int py, [Color? color]) {
    if (px < 0 || px >= pixelWidth || py < 0 || py >= pixelHeight) return;
    final cellRow = py >> 1;
    final dotPy = py - (cellRow << 1);
    final idx = cellRow * cols + px;
    _bits[idx] |= 1 << dotPy;
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
  /// Cells with no lit pixels are left untouched.
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
              ? densityGlyph(glyphTier, _bitCount(bits), 2)
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
