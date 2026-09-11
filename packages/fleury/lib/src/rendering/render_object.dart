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
/// Where the owner is in its frame; see [RenderDamageTracker.onInvalidate].
enum RenderFramePhase { idle, build, layout, paint }

final class RenderDamageTracker {
  // ---- Frame phase and the invalidation hook ------------------------------
  //
  // An invalidation is a request for a frame. Which frame depends on WHEN it
  // lands: during build or layout, this frame's paint covers it (absorbed);
  // during paint or between frames, the NEXT frame must render it. Before
  // this, a paint-only or layout invalidation raised outside a build — a
  // render-object setter driven by a timer, an anchor retracted at the end
  // of a paint pass — only set a flag that frames consult; nothing asked for
  // the frame, and the flag was consumed with the frame that was finishing.
  // [onInvalidate] is installed by the frame driver and is the one
  // scheduling primitive layout, paint and build invalidation share.

  /// Called when an invalidation lands that this frame cannot cover: outside
  /// a frame, or during its paint phase. Coalescing is the callee's job.
  void Function()? onInvalidate;

  /// The phase the owner is in; set by `BuildOwner.renderFrame`.
  RenderFramePhase phase = RenderFramePhase.idle;

  bool _carryVisualChange = false;

  void _invalidated() {
    switch (phase) {
      case RenderFramePhase.build:
      case RenderFramePhase.layout:
        return;
      case RenderFramePhase.paint:
        _carryVisualChange = true;
      case RenderFramePhase.idle:
        break;
    }
    onInvalidate?.call();
  }

  bool _requiresFullDiff = false;
  bool _visualChange = false;

  // ---- Geometry epoch -----------------------------------------------------
  //
  // Derived screen geometry (`RenderObject.screenGeometry`) is memoized per
  // render object against this counter. Any invalidation may move something,
  // and a paint pass begins after layout has settled, so both advance it.
  int _geometryEpoch = 0;

  /// Advances whenever derived geometry may have changed.
  int get geometryEpoch => _geometryEpoch;

  /// The size of the buffer the tree renders into, set by the owner before
  /// each frame's layout. The outermost clip of every derived geometry.
  CellSize? screenSize;

  final List<void Function()> _paintPassListeners = <void Function()>[];

  /// Registers [listener] to run when a paint pass ends — the point at which
  /// this frame's layout, and so every derived geometry, is final. The
  /// semantics tier re-derives node bounds here.
  void addPaintPassListener(void Function() listener) {
    _paintPassListeners.add(listener);
  }

  void removePaintPassListener(void Function() listener) {
    _paintPassListeners.remove(listener);
  }

  void recordLayoutOrConservativePaint() {
    _requiresFullDiff = true;
    _visualChange = true;
    _geometryEpoch++;
    _invalidated();
  }

  /// Records that some render object's visual output may differ next frame
  /// (audited paint-only invalidations included). Cleared when a frame
  /// consumes it via [takeVisualChange].
  void recordVisualChange() {
    _visualChange = true;
    _geometryEpoch++;
    _invalidated();
  }

  /// Whether any invalidation has been recorded since the last rendered
  /// frame. While false (and the buffer pool is warm), a frame request can
  /// skip build/layout/paint entirely: the front buffer is still exact.
  bool get hasVisualChange => _visualChange;

  bool takeVisualChange() {
    final result = _visualChange;
    // What landed during paint belongs to the next frame, not to nothing.
    _visualChange = _carryVisualChange;
    _carryVisualChange = false;
    return result;
  }

  final Set<RenderObject> _scheduledLayouts = Set<RenderObject>.identity();

  /// Registers [node] to be laid out with its last constraints after the
  /// root layout pass. Used when a tight-constraint node stops the
  /// ancestor walk so the rest of the tree stays cached.
  void scheduleLayout(RenderObject node) {
    _scheduledLayouts.add(node);
  }

