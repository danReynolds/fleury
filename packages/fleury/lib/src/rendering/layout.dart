import 'package:meta/meta.dart';

import '../foundation/geometry.dart';

/// Integer cell constraints passed parent-to-child during layout.
///
/// Unbounded axes are represented as a null `maxCols`/`maxRows` rather than
/// `double.maxFinite`. This avoids floating-point math in the cell grid and
/// makes "no upper bound" explicit at the type level.
@immutable
final class CellConstraints {
  const CellConstraints({
    this.minCols = 0,
    this.maxCols,
    this.minRows = 0,
    this.maxRows,
  }) : assert(minCols >= 0, 'minCols must be non-negative'),
       assert(minRows >= 0, 'minRows must be non-negative'),
       assert(
         maxCols == null || maxCols >= minCols,
         'maxCols must be >= minCols when bounded',
       ),
       assert(
         maxRows == null || maxRows >= minRows,
         'maxRows must be >= minRows when bounded',
       );

  /// Constraints that require the exact [size].
  CellConstraints.tight(CellSize size)
    : minCols = size.cols,
      maxCols = size.cols,
      minRows = size.rows,
      maxRows = size.rows;

  /// Constraints that allow anything from zero up to [size].
  CellConstraints.loose(CellSize size)
    : minCols = 0,
      maxCols = size.cols,
      minRows = 0,
      maxRows = size.rows;

  final int minCols;
  final int? maxCols;
  final int minRows;
  final int? maxRows;

  bool get hasBoundedWidth => maxCols != null;
  bool get hasBoundedHeight => maxRows != null;

  bool get isTight =>
      hasBoundedWidth &&
      minCols == maxCols &&
      hasBoundedHeight &&
      minRows == maxRows;

  int constrainWidth(int cols) {
    var result = cols < minCols ? minCols : cols;
    final max = maxCols;
    if (max != null && result > max) result = max;
    return result;
  }

  int constrainHeight(int rows) {
    var result = rows < minRows ? minRows : rows;
    final max = maxRows;
    if (max != null && result > max) result = max;
    return result;
  }

  CellSize constrain(CellSize size) =>
      CellSize(constrainWidth(size.cols), constrainHeight(size.rows));

  /// Returns constraints with the same upper bounds but [minCols] /
  /// [minRows] dropped to zero — used when a parent wants its child to be
  /// as small as it wants to be inside an outer envelope.
  CellConstraints loosen() =>
      CellConstraints(maxCols: maxCols, maxRows: maxRows);

  bool isSatisfiedBy(CellSize size) {
    if (size.cols < minCols || size.rows < minRows) return false;
    final maxC = maxCols;
    if (maxC != null && size.cols > maxC) return false;
    final maxR = maxRows;
    if (maxR != null && size.rows > maxR) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is CellConstraints &&
      other.minCols == minCols &&
      other.maxCols == maxCols &&
      other.minRows == minRows &&
      other.maxRows == maxRows;

  @override
  int get hashCode => Object.hash(minCols, maxCols, minRows, maxRows);

  @override
  String toString() {
    final cols = '$minCols..${maxCols ?? '∞'}';
    final rows = '$minRows..${maxRows ?? '∞'}';
    return 'CellConstraints(cols $cols, rows $rows)';
  }
}
