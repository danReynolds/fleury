import '../foundation/geometry.dart';
import '../input/events.dart';
import 'layout.dart';
import 'render_flex.dart';

/// Geometry shared by one-dimensional scrollable render objects.
/// Kept internal to the implementation; public widgets use [Axis].
extension ScrollAxisGeometry on Axis {
  int extent(CellSize size) => this == Axis.vertical ? size.rows : size.cols;
  int crossExtent(CellSize size) =>
      this == Axis.vertical ? size.cols : size.rows;
  int position(CellOffset offset) =>
      this == Axis.vertical ? offset.row : offset.col;
  int? maxExtent(CellConstraints constraints) =>
      this == Axis.vertical ? constraints.maxRows : constraints.maxCols;
  int? maxCrossExtent(CellConstraints constraints) =>
      this == Axis.vertical ? constraints.maxCols : constraints.maxRows;
  CellOffset offset(int main) =>
      this == Axis.vertical ? CellOffset(0, main) : CellOffset(main, 0);
  CellSize size(int main, int cross) =>
      this == Axis.vertical ? CellSize(cross, main) : CellSize(main, cross);

  /// Unbounds the scrolling axis, preserving the cross-axis limit.
  CellConstraints childConstraints(
    CellConstraints constraints, {
    bool keepCrossMinimum = false,
  }) => this == Axis.vertical
      ? CellConstraints(
          minCols: keepCrossMinimum ? constraints.minCols : 0,
          maxCols: constraints.maxCols,
        )
      : CellConstraints(
          minRows: keepCrossMinimum ? constraints.minRows : 0,
          maxRows: constraints.maxRows,
        );

  /// Reuses the navigation model for either axis. Cross-axis arrows remain
  /// unhandled so spatial focus traversal can move to a neighboring control.
  KeyCode? navigationKey(KeyCode code) {
    if (this == Axis.horizontal) {
      if (code == KeyCode.arrowLeft) return KeyCode.arrowUp;
      if (code == KeyCode.arrowRight) return KeyCode.arrowDown;
      if (code == KeyCode.arrowUp || code == KeyCode.arrowDown) return null;
    } else if (code == KeyCode.arrowLeft || code == KeyCode.arrowRight) {
      return null;
    }
    return code;
  }
}
