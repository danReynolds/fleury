import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import 'framework.dart';

/// Sizes [child] to its own intrinsic width — the widest it wants to be,
/// not the widest the parent would allow. The classic use: a button or
/// label sized exactly to its text rather than stretched to fill a Row.
///
/// Mirrors Flutter's `IntrinsicWidth`. Costs an extra intrinsic-width query
/// on the child each layout, so use it where "tight to content" matters
/// (forms, toolbars, single-line buttons), not on every leaf.
class IntrinsicWidth extends SingleChildRenderObjectWidget {
  const IntrinsicWidth({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicWidth();
}

class _RenderIntrinsicWidth extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderObject? _child;

  @override
  RenderObject? get child => _child;

  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    final natural = c.computeMaxIntrinsicWidth(constraints.maxRows);
    final tight = constraints.constrainWidth(natural);
    return c.layout(
      CellConstraints(
        minCols: tight,
        maxCols: tight,
        minRows: constraints.minRows,
        maxRows: constraints.maxRows,
      ),
    );
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
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }

  // Defer to child for intrinsics: we just tighten *layout* to the child's
  // natural width; we don't change what it would prefer to be.
  @override
  int computeMaxIntrinsicWidth(int? height) =>
      _child?.computeMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicWidth(int? height) =>
      _child?.computeMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int? width) =>
      _child?.computeMaxIntrinsicHeight(width) ?? 0;

  @override
  int computeMinIntrinsicHeight(int? width) =>
      _child?.computeMinIntrinsicHeight(width) ?? 0;
}

/// Sizes [child] to its own intrinsic height — the tallest it wants to be,
/// not the tallest the parent allows. Mirror of [IntrinsicWidth].
class IntrinsicHeight extends SingleChildRenderObjectWidget {
  const IntrinsicHeight({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicHeight();
}

class _RenderIntrinsicHeight extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderObject? _child;

  @override
  RenderObject? get child => _child;

  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    final natural = c.computeMaxIntrinsicHeight(constraints.maxCols);
    final tight = constraints.constrainHeight(natural);
    return c.layout(
      CellConstraints(
        minCols: constraints.minCols,
        maxCols: constraints.maxCols,
        minRows: tight,
        maxRows: tight,
      ),
    );
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
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }

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
      _child?.computeMaxIntrinsicHeight(width) ?? 0;
}
