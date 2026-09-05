// Derived screen geometry: the position and visibility of a render object,
// computed from layout state by walking its ancestors, instead of recorded
// during paint. Every container declares where it put each child
// (`RenderObject.childOffsetOf`), what it clips (`childClip`), and whether it
// presents the child at all (`presentsChild`); this file composes them.

import '../foundation/geometry.dart';
import 'render_object.dart';

/// Where a render object sits on screen and how much of it is visible.
final class RenderGeometry {
  const RenderGeometry({required this.bounds, required this.visible});

  /// The full rectangle in screen cells, ignoring clips.
  final CellRect bounds;

  /// The part of [bounds] inside every ancestor clip, or null when nothing
  /// of it is visible.
  final CellRect? visible;
}

/// The screen geometry of [node], derived from layout state.
///
/// Returns null when some ancestor does not present [node] this frame. The
/// root render object is at the screen origin; a node that has not been laid
/// out throws, like `RenderObject.size`.
RenderGeometry? screenGeometryOf(RenderObject node) {
  var bounds = CellRect(offset: CellOffset.zero, size: node.size);
  CellRect? visible = bounds;
  var child = node;
  var parent = node.parent;
  while (parent != null) {
    if (!parent.presentsChild(child)) return null;
    final offset = parent.childOffsetOf(child);
    bounds = CellRect(offset: bounds.offset + offset, size: bounds.size);
    if (visible != null) {
      visible = CellRect(offset: visible.offset + offset, size: visible.size);
      final clip = parent.childClip;
      if (clip != null) visible = visible.intersect(clip);
    }
    child = parent;
    parent = parent.parent;
  }
  return RenderGeometry(bounds: bounds, visible: visible);
}

/// Every render object in the subtree of [root], in paint order.
Iterable<RenderObject> renderSubtree(RenderObject root) sync* {
  yield root;
  final children = <RenderObject>[];
  root.visitRenderChildren(children.add);
  for (final child in children) {
    yield* renderSubtree(child);
  }
}
