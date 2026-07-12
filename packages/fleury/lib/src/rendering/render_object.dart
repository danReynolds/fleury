import 'package:meta/meta.dart';

import '../debug/debug_invalidation.dart';
import '../foundation/fleury_error.dart';
import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_layout_stats.dart';

/// Frame-level signal for whether the terminal presenter can trust
/// paint-buffer damage bounds.
///
/// Paint-only mutations can be bounded by the cells repainted into the frame
/// buffer. Layout-affecting mutations cannot: cells may disappear or move
/// without being rewritten, so the presenter must fall back to full-buffer
/// diffing for that frame.
///
/// One instance is owned per [BuildOwner]/runtime: render objects publish
/// into the tracker attached at their tree's root, so two Fleury runtimes in
/// one isolate never observe each other's damage. The signal accumulates
/// across frames until [takeRequiresFullDiff] consumes it, so deferred
/// consumers can coalesce several invalidations into one read.
final class RenderDamageTracker {
  bool _requiresFullDiff = false;
  bool _visualChange = false;

  void recordLayoutOrConservativePaint() {
    _requiresFullDiff = true;
    _visualChange = true;
  }

  /// Records that some render object's visual output may differ next frame
  /// (audited paint-only invalidations included). Cleared when a frame
  /// consumes it via [takeVisualChange].
  void recordVisualChange() {
    _visualChange = true;
  }

  /// Whether any invalidation has been recorded since the last rendered
  /// frame. While false (and the buffer pool is warm), a frame request can
  /// skip build/layout/paint entirely: the front buffer is still exact.
  bool get hasVisualChange => _visualChange;

  bool takeVisualChange() {
    final result = _visualChange;
    _visualChange = false;
    return result;
  }

  bool takeRequiresFullDiff() {
    final result = _requiresFullDiff;
    _requiresFullDiff = false;
    return result;
  }

  void reset() {
    _requiresFullDiff = false;
    _visualChange = false;
  }
}

typedef SemanticPaintBoundsCallback = void Function(CellRect? bounds);

/// A paint-captured semantic bounds callback plus its cache-local bounds.
///
/// Repaint boundaries paint children into scratch buffers, then copy cached
/// cells on later frames. Semantic bounds still need to be refreshed in
/// screen coordinates on those cached frames. Records captured while painting
/// into a boundary cache let the boundary replay the callback without
/// re-walking the visual paint path.
final class SemanticPaintBoundsRecord {
  const SemanticPaintBoundsRecord({
    required this.onPaintBounds,
    required this.localBounds,
  });

  final SemanticPaintBoundsCallback onPaintBounds;
  final CellRect localBounds;

  void publishToActiveCapture(CellOffset paintOffset) {
    SemanticPaintBoundsCapture.record(
      onPaintBounds,
      _translate(localBounds, paintOffset),
    );
  }

  void replay({
    required CellOffset paintOffset,
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    publishToActiveCapture(paintOffset);
    final screenBounds = _translate(localBounds, screenOffset);
    onPaintBounds(
      clipRect == null ? screenBounds : screenBounds.intersect(clipRect),
    );
  }

  static CellRect _translate(CellRect rect, CellOffset offset) {
    return CellRect(offset: offset + rect.offset, size: rect.size);
  }
}

/// Stack-scoped collector for semantic bounds produced during paint.
final class SemanticPaintBoundsCapture {
  SemanticPaintBoundsCapture._();

  static final List<List<SemanticPaintBoundsRecord>> _stack =
      <List<SemanticPaintBoundsRecord>>[];

  static void collect(
    List<SemanticPaintBoundsRecord> records,
    void Function() paint,
  ) {
    _stack.add(records);
    try {
      paint();
    } finally {
      _stack.removeLast();
    }
  }

  static void record(
    SemanticPaintBoundsCallback onPaintBounds,
    CellRect localBounds,
  ) {
    if (_stack.isEmpty) return;
    _stack.last.add(
      SemanticPaintBoundsRecord(
        onPaintBounds: onPaintBounds,
        localBounds: localBounds,
      ),
    );
  }
}

/// Re-registers a pointer region at [screenRect] — the replay counterpart of
/// [RenderPointerListener]'s in-paint registration.
typedef PointerRegionRegister = void Function(CellRect screenRect);

/// A pointer region registered during a paint that a [RenderRepaintBoundary]
/// cached. Pointer hit-testing in Fleury is fed by *paint-order registration*
/// (regions re-register every frame as they paint), so a cached boundary that
/// skips the subtree walk would drop every region inside it — the item, or a
/// button within it, silently stops responding on cache-hit frames. This is
/// the exact problem [SemanticPaintBoundsRecord] solves for semantics; pointer
/// regions get the same capture-and-replay treatment so the boundary stays
/// transparent to input.
final class PointerRegionRecord {
  const PointerRegionRecord({
    required this.register,
    required this.localBounds,
  });