  /// Layouts dirtied relayout-boundary subtrees the root pass did not
  /// reach. Parent-before-child; a node already laid out this frame is
  /// skipped. Loops so a size change that dirties a parent is flushed
  /// in the same frame.
  void flushScheduledLayouts() {
    while (_scheduledLayouts.isNotEmpty) {
      final nodes = _scheduledLayouts.toList(growable: false);
      _scheduledLayouts.clear();
      nodes.sort((a, b) => a._layoutDepth - b._layoutDepth);
      for (final node in nodes) {
        node._flushScheduledLayout();
      }
    }
  }

  bool takeRequiresFullDiff() {
    final result = _requiresFullDiff;
    _requiresFullDiff = false;
    return result;
  }

  void reset() {
    _requiresFullDiff = false;
    _visualChange = false;
    _carryVisualChange = false;
    _geometryEpoch++;
    phase = RenderFramePhase.idle;
  }

  // ---- Paint passes ------------------------------------------------------
  //
  // The root paint pass is numbered. A participant that publishes a
  // paint-time fact about its subtree (painted bounds) stamps the pass it
  // published in; when the pass ends, one that neither painted nor replayed
  // belongs to a subtree that stopped painting while staying mounted — a
  // hidden IndexedStack child, a route beneath an opaque one — and is told to
  // retract. Cached repaint boundaries replay their retained geometry every
  // pass, so a clean subtree counts as painted. Per owner, like the damage
  // signal: two runtimes in one isolate never sweep each other's
  // participants.

  int _paintPass = 0;

  /// The pass currently painting (or the last one, between passes).
  int get paintPass => _paintPass;

  final Set<PaintPassParticipant> _participants =
      Set<PaintPassParticipant>.identity();

  /// Registers [participant] for the end-of-pass sweep. Idempotent.
  void registerPaintPassParticipant(PaintPassParticipant participant) {
    _participants.add(participant);
  }

  /// Removes [participant] from the sweep (it left the tree, or moved to
  /// another owner).
  void unregisterPaintPassParticipant(PaintPassParticipant participant) {
    _participants.remove(participant);
  }

  /// Starts a root paint pass; returns its number.
  int beginPaintPass() {
    _geometryEpoch++;
    return ++_paintPass;
  }

  /// Ends the current pass: every participant that did not publish in it —
  /// its subtree stayed mounted but did not paint (a cached repaint boundary,
  /// the other IndexedStack tab, a route beneath an opaque one) — re-derives
  /// its fact from layout state and publishes it. Publishing an unchanged
  /// fact notifies nobody, so a participant that stays hidden costs one
  /// derivation per pass and never requests a frame.
  void endPaintPass() {
    for (final participant in _participants) {
      if (participant.publishedPaintPass == _paintPass) continue;
      participant.refreshPaintFacts();
    }
    for (var i = 0; i < _paintPassListeners.length; i++) {
      _paintPassListeners[i]();
    }
  }
}

/// A render object that publishes a fact about its subtree's geometry — its
/// bounds on screen — during its own paint, and re-derives that fact when a
/// root paint pass ends without the subtree having painted. It registers with
/// the tree's [RenderDamageTracker] when it first publishes and unregisters on
/// detach.
abstract interface class PaintPassParticipant {
  /// The [RenderDamageTracker.paintPass] this participant last published in.
  int get publishedPaintPass;

  /// Re-derive the fact from layout state and publish it. Called at the end
  /// of every pass in which this participant did not paint; the fact may be
  /// unchanged, in which case publishing must notify nobody.
  void refreshPaintFacts();
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
abstract class RenderObject implements ScreenGeometrySource {
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

  /// Whether a descendant layout invalidation can stop here.
  ///
  /// Tight constraints fully determine [size], so a child's size change
  /// cannot change this node, and the parent does not need to relayout.
  /// The node itself is scheduled for a constraints-cached layout pass
  /// instead of dirtying the ancestor chain.
  bool get isRelayoutBoundary {
    final constraints = _constraints;
    return constraints != null && constraints.isTight;
  }

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
    // Memoized geometry is stamped against the previous tracker's epoch;
    // nothing below may keep answering from it.
    if (isNew) _forgetGeometryTracker();
    return isNew;
  }

