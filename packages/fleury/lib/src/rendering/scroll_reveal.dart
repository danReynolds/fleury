// Bringing a laid-out render object into view through the scrolling
// viewports above it. The rendering layer owns it so focus traversal can
// reveal what it moves to, and a scroll view is one kind of viewport.

import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import 'render_flex.dart' show Axis;
import 'render_object.dart';
import 'scroll_axis.dart';

/// A render object that scrolls its child along one axis: a scroll view's
/// viewport, as [revealInScrollViews] moves it.
@internal
abstract interface class RenderScrollViewport implements RenderObject {
  /// The axis the child scrolls along.
  Axis get scrollAxis;

  /// The movement permitted by the current scroll limits, without scrolling.
  int clampScrollDelta(int delta);

  /// Scrolls the child by [delta] cells, toward its end when positive.
  void scrollContentBy(int delta);
}

/// Reveals a laid-out target through enclosing scroll viewports.
///
/// Call after layout. When [surrounding] fits,
/// include it as well (for example, a control's label and validation message).
/// Otherwise prioritize the target, aligning an oversized target's start.
/// Does not change focus or reveal children hidden by presentation policy.
void revealInScrollViews(RenderObject target, {RenderObject? surrounding}) {
  final plan = _revealPlan(target, surrounding: surrounding);
  if (plan == null) return;
  for (final entry in plan.entries) {
    entry.key.scrollContentBy(entry.value);
  }
}

/// Whether the same bounded reveal plan used by [revealInScrollViews] leaves
/// any of [target] visible. Scrollable ancestor clips move with the plan;
/// fixed clips and the screen remain limits. Does not change scroll or focus.
@internal
bool canRevealInScrollViews(RenderObject target) {
  final plan = _revealPlan(target);
  if (plan == null) return false;
  var visible = CellRect(offset: CellOffset.zero, size: target.size);
  var child = target;
  while (true) {
    final parent = child.parent;
    if (parent == null) break;
    visible = _translateThroughParent(visible, child, parent, plan);
    final clip = parent.childClipOf(child);
    if (clip != null) {
      final clipped = visible.intersect(clip);
      if (clipped == null) return false;
      visible = clipped;
    }
    child = parent;
  }
  final root = child.screenGeometry();
  final screen = root?.visible;
  if (root == null || screen == null) return false;
  return CellRect(
        offset: visible.offset + root.bounds.offset,
        size: visible.size,
      ).intersect(screen) !=
      null;
}

Map<RenderScrollViewport, int>? _revealPlan(
  RenderObject target, {
  RenderObject? surrounding,
}) {
  if (!target.hasLayout || target.size.isEmpty) return null;
  final viewports = <RenderScrollViewport>[];
  var child = target;
  // Check the entire presentation chain before moving any viewport. Clipping
  // is expected here; an inactive route or IndexedStack child is different.
  while (true) {
    final parent = child.parent;
    if (parent == null) break;
    if (!parent.hasLayout || !parent.presentsChild(child)) return null;
    if (parent is RenderScrollViewport) viewports.add(parent);
    child = parent;
  }
  final deltas = <RenderScrollViewport, int>{};
  for (final viewport in viewports) {
    final axis = viewport.scrollAxis;
    final extent = axis.extent(viewport.size);
    if (extent == 0) continue;
    var bounds = _boundsInScrollAncestor(target, viewport, deltas);
    if (bounds == null) continue;
    if (surrounding != null) {
      final extra = _boundsInScrollAncestor(surrounding, viewport, deltas);
      if (extra != null) {
        final combined = bounds.union(extra);
        if (axis.extent(combined.size) <= extent) bounds = combined;
      }
    }
    final delta = scrollDeltaToReveal(viewport, bounds);
    if (delta != 0) deltas[viewport] = delta;
  }
  return deltas;
}

/// The bounded movement [revealInScrollViews] will make for [bounds] in a
/// viewport's coordinates. Focus eligibility uses the same calculation before
/// moving, so positioned overflow cannot promise a reveal beyond scroll limits.
@internal
int scrollDeltaToReveal(RenderScrollViewport viewport, CellRect bounds) {
  final axis = viewport.scrollAxis;
  final extent = axis.extent(viewport.size);
  if (extent == 0) return 0;
  final start = axis.position(bounds.offset);
  final length = axis.extent(bounds.size);
  final end = start + length;
  final delta = length > extent || start < 0
      ? start
      : end > extent
      ? end - extent
      : 0;
  return viewport.clampScrollDelta(delta);
}

CellRect? _boundsInScrollAncestor(
  RenderObject target,
  RenderObject ancestor,
  Map<RenderScrollViewport, int> deltas,
) {
  if (!target.hasLayout || target.size.isEmpty) return null;
  var bounds = CellRect(offset: CellOffset.zero, size: target.size);
  var child = target;
  while (!identical(child, ancestor)) {
    final parent = child.parent;
    if (parent == null || !parent.presentsChild(child)) return null;
    bounds = _translateThroughParent(bounds, child, parent, deltas);
    // Project inner moves before computing an outer move. Intervening fixed
    // clips still constrain the target, just as they do during real painting.
    if (!identical(parent, ancestor)) {
      final clip = parent.childClipOf(child);
      if (clip != null) {
        final visible = bounds.intersect(clip);
        if (visible == null) return null;
        bounds = visible;
      }
    }
    child = parent;
  }
  return bounds;
}

CellRect _translateThroughParent(
  CellRect bounds,
  RenderObject child,
  RenderObject parent,
  Map<RenderScrollViewport, int> deltas,
) {
  var offset = parent.childOffsetOf(child);
  if (parent is RenderScrollViewport) {
    offset = offset - parent.scrollAxis.offset(deltas[parent] ?? 0);
  }
  return CellRect(offset: bounds.offset + offset, size: bounds.size);
}
