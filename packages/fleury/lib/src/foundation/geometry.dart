import 'package:meta/meta.dart';

/// An integer width/height in terminal cells.
@immutable
final class CellSize {
  const CellSize(this.cols, this.rows)
    : assert(cols >= 0, 'cols must be non-negative'),
      assert(rows >= 0, 'rows must be non-negative');

  static const CellSize zero = CellSize(0, 0);

  final int cols;
  final int rows;

  bool get isEmpty => cols == 0 || rows == 0;

  @override
  bool operator ==(Object other) =>
      other is CellSize && other.cols == cols && other.rows == rows;

  @override
  int get hashCode => Object.hash(cols, rows);

  @override
  String toString() => 'CellSize(${cols}x$rows)';
}

/// An integer (column, row) position in the terminal grid.
///
/// Origin is top-left; column 0, row 0 is the top-left cell.
@immutable
final class CellOffset {
  const CellOffset(this.col, this.row);

  static const CellOffset zero = CellOffset(0, 0);

  final int col;
  final int row;

  CellOffset operator +(CellOffset other) =>
      CellOffset(col + other.col, row + other.row);

  CellOffset operator -(CellOffset other) =>
      CellOffset(col - other.col, row - other.row);

  @override
  bool operator ==(Object other) =>
      other is CellOffset && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => 'CellOffset($col, $row)';
}

/// A rectangle in the terminal grid expressed as an [offset] and [size].
@immutable
final class CellRect {
  const CellRect({required this.offset, required this.size});

  CellRect.fromLTWH(int left, int top, int width, int height)
    : offset = CellOffset(left, top),
      size = CellSize(width, height);

  final CellOffset offset;
  final CellSize size;

  int get left => offset.col;
  int get top => offset.row;
  int get right => offset.col + size.cols;
  int get bottom => offset.row + size.rows;

  bool contains(CellOffset point) {
    return point.col >= left &&
        point.col < right &&
        point.row >= top &&
        point.row < bottom;
  }

  /// Returns the rectangle of cells contained in both rects, or null if
  /// they don't overlap. Used by paint clipping: a child that's
  /// partially scrolled off intersects its painted rect with the
  /// viewport's clip to find the visible portion.
  CellRect? intersect(CellRect other) {
    final l = left > other.left ? left : other.left;
    final t = top > other.top ? top : other.top;
    final r = right < other.right ? right : other.right;
    final b = bottom < other.bottom ? bottom : other.bottom;
    if (l >= r || t >= b) return null;
    return CellRect.fromLTWH(l, t, r - l, b - t);
  }

  /// Returns the smallest rectangle containing both rects. Symmetric
  /// with [intersect]; useful when computing the bounding region of
  /// several painted children (e.g. auto-scroll's "what's the
  /// effective viewport for selection" union).
  CellRect union(CellRect other) {
    final l = left < other.left ? left : other.left;
    final t = top < other.top ? top : other.top;
    final r = right > other.right ? right : other.right;
    final b = bottom > other.bottom ? bottom : other.bottom;
    return CellRect.fromLTWH(l, t, r - l, b - t);
  }

  @override
  bool operator ==(Object other) =>
      other is CellRect && other.offset == offset && other.size == size;

  @override
  int get hashCode => Object.hash(offset, size);

  @override
  String toString() => 'CellRect($offset, $size)';
}