  /// The damage tracker attached at this tree's root, if any.
  /// The frame damage tracker attached at this tree's root — the per-owner
  /// object a render object publishes frame-scoped facts into — or null while
  /// detached or before the first frame.
  @protected
  RenderDamageTracker? get rootFrameDamage => _rootFrameDamage;

  RenderDamageTracker? get _rootFrameDamage {
    RenderObject node = this;
    while (true) {
      final parent = node._parent;
      if (parent == null) return node._frameDamage;
      node = parent;
    }
  }

  /// This render object's invalidation source, for the debug collector.
  ///
  /// Only ever evaluated behind a [DebugInvalidations.isRecording] check:
  /// `runtimeType.toString()` is not free, and this runs on every layout and
  /// paint invalidation of every render object.
  String get _debugInvalidationLabel {
    DebugInvalidations.debugCountLabel();
    return runtimeType.toString();
  }

  /// Marks this render object and its ancestors as needing layout, and marks
  /// the nearest enclosing repaint boundary as dirty. Use this for changes
  /// that can affect size, child constraints, child offsets, or layout-derived
  /// paint state.
  void markNeedsLayout() {
    if (DebugInvalidations.isRecording) {
      DebugInvalidations.recordLayout(_debugInvalidationLabel);
    }
    _markNeedsLayoutUp();
    _markEnclosingRepaintBoundariesDirty();
  }

  void _markNeedsLayoutUp() {
    if (_needsLayout) return;
    _needsLayout = true;
    final parent = _parent;
    if (parent == null) {
      // Terminal node of the invalidation walk: publish frame damage at the
      // root so the presenter falls back to a full diff this frame.
      _frameDamage?.recordLayoutOrConservativePaint();
      return;
    }
    if (isRelayoutBoundary) {
      _rootFrameDamage?.scheduleLayout(this);
      _rootFrameDamage?.recordVisualChange();
      return;
    }
    parent._markNeedsLayoutUp();
  }

  /// Marks this render object as visually stale without dirtying layout.
  ///
  /// Size, constraints, and child offsets are unchanged. Use
  /// [markNeedsLayout] when they might be. [markNeedsPaintOnly] is the
  /// same signal with an audited-setter name.
  void markNeedsPaint() {
    markNeedsPaintOnly();
  }

  /// Marks only the nearest enclosing repaint boundary as visually stale.
  ///
  /// Subclasses should use this for audited visual-only mutations such as
  /// color, text style, cursor blink, or paint-time visibility toggles. It
  /// intentionally does not mark this render object or its ancestors as layout
  /// dirty, so the next same-constraint layout call can reuse cached sizes.
  @protected
  void markNeedsPaintOnly() {
    if (DebugInvalidations.isRecording) {
      DebugInvalidations.recordPaint(_debugInvalidationLabel);
    }
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
  /// gives the parent a chance to ensure [RenderObject.parentData] is the right
  /// type via [setupParentData].
  @protected
  void adoptChild(RenderObject child) {
    assert(child._parent == null, 'Render object adopted twice.');
    child._parent = this;
    // The subtree may have been built detached or under another root: its
    // memoized geometry must resolve against this tree's epoch.
    child._forgetGeometryTracker();
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
      // A relayout boundary stopped the ancestor walk. If our size
      // actually changed, the parent still has to run — unless it is
      // already laying us out (its `_needsLayout` is still true).
      final parent = _parent;
      if (parent != null && !parent._needsLayout) {
        parent.markNeedsLayout();
      }
    }
    return result;
  }

  int get _layoutDepth {
    var depth = 0;
    var node = _parent;
    while (node != null) {
      depth++;
      node = node._parent;
    }
    return depth;
  }

  void _flushScheduledLayout() {
    if (!_needsLayout) return;
    final constraints = _constraints;
    if (constraints == null) return;
    layout(constraints);
  }

  /// Override to compute the chosen size and lay out children. Must
  /// return a size that satisfies [constraints].
  @protected
  CellSize performLayout(CellConstraints constraints);

