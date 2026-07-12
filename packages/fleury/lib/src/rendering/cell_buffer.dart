import 'dart:typed_data';

import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import 'cell.dart';
import 'inline_image.dart';
import 'width_resolver.dart';

export 'inline_image.dart';

/// A two-dimensional grid of [Cell]s representing one frame of the terminal
/// rendering output.
///
/// The buffer enforces the cell-grid invariants the rest of the renderer
/// depends on:
///
///   1. A wide grapheme (width 2) occupies a leading cell at column N and
///      a continuation cell at column N+1.
///   2. Writing to a continuation cell evicts the orphaned leading cell to
///      its left (replacing it with an empty cell).
///   3. Writing over a wide leading cell evicts the orphaned continuation
///      cell to its right.
///   4. A wide grapheme that would not fit (column N+1 outside the grid) is
///      replaced with a single-cell '?' marker rather than spilling.
///
/// The buffer never emits ANSI sequences; that responsibility belongs to
/// the diff renderer which compares two buffers and writes the result.
final class CellBuffer {
  CellBuffer(CellSize size)
    : _size = size,
      _cells = List<Cell>.filled(
        size.cols * size.rows,
        const Cell.empty(),
        growable: false,
      );

  CellSize _size;
  List<Cell> _cells;
  // Inline image bytes placed this frame, deduplicated by content hash.
  // Repopulated by [writeImage] each paint; cleared with the cells.
  final Map<String, InlineImage> _images = <String, InlineImage>{};
  // Per-placement geometry, one entry per [writeImage] call, in paint order.
  final List<InlineImagePlacement> _imagePlacements = <InlineImagePlacement>[];
  var _damageTrackingEnabled = false;
  CellRect? _damageBounds;
  final Set<int> _damageRows = <int>{};
  var _damageSuppressionDepth = 0;

  CellSize get size => _size;

  /// Inline image content placed this frame, deduplicated by content hash.
  /// The cell grid marks each placement's region with [Cell.overlay] cells;
  /// presenters resolve geometry through [imagePlacements]. Read-only.
  Map<String, InlineImage> get images => _images;

  /// Per-placement geometry for the inline images placed this frame, in paint
  /// order. Each entry is a distinct on-screen rectangle even when two share an
  /// [InlineImagePlacement.id] (same bytes drawn twice). Read-only.
  List<InlineImagePlacement> get imagePlacements => _imagePlacements;

  /// Conservative bounds of cells mutated since the last
  /// [resetDamageTracking].
  ///
  /// This is a paint-to-presenter hint, not a correctness oracle. Callers can
  /// use it to bound a later diff only when they know every possible visual
  /// change went through this buffer while tracking was active.
  CellRect? get damageBounds => _damageBounds;

  /// Starts or resets damage tracking without changing cell contents.
  void resetDamageTracking() {
    _damageTrackingEnabled = true;
    _damageBounds = null;
    _damageRows.clear();
  }

  /// Clears and returns the accumulated damage bounds.
  /// The exact rows written since [resetDamageTracking], independent of the
  /// single-rect union in [takeDamageBounds]. Scattered writes (disjoint
  /// rows) stay disjoint here instead of being smeared into one tall rect.
  Set<int> takeDamageRows() {
    final result = Set<int>.of(_damageRows);
    _damageRows.clear();
    return result;
  }

  CellRect? takeDamageBounds() {
    final result = _damageBounds;
    _damageBounds = null;
    return result;
  }

  /// Runs [body] without recording buffer writes as damage.
  ///
  /// Used by repaint boundaries when blitting an unchanged cached subtree into
  /// the frame buffer: the copy is necessary to reconstruct the next frame, but
  /// it should not force the terminal presenter to scan that region.
  T withoutDamageTracking<T>(T Function() body) {
    _damageSuppressionDepth += 1;
    try {
      return body();
    } finally {
      _damageSuppressionDepth -= 1;
    }
  }

