import 'package:fleury/fleury_core.dart';

/// A sub-cell drawing surface: a monochrome-per-cell pixel grid that packs
/// several pixels into each terminal cell and renders them as one Unicode
/// glyph. `BrailleBuffer`, `HalfBlockBuffer`, `QuadrantBuffer`,
/// `SextantBuffer`, and `OctantBuffer` are the concrete tiers, trading
/// resolution against font/terminal coverage and a stippled-vs-solid look.
///
/// The tiers share this shape so a caller (e.g. `LineChart`) can pick one at
/// runtime and draw against a single interface: map data into `pixelWidth ×
/// pixelHeight`, [setPixel]/[drawLine], then [writeTo] the target cell buffer.
abstract interface class SubCellBuffer {
  /// Pixel columns across the whole buffer (`cols × pixelsPerCellX`).
  int get pixelWidth;

  /// Pixel rows down the whole buffer (`rows × pixelsPerCellY`).
  int get pixelHeight;

  /// Whether this tier renders as separated dots (braille) rather than solid
  /// blocks. A solid tier already reads as a continuous one-pixel line;
  /// a stippled one benefits from being drawn thicker.
  bool get isStippled;

  /// Lights the pixel at `(px, py)`; out-of-range pixels are clipped.
  /// The most-recently-set color on a cell wins.
  void setPixel(int px, int py, [Color? color]);

  /// Rasterizes a Bresenham line between two pixels.
  void drawLine(int x0, int y0, int x1, int y1, [Color? color]);

  /// Writes populated cells into [target] at [offset]; empty cells untouched.
  void writeTo(
    CellBuffer target,
    CellOffset offset,
    CellStyle defaultStyle, {
    GlyphTier glyphTier = GlyphTier.unicode,
  });
}

/// Population count helper shared by the sub-cell buffers (used for the ASCII
/// density fallback).
int subCellBitCount(int value) {
  var count = 0;
  var remaining = value;
  while (remaining != 0) {
    count += remaining & 1;
    remaining >>= 1;
  }
  return count;
}
