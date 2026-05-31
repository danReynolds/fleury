import 'package:meta/meta.dart';

import '../foundation/fleury_error.dart';
import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';

/// Parent-attached layout metadata.
///
/// Multi-child render objects (Flex, Stack) keep per-child layout state
/// (offset, flex factor, alignment) here so children don't need to know
/// about their parent's layout discipline. Mirrors Flutter's
/// `ParentData` abstraction at a much smaller scope.
abstract class ParentData {
  /// Subclasses can override this to release any resources tied to the
  /// child's previous parent. Today this is a no-op; the hook exists so
  /// future multi-child layouts can implement it.
  @mustCallSuper
  void detach() {}
}

/// Base for everything that participates in layout and paint.
///
/// The contract is the Flutter constraints-down / sizes-up protocol,
/// translated to integer cell coordinates:
///
///   1. Parent calls `layout(constraints)`.
///   2. Subclass `performLayout(constraints)` returns the chosen [CellSize]
///      and lays out any children (calling `layout` on them in turn).
///   3. Paint placement is the parent's responsibility — there is no
///      `setOffset` on the child. Each parent remembers where it decided
///      to put each child (e.g. `RenderFlex` keeps a child→offset map,
///      `RenderAlign` a single child offset) and applies that during its
///      own `paint` by calling `child.paint(buffer, offset + childOffset)`.
///      So offsets live in the parent, not as state on the child. (A
///      [ParentData] slot exists for parents that prefer to stash
///      layout bookkeeping on the child, but most parents use their own
///      fields.)
///   4. Parent calls `paint(buffer, offset)` during the paint pass. The
///      `offset` passed in is the absolute position in the buffer.
///
/// Subclasses must call `super.layout` (or invoke the protocol on each
/// child themselves); the framework relies on `_size` being current after
/// every layout pass.
abstract class RenderObject {
  RenderObject? _parent;
  ParentData? parentData;

  CellConstraints? _constraints;
  CellSize? _size;

  // Cache-invalidation flag, meaningful only at [isRepaintBoundary] render
  // objects. Non-boundary nodes always re-paint, so the flag is just the
  // walk-up target; the boundary clears it after painting its cache.
  bool _needsPaint = true;

  /// Whether the enclosing boundary's cache has been invalidated. Set true
  /// by [markNeedsPaint]; subclasses that implement a paint cache clear it
  /// once they have re-painted into their cache.
  @protected
  bool get needsPaint => _needsPaint;

  @protected
  set needsPaint(bool value) => _needsPaint = value;

  /// Whether this render object owns its own paint cache (a `CellBuffer`
  /// it can blit instead of re-walking its subtree's paint). Override to
  /// true in subclasses that implement the cache discipline.
  bool get isRepaintBoundary => false;

  /// Marks the nearest enclosing repaint boundary as needing to re-paint
  /// into its cache. Cheap when nothing in the path is a boundary — walks
  /// up `_parent` until it finds one (or reaches the root). Idempotent at
  /// the boundary.
  ///
  /// Called automatically when a render object's child list changes (via
  /// [adoptChild] / [dropChild]) and when a `RenderObjectElement` reconciles
  /// its widget. Subclasses with mutable configuration should also call it
  /// from setters whose value actually changed.
  void markNeedsPaint() {
    if (isRepaintBoundary) {
      _needsPaint = true;
      return;
    }
    _parent?.markNeedsPaint();
  }

  /// The constraints from the most recent layout pass.
  CellConstraints get constraints {
    final c = _constraints;
    if (c == null) {
      throw FleuryError(
        summary: '$runtimeType has no constraints — layout has not run yet.',
        details:
            'Constraints are recorded inside `layout()`, which the '
            'framework calls during the layout phase. Reading them before '
            'then means the render object was queried out-of-order.',
        hint:
            'If you are reading constraints inside `performLayout`, use '
            'the `constraints` argument directly. If you are reading them '
            'from `paint`, the render object has already laid out so this '
            'should not happen — it indicates the parent skipped the '
            'layout call.',
      );
    }
    return c;
  }

  /// The size computed by the most recent layout pass.
  CellSize get size {
    final s = _size;
    if (s == null) {
      throw FleuryError(
        summary: '$runtimeType has no size — layout has not run yet.',
        details:
            'Sizes are recorded inside `layout()`, which the framework '
            'calls during the layout phase. Reading the size before then '
            'means the render object was queried out-of-order.',
        hint:
            'If you are reading `size` from a paint or hit-test method, '
            'the framework has skipped the layout pass for this node — '
            'check that the parent forwarded `child.layout(constraints)`.',
      );
    }
    return s;
  }

  RenderObject? get parent => _parent;

  /// Attaches [child] to this render object as its parent. Subclasses
  /// that hold children call this whenever they accept one; it also
  /// gives the parent a chance to ensure [child.parentData] is the right
  /// type via [setupParentData].
  @protected
  void adoptChild(RenderObject child) {
    assert(child._parent == null, 'Render object adopted twice.');
    child._parent = this;
    setupParentData(child);
    markNeedsPaint();
  }