  /// Returns the cell at [position]. Throws if [position] is out of bounds.
  Cell at(CellOffset position) {
    _checkBounds(position);
    return _cells[_indexOf(position)];
  }

  /// Returns the cell at the raw `(col, row)` coordinates. Throws if out
  /// of bounds. Convenience for tight inner loops where allocating
  /// [CellOffset] is wasteful.
  Cell atColRow(int col, int row) {
    _checkBoundsColRow(col, row);
    return _cells[row * _size.cols + col];
  }

  /// Clears every cell back to [Cell.empty].
  void clear() {
    _recordDamageRect(0, 0, _size.cols, _size.rows);
    _cells.fillRange(0, _cells.length, const Cell.empty());
    _images.clear();
    _imagePlacements.clear();
  }

  /// Scrolls the buffer up by [rows] rows: row `r + rows` moves to row `r`,
  /// and the bottom [rows] rows are cleared to [Cell.empty]. A non-positive
  /// or oversized shift clears the whole buffer. Used by the remote client
  /// to apply a scroll-up frame to its mirror before the residual patches.
  void scrollUp(int rows) {
    if (rows <= 0) return;
    if (rows >= _size.rows) {
      clear();
      return;
    }
    final cols = _size.cols;
    final retained = (_size.rows - rows) * cols;
    // setRange handles the overlap correctly here: the destination range
    // starts before the source range, so the ascending element copy is safe.
    _cells.setRange(0, retained, _cells, rows * cols);
    _cells.fillRange(retained, _cells.length, const Cell.empty());
    _recordDamageRect(0, 0, _size.cols, _size.rows);
  }

  /// Resizes the buffer to [newSize], discarding any existing content.
  /// The caller is expected to repaint after a resize.
  void resize(CellSize newSize) {
    _size = newSize;
    _cells = List<Cell>.filled(
      newSize.cols * newSize.rows,
      const Cell.empty(),
      growable: false,
    );
    _images.clear();
    _imagePlacements.clear();
    _damageBounds = null;
    _recordDamageRect(0, 0, newSize.cols, newSize.rows);
  }

  /// Copies every cell from [source] into this buffer with its top-left
  /// landing at [destOffset]. Cells outside this buffer are clipped. Used by
  /// `RenderRepaintBoundary` to blit a cached sub-buffer into the main frame
  /// — much faster than re-walking the subtree's paint.
  ///
  /// Assumes the destination region was cleared (or contains no wide-cell
  /// invariants that would be violated by direct overwrite). The main paint
  /// path satisfies this because the frame buffer is cleared at the start of
  /// every frame.
  void copyFrom(CellBuffer source, CellOffset destOffset) {
    _copyRect(source, 0, 0, source._size.cols, source._size.rows, destOffset);
  }

  /// Copies the [srcRect] region of [source] into this buffer with its
  /// top-left landing at [destOffset]. Same assumptions as [copyFrom];
  /// useful when the source is largely empty (e.g. a `RepaintBoundary`'s
  /// cache) and only the tight bounding box of its content needs to be
  /// blitted.
  void copyRectFrom(
    CellBuffer source,
    CellRect srcRect,
    CellOffset destOffset,
  ) {
    _copyRect(
      source,
      srcRect.offset.col,
      srcRect.offset.row,
      srcRect.size.cols,
      srcRect.size.rows,
      destOffset,
    );
  }

