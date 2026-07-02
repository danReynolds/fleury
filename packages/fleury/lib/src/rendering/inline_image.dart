// The backend-neutral inline-image model: content ([InlineImage]),
// geometry ([InlineImagePlacement]), and the single fit resolver every
// surface derives its geometry from.
//
// Widgets place images into the [CellBuffer] (bytes + box + fit); the
// PRESENTER renders them — a DOM `<img>` overlay on browser surfaces, a
// terminal graphics protocol (Kitty/iTerm2/Sixel) via the terminal image
// encoder. Escape bytes never enter cells.

import 'dart:typed_data';

/// How an inline image fills its placement rectangle on a true-pixel
/// surface. The four modes mirror the widget-level `ImageFit`, and — by
/// design — their names are exactly the CSS `object-fit` keywords, so the
/// serve client applies `el.style.objectFit = fit.name` with no lookup
/// table. [contain] (the default) preserves the source aspect ratio;
/// without it a wrong-aspect cell box would stretch the image.
enum InlineImageFit { contain, cover, fill, none }

/// One inline image's content, off the cell grid, content-addressed by
/// [id]. The grid carries [Cell.overlay] cells over the placement region;
/// presenters read the bytes from here. Geometry (where and how big) is
/// NOT here — it belongs to the *placement*, since the same bytes can
/// appear at several sizes/positions in one frame.
///
/// [sourceWidth]/[sourceHeight] are the decoded pixel dimensions, needed
/// by terminal presenters to resolve aspect-preserving fits without
/// decoding [bytes] (the core cannot decode PNG). [pixels] is an optional
/// lazy provider of the decoded RGBA pixels (row-major, 4 bytes per
/// pixel, [sourceWidth]×[sourceHeight]) — required only by presenters
/// that must re-rasterize (Sixel); browser surfaces never call it.
final class InlineImage {
  const InlineImage({
    required this.id,
    required this.bytes,
    this.sourceWidth,
    this.sourceHeight,
    this.pixels,
  });

  final String id;
  final Uint8List bytes;
  final int? sourceWidth;
  final int? sourceHeight;
  final Uint8List Function()? pixels;
}

/// One placement of an inline image: which [id]'s bytes go where ([col],
/// [row]) over how many cells ([cols]×[rows]) and how they fill that box
/// ([fit]). One is recorded per [CellBuffer.writeImage] call, so the same
/// image drawn twice yields two placements with independent geometry.
final class InlineImagePlacement {
  const InlineImagePlacement({
    required this.id,
    required this.col,
    required this.row,
    required this.cols,
    required this.rows,
    required this.fit,
  });

  final String id;
  final int col;
  final int row;
  final int cols;
  final int rows;
  final InlineImageFit fit;
}

