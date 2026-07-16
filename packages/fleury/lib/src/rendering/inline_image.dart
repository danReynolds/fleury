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
    this.croppedBytes,
  });

  final String id;
  final Uint8List bytes;
  final int? sourceWidth;
  final int? sourceHeight;
  final Uint8List Function()? pixels;

  /// Lazily encodes a source-pixel crop as PNG bytes. Most presenters can
  /// express a crop directly (Kitty) or rasterize from [pixels] (Sixel), but
  /// iTerm2's inline-image protocol cannot. Image providers that already own
  /// a decoded bitmap can supply this without making the rendering core learn
  /// how to decode or encode PNGs.
  final Uint8List Function(int x, int y, int width, int height)? croppedBytes;
}

/// One visible placement of an inline image.
///
/// [col], [row], [cols], and [rows] describe the non-empty rectangle visible
/// in the current buffer. [boxCols]×[boxRows] is the original laid-out image
/// box, and [boxOffsetCol]/[boxOffsetRow] locate the visible rectangle inside
/// that box. Keeping both rectangles is essential: fitting is resolved against
/// the original box and only then clipped, so scrolling or clipping a `cover`,
/// `contain`, or `none` image never rescales or recenters it.
///
/// One is recorded per image paint, so the same [id] drawn twice yields two
/// placements with independent geometry and stable paint-list order.
final class InlineImagePlacement {
  const InlineImagePlacement({
    required this.id,
    required this.col,
    required this.row,
    required this.cols,
    required this.rows,
    required this.fit,
    int? boxCols,
    int? boxRows,
    this.boxOffsetCol = 0,
    this.boxOffsetRow = 0,
  }) : boxCols = boxCols ?? cols,
       boxRows = boxRows ?? rows,
       assert(cols > 0 && rows > 0, 'visible box must be non-empty'),
       assert((boxCols ?? cols) > 0 && (boxRows ?? rows) > 0),
       assert(boxOffsetCol >= 0 && boxOffsetRow >= 0),
       assert(boxOffsetCol + cols <= (boxCols ?? cols)),
       assert(boxOffsetRow + rows <= (boxRows ?? rows));

  final String id;
  final int col;
  final int row;
  final int cols;
  final int rows;
  final InlineImageFit fit;
  final int boxCols;
  final int boxRows;
  final int boxOffsetCol;
  final int boxOffsetRow;

  bool get isClipped =>
      boxOffsetCol != 0 ||
      boxOffsetRow != 0 ||
      cols != boxCols ||
      rows != boxRows;
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

/// Resolves [placement]'s fit against its original box, then intersects that
/// result with the placement's visible window.
///
/// The returned destination is relative to the visible placement rectangle,
/// while its source crop is refined to the same window. `null` means the
/// visible window contains only a letterbox band and therefore has no image
/// pixels to present.
ResolvedImageFit? resolveClippedInlineImageFit({
  required InlineImagePlacement placement,
  required int sourceWidth,
  required int sourceHeight,
  int pixelsPerCellX = 1,
  int pixelsPerCellY = 2,
}) {
  final fitted = resolveInlineImageFit(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    cols: placement.boxCols,
    rows: placement.boxRows,
    fit: placement.fit,
    pixelsPerCellX: pixelsPerCellX,
    pixelsPerCellY: pixelsPerCellY,
  );

  final visibleLeft = placement.boxOffsetCol;
  final visibleTop = placement.boxOffsetRow;
  final visibleRight = visibleLeft + placement.cols;
  final visibleBottom = visibleTop + placement.rows;
  final fittedRight = fitted.col + fitted.cols;
  final fittedBottom = fitted.row + fitted.rows;
  final left = visibleLeft > fitted.col ? visibleLeft : fitted.col;
  final top = visibleTop > fitted.row ? visibleTop : fitted.row;
  final right = visibleRight < fittedRight ? visibleRight : fittedRight;
  final bottom = visibleBottom < fittedBottom ? visibleBottom : fittedBottom;
  if (left >= right || top >= bottom) return null;

  int cropBoundary(int position, int extent, int cropStart, int cropExtent) {
    return cropStart + (position * cropExtent / extent).round();
  }

  var cropLeft = cropBoundary(
    left - fitted.col,
    fitted.cols,
    fitted.cropX,
    fitted.cropW,
  );
  var cropRight = cropBoundary(
    right - fitted.col,
    fitted.cols,
    fitted.cropX,
    fitted.cropW,
  );
  var cropTop = cropBoundary(
    top - fitted.row,
    fitted.rows,
    fitted.cropY,
    fitted.cropH,
  );
  var cropBottom = cropBoundary(
    bottom - fitted.row,
    fitted.rows,
    fitted.cropY,
    fitted.cropH,
  );

  // A source pixel may be stretched across several cells. Any non-empty
  // visible destination still needs at least that one pixel in the protocol
  // crop, even when both rounded boundaries land on it.
  if (cropRight <= cropLeft) {
    cropLeft = cropLeft.clamp(fitted.cropX, fitted.cropX + fitted.cropW - 1);
    cropRight = cropLeft + 1;
  }
  if (cropBottom <= cropTop) {
    cropTop = cropTop.clamp(fitted.cropY, fitted.cropY + fitted.cropH - 1);
    cropBottom = cropTop + 1;
  }

  return ResolvedImageFit(
    col: left - visibleLeft,
    row: top - visibleTop,
    cols: right - left,
    rows: bottom - top,
    cropX: cropLeft,
    cropY: cropTop,
    cropW: cropRight - cropLeft,
    cropH: cropBottom - cropTop,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );
}