  void _copyRect(
    CellBuffer source,
    int srcCol,
    int srcRow,
    int cols,
    int rows,
    CellOffset destOffset,
  ) {
    if (cols <= 0 || rows <= 0) return;
    final dstCol0 = destOffset.col;
    final dstRow0 = destOffset.row;
    final srcStride = source._size.cols;
    _recordDamageRect(dstCol0, dstRow0, cols, rows);

    // Inline images ride along: placements live on the buffer, not in
    // cells, so a cached-subtree blit (RenderRepaintBoundary) must carry
    // them or the presenter would see overlay cells with no placement and
    // the image would vanish on the first cached frame. Geometry
    // translates by the copy delta; content dedupes by id.
    for (final p in source._imagePlacements) {
      final intersects =
          p.col < srcCol + cols &&
          p.col + p.cols > srcCol &&
          p.row < srcRow + rows &&
          p.row + p.rows > srcRow;
      if (!intersects) continue;
      final newCol = p.col - srcCol + dstCol0;
      final newRow = p.row - srcRow + dstRow0;
      // Only carry a placement whose top-left lands in-bounds — the same
      // rule [writeImageWithId] applies. A blit at a negative destOffset
      // (a repaint boundary under a negatively-positioned parent) would
      // otherwise record a placement at a negative cell, which a terminal
      // presenter turns into an invalid cursor address and the wire codec
      // into an out-of-range varint.
      if (!_containsColRow(newCol, newRow)) continue;
      final image = source._images[p.id];
      if (image == null) continue;
      _images[p.id] = image;
      _imagePlacements.add(
        InlineImagePlacement(
          id: p.id,
          col: newCol,
          row: newRow,
          cols: p.cols,
          rows: p.rows,
          fit: p.fit,
        ),
      );
    }

    // Fast path: full-width rows landing at column 0 of this buffer — the
    // sliced source rows map to a contiguous range in the destination, so
    // one `setRange` covers the whole block.
    if (dstCol0 == 0 &&
        srcCol == 0 &&
        cols == _size.cols &&
        cols == srcStride) {
      var dstStartRow = dstRow0;
      var dstEndRow = dstRow0 + rows;
      var srcStartRow = srcRow;
      if (dstStartRow < 0) {
        srcStartRow += -dstStartRow;
        dstStartRow = 0;
      }
      if (dstEndRow > _size.rows) dstEndRow = _size.rows;
      if (dstEndRow <= dstStartRow) return;
      _cells.setRange(
        dstStartRow * _size.cols,
        dstEndRow * _size.cols,
        source._cells,
        srcStartRow * srcStride,
      );
      return;
    }

    // General case: clip per row.
    for (var r = 0; r < rows; r++) {
      final dstRow = dstRow0 + r;
      if (dstRow < 0 || dstRow >= _size.rows) continue;
      var colStart = 0;
      var colEnd = cols;
      if (dstCol0 < 0) colStart = -dstCol0;
      if (dstCol0 + colEnd > _size.cols) colEnd = _size.cols - dstCol0;
      if (colEnd <= colStart) continue;
      final srcStart = (srcRow + r) * srcStride + srcCol + colStart;
      final dstStart = dstRow * _size.cols + dstCol0 + colStart;
      final len = colEnd - colStart;
      _cells.setRange(dstStart, dstStart + len, source._cells, srcStart);
    }
  }

  /// The tight bounding box of non-empty cells in this buffer, or null if the
  /// buffer is entirely empty. Used by `RenderRepaintBoundary` to blit only
  /// the cells that actually have content — keeps the boundary at-worst neutral
  /// on sparse subtrees that would otherwise pay a full-buffer copy.
  CellRect? boundingBoxOfNonEmpty() {
    final cols = _size.cols;
    final rows = _size.rows;
    int? firstRow;
    for (var r = 0; r < rows; r++) {
      final base = r * cols;
      for (var c = 0; c < cols; c++) {
        if (_cells[base + c].role != CellRole.empty) {
          firstRow = r;
          break;
        }
      }
      if (firstRow != null) break;
    }
    if (firstRow == null) return null;
    var lastRow = firstRow;
    for (var r = rows - 1; r > firstRow; r--) {
      final base = r * cols;
      var found = false;
      for (var c = 0; c < cols; c++) {
        if (_cells[base + c].role != CellRole.empty) {
          found = true;
          break;
        }
      }
      if (found) {
        lastRow = r;
        break;
      }
    }
    var minCol = cols;
    var maxCol = -1;
    for (var r = firstRow; r <= lastRow; r++) {
      final base = r * cols;
      for (var c = 0; c < cols; c++) {
        if (_cells[base + c].role != CellRole.empty) {
          if (c < minCol) minCol = c;
          if (c > maxCol) maxCol = c;
        }
      }
    }
    if (maxCol < 0) return null;
    return CellRect(
      offset: CellOffset(minCol, firstRow),
      size: CellSize(maxCol - minCol + 1, lastRow - firstRow + 1),
    );
  }

