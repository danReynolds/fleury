import 'dart:typed_data';

import 'package:fleury/fleury.dart';

/// A 2×4-pixel-per-cell drawing surface that renders as Unicode braille
/// patterns (`U+2800..U+28FF`). Internal helper used by `Canvas` and
/// `LineChart` to draw at sub-cell resolution on the terminal grid.
///
/// Each terminal cell holds an 8-bit dot mask. The Unicode mapping is:
///
///     dot 1  dot 4      bit 0  bit 3
///     dot 2  dot 5  →   bit 1  bit 4
///     dot 3  dot 6      bit 2  bit 5
///     dot 7  dot 8      bit 6  bit 7
///
/// Glyph at offset N = `U+2800 + N`, where N is the OR of set bits.
class BrailleBuffer {
  BrailleBuffer(this.cols, this.rows)
    : _dots = Uint8List(cols * rows),
      _colors = List<Color?>.filled(cols * rows, null);

  final int cols;
  final int rows;
  final Uint8List _dots;
  final List<Color?> _colors;

  int get pixelWidth => cols * 2;
  int get pixelHeight => rows * 4;

  static int _bitFor(int px, int py) {
    if (px == 0) {
      if (py < 3) return py; // 0,1,2 → dots 1,2,3
      return 6; // 3 → dot 7
    }
    if (py < 3) return 3 + py; // 0,1,2 → dots 4,5,6
    return 7; // 3 → dot 8
  }

  /// Lights a single pixel at `(px, py)`. Pixels outside the grid are
  /// silently clipped. The most-recently-set color on a cell wins when
  /// multiple lines cross it (matching Ratatui's behaviour).
  void setPixel(int px, int py, [Color? color]) {
    if (px < 0 || px >= pixelWidth || py < 0 || py >= pixelHeight) return;
    final cellCol = px >> 1;
    final cellRow = py >> 2;
    final dotPx = px - (cellCol << 1);
    final dotPy = py - (cellRow << 2);
    final idx = cellRow * cols + cellCol;
    _dots[idx] |= 1 << _bitFor(dotPx, dotPy);
    if (color != null) _colors[idx] = color;
  }

  /// Bresenham line in pixel space.
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
  /// Cells with no dots are left untouched.
  void writeTo(CellBuffer target, CellOffset offset, CellStyle defaultStyle) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final dots = _dots[idx];
        if (dots == 0) continue;
        final color = _colors[idx];
        final style = color == null
            ? defaultStyle
            : defaultStyle.merge(CellStyle(foreground: color));
        target.writeGrapheme(
          CellOffset(offset.col + c, offset.row + r),
          String.fromCharCode(0x2800 + dots),
          style: style,
        );
      }
    }
  }
}