  final PointerRegionRegister register;
  final CellRect localBounds;

  void publishToActiveCapture(CellOffset paintOffset) {
    PointerRegionCapture.record(register, _translate(localBounds, paintOffset));
  }

  void replay({
    required CellOffset paintOffset,
    required CellOffset screenOffset,
  }) {
    // Re-record into an enclosing boundary's capture (nested boundaries), then
    // re-register at the current screen position. Unlike semantic bounds the
    // pointer path does not intersect clipRect — the live registration
    // (RenderPointerListener.paint) doesn't either, so replay stays faithful.
    publishToActiveCapture(paintOffset);
    register(_translate(localBounds, screenOffset));
  }

  static CellRect _translate(CellRect rect, CellOffset offset) {
    return CellRect(offset: offset + rect.offset, size: rect.size);
  }
}

/// Stack-scoped collector for pointer regions registered during paint — the
/// pointer counterpart of [SemanticPaintBoundsCapture].
final class PointerRegionCapture {
  PointerRegionCapture._();

  static final List<List<PointerRegionRecord>> _stack =
      <List<PointerRegionRecord>>[];

  /// Whether a boundary is currently capturing. Regions check this before
  /// building their record so an unenclosed region — the common case — does
  /// no per-paint allocation at all.
  static bool get isActive => _stack.isNotEmpty;

  static void collect(
    List<PointerRegionRecord> records,
    void Function() paint,
  ) {
    _stack.add(records);
    try {
      paint();
    } finally {
      _stack.removeLast();
    }
  }

  static void record(PointerRegionRegister register, CellRect localBounds) {
    if (_stack.isEmpty) return;
    _stack.last.add(
      PointerRegionRecord(register: register, localBounds: localBounds),
    );
  }
}

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
  bool _needsLayout = true;

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

  /// Whether this render object must run [performLayout] the next time it is
  /// reached with the same constraints. Constraints changes always force a new
  /// layout even when this flag is false.
  @protected
  bool get needsLayout => _needsLayout;

  /// Whether this render object owns its own paint cache (a `CellBuffer`
  /// it can blit instead of re-walking its subtree's paint). Override to
  /// true in subclasses that implement the cache discipline.
  bool get isRepaintBoundary => false;

  /// The frame damage tracker for this render tree, held at the root.
  ///
  /// Set by the frame driver (via [attachFrameDamageTracker]) on the root
  /// render object only. Invalidation walks ([_markNeedsLayoutUp]) terminate
  /// at the root and publish there, so per-object storage stays nil and two
  /// runtimes in one isolate never share damage state.
  RenderDamageTracker? _frameDamage;

  /// Attaches the per-runtime damage tracker at this (root) render object.
  ///
  /// Returns true when the tracker was not already attached — a fresh root —
  /// so callers can record conservative damage for invalidations that may
  /// have happened while the subtree was being built detached.
  bool attachFrameDamageTracker(RenderDamageTracker tracker) {
    final isNew = !identical(_frameDamage, tracker);
    _frameDamage = tracker;
    return isNew;
  }

  /// The damage tracker attached at this tree's root, if any.
  RenderDamageTracker? get _rootFrameDamage {
    RenderObject node = this;
    while (true) {
      final parent = node._parent;
      if (parent == null) return node._frameDamage;
      node = parent;
    }
  }

  /// Marks this render object and its ancestors as needing layout, and marks
  /// the nearest enclosing repaint boundary as dirty. Use this for changes
  /// that can affect size, child constraints, child offsets, or layout-derived
  /// paint state.
  void markNeedsLayout() {
    DebugInvalidations.recordLayout(runtimeType.toString());
    _markNeedsLayoutUp();
    _markEnclosingRepaintBoundariesDirty();
  }