  /// [boundingBoxOfNonEmpty] restricted to [within], which the caller
  /// guarantees contains every non-empty cell (e.g. this buffer's damage
  /// bounds over a paint into a cleared buffer — a conservative superset,
  /// since grapheme writes pad damage by the wide-cell guard columns).
  ///
  /// Trims [within]'s all-empty edge rows/columns and returns the tight
  /// bounds, or null if the region is entirely empty. Same result as the
  /// full-grid scan, but the cost is bounded by the hint: typically the
  /// hint's perimeter, not the whole buffer.
  CellRect? boundingBoxOfNonEmptyWithin(CellRect within) {
    var top = within.offset.row;
    var left = within.offset.col;
    var bottom = top + within.size.rows - 1; // inclusive
    var right = left + within.size.cols - 1; // inclusive
    // Damage rects are already grid-clamped; clamp again defensively so a
    // hand-built hint cannot walk out of the cell array.
    if (top < 0) top = 0;
    if (left < 0) left = 0;
    if (bottom >= _size.rows) bottom = _size.rows - 1;
    if (right >= _size.cols) right = _size.cols - 1;
    if (top > bottom || left > right) return null;

    bool rowEmpty(int row) {
      final base = row * _size.cols;
      for (var c = left; c <= right; c++) {
        if (_cells[base + c].role != CellRole.empty) return false;
      }
      return true;
    }

    bool colEmpty(int col) {
      for (var r = top; r <= bottom; r++) {
        if (_cells[r * _size.cols + col].role != CellRole.empty) return false;
      }
      return true;
    }

    while (top <= bottom && rowEmpty(top)) top++;
    if (top > bottom) return null;
    while (bottom > top && rowEmpty(bottom)) bottom--;
    // A non-empty cell exists in [top..bottom], so both trims terminate.
    while (colEmpty(left)) left++;
    while (colEmpty(right)) right--;
    return CellRect(
      offset: CellOffset(left, top),
      size: CellSize(right - left + 1, bottom - top + 1),
    );
  }