/// The geometry a fit resolves to: a destination sub-rectangle inside the
/// placement box (in cells, relative to the box top-left) plus the
/// source-pixel window to display there.
///
/// `contain` yields a centered aspect-true sub-rect with the full source;
/// `cover` yields the full box with a centered source crop; `fill` is the
/// whole box and whole source; `none` is a centered native-resolution
/// sub-rect cropped to what fits.
final class ResolvedImageFit {
  const ResolvedImageFit({
    required this.col,
    required this.row,
    required this.cols,
    required this.rows,
    required this.cropX,
    required this.cropY,
    required this.cropW,
    required this.cropH,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  /// Destination sub-rect, in cells, relative to the placement box.
  final int col, row, cols, rows;

  /// Source-pixel window displayed in the destination sub-rect.
  final int cropX, cropY, cropW, cropH;

  /// The source dimensions the resolution was computed against.
  final int sourceWidth, sourceHeight;

  /// Whether displaying this fit requires cropping the source (true for
  /// `cover` and for `none` on a source larger than the box).
  bool get cropsSource =>
      cropX != 0 || cropY != 0 || cropW != sourceWidth || cropH != sourceHeight;
}

/// Resolves an [InlineImageFit] into concrete geometry — THE fit math for
/// every surface. The terminal image encoder feeds it the protocol cell
/// box; the glyph painters feed it their sub-pixel density; the browser's
/// CSS `object-fit` implements the same math at sub-cell precision (the
/// only sanctioned divergence: DOM letterboxes land on CSS pixels, cell
/// surfaces land on whole cells).
///
/// [pixelsPerCellX]/[pixelsPerCellY] describe the cell's pixel aspect for
/// the target surface: glyph half-blocks are 1×2 (one column ≈ half the
/// height of a row), Sixel rasterization uses the terminal's cell pixel
/// size (10×20 by convention). Destination geometry snaps to whole cells
/// so protocol placements, glyph letterboxes, and test assertions agree.
ResolvedImageFit resolveInlineImageFit({
  required int sourceWidth,
  required int sourceHeight,
  required int cols,
  required int rows,
  required InlineImageFit fit,
  int pixelsPerCellX = 1,
  int pixelsPerCellY = 2,
}) {
  assert(sourceWidth > 0 && sourceHeight > 0, 'source must be non-empty');
  assert(cols > 0 && rows > 0, 'placement box must be non-empty');
  int centerOffset(int outer, int inner) =>
      ((outer - inner) / 2).round().clamp(0, outer - inner);
  final srcW = sourceWidth;
  final srcH = sourceHeight;
  final tgtW = (cols * pixelsPerCellX).toDouble();
  final tgtH = (rows * pixelsPerCellY).toDouble();
  switch (fit) {
    case InlineImageFit.fill:
      return ResolvedImageFit(
        col: 0,
        row: 0,
        cols: cols,
        rows: rows,
        cropX: 0,
        cropY: 0,
        cropW: srcW,
        cropH: srcH,
        sourceWidth: srcW,
        sourceHeight: srcH,
      );
    case InlineImageFit.contain:
      final scale = (tgtW / srcW < tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
      final dCols = (srcW * scale / pixelsPerCellX).round().clamp(1, cols);
      final dRows = (srcH * scale / pixelsPerCellY).round().clamp(1, rows);
      return ResolvedImageFit(
        col: centerOffset(cols, dCols),
        row: centerOffset(rows, dRows),
        cols: dCols,
        rows: dRows,
        cropX: 0,
        cropY: 0,
        cropW: srcW,
        cropH: srcH,
        sourceWidth: srcW,
        sourceHeight: srcH,
      );
    case InlineImageFit.cover:
      final scale = (tgtW / srcW > tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
      final cropW = (tgtW / scale).round().clamp(1, srcW);
      final cropH = (tgtH / scale).round().clamp(1, srcH);
      return ResolvedImageFit(
        col: 0,
        row: 0,
        cols: cols,
        rows: rows,
        cropX: centerOffset(srcW, cropW),
        cropY: centerOffset(srcH, cropH),
        cropW: cropW,
        cropH: cropH,
        sourceWidth: srcW,
        sourceHeight: srcH,
      );
    case InlineImageFit.none:
      // Native resolution, centered: one source pixel maps to one target
      // pixel at the surface's cell density; overflow is cropped.
      final cropW = srcW <= tgtW ? srcW : tgtW.round();
      final cropH = srcH <= tgtH ? srcH : tgtH.round();
      final dCols = (cropW / pixelsPerCellX).round().clamp(1, cols);
      final dRows = (cropH / pixelsPerCellY).round().clamp(1, rows);
      return ResolvedImageFit(
        col: centerOffset(cols, dCols),
        row: centerOffset(rows, dRows),
        cols: dCols,
        rows: dRows,
        cropX: centerOffset(srcW, cropW),
        cropY: centerOffset(srcH, cropH),
        cropW: cropW,
        cropH: cropH,
        sourceWidth: srcW,
        sourceHeight: srcH,
      );
  }
}
