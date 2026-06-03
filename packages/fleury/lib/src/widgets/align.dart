// Align + Center: lay out a single child within a region using a
// 2D alignment hint. Mirrors Flutter's Align/Center, scoped to
// integer cell coordinates.

import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import 'framework.dart';

/// A 2D alignment hint for [Align].
///
/// Nine well-known positions cover the typical placement needs of a
/// TUI: corners, edges, center. The full Flutter `Alignment(x, y)`
/// continuum isn't necessary for cell-based layout; if a richer
/// alignment is ever needed, this enum can grow alongside.
enum Alignment {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Positions a single [child] within the available space according
/// to [alignment].
///
/// `Align` takes the largest size its constraints allow, then lays
/// the child out with loosened constraints (so the child can be
/// smaller than the parent), then paints the child at the computed
/// alignment offset. Cells around the child are left empty so any
/// content beneath in a [Stack] shows through.
///
/// With unbounded constraints `Align` collapses to the child's size
/// — there's nothing to align inside an unbounded region.
@immutable
final class Align extends SingleChildRenderObjectWidget {
  const Align({
    super.key,
    this.alignment = Alignment.center,
    required Widget super.child,
  });

  final Alignment alignment;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderAlign(alignment: alignment);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderAlign renderObject,
  ) {
    renderObject.alignment = alignment;
  }
}

/// Convenience for `Align(alignment: Alignment.center, child: …)`.
@immutable
final class Center extends SingleChildRenderObjectWidget {
  const Center({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderAlign(alignment: Alignment.center);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderAlign renderObject,
  ) {
    renderObject.alignment = Alignment.center;
  }
}

/// Render object for [Align] and [Center]. Lays out its child with
/// loosened constraints, then places the child at the alignment-
/// determined offset within the parent's box.
class RenderAlign extends RenderObject implements RenderObjectWithSingleChild {
  RenderAlign({required Alignment alignment, RenderObject? child})
    : _alignment = alignment {
    if (child != null) {
      this.child = child;
    }
  }

  Alignment _alignment;
  Alignment get alignment => _alignment;
  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  CellOffset _childOffset = CellOffset.zero;

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    final maxCols = constraints.maxCols;
    final maxRows = constraints.maxRows;
    if (c == null) {
      return constraints.constrain(CellSize(maxCols ?? 0, maxRows ?? 0));
    }
    if (maxCols == null || maxRows == null) {
      // No bounded region to align within — collapse to child size.
      final childSize = c.layout(constraints);
      _childOffset = CellOffset.zero;
      return constraints.constrain(childSize);
    }
    // Lay out child with loosened constraints so it can be smaller
    // than the parent. The result is the size we'll align within
    // (maxCols x maxRows).
    final childSize = c.layout(constraints.loosen());
    _childOffset = _offsetFor(_alignment, maxCols, maxRows, childSize);
    return constraints.constrain(CellSize(maxCols, maxRows));
  }

  // Align reports its child's intrinsic size as its own — alignment only
  // chooses *where* inside the available area to place the child; it doesn't
  // ask for more or less than the child wants.
  @override
  int computeMaxIntrinsicWidth(int? height) =>
      _child?.computeMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicWidth(int? height) =>
      _child?.computeMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int? width) =>
      _child?.computeMaxIntrinsicHeight(width) ?? 0;

  @override
  int computeMinIntrinsicHeight(int? width) =>
      _child?.computeMinIntrinsicHeight(width) ?? 0;

  static CellOffset _offsetFor(
    Alignment alignment,
    int width,
    int height,
    CellSize childSize,
  ) {
    final slackX = width - childSize.cols;
    final slackY = height - childSize.rows;
    int x;
    int y;
    switch (alignment) {
      case Alignment.topLeft:
        x = 0;
        y = 0;
      case Alignment.topCenter:
        x = slackX ~/ 2;
        y = 0;
      case Alignment.topRight:
        x = slackX;
        y = 0;
      case Alignment.centerLeft:
        x = 0;
        y = slackY ~/ 2;
      case Alignment.center:
        x = slackX ~/ 2;
        y = slackY ~/ 2;
      case Alignment.centerRight:
        x = slackX;
        y = slackY ~/ 2;
      case Alignment.bottomLeft:
        x = 0;
        y = slackY;
      case Alignment.bottomCenter:
        x = slackX ~/ 2;
        y = slackY;
      case Alignment.bottomRight:
        x = slackX;
        y = slackY;
    }
    // Clamp at zero so a child larger than the parent paints at the
    // top-left rather than at a negative offset (which would clip
    // unpredictably).
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    return CellOffset(x, y);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _child?.paint(
      buffer,
      offset + _childOffset,
      screenOffset: (screenOffset ?? offset) + _childOffset,
      clipRect: clipRect,
    );
  }
}