  /// Writes a single grapheme cluster at [position] using [style].
  ///
  /// [grapheme] must be a single Unicode grapheme cluster (per UAX #29);
  /// pre-split with the `characters` package. [grapheme] must also be
  /// safe — i.e. already passed through `sanitizeForDisplay` if it came
  /// from arbitrary input. The buffer does not re-sanitize on every write.
  ///
  /// Returns the number of columns the write actually advanced (0, 1, or
  /// 2). A grapheme of width 0 (combining-only) is dropped. Out-of-bounds
  /// writes are clipped and return 0; reads still throw.
  int writeGrapheme(
    CellOffset position,
    String grapheme, {
    CellStyle style = CellStyle.empty,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) {
    if (!_containsColRow(position.col, position.row)) return 0;
    return _writeGraphemeAt(
      position.col,
      position.row,
      grapheme,
      style: style,
      widthResolver: widthResolver,
      profile: profile,
    );
  }

  /// Internal write that takes raw `(col, row)` to avoid allocating a
  /// `CellOffset` per call. Used by [writeText]'s grapheme loop.
  int _writeGraphemeAt(
    int col,
    int row,
    String grapheme, {
    CellStyle style = CellStyle.empty,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) {
    final width = widthResolver.widthOfGrapheme(grapheme, profile);
    if (width == 0) return 0;
    // Include adjacent cells because writing can evict wide-cell neighbors.
    _recordDamageRect(col - 1, row, width + 2, 1);

    final base = row * _size.cols + col;

    if (width == 2) {
      if (col + 1 >= _size.cols) {
        _evictWideNeighbors(col, row);
        _cells[base] = Cell.leading(grapheme: '?', style: style);
        return 1;
      }
      _evictWideNeighbors(col, row);
      _evictWideNeighbors(col + 1, row);
      _cells[base] = Cell.leading(grapheme: grapheme, style: style);
      _cells[base + 1] = Cell.continuation(style: style);
      return 2;
    }

    _evictWideNeighbors(col, row);
    _cells[base] = Cell.leading(grapheme: grapheme, style: style);
    return 1;
  }

  /// Writes the grapheme clusters of [text] horizontally starting at
  /// [position], using [style]. The caller is responsible for splitting
  /// [text] across lines; this method does not interpret newlines.
  ///
  /// Returns the number of columns advanced. Stops at the right edge of
  /// the row. A start position outside the buffer is clipped, which lets
  /// translated paints draw only the visible tail of a line.
  int writeText(
    CellOffset position,
    String text, {
    CellStyle style = CellStyle.empty,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) {
    var col = position.col;
    final startCol = col;
    final row = position.row;
    if (row < 0 || row >= _size.rows) return 0;
    for (final grapheme in text.characters) {
      if (col >= _size.cols) break;
      final width = widthResolver.widthOfGrapheme(grapheme, profile);
      if (width == 0) continue;
      if (col >= 0) {
        _writeGraphemeAt(
          col,
          row,
          grapheme,
          style: style,
          widthResolver: widthResolver,
          profile: profile,
        );
      }
      col += width;
    }
    return col - startCol;
  }

  /// Places an inline image over a [width]×[height] cell region. The bytes are
  /// stored in [images] keyed by a content hash; the geometry (plus [fit]) is
  /// recorded as an [InlineImagePlacement]; the grid cells become
  /// [Cell.overlay] so text renderers leave the region alone. The PRESENTER
  /// renders the pixels: the serve codec ships the bytes once per id and the
  /// DOM client overlays an `<img>`; the terminal image encoder emits the
  /// active graphics protocol (Kitty/iTerm2/Sixel).
  ///
  /// [sourceWidth]/[sourceHeight] (decoded pixel dimensions) let terminal
  /// presenters resolve aspect-preserving fits without decoding the bytes;
  /// without them a terminal presenter falls back to `fill` geometry.
  /// [pixels] lazily provides decoded RGBA (row-major, 4 bytes/pixel) —
  /// required only by Sixel, which must re-rasterize.
  void writeImage(
    CellOffset topLeft,
    Uint8List bytes, {
    required int width,
    required int height,
    InlineImageFit fit = InlineImageFit.contain,
    int? sourceWidth,
    int? sourceHeight,
    Uint8List Function()? pixels,
  }) {
    writeImageWithId(
      topLeft,
      _hashBytes(bytes),
      bytes,
      width: width,
      height: height,
      fit: fit,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      pixels: pixels,
    );
  }

  /// Records an inline image whose bytes are already hashed/encoded (the widget
  /// caches the PNG + id across repaints). Skips the per-paint re-hash on the
  /// hot path; see [writeImage] for the deduplication + placement model.
  void writeImageWithId(
    CellOffset topLeft,
    String id,
    Uint8List bytes, {
    required int width,
    required int height,
    InlineImageFit fit = InlineImageFit.contain,
    int? sourceWidth,
    int? sourceHeight,
    Uint8List Function()? pixels,
  }) {
    // A zero (or negative) dimension is a no-op, like a width-0 grapheme:
    // recording it would hand the terminal image encoder a degenerate box
    // whose fit math divides/clamps by zero and throws in the present
    // phase — outside the render backstop, so it would wedge the session.
    if (width <= 0 || height <= 0) return;
    if (!_containsColRow(topLeft.col, topLeft.row)) return;
    // Bytes are deduplicated by id; geometry is recorded per placement so the
    // same image drawn twice (or at two sizes) keeps independent rectangles.
    _images[id] = InlineImage(
      id: id,
      bytes: bytes,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      pixels: pixels,
    );
    _imagePlacements.add(
      InlineImagePlacement(
        id: id,
        col: topLeft.col,
        row: topLeft.row,
        cols: width,
        rows: height,
        fit: fit,
      ),
    );
    _recordDamageRect(topLeft.col, topLeft.row, width, height);
    final r0 = topLeft.row;
    final c0 = topLeft.col;
    final maxR = (r0 + height).clamp(0, _size.rows);
    final maxC = (c0 + width).clamp(0, _size.cols);
    for (var r = r0; r < maxR; r++) {
      for (var c = c0; c < maxC; c++) {
        _cells[r * _size.cols + c] = const Cell.overlay();
      }
    }
  }

  /// Carries the inline-image placements of [source] into this buffer,
  /// translated by [destOffset] — the image analogue of a manual cell
  /// composite.
  ///
  /// Widgets that paint their children into a scratch [CellBuffer] and then
  /// copy the visible cells back (ScrollView, an overflow-clipped Flex, the
  /// effect layers) must also carry the scratch's placements, or an Image
  /// inside them renders nothing on a true-pixel surface: the presenter
  /// sees no placement and the renderer emits nothing for the overlay
  /// cells. Each placement is re-recorded through [writeImageWithId] (so
  /// the overlay cells, damage, and image dedup all happen the normal way)
  /// and dropped when its translated top-left lands out of bounds — the
  /// same clip the manual cell loops apply.
  void compositeImagesFrom(CellBuffer source, CellOffset destOffset) {
    if (source._imagePlacements.isEmpty) return;
    for (final p in source._imagePlacements) {
      final image = source._images[p.id];
      if (image == null) continue;
      writeImageWithId(
        CellOffset(p.col + destOffset.col, p.row + destOffset.row),
        p.id,
        image.bytes,
        width: p.cols,
        height: p.rows,
        fit: p.fit,
        sourceWidth: image.sourceWidth,
        sourceHeight: image.sourceHeight,
        pixels: image.pixels,
      );
    }
  }

  /// Public content hash for inline-image bytes — the same scheme [writeImage]
  /// uses, exposed so a caller that caches its encoded bytes (the Image widget
  /// caches the PNG across repaints) can precompute the id once and pass it to
  /// [writeImageWithId], skipping a per-frame re-hash of the whole image.
  static String hashImageBytes(Uint8List bytes) => _hashBytes(bytes);

  /// Content hash, stable across re-encodes of the same image so the serve
  /// ships identical bytes only once. Two independent rolling hashes (distinct
  /// multipliers and Mersenne-prime moduli) combine with the byte length into
  /// one id — ~62 effective bits, so distinct images are overwhelmingly
  /// unlikely to collide and alias to one another's pixels. Each intermediate
  /// stays JS-safe: `h * 769 + b < 2^31 * 2^10 = 2^41 < 2^53` (this file
  /// compiles to dart2js, where ints are 53-bit).
  static String _hashBytes(Uint8List bytes) {
    const mod1 = 0x7FFFFFFF; // 2^31 - 1
    const mod2 =
        0x7FFFFFED; // largest prime below 2^31 - 1, independent of mod1
    var h1 = 0;
    var h2 = 0;
    for (final b in bytes) {
      h1 = (h1 * 257 + b) % mod1;
      h2 = (h2 * 769 + b) % mod2;
    }
    return '${h1.toRadixString(16)}-${h2.toRadixString(16)}-${bytes.length}';
  }

  // ---- Invariants --------------------------------------------------------

  /// If `(col, row)` is currently a continuation cell, the wide leading
  /// at `(col-1, row)` is now orphaned — replace it with empty.
  ///
  /// If `(col, row)` is currently a leading cell whose continuation is at
  /// `(col+1, row)`, the continuation is now orphaned — replace it with
  /// empty.
  void _evictWideNeighbors(int col, int row) {
    final current = _cells[row * _size.cols + col];
    if (current.role == CellRole.continuation && col > 0) {
      _cells[row * _size.cols + col - 1] = const Cell.empty();
    }
    if (current.role == CellRole.leading && col + 1 < _size.cols) {
      final right = _cells[row * _size.cols + col + 1];
      if (right.role == CellRole.continuation) {
        _cells[row * _size.cols + col + 1] = const Cell.empty();
      }
    }
  }

  int _indexOf(CellOffset position) => position.row * _size.cols + position.col;

  void _checkBounds(CellOffset position) {
    _checkBoundsColRow(position.col, position.row);
  }

  bool _containsColRow(int col, int row) =>
      col >= 0 && row >= 0 && col < _size.cols && row < _size.rows;

  void _recordDamageRect(int col, int row, int cols, int rows) {
    if (!_damageTrackingEnabled ||
        _damageSuppressionDepth > 0 ||
        cols <= 0 ||
        rows <= 0) {
      return;
    }
    final left = col < 0 ? 0 : col;
    final top = row < 0 ? 0 : row;
    final right = col + cols > _size.cols ? _size.cols : col + cols;
    final bottom = row + rows > _size.rows ? _size.rows : row + rows;
    if (left >= right || top >= bottom) return;
    final rect = CellRect.fromLTWH(left, top, right - left, bottom - top);
    final current = _damageBounds;
    _damageBounds = current == null ? rect : current.union(rect);
    for (var damagedRow = top; damagedRow < bottom; damagedRow++) {
      _damageRows.add(damagedRow);
    }
  }

  void _checkBoundsColRow(int col, int row) {
    if (!_containsColRow(col, row)) {
      throw RangeError(
        'Cell ($col, $row) is out of bounds for buffer of size $_size.',
      );
    }
  }

  /// Extracts the painted text within [rect] as a single string, joining
  /// rows with `\n`. The result is what the user actually *sees* in that
  /// rectangle — never the source string a `Text` widget was constructed
  /// from, but the post-wrap, post-clip, post-style glyphs as they
  /// landed in the cells.
  ///
  /// This is the Notcurses-style "give me the painted UTF-8 in this cell
  /// region" primitive (`ncplane_contents`). Typical uses:
  ///
  ///   - Region snapshot for tests (assert on rendered output).
  ///   - Copy-as-rendered for screen dumps / bug reports.
  ///   - A custom fallback path for app code that wants to grab text
  ///     from a region containing non-`Selectable` widgets — wire it
  ///     up by tracking the drag rectangle and calling this against
  ///     the live cell buffer. (The default `SelectionArea` does NOT
  ///     do this automatically — Selectables are the supported path.
  ///     This primitive is the building block for apps that want
  ///     more.)
  ///
  /// Cells outside the buffer are silently clipped. Empty cells render
  /// as a single space. Continuation cells (the trailing half of a
  /// wide grapheme) contribute nothing — the leading cell carries the
  /// grapheme. Trailing whitespace on each row is preserved.
  String textInRange(CellRect rect) {
    final left = rect.offset.col < 0 ? 0 : rect.offset.col;
    final top = rect.offset.row < 0 ? 0 : rect.offset.row;
    final right = rect.offset.col + rect.size.cols > _size.cols
        ? _size.cols
        : rect.offset.col + rect.size.cols;
    final bottom = rect.offset.row + rect.size.rows > _size.rows
        ? _size.rows
        : rect.offset.row + rect.size.rows;
    if (left >= right || top >= bottom) return '';
    final buf = StringBuffer();
    for (var row = top; row < bottom; row++) {
      if (row > top) buf.write('\n');
      for (var col = left; col < right; col++) {
        final cell = _cells[row * _size.cols + col];
        switch (cell.role) {
          case CellRole.empty:
            buf.write(' ');
          case CellRole.leading:
            buf.write(cell.grapheme ?? ' ');
          case CellRole.continuation:
            // Wide-grapheme trailer — already emitted by its leading cell.
            break;
          case CellRole.overlay:
            // Inline-image region — not human-readable text; emit a
            // space placeholder.
            buf.write(' ');
        }
      }
    }
    return buf.toString();
  }
}
