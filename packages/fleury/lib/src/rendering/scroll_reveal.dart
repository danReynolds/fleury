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

  /// Scrolls the child by [delta] cells, toward its end when positive.
  void scrollContentBy(int delta);
}

/// Reveals a laid-out target through enclosing scroll viewports.
///
/// Internal cross-package hook. Call after layout. When [surrounding] fits,
/// include it as well (for example, a control's label and validation message).
/// Otherwise prioritize the target, aligning an oversized target's start.
/// Does not change focus or reveal children hidden by presentation policy.
void revealInScrollViews(RenderObject target, {RenderObject? surrounding}) {
  if (!target.hasLayout || target.size.isEmpty) return;
  final viewports = <RenderScrollViewport>[];
  var child = target;
  // Check the entire presentation chain before moving any viewport. Clipping
  // is expected here; an inactive route or IndexedStack child is different.
  while (true) {
    final parent = child.parent;
    if (parent == null) break;
    if (!parent.hasLayout || !parent.presentsChild(child)) return;
    if (parent is RenderScrollViewport) viewports.add(parent);
    child = parent;
  }
  for (final viewport in viewports) {
    final axis = viewport.scrollAxis;
    final extent = axis.extent(viewport.size);
    if (extent == 0) continue;
    var bounds = _boundsInScrollAncestor(target, viewport);
    if (bounds == null) continue;
    if (surrounding != null) {
      final extra = _boundsInScrollAncestor(surrounding, viewport);
      if (extra != null) {
        final combined = bounds.union(extra);
        if (axis.extent(combined.size) <= extent) bounds = combined;
      }
    }
    final start = axis.position(bounds.offset);
    final length = axis.extent(bounds.size);
    final end = start + length;
    final delta = length > extent || start < 0
        ? start
        : end > extent
        ? end - extent
        : 0;
    if (delta != 0) viewport.scrollContentBy(delta);
  }
}

CellRect? _boundsInScrollAncestor(RenderObject target, RenderObject ancestor) {
  if (!target.hasLayout || target.size.isEmpty) return null;
  var bounds = CellRect(offset: CellOffset.zero, size: target.size);
  var child = target;
  while (!identical(child, ancestor)) {
    final parent = child.parent;
    if (parent == null || !parent.presentsChild(child)) return null;
    bounds = CellRect(
      offset: bounds.offset + parent.childOffsetOf(child),
      size: bounds.size,
    );
    // Inner viewports have already moved. Outer viewports should reveal the
    // visible part of the target, respecting intervening clips. Read offsets
    // directly: the newly changed controllers have not had another frame yet.
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
