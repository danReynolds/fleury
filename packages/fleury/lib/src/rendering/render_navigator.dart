// RenderNavigatorStack: the layout primitive behind a Navigator's route
// stack. Unlike a plain RenderStack (which sizes to its largest child),
// this fills its layout slot so a navigator occupies the region it was
// given — routes stack within that region and transitions have room to
// play. It also owns occlusion: only routes at or above the topmost
// settled (opaque) route are painted, so lower routes stay mounted (their
// State survives back-navigation) without bleeding through the screen on
// top.
//
// Why a dedicated render object rather than reusing RenderStack:
//   - Fill, not shrink-wrap. A navigator is a screen region, not a
//     content-sized box; it claims its slot so a parent Flex/SizedBox
//     allocates space to it and an off-screen entering route has room to
//     slide in from.
//   - Loose child layout. Routes are laid out loosely (up to the slot)
//     so ordinary content sizes to itself; a route that wants to fill
//     uses max-size widgets, mirroring the framework's loose-at-root
//     constraint philosophy. Forcing tight constraints would break
//     content widgets (e.g. Text) that report their intrinsic size.
//   - Occlusion by paint-gating from [firstPainted], computed by the
//     NavigatorState from route opacity. Lower routes are skipped at
//     paint time only — they remain laid out and mounted.

import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_object.dart';

/// Lays out a navigator's routes filling the available slot and paints
/// the visible suffix of the route stack.
class RenderNavigatorStack extends RenderObject
    implements RenderObjectWithChildren {
  RenderNavigatorStack({int firstPainted = 0}) : _firstPainted = firstPainted;

  /// Index of the first child to paint, root-first. Children below this
  /// index are occluded by a settled opaque route above and skipped at
  /// paint time. Set by the NavigatorState each time route opacity
  /// changes. Paint-only — the framework repaints every frame, so no
  /// explicit invalidation is needed.
  int _firstPainted;
  int get firstPainted => _firstPainted;
  set firstPainted(int value) {
    if (_firstPainted == value) return;
    _firstPainted = value;
    markNeedsPaintOnly();
  }

  final List<RenderObject> _children = <RenderObject>[];

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    if (hasSameRenderChildrenInOrder(_children, newChildren)) return;
    final newSet = Set<RenderObject>.identity()..addAll(newChildren);
    for (final c in List<RenderObject>.from(_children)) {
      if (!newSet.contains(c)) dropChild(c);
    }
    final oldSet = Set<RenderObject>.identity()..addAll(_children);
    for (final c in newChildren) {
      if (!oldSet.contains(c)) adoptChild(c);
    }
    _children
      ..clear()
      ..addAll(newChildren);
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    // Each route lays out loosely up to the slot, so content sizes to
    // itself; a route fills only if it asks to (max-size widgets).
    final childConstraints = constraints.loosen();
    var maxCols = 0;
    var maxRows = 0;
    for (final c in _children) {
      final size = c.layout(childConstraints);
      if (size.cols > maxCols) maxCols = size.cols;
      if (size.rows > maxRows) maxRows = size.rows;
    }

    // Fill the slot on bounded axes (a navigator claims its region);
    // fall back to the largest route on unbounded axes.
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : maxCols;
    final rows = constraints.hasBoundedHeight ? constraints.maxRows! : maxRows;
    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final start = _firstPainted < 0
        ? 0
        : (_firstPainted > _children.length ? _children.length : _firstPainted);
    for (var i = start; i < _children.length; i++) {
      _children[i].paint(
        buffer,
        offset,
        screenOffset: screenOffset ?? offset,
        clipRect: clipRect,
      );
    }
  }
}