  /// Paints this render object into [buffer] at [offset]: its origin in the
  /// buffer's coordinates. The buffer's bounds are the clip.
  ///
  /// Not overridable. In debug mode it records the placement and checks it
  /// against the geometry contract before delegating to [performPaint], so
  /// every painted frame of every test verifies that a container paints each
  /// child where [childOffsetOf] says it does, and only when [presentsChild]
  /// says it is shown. Position and visibility are derived from that
  /// contract ([screenGeometry]); paint never reports them.
  @nonVirtual
  void paint(CellBuffer buffer, CellOffset offset) {
    assert(_debugCheckPaintPlacement(buffer, offset));
    performPaint(buffer, offset);
  }

  /// Paints this render object's cells into [buffer] at [offset].
  ///
  /// A container paints each presented child at
  /// `offset + childOffsetOf(child)` into the same buffer — or into a scratch
  /// buffer of its own that it then composites (a viewport, a clip, an
  /// effect), in which case the children paint at scratch-local offsets and
  /// the composite places the result. Nothing about screen position is
  /// threaded through paint: a render object that needs to know where it is
  /// asks [screenGeometry].
  @protected
  void performPaint(CellBuffer buffer, CellOffset offset);

  CellBuffer? _debugPaintBuffer;
  CellOffset _debugPaintOffset = CellOffset.zero;

  bool _debugCheckPaintPlacement(CellBuffer buffer, CellOffset offset) {
    _debugPaintBuffer = buffer;
    _debugPaintOffset = offset;
    final parent = _parent;
    // A composite paints its children into a buffer of its own; only a
    // parent painting into the same buffer places a child directly.
    if (parent == null || !identical(parent._debugPaintBuffer, buffer)) {
      return true;
    }
    if (!parent.presentsChild(this)) {
      throw StateError(
        '${parent.runtimeType} painted a $runtimeType that its '
        'presentsChild() reports as not presented. Derived geometry hides '
        'that child; paint must agree.',
      );
    }
    final expected = parent._debugPaintOffset + parent.childOffsetOf(this);
    if (expected != offset) {
      throw StateError(
        '${parent.runtimeType} painted a $runtimeType at $offset but its '
        'childOffsetOf() places it at $expected. Derived geometry follows '
        'childOffsetOf; paint must agree.',
      );
    }
    return true;
  }

  // ---- Geometry contract ---------------------------------------------------
  //
  // Where a render object put each child is layout state. Declaring it lets
  // screen geometry be DERIVED on demand (see [screenGeometry]) instead of
  // recorded during paint and replayed by repaint boundaries. Pass-through
  // wrappers keep the defaults; every container that offsets, clips, or
  // hides a child overrides the matching member.

  /// Where this render object paints [child], relative to its own origin.
  CellOffset childOffsetOf(RenderObject child) => CellOffset.zero;

  /// Whether [child] is presented this frame: painted and interactive. False
  /// for a child hidden by policy — an inactive `IndexedStack` child, a route
  /// under an opaque route, an overlay entry under an opaque one, a list row
  /// outside the mounted window, a contained-error subtree.
  bool presentsChild(RenderObject child) => true;

  /// The clip this render object imposes on [child], in its own coordinates,
  /// or null when it does not clip. Usually the same rectangle for every
  /// child (a viewport); a container with several scrolling regions — a
  /// table with a pinned header — answers per child.
  CellRect? childClipOf(RenderObject child) => null;

  /// Whether a point outside this render object's box can hit something in
  /// its subtree. False by default: hit-testing prunes a subtree by its box,
  /// as Flutter does, so a pointer event walks one chain of the tree rather
  /// than every region. A container that places children outside its box
  /// and wants them to stay interactive there — a `Stack` with an
  /// overflowing `Positioned` — answers true.
  bool get hitTestsBeyondBounds => false;

  /// Visits this render object's children in paint order. The default reads
  /// the single-child / multi-child interfaces; a container whose [children]
  /// accessor copies its list overrides this to iterate in place, since
  /// hit-testing and geometry tooling walk the tree on every event.
  void visitRenderChildren(void Function(RenderObject child) visitor) {
    final self = this;
    if (self is RenderObjectWithSingleChild) {
      final child = self.child;
      if (child != null) visitor(child);
    } else if (self is RenderObjectWithChildren) {
      for (final child in self.children) {
        visitor(child);
      }
    }
  }

