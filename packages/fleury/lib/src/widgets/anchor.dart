// Anchored overlay positioning: an [Anchor] records its painted rect into
// a shared [AnchorLink], and a [Follower] reads that rect to place its
// child relative to it (below by default, flipping above and clamping
// when it would run off-screen). Drop a Follower into an OverlayEntry to
// float a popup over everything — the primitive behind dropdown menus,
// autocomplete, and tooltips. Mirrors Flutter's LayerLink +
// CompositedTransformTarget/Follower, at cell resolution.

import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import 'framework.dart';

/// Shared handle linking an [Anchor] to its [Follower]. The anchor writes
/// its absolute painted [rect] each paint; the follower reads it.
class AnchorLink {
  /// The anchor's painted bounds in absolute cell coordinates, or null
  /// before the anchor has painted (or after it leaves the tree).
  CellRect? rect;
}

/// Records its [child]'s painted rect into [link] — the trigger a
/// [Follower] positions against (a button, a list row, a text span).
/// Layout-transparent: reports the child's size unchanged.
class Anchor extends SingleChildRenderObjectWidget {
  const Anchor({super.key, required this.link, required Widget super.child});

  final AnchorLink link;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderAnchorBounds(link);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderAnchorBounds renderObject,
  ) {
    renderObject.link = link;
  }
}

/// Records its child's painted rect into an [AnchorLink]; see [Anchor].
class RenderAnchorBounds extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderAnchorBounds(this._link);

  AnchorLink _link;
  set link(AnchorLink value) {
    if (identical(_link, value)) return;
    _link.rect = null;
    _link = value;
    markNeedsPaintOnly();
  }

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
  CellSize performLayout(CellConstraints constraints) =>
      _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _link.rect = CellRect(offset: offset, size: size);
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}

/// Which side of the anchor a [Follower] places its child on.
enum FollowerPlacement {
  /// Below the anchor (the default), flipping above when it won't fit —
  /// dropdowns, autocomplete, tooltips.
  below,

  /// To the right of the anchor, flipping to the left when it won't fit —
  /// cascading submenus, side popovers.
  right,
}

/// Fills its slot and positions [child] relative to [link]'s anchor:
/// just below it (or beside it, per [placement]), offset by [gap] cells,
/// flipping to the opposite side and clamping so it stays on screen. Use
/// as the content of an OverlayEntry so it floats over everything at the
/// anchor.
class Follower extends SingleChildRenderObjectWidget {
  const Follower({
    super.key,
    required this.link,
    this.gap = 0,
    this.placement = FollowerPlacement.below,
    required Widget super.child,
  });

  final AnchorLink link;

  /// Cells between the anchor and the follower.
  final int gap;

  /// Which side of the anchor to place the child on.
  final FollowerPlacement placement;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFollower(link, gap, placement);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderFollower renderObject,
  ) {
    renderObject
      ..link = link
      ..gap = gap
      ..placement = placement;
  }
}

/// Fills its slot and paints its child at the anchor's rect; see [Follower].
class RenderFollower extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderFollower(this._link, this._gap, this._placement);

  AnchorLink _link;
  set link(AnchorLink value) {
    if (identical(_link, value)) return;
    _link = value;
    markNeedsLayout();
  }

  int _gap;
  set gap(int value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  FollowerPlacement _placement;
  set placement(FollowerPlacement value) {
    if (_placement == value) return;
    _placement = value;
    markNeedsLayout();
  }

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
    c.layout(constraints.loosen()); // child sizes to content
    // Fill the slot (the overlay = screen) so we can place + clamp within.
    final size = c.size;
    final w = constraints.hasBoundedWidth ? constraints.maxCols! : size.cols;
    final h = constraints.hasBoundedHeight ? constraints.maxRows! : size.rows;
    return constraints.constrain(CellSize(w, h));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final c = _child;
    if (c == null) return;
    // Resolve placement at paint time: the anchor records its rect during
    // its own paint, which runs before this follower's (anchors sit below
    // followers in the overlay/stack order), so we read the current frame.
    final placement = _placeChild(c.size);
    _child!.paint(
      buffer,
      offset + placement,
      screenOffset: (screenOffset ?? offset) + placement,
      clipRect: clipRect,
    );
  }

  CellOffset _placeChild(CellSize childSize) {
    final r = _link.rect;
    if (r == null) return CellOffset.zero;
    final w = size.cols;
    final h = size.rows;
    return switch (_placement) {
      FollowerPlacement.below => _placeBelow(r, childSize, w, h),
      FollowerPlacement.right => _placeRight(r, childSize, w, h),
    };
  }

  CellOffset _placeBelow(CellRect r, CellSize childSize, int w, int h) {
    // Vertical: below the anchor; flip above if it won't fit; clamp.
    var top = r.bottom + _gap;
    if (top + childSize.rows > h) {
      final above = r.top - _gap - childSize.rows;
      top = above >= 0 ? above : h - childSize.rows;
    }
    if (top < 0) top = 0;
    // Horizontal: aligned to the anchor's left edge; clamp on-screen.
    var left = r.left;
    if (left + childSize.cols > w) left = w - childSize.cols;
    if (left < 0) left = 0;
    return CellOffset(left, top);
  }

  CellOffset _placeRight(CellRect r, CellSize childSize, int w, int h) {
    // Horizontal: to the right of the anchor; flip left if it won't fit.
    var left = r.right + _gap;
    if (left + childSize.cols > w) {
      final leftSide = r.left - _gap - childSize.cols;
      left = leftSide >= 0 ? leftSide : w - childSize.cols;
    }
    if (left < 0) left = 0;
    // Vertical: aligned to the anchor's top edge; clamp on-screen.
    var top = r.top;
    if (top + childSize.rows > h) top = h - childSize.rows;
    if (top < 0) top = 0;
    return CellOffset(left, top);
  }
}