  void _markNeedsLayoutUp() {
    _needsLayout = true;
    final parent = _parent;
    if (parent == null) {
      // Terminal node of the invalidation walk: publish frame damage at the
      // root so the presenter falls back to a full diff this frame.
      _frameDamage?.recordLayoutOrConservativePaint();
      return;
    }
    parent._markNeedsLayoutUp();
  }

  /// Marks this render object as visually stale and conservatively marks
  /// layout dirty.
  ///
  /// This remains the compatibility-safe default for unaudited setters. Use
  /// [markNeedsLayout] when the value can change size, child constraints,
  /// offsets, or layout-derived paint state. Use [markNeedsPaintOnly] only
  /// after verifying that the value cannot affect layout.
  void markNeedsPaint() {
    DebugInvalidations.recordPaint(runtimeType.toString());
    _markNeedsLayoutUp();
    _markEnclosingRepaintBoundariesDirty();
  }

  /// Marks only the nearest enclosing repaint boundary as visually stale.
  ///
  /// Subclasses should use this for audited visual-only mutations such as
  /// color, text style, cursor blink, or paint-time visibility toggles. It
  /// intentionally does not mark this render object or its ancestors as layout
  /// dirty, so the next same-constraint layout call can reuse cached sizes.
  @protected
  void markNeedsPaintOnly() {
    DebugInvalidations.recordPaint(runtimeType.toString());
    _rootFrameDamage?.recordVisualChange();
    _markEnclosingRepaintBoundariesDirty();
  }

  // Marks EVERY enclosing repaint boundary dirty, not just the nearest — an
  // outer boundary's cached blit embeds the inner boundary's painted cells, so
  // a change under the inner boundary makes the outer's cache stale too. Marking
  // only the nearest leaves the outer to cache-hit and blit stale cells (and,
  // with pointer/semantic replay, re-register regions from a subtree that has
  // since changed). An already-dirty boundary short-circuits: it was marked by
  // an earlier walk this frame that already continued to the root, so its
  // ancestors are dirty too. (Named for the audited paint-only path; also used
  // by the conservative markNeedsPaint. Layout dirtiness is handled separately.)
  void _markEnclosingRepaintBoundariesDirty() {
    if (isRepaintBoundary) {
      if (_needsPaint) return;
      _needsPaint = true;
    }
    _parent?._markEnclosingRepaintBoundariesDirty();
  }

  /// Marks every repaint boundary STRICTLY ABOVE this node as needing paint.
  ///
  /// For a node that gains caching authority at runtime ([isRepaintBoundary]
  /// flipping true — `RenderRepaintBoundary.cachingEnabled`): setting its own
  /// [needsPaint] is not enough, because enclosing boundary caches embed this
  /// subtree's painted cells, and every later invalidation from inside the
  /// subtree short-circuits at this now-dirty boundary — the ancestors would
  /// never be told. Deliberately starts at the parent: the self-inclusive
  /// walk ([_markEnclosingRepaintBoundariesDirty]) would see this boundary
  /// already dirty and stop before reaching any ancestor.
  @protected
  void markAncestorRepaintBoundariesDirty() {
    _parent?._markEnclosingRepaintBoundariesDirty();
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
    markNeedsLayout();
  }

  /// Detaches [child] from this render object.
  @protected
  void dropChild(RenderObject child) {
    assert(child._parent == this, 'dropChild called on the wrong parent.');
    child.parentData?.detach();
    child.parentData = null;
    child._parent = null;
    markNeedsLayout();
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
    final cachedSize = _size;
    if (!_needsLayout && cachedSize != null && _constraints == constraints) {
      RenderLayoutDebugStats.recordSkipped();
      return cachedSize;
    }
    final previousSize = _size;
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
    _needsLayout = false;
    RenderLayoutDebugStats.recordPerformed();
    if (previousSize != null && previousSize != result) {
      _rootFrameDamage?.recordLayoutOrConservativePaint();
      _markEnclosingRepaintBoundariesDirty();
    }
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

/// Whether two render-child lists contain the same child identities in the
/// same order.
///
/// Multi-child render objects call this before reconciling children so ordinary
/// widget rebuilds that preserve child identity do not accidentally dirty
/// layout.
@protected
bool hasSameRenderChildrenInOrder(
  List<RenderObject> current,
  List<RenderObject> next,
) {
  if (current.length != next.length) return false;
  for (var i = 0; i < current.length; i++) {
    if (!identical(current[i], next[i])) return false;
  }
  return true;
}