  /// Detaches [child] from this render object.
  @protected
  void dropChild(RenderObject child) {
    assert(child._parent == this, 'dropChild called on the wrong parent.');
    child.parentData?.detach();
    child.parentData = null;
    child._parent = null;
    markNeedsPaint();
  }

  /// Override to install a subclass of [ParentData] on the child. The
  /// default is a no-op; multi-child render objects override this so a
  /// child's `parentData` is always the type that parent expects.
  @protected
  void setupParentData(RenderObject child) {}

  /// Lays out this render object against [constraints] and returns the
  /// chosen size. Subclasses implement [performLayout] rather than
  /// overriding this; the framework needs the bookkeeping around it.
  CellSize layout(CellConstraints constraints) {
    _constraints = constraints;
    final result = performLayout(constraints);
    if (!constraints.isSatisfiedBy(result)) {
      throw FleuryError(
        summary:
            '$runtimeType.performLayout returned $result, which does '
            'not satisfy $constraints.',
        details:
            'The widget tried to size itself outside the bounds its '
            'parent allowed. This usually means a child Widget asked for '
            'more space than its parent will give it (a SizedBox bigger '
            'than the available cells, a Container in unbounded constraints '
            'with no width/height), or a custom `performLayout` returned a '
            "size that doesn't respect its own constraints argument.",
        hint:
            'Wrap the child in a Flexible or Expanded, give it explicit '
            'width/height that fit inside the parent, or check that '
            "performLayout uses `constraints.constrain(...)` on its result.",
      );
    }
    _size = result;
    return result;
  }

  /// Override to compute the chosen size and lay out children. Must
  /// return a size that satisfies [constraints].
  @protected
  CellSize performLayout(CellConstraints constraints);

  /// Paints this render object into [buffer] at the absolute [offset].
  ///
  /// Subclasses that hold children compute each child's absolute offset
  /// (their own [offset] plus the child's per-parent layout position)
  /// and recursively call [paint] on them.
  ///
  /// **Screen-space context.** [screenOffset] is the cumulative screen
  /// position that [offset] in this [buffer] corresponds to. For nearly
  /// every paint, [buffer] IS the screen and `screenOffset == offset`.
  /// Render objects that paint into a scratch buffer (notably
  /// [ScrollView]) pass the visible-on-screen position so descendants
  /// can capture screen-space bounds for hit-testing.
  ///
  /// **Clipping.** [clipRect] is the visible screen rectangle for this
  /// subtree. Anything painted (or hit-tested) outside it is clipped
  /// out. Null means "no clip" — the full screen is visible. Render
  /// objects that introduce clipping (scrollables, future overlays)
  /// intersect their own clip with the inherited [clipRect] and pass
  /// the intersection down.
  ///
  /// Defaults preserve the legacy contract: when omitted, screenOffset
  /// equals offset and there is no clip — so paints not involved with
  /// selection or hit-testing don't need to thread anything through.
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  });

  // ---- Intrinsic sizing -------------------------------------------------
  //
  // Subclasses override these to report the size they'd naturally take
  // given a cross-axis constraint. Used by widgets like [IntrinsicWidth]
  // and intrinsic-sized [Table] columns to size a child "tight to content"
  // instead of expanding it to the available space.
  //
  // Pass `null` for `height` / `width` to mean "no cross-axis constraint."
  // Defaults return 0 — a render object that doesn't care declares no
  // intrinsic preference.

  /// The widest this render object would want to be at the given [height].
  /// Most relevant override: text returns its unwrapped width.
  int computeMaxIntrinsicWidth(int? height) => 0;

  /// The narrowest width below which content would clip. Defaults to 0;
  /// text-like leaves can return a longest-token width if they word-wrap.
  int computeMinIntrinsicWidth(int? height) => 0;

  /// The tallest this render object would want to be at the given [width].
  int computeMaxIntrinsicHeight(int? width) => 0;

  /// The shortest this render object can be at the given [width].
  int computeMinIntrinsicHeight(int? width) => 0;
}

/// Marker interface for render objects that hold exactly one child. The
/// element layer uses this to attach/detach the child render object when
/// the widget tree changes.
abstract class RenderObjectWithSingleChild implements RenderObject {
  /// The single child render object, if any.
  RenderObject? get child;

  /// Replaces (or clears, with null) the single child render object.
  set child(RenderObject? value);
}

/// Marker interface for render objects that hold an ordered list of
/// children. The multi-child element layer manages the list explicitly
/// during reconciliation via [replaceAllChildren] rather than the
/// single-child attach/detach hooks.
abstract class RenderObjectWithChildren implements RenderObject {
  /// The current ordered list of children. Mutating the returned list
  /// is not supported; use [replaceAllChildren] instead.
  List<RenderObject> get children;

  /// Replaces the entire children list with [newChildren] in the given
  /// order. Implementations must adopt children that are new and drop
  /// children that are no longer present.
  void replaceAllChildren(List<RenderObject> newChildren);
}