  // ---- Derived screen geometry ---------------------------------------------
  //
  // Position and visibility are derived from layout state on demand — every
  // container reports where it put each child ([childOffsetOf]), what it
  // clips ([childClipOf]) and whether it presents the child at all
  // ([presentsChild]) — and memoized against the tree's geometry epoch, which
  // advances on every invalidation and at the start of every paint pass. A
  // memo hit allocates nothing; a miss resolves the ancestor chain once and
  // leaves every ancestor memoized for the other queries of the same epoch.

  RenderDamageTracker? _geometryTracker;
  int _geometryStamp = -1;
  RenderGeometry? _screenGeometry;
  CellOffset _screenOrigin = CellOffset.zero;
  CellRect? _screenClip; // zero-sized when fully clipped

  /// Whether this render object has been laid out at least once.
  bool get hasLayout => _size != null;

  /// This render object's screen geometry, derived from layout state: where
  /// it is, and how much of it is visible.
  ///
  /// Null when it is not presented — hidden by an ancestor's policy
  /// ([presentsChild]), detached from the rendered tree, or not laid out yet.
  /// Reflects the latest completed layout at any time between frames, and
  /// the current frame's layout once its paint pass has begun.
  @override
  RenderGeometry? screenGeometry() {
    if (_size == null) return null;
    final tracker = _geometryTracker ??= _rootFrameDamage;
    if (tracker == null) return null; // never attached to a rendered tree
    final epoch = tracker.geometryEpoch;
    if (_geometryStamp != epoch) _resolveScreenGeometry(epoch);
    return _screenGeometry;
  }

  void _resolveScreenGeometry(int epoch) {
    final parent = _parent;
    var presented = false;
    if (parent == null) {
      // Only the rendered root carries the tracker; the top of a detached
      // subtree has none and presents nothing.
      final tracker = _frameDamage;
      presented = tracker != null;
      _screenOrigin = CellOffset.zero;
      // The screen is the outermost clip.
      final screen = tracker?.screenSize;
      _screenClip = screen == null
          ? null
          : CellRect(offset: CellOffset.zero, size: screen);
    } else {
      if (parent._geometryStamp != epoch) parent._resolveScreenGeometry(epoch);
      if (parent._screenGeometry != null && parent.presentsChild(this)) {
        presented = true;
        _screenOrigin = parent._screenOrigin + parent.childOffsetOf(this);
        var clip = parent._screenClip;
        final ownClip = parent.childClipOf(this);
        if (ownClip != null) {
          final screenClip = CellRect(
            offset: parent._screenOrigin + ownClip.offset,
            size: ownClip.size,
          );
          clip = clip == null
              ? screenClip
              : (clip.intersect(screenClip) ??
                    CellRect(offset: screenClip.offset, size: CellSize.zero));
        }
        _screenClip = clip;
      }
    }
    if (presented) {
      final bounds = CellRect(offset: _screenOrigin, size: size);
      final clip = _screenClip;
      final previous = _screenGeometry;
      // Keep the instance when nothing moved: consumers compare and cache it.
      if (previous == null ||
          previous.bounds != bounds ||
          previous.clip != clip) {
        _screenGeometry = RenderGeometry(bounds: bounds, clip: clip);
      }
    } else {
      _screenGeometry = null;
    }
    _geometryStamp = epoch;
  }

  /// Drops the memoized geometry below a subtree that is moving to another
  /// parent or root, so it resolves against its new root's epoch. Resolving
  /// any node stamps every ancestor, so a subtree whose top was never stamped
  /// holds no memo at all and costs nothing here — the fresh-mount case.
  void _forgetGeometryTracker() {
    if (_geometryStamp == -1) return;
    _geometryTracker = null;
    _geometryStamp = -1;
    _screenGeometry = null;
    visitRenderChildren((child) => child._forgetGeometryTracker());
  }

  // ---- Intrinsic sizing -------------------------------------------------
  //
  // Subclasses override these to report the size they'd naturally take
  // given a cross-axis constraint. Used by widgets like [IntrinsicWidth]
  // and intrinsic-sized [Table] columns to size a child "tight to content"
  // instead of expanding it to the available space.
  //
  // Pass `null` for `height` / `width` to mean "no cross-axis constraint."
  //
  // Defaults: a single-child wrapper ([RenderObjectWithSingleChild]) answers
  // with its child's preference — a proxy that adds no geometry of its own
  // (focus, pointer, semantics, repaint boundary, error containment) wants
  // exactly that. Wrappers that DO add geometry (padding, a frame, a fixed
  // box) override and adjust. Everything else returns 0: a leaf or a
  // multi-child layout that doesn't override declares no preference.
  //
  // Before this, every non-overriding wrapper reported 0, which
  // [IntrinsicWidth]/[IntrinsicHeight] read as "wants to be empty" and laid
  // the whole subtree out at zero — blank — for almost any real child.

  /// The widest this render object would want to be at the given [height].
  /// Most relevant override: text returns its unwrapped width.
  int computeMaxIntrinsicWidth(int? height) {
    final self = this;
    if (self is! RenderObjectWithSingleChild) return 0;
    return self.child?.computeMaxIntrinsicWidth(height) ?? 0;
  }

  /// The narrowest width below which content would clip. Text-like leaves
  /// can return a longest-token width if they word-wrap.
  int computeMinIntrinsicWidth(int? height) {
    final self = this;
    if (self is! RenderObjectWithSingleChild) return 0;
    return self.child?.computeMinIntrinsicWidth(height) ?? 0;
  }

  /// The tallest this render object would want to be at the given [width].
  int computeMaxIntrinsicHeight(int? width) {
    final self = this;
    if (self is! RenderObjectWithSingleChild) return 0;
    return self.child?.computeMaxIntrinsicHeight(width) ?? 0;
  }

  /// The shortest this render object can be at the given [width].
  int computeMinIntrinsicHeight(int? width) {
    final self = this;
    if (self is! RenderObjectWithSingleChild) return 0;
    return self.child?.computeMinIntrinsicHeight(width) ?? 0;
  }
}

/// Where something sits on screen and how much of it is visible.
final class RenderGeometry {
  RenderGeometry({required this.bounds, this.clip})
    : visible = bounds.size.isEmpty
          ? null
          : (clip == null ? bounds : bounds.intersect(clip));

  /// The full rectangle in screen cells, ignoring clips.
  final CellRect bounds;

  /// The intersection of every clip an ancestor applies, in screen cells —
  /// the screen itself is the outermost — or null when nothing clips.
  final CellRect? clip;

  /// The part of [bounds] inside [clip], or null when nothing of it is
  /// visible (clipped out, or empty).
  final CellRect? visible;

  @override
  bool operator ==(Object other) =>
      other is RenderGeometry && other.bounds == bounds && other.clip == clip;

  @override
  int get hashCode => Object.hash(bounds, clip);

  @override
  String toString() =>
      'RenderGeometry(bounds: $bounds, clip: $clip, visible: $visible)';
}

/// Something that knows where it is on screen. Every [RenderObject] is one;
/// focus nodes, carets, and bounds notifiers read geometry through this
/// interface rather than recording it during paint, so a test can stand in
/// a fixed rectangle without mounting a tree.
abstract interface class ScreenGeometrySource {
  /// The current screen geometry, or null when not presented.
  RenderGeometry? screenGeometry();
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

/// The removed index when [next] preserves all other child identities in order.
/// Returns null for general reconciliation or if the removed child is retained
/// elsewhere in [next].
/// Container removal can then drop that child without rebuilding identity sets.
@protected
int? singleRemovedRenderChildIndex(
  List<RenderObject> current,
  List<RenderObject> next,
) {
  if (current.length != next.length + 1) return null;
  var removedIndex = 0;
  while (removedIndex < next.length &&
      identical(current[removedIndex], next[removedIndex])) {
    removedIndex++;
  }
  final removed = current[removedIndex];
  for (var i = 0; i < next.length; i++) {
    if (identical(next[i], removed)) return null;
    if (i >= removedIndex && !identical(current[i + 1], next[i])) return null;
  }
  return removedIndex;
}
