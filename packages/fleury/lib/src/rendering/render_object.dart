import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../debug/debug_invalidation.dart';
import '../foundation/fleury_error.dart';
import '../foundation/geometry.dart';
import 'cell.dart';
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

  // ---- Incremental paint ---------------------------------------------------
  //
  // Two bits, recorded by the invalidation walk that already runs to the root:
  // [_selfDirty] means THIS node's own painted cells may differ, [_subtreeDirty]
  // means something below it is self-dirty. The distinction is what keeps the
  // root from clearing the screen every time a leaf changes — an ancestor on
  // the dirty path repaints its own chrome and recurses, while a clean sibling
  // of the changed leaf is skipped outright.
  bool _selfDirty = true;
  bool _subtreeDirty = true;

  /// The last pass in which this node was PRESENT — painted, or skipped
  /// because its carried cells were still valid. Both count: a skip means the
  /// cells stayed on screen.
  ///
  /// A frame can be rendered and then NOT committed — the loop supports it, and
  /// an uncommitted frame must not become the reference. Clearing the dirty
  /// bits during paint would lose the invalidation for good, so paint stamps
  /// the pass instead and a node only counts as carried once that pass has
  /// been committed.
  int _presentedAtPass = -1;

  /// Geometry this node was last painted at, so a subtree that MOVED is never
  /// mistaken for one that did not change. Derived, not declared: a widget
  /// cannot forget to report it (see [screenGeometry]).
  RenderGeometry? _lastPaintGeometry;

  // The screen rectangle this node AND EVERYTHING UNDER IT last painted into,
  // as left/top/right/bottom; empty when `_subR <= _subL`. Four ints rather
  // than a CellRect because every painted node updates it every frame and the
  // allocation gate would see the garbage.
  //
  // The subtree footprint, not the node's own rect, is what the two questions
  // this design asks are really about. "What must be erased when this node
  // changes" has to include children painting outside it — an overflowing row,
  // a child the container stopped presenting — or their cells survive with
  // nothing left to repaint them. And "may this node be skipped" is a claim
  // about every cell the subtree owns, not just this node's own.
  // Whether this node's last paint went into the screen buffer. False for a
  // subtree a composite paints into a scratch buffer of its own (a repaint
  // boundary's cache, a viewport, an effect): those cells reach the screen
  // through the composite's blit, at whatever rectangle the composite chose,
  // so the node's own footprint says nothing about where they landed.
  //
  // Only meaningful once the node HAS painted — [_presentedAtPass] says
  // whether it has. The two are not the same question, and conflating them
  // charged a subtree that had never painted at all to its parent's footprint,
  // which is a rectangle that by definition does not contain it: a pane whose
  // content mounted after the first frame stayed blank forever.
  bool _paintedOnScreen = false;

  // Whether this node's paint laid something out — see [layout]. A node that
  // does cannot be skipped: its paint is how that work happens at all.
  bool _layoutsDuringPaint = false;

  int _subL = 0;
  int _subT = 0;
  int _subR = 0;
  int _subB = 0;

  /// Whether the enclosing boundary's cache has been invalidated. Set true
  /// by [markNeedsPaint]; subclasses that implement a paint cache clear it
  /// once they have re-painted into their cache.
  @protected
  bool get needsPaint => _needsPaint;

  @protected
  set needsPaint(bool value) {
    _needsPaint = value;
    // A boundary sets this directly — on a cache resize, or when engagement
    // flips — without going through markNeedsPaint. Incremental paint reads a
    // different channel, and two channels that can disagree is exactly how a
    // subtree gets skipped while something under it is dirty.
    if (value) _markPaintOriginDirty();
  }

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
    _markPaintOriginDirty();
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
    if (DebugInvalidations.isRecording) {
      DebugInvalidations.recordPaint(_debugInvalidationLabel);
    }
    _markPaintOriginDirty();
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
    if (DebugInvalidations.isRecording) {
      DebugInvalidations.recordPaint(_debugInvalidationLabel);
    }
    _markPaintOriginDirty();
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

  /// Records an invalidation whose ORIGIN is this node: its own painted cells
  /// may differ, and every ancestor now contains a change without necessarily
  /// having changed itself.
  ///
  /// The distinction is the whole design. If an ancestor were marked
  /// self-dirty it would erase its own rect before repainting — and its clean
  /// children, skipping into that hole, would leave it blank. Ancestors repaint
  /// their own chrome and recurse; only the origin erases.
  void _markPaintOriginDirty() {
    // A mark raised after this pass derived its damage belongs to the NEXT
    // frame (the tracker's own phase model says so). Recorded because the
    // full-repaint check cannot fairly compare across it: the tree it would
    // repaint is no longer the tree that was painted.
    if (IncrementalPaint._damagePass == IncrementalPaint._pass) {
      IncrementalPaint._dirtiedDuringPass = true;
    }
    _selfDirty = true;
    _markPaintPathDirty();
  }

  /// Marks the path to the root as containing a change, without claiming any
  /// of those nodes changed themselves. Free: the boundary walk already visits
  /// exactly these nodes, it just never recorded anything on them.
  void _markPaintPathDirty() {
    // No short-circuit on an already-marked ancestor. That optimization assumes
    // "marked implies everything above is marked", which is exactly the
    // invariant this walk exists to establish — and it does not hold for a
    // node marked while DETACHED, whose chain above did not exist yet. One
    // stale mark low in the tree would then swallow every later walk through
    // it. The walk is pointer-chasing to the root; the boundary walk beside it
    // already pays the same.
    for (RenderObject? node = _parent; node != null; node = node._parent) {
      node._subtreeDirty = true;
    }
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
    // Attachment IS an invalidation, and it is the one case where dirtiness is
    // not raised but INHERITED: a fresh render object is born dirty, so nothing
    // ever walked its ancestors to say so. Until it has been connected there is
    // no chain to walk — this is the first moment there is one. Without it an
    // ancestor can skip over a subtree that has never painted at all.
    child._markPaintOriginDirty();
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
    // Laying out DURING paint means the node currently painting has a side
    // effect beyond writing cells: a LayoutBuilder run here builds widgets,
    // mounts elements and creates render objects. Skipping that node's paint
    // would skip the build too, and a pane whose content is produced this way
    // would simply never come into existence. Recorded, not declared — the
    // node that does it is the one that finds out.
    if (IncrementalPaint.enabled &&
        _rootFrameDamage?.phase == RenderFramePhase.paint) {
      IncrementalPaint._painting?._layoutsDuringPaint = true;
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
    if (!IncrementalPaint.enabled || IncrementalPaint._observingDepth > 0) {
      // An OBSERVING repaint reads the tree, it does not advance it: nothing
      // is stamped, no dirty bit is cleared, no footprint is measured. A
      // verifier that walks the tree a second time in the same frame has to
      // leave the bookkeeping exactly as it found it, or it decides the next
      // frame's skips from state that only its own extra pass produced.
      performPaint(buffer, offset);
      return;
    }
    if (buffer.carriesPreviousFrame) {
      // First paint into a carried frame buffer this pass: derive the damage.
      // Nothing has painted yet, so this is the one moment at which erasing a
      // vacated region cannot destroy something already drawn over it.
      if (IncrementalPaint._damagePass != IncrementalPaint._pass) {
        IncrementalPaint._prepareFrame(this, buffer);
      }
      final geometry = screenGeometry();
      if (!_selfDirty && !_subtreeDirty && _isSkippable(geometry)) {
        assert(
          _debugSubtreeIsClean(),
          'skipped $runtimeType while a descendant was dirty '
          '(${_debugDirtyDescendant()}) — the invalidation walk did not reach '
          'this node',
        );
        IncrementalPaint._skipped += 1;
        // A skip keeps the cells on screen, so it counts as presence — and the
        // footprint it kept still belongs to the enclosing subtree's.
        _presentedAtPass = IncrementalPaint._pass;
        _paintedOnScreen = true;
        IncrementalPaint._growEnclosing(_subL, _subT, _subR, _subB);
        return;
      }
      IncrementalPaint._painted += 1;
      _lastPaintGeometry = geometry;
    } else {
      // A full-repaint frame, or a scratch buffer. Nothing may be skipped —
      // neither carries anything — but the geometry still has to be recorded.
      // On a frame buffer because the NEXT frame has no idea what a node that
      // shrinks used to cover; on a scratch buffer because this is the record
      // the damage walk compares against to notice that a subtree inside a
      // composite MOVED, which is invisible from anywhere else.
      _lastPaintGeometry = screenGeometry();
    }
    // Clear the bits on ANY buffer this actually painted into, including a
    // scratch one (a boundary cache, a viewport). Clearing only for the screen
    // buffer left everything behind a composite permanently self-dirty while
    // its ancestors on the screen path went clean — so an ancestor could skip
    // over a subtree that still needed painting. What repaints a composite is
    // the composite's own channel ([needsPaint]), not its children's.
    //
    // Cleared BEFORE painting, not after: painting can itself raise an
    // invalidation — a selection geometry recompute, a layout performed inside
    // paint — and clearing afterwards would wipe the mark just set, losing it
    // for good. Cleared first, the mark survives into the next frame, which is
    // where it belongs.
    _selfDirty = false;
    _subtreeDirty = false;
    _presentedAtPass = IncrementalPaint._pass;
    _paintedOnScreen = buffer.isFrameBuffer;
    // Only cells in the screen buffer have a screen footprint; what a subtree
    // paints into a scratch buffer lands wherever the composite later puts it,
    // and the composite's own rect is the footprint that counts. Give up any
    // footprint recorded from an earlier on-screen paint rather than leaving a
    // stale rect behind: a boundary whose caching engages at runtime moves its
    // whole subtree off the screen buffer in one frame, and a footprint that
    // outlived that move would keep claiming cells the node no longer owns.
    if (!buffer.isFrameBuffer) {
      _subR = _subL;
      _subB = _subT;
      performPaint(buffer, offset);
      return;
    }
    // Measure what this subtree actually WRITES, by clearing the buffer's
    // damage window, painting, and reading it back.
    //
    // The footprint used to be derived from geometry — this node's visible
    // rect unioned with its children's. That is wrong for any node that puts
    // cells somewhere other than where it sits, and those exist: a slide
    // effect shifts its child's cells sideways, an expand effect writes rows
    // its own box does not cover. Their old cells were then never erased, and
    // stale text stayed on screen next to the new. Geometry is authoritative
    // for where a node IS; only the buffer knows where its cells LANDED.
    //
    // Hand-inlined rather than wrapped in a helper taking a closure: this runs
    // for every painted node of every frame, and the closure would be a
    // per-node allocation the gate would see.
    final hadDamage = buffer.hasDamage;
    final outerDL = buffer.damageLeft;
    final outerDT = buffer.damageTop;
    final outerDR = buffer.damageRight;
    final outerDB = buffer.damageBottom;
    final outerL = IncrementalPaint._accL;
    final outerT = IncrementalPaint._accT;
    final outerR = IncrementalPaint._accR;
    final outerB = IncrementalPaint._accB;
    buffer.clearDamage();
    IncrementalPaint._accR = IncrementalPaint._accL = 0;
    IncrementalPaint._accB = IncrementalPaint._accT = 0;
    final outerPainting = IncrementalPaint._painting;
    IncrementalPaint._painting = this;
    try {
      performPaint(buffer, offset);
    } finally {
      IncrementalPaint._painting = outerPainting;
      // Written cells, plus the footprints of descendants that skipped — they
      // wrote nothing this frame but still own those cells, and if this node
      // later moves they are what has to be erased.
      _subL = IncrementalPaint._accL;
      _subT = IncrementalPaint._accT;
      _subR = IncrementalPaint._accR;
      _subB = IncrementalPaint._accB;
      final wrote = buffer.hasDamage;
      final wroteL = buffer.damageLeft;
      final wroteT = buffer.damageTop;
      final wroteR = buffer.damageRight;
      final wroteB = buffer.damageBottom;
      if (wrote) _growFootprint(wroteL, wroteT, wroteR, wroteB);
      // Put the enclosing node's window back, with what this one wrote folded
      // in — those writes really happened and belong to every ancestor's
      // measurement too.
      buffer.clearDamage();
      if (hadDamage) buffer.addDamage(outerDL, outerDT, outerDR, outerDB);
      if (wrote) buffer.addDamage(wroteL, wroteT, wroteR, wroteB);
      IncrementalPaint._accL = outerL;
      IncrementalPaint._accT = outerT;
      IncrementalPaint._accR = outerR;
      IncrementalPaint._accB = outerB;
      IncrementalPaint._growEnclosing(_subL, _subT, _subR, _subB);
      // Unfinished business: a child this node PRESENTS that has still never
      // painted, anywhere. Containers decline to paint children for reasons
      // that change from frame to frame — a flex skips one sized outside the
      // buffer, a lazy list one outside its mounted window — and a child
      // mounted during layout can arrive after the frame that would have
      // painted it. Going clean over one lets every ancestor skip it forever:
      // a storybook preview pane whose content mounts lazily stayed blank for
      // the life of the app. Staying subtree-dirty costs this node a repaint
      // per frame (its clean children still skip) until the child either
      // paints or stops being presented.
      // Recompute rather than leave cleared. [_subtreeDirty] was cleared on
      // the way down so an invalidation raised DURING this paint survives; but
      // clearing it also discharged dirt this paint never reached, and a
      // container declines to paint a child for reasons that change frame to
      // frame. Unserviced dirt has to stay, or every ancestor is free to skip
      // over it forever — which is how a pane whose content mounts lazily
      // stayed blank for the life of the app.
      if (_anyChildStillDirty()) _subtreeDirty = true;
    }
  }

  /// Whether a child still carries dirt this paint did not discharge.
  bool _anyChildStillDirty() {
    final self = this;
    if (self is RenderObjectWithChildren) {
      final kids = self.children;
      for (var i = 0; i < kids.length; i++) {
        if (kids[i]._carriesUndischargedDirt) return true;
      }
    } else if (self is RenderObjectWithSingleChild) {
      final child = self.child;
      if (child != null && child._carriesUndischargedDirt) return true;
    }
    return false;
  }

  /// Dirt that could still change the screen.
  ///
  /// A node that is laid out and has nothing visible is excluded: it owns no
  /// cells, so its dirt can never change anything, and a container that has
  /// settled on not painting such a child (a flex child sized outside the
  /// buffer) would otherwise hold its whole ancestry dirty forever. A node
  /// with NO geometry at all is not the same claim — it has not been laid out,
  /// so nothing is known yet and a frame is still owed.
  bool get _carriesUndischargedDirt {
    if (!_selfDirty && !_subtreeDirty) return false;
    final geometry = screenGeometry();
    return geometry == null || geometry.visible != null;
  }

  void _growFootprint(int l, int t, int r, int b) {
    if (r <= l || b <= t) return;
    if (_subR <= _subL || _subB <= _subT) {
      _subL = l;
      _subT = t;
      _subR = r;
      _subB = b;
      return;
    }
    if (l < _subL) _subL = l;
    if (t < _subT) _subT = t;
    if (r > _subR) _subR = r;
    if (b > _subB) _subB = b;
  }

  /// Adds everything this node's cells occupy — before this frame and after it
  /// — to the damage region, recursing only along the dirty path.
  ///
  /// A self-dirty node contributes both footprints and stops: its whole
  /// subtree is inside that union, so nothing under it can be skipped and
  /// there is nothing more to learn by descending.
  void _collectDamage() {
    // Dirty, or moved. Movement has to be checked at EVERY node, not just
    // along the path of something that was marked, because a node moves
    // without ever being marked and the mark that caused it can be anywhere:
    // a sibling above it grew, or — since geometry is derived globally — an
    // entirely different subtree changed and this node's parent places it
    // relative to that. A float anchored to a widget in another branch moved
    // with the widget while nothing on its own path was ever invalidated, and
    // its cells stayed behind at the old column. The walk is pointer-chasing
    // plus one memoized geometry read per node — the same read the paint walk
    // is about to make, at the same epoch, so it is computed once.
    if (screenGeometry()?.visible == null) {
      // Nothing of THIS node is on screen, so it writes no cells — and a
      // container is free not to paint it at all, which several do (a flex
      // skips a child entirely outside the buffer). It must still GIVE UP the
      // cells it owned before, once: a node that is never painted never
      // clears its own dirty bit, so without this its stale footprint was
      // re-damaged every frame forever — which repainted the enclosing
      // composite on every frame of every app that has one off-screen child.
      //
      // The descent continues below rather than stopping here. A node with no
      // visible rectangle of its own is not a lid on its subtree: a wrapper
      // that sizes to nothing can still lay out a child that paints, and
      // stopping made every change under one invisible to damage.
      if (_subR > _subL) {
        IncrementalPaint._damage.add(_subL, _subT, _subR, _subB);
        _subR = _subL;
        _subB = _subT;
      }
    } else if (_selfDirty ||
        (_lastPaintGeometry != null &&
            screenGeometry() != _lastPaintGeometry)) {
      IncrementalPaint._damage.add(_subL, _subT, _subR, _subB);
      _addPendingFootprint();
      return;
    }
    final self = this;
    if (self is RenderObjectWithChildren) {
      final kids = self.children;
      for (var i = 0; i < kids.length; i++) {
        final child = kids[i];
        if (!presentsChild(child)) continue;
        if (child._paintsThroughComposite) {
          if (child._subtreeChanged()) _compositeDamage();
          return;
        }
        child._collectDamage();
      }
    } else if (self is RenderObjectWithSingleChild) {
      final child = self.child;
      if (child == null || !presentsChild(child)) return;
      if (child._paintsThroughComposite) {
        if (child._subtreeChanged()) _compositeDamage();
        return;
      }
      child._collectDamage();
    }
  }

  /// Whether anything in this subtree is dirty or has moved.
  ///
  /// Asked of a subtree a composite paints into a buffer of its own, where
  /// individual footprints mean nothing — the answer decides only whether the
  /// COMPOSITE's rectangle is damage. Movement counts, and it is why geometry
  /// is recorded for scratch paints too: an anchored float inside a cached
  /// entry follows a widget in a different branch, so it moves with nothing on
  /// its own path ever being marked.
  bool _subtreeChanged() {
    // A node with nothing on screen writes no cells, so its dirt cannot change
    // what the composite blits — and it may legitimately stay dirty forever,
    // never having been painted at all. Its children are still asked, for the
    // same reason the damage walk asks them.
    if (screenGeometry()?.visible == null) {
      if (_subR > _subL) return true;
    } else if (_selfDirty ||
        (_lastPaintGeometry != null &&
            screenGeometry() != _lastPaintGeometry)) {
      return true;
    }
    final self = this;
    if (self is RenderObjectWithChildren) {
      final kids = self.children;
      for (var i = 0; i < kids.length; i++) {
        final child = kids[i];
        if (presentsChild(child) && child._subtreeChanged()) return true;
      }
    } else if (self is RenderObjectWithSingleChild) {
      final child = self.child;
      if (child != null && presentsChild(child) && child._subtreeChanged()) {
        return true;
      }
    }
    return false;
  }

  /// Whether this node's cells reach the screen through an enclosing
  /// composite's blit rather than being written to the screen buffer directly.
  ///
  /// A node that has never painted is NOT one of these — it has no cells
  /// anywhere yet, and the answer for it is that it must paint.
  bool get _paintsThroughComposite =>
      _presentedAtPass >= 0 && !_paintedOnScreen;

  /// Damage for a change UNDER a composite, charged to the composite.
  ///
  /// A node that paints into a scratch buffer has no screen footprint of its
  /// own — its cells reached the screen through this node's blit, at whatever
  /// rectangle this node chose. So when something below changes, the region
  /// that has to be erased is what THIS node covered, not what the changed
  /// node did. Without this, content that shrank inside a cached boundary or
  /// an effect left its longer previous text on screen: the blit is tightened
  /// to the new content, and nothing had claimed the rest.
  void _compositeDamage() {
    IncrementalPaint._damage.add(_subL, _subT, _subR, _subB);
    _addPendingFootprint();
  }

  /// Adds the rect this node's subtree is ABOUT to occupy, read from derived
  /// geometry rather than from paint. Layout has already run, so this is known
  /// before a single cell is written — which is what lets a clean node that
  /// something is about to grow over be forced to repaint.
  void _addPendingFootprint() {
    final visible = screenGeometry()?.visible;
    if (visible != null) {
      IncrementalPaint._damage.add(
        visible.left,
        visible.top,
        visible.right,
        visible.bottom,
      );
    }
    final self = this;
    if (self is RenderObjectWithChildren) {
      final kids = self.children;
      for (var i = 0; i < kids.length; i++) {
        final child = kids[i];
        if (presentsChild(child)) child._addPendingFootprint();
      }
    } else if (self is RenderObjectWithSingleChild) {
      final child = self.child;
      if (child != null && presentsChild(child)) child._addPendingFootprint();
    }
  }

  /// Debug invariant: nothing under a skipped node may be dirty AND own cells.
  /// If this trips, the invalidation walk has a hole and skipping is unsound.
  ///
  /// "And own cells" is the precise form, and it is not a loosening. A skip is
  /// a claim about cells: the ones carried forward are still right. A dirty
  /// node with no visible rectangle writes none, so it cannot falsify that
  /// claim — and such nodes are ordinary, because a container with nothing to
  /// show does not paint its child at all, which leaves the child's mark set
  /// with no way to ever clear it. (A zero-size repaint boundary returns
  /// before touching its cache; a fully clipped row is not reached.) The
  /// descent continues through them regardless: a child can overflow a parent
  /// that has no size of its own.
  String? _debugDirtyDescendant() {
    final self = this;
    final kids = <RenderObject>[
      if (self is RenderObjectWithChildren) ...self.children,
      if (self is RenderObjectWithSingleChild) ?self.child,
    ];
    for (final child in kids) {
      // A subtree its parent does not present — a hidden tab, a clipped-out
      // row — is legitimately dirty and unpainted, and stays that way until it
      // is shown again. It writes no cells, so it cannot make a skip unsound.
      if (!presentsChild(child)) continue;
      if (child._selfDirty && child.screenGeometry()?.visible != null) {
        return '${child.runtimeType}(self)';
      }
      final deeper = child._debugDirtyDescendant();
      if (deeper != null) return '${child.runtimeType} > $deeper';
    }
    return null;
  }

  bool _debugSubtreeIsClean() => _debugDirtyDescendant() == null;

  /// Debug helpers for diagnosing incremental paint. Kept because the one
  /// open divergence (RFC 0026 §8) is diagnosed with them.
  @internal
  bool get debugNeverPainted => _presentedAtPass < 0;

  @internal
  bool get debugIsDirty => _selfDirty;

  @internal
  void debugVisitChildren(void Function(RenderObject) visit) {
    final self = this;
    if (self is RenderObjectWithChildren) {
      for (final c in self.children) {
        visit(c);
      }
    } else if (self is RenderObjectWithSingleChild) {
      final c = self.child;
      if (c != null) visit(c);
    }
  }

  /// Debug: this node's incremental-paint bookkeeping, and its ancestors'.
  @internal
  String debugPaintState() {
    final out = StringBuffer();
    for (RenderObject? n = this; n != null; n = n._parent) {
      out.writeln(
        '  ${n.runtimeType} self=${n._selfDirty} sub=${n._subtreeDirty} '
        'pass=${n._presentedAtPass}/${IncrementalPaint._pass} '
        'onScreen=${n._paintedOnScreen} '
        'presentedByParent=${n._parent?.presentsChild(n)} '
        'geom=${n.screenGeometry() == null ? "NULL" : n.screenGeometry()!.visible} '
        'foot=${n._subL},${n._subT},${n._subR},${n._subB}',
      );
    }
    return out.toString();
  }

  /// Debug: every dirty or never-painted node in the subtree, with state.
  @internal
  List<String> debugDirtyReport([String path = '']) {
    final out = <String>[];
    final self = this;
    final kids = <RenderObject>[
      if (self is RenderObjectWithChildren) ...self.children,
      if (self is RenderObjectWithSingleChild) ?self.child,
    ];
    for (final child in kids) {
      final tag = '$path>${child.runtimeType}';
      if (child._selfDirty || child._presentedAtPass < 0) {
        out.add(
          '$tag self=${child._selfDirty} sub=${child._subtreeDirty} '
          'pass=${child._presentedAtPass} onScreen=${child._paintedOnScreen} '
          'presented=${presentsChild(child)} '
          'vis=${child.screenGeometry()?.visible} '
          'foot=${child._subL},${child._subT},${child._subR},${child._subB}',
        );
      }
      out.addAll(child.debugDirtyReport(tag));
    }
    return out;
  }

  /// Whether this node's cells from the previous frame are still valid where
  /// they sit.
  bool _isSkippable(RenderGeometry? geometry) {
    // Carrying cells forward is a claim about the PREVIOUS frame: they are
    // still on screen where this node left them. That requires being present
    // in the immediately preceding pass, and that pass having been committed.
    //
    // Presence, not paint-at-some-point. A node the parent stopped presenting
    // — an error boundary showing its panel instead of the child, a hidden tab
    // — is unchanged in itself while the cells it once owned were overwritten
    // by whatever took its place. When it comes back it must repaint, and its
    // own dirty bits will never say so.
    final previousPass = IncrementalPaint._pass - 1;
    if (_presentedAtPass != previousPass) return false;
    if (!_paintedOnScreen) return false;
    if (_layoutsDuringPaint) return false;
    if (IncrementalPaint._committedPass != previousPass) return false;
    if (geometry == null || _lastPaintGeometry == null) return false;
    if (geometry != _lastPaintGeometry) return false;
    // Anything inside the damage region was either just erased or is about to
    // be painted over by a node that changed. This one test replaces the
    // per-parent "my children never overlap each other" declaration the first
    // version needed: overlap only matters when one of the overlapping nodes
    // changed, and then it is damage.
    return !IncrementalPaint._damage.intersects(_subL, _subT, _subR, _subB);
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

/// Incremental paint: carry the previous frame forward, erase what changed,
/// and skip every subtree whose cells are still valid where they sit.
///
/// The usual way to skip painting is a per-subtree cache that gets blitted —
/// which costs memory, a placement decision, and a penalty whenever the cache
/// misses. None of that is needed here. The frame loop already keeps the
/// previous frame in the other buffer, so carrying it forward makes it a cache
/// of EVERYTHING; and screen geometry is DERIVED from layout rather than
/// declared by paint, so "did this subtree move" is not something a widget can
/// forget to report. What was missing was only a per-node dirty bit — and the
/// invalidation walk already visits every ancestor, so recording one costs no
/// extra traversal.
///
/// The frame runs in two phases, which is what makes it correct rather than
/// merely fast:
///
///  1. **Damage.** Walk the dirty path only. Every self-dirty node contributes
///     the rect its subtree painted last frame and the rect it is about to
///     occupy — both knowable before any cell is written, because layout has
///     run and geometry is derived. Erase that region once, up front.
///  2. **Paint.** Walk the tree. A node repaints if it is dirty or if its
///     subtree footprint intersects the damage; otherwise it is skipped whole,
///     children included, and the carried cells stand.
///
/// Doing the erasing once, before anything paints, is not a detail. The first
/// version erased per node just before repainting it, and a node that MOVES
/// then wipes its old rect after whatever replaced it has already drawn there
/// — a subtree reparented from the first slot to the second blanked the widget
/// that took its place. There is exactly one instant at which erasing is safe,
/// and it is before the first cell of the frame.
///
/// Phase 1 is also what removes the need for render objects to declare whether
/// their children overlap. Overlap only matters when one of the overlapping
/// nodes changed — and a node that changed is damage, which forces everything
/// it touches to repaint in tree order.
final class IncrementalPaint {
  IncrementalPaint._();

  /// Whether frames may be painted incrementally at all. The frame loop
  /// additionally requires the presenter to accept carried-forward frames
  /// (`FramePresenter.requiresSelfContainedFrames`).
  ///
  /// OFF by default, with one known divergence left. `packages/storybook`
  /// renders a blank preview pane with it on: some subtree there is produced
  /// as a side effect of an ancestor's paint, so skipping that paint skips the
  /// work, and the pane's widgets are never built at all. Disabling skipping
  /// alone restores it; nothing else in the design is implicated, and the
  /// full-repaint verifier over `packages/fleury`'s whole suite finds no
  /// divergence. Until that is understood, the mode is opt-in: this package's
  /// test harness turns it on, so the machinery and its verifier stay
  /// exercised rather than becoming dead code waiting for a flag.
  static bool enabled = false;

  /// Debug mode: after each incremental frame, paint the same tree the old way
  /// into a scratch buffer and require the two agree cell for cell.
  ///
  /// This is the check that makes incremental paint adoptable, and it is the
  /// only one that can see the failure that matters. A skipped subtree writes
  /// nothing, so if its carried cells were stale the buffer still *matches
  /// what was painted* — and frame damage, which is derived by comparing the
  /// two buffers, reports no change. The screen is wrong and every other check
  /// in the pipeline agrees it is right. Repainting the whole tree and
  /// comparing is the only independent authority.
  ///
  /// Off by default (it pays the full repaint the mode exists to avoid); CI
  /// runs the suite once with it on.
  static bool verifyAgainstFullRepaint = false;

  static int _pass = 0;
  static int _committedPass = -1;
  static int _damagePass = -1;
  static final _DamageRegion _damage = _DamageRegion();

  /// The node whose [RenderObject.performPaint] is running, so work triggered
  /// from inside it can be attributed back.
  static RenderObject? _painting;

  static int _observingDepth = 0;

  /// Runs [body] as an OBSERVING repaint: the tree is painted, but none of the
  /// incremental-paint bookkeeping is touched. For verifiers that repaint a
  /// subtree to compare it against what was blitted or carried.
  @internal
  static T observing<T>(T Function() body) {
    _observingDepth += 1;
    try {
      return body();
    } finally {
      _observingDepth -= 1;
    }
  }

  // The subtree footprint being accumulated by the node currently painting.
  static int _accL = 0;
  static int _accT = 0;
  static int _accR = 0;
  static int _accB = 0;

  /// Whether an invalidation was raised after this pass derived its damage —
  /// during paint, or by an end-of-pass participant. Such a frame is correct
  /// as painted and schedules another; it just cannot be compared against a
  /// repaint of the tree as it stands afterwards.
  static bool _dirtiedDuringPass = false;

  /// See [_dirtiedDuringPass].
  @internal
  static bool get dirtiedDuringPass => _dirtiedDuringPass;

  /// Starts a render pass. Called by the frame loop before painting.
  static void beginPass() {
    _pass += 1;
    _dirtiedDuringPass = false;
  }

  /// Marks the current pass as the one the reference buffer now holds. Only
  /// committed passes may be carried forward.
  static void commitPass() => _committedPass = _pass;

  static void _prepareFrame(RenderObject root, CellBuffer buffer) {
    _damagePass = _pass;
    _damage.clear();
    root._collectDamage();
    _damage.eraseInto(buffer);
  }

  static void _growEnclosing(int l, int t, int r, int b) {
    if (r <= l || b <= t) return;
    if (_accR <= _accL || _accB <= _accT) {
      _accL = l;
      _accT = t;
      _accR = r;
      _accB = b;
      return;
    }
    if (l < _accL) _accL = l;
    if (t < _accT) _accT = t;
    if (r > _accR) _accR = r;
    if (b > _accB) _accB = b;
  }

  /// Rects erased at the start of the current frame — diagnostics and tests.
  static List<CellRect> get damageRects => _damage.toRects();

  static int get skippedCount => _skipped;
  static int _skipped = 0;

  static int get paintedCount => _painted;
  static int _painted = 0;

  static void resetCounters() {
    _skipped = 0;
    _painted = 0;
  }
}

/// The set of screen rectangles this frame invalidated.
///
/// A handful of disjoint rects rather than a general region algebra: real
/// frames change a few places, and the cost of being approximate is repainting
/// slightly more than necessary, never showing something stale. Above
/// [_capacity] rects it collapses to their bounding box — a frame with that
/// many separate changes is repainting most of the screen anyway.
final class _DamageRegion {
  static const int _capacity = 32;

  final Int32List _rects = Int32List(_capacity * 4);
  int _count = 0;

  void clear() => _count = 0;

  bool get isEmpty => _count == 0;

  void add(int l, int t, int r, int b) {
    if (r <= l || b <= t) return;
    for (var i = 0; i < _count; i++) {
      final j = i * 4;
      // Merge into a rect this one touches. Adjacency counts, not just
      // overlap: two stacked rows of a column are one region, and keeping
      // them separate only buys a longer list to scan.
      if (l <= _rects[j + 2] &&
          _rects[j] <= r &&
          t <= _rects[j + 3] &&
          _rects[j + 1] <= b) {
        if (l < _rects[j]) _rects[j] = l;
        if (t < _rects[j + 1]) _rects[j + 1] = t;
        if (r > _rects[j + 2]) _rects[j + 2] = r;
        if (b > _rects[j + 3]) _rects[j + 3] = b;
        return;
      }
    }
    if (_count == _capacity) {
      _collapse();
      add(l, t, r, b);
      return;
    }
    final j = _count * 4;
    _rects[j] = l;
    _rects[j + 1] = t;
    _rects[j + 2] = r;
    _rects[j + 3] = b;
    _count += 1;
  }

  void _collapse() {
    for (var i = 1; i < _count; i++) {
      final j = i * 4;
      if (_rects[j] < _rects[0]) _rects[0] = _rects[j];
      if (_rects[j + 1] < _rects[1]) _rects[1] = _rects[j + 1];
      if (_rects[j + 2] > _rects[2]) _rects[2] = _rects[j + 2];
      if (_rects[j + 3] > _rects[3]) _rects[3] = _rects[j + 3];
    }
    _count = 1;
  }

  bool intersects(int l, int t, int r, int b) {
    if (r <= l || b <= t) return false;
    for (var i = 0; i < _count; i++) {
      final j = i * 4;
      if (l < _rects[j + 2] &&
          _rects[j] < r &&
          t < _rects[j + 3] &&
          _rects[j + 1] < b) {
        return true;
      }
    }
    return false;
  }

  void eraseInto(CellBuffer buffer) {
    for (var i = 0; i < _count; i++) {
      final j = i * 4;
      buffer.eraseRect(
        CellRect.fromLTWH(
          _rects[j],
          _rects[j + 1],
          _rects[j + 2] - _rects[j],
          _rects[j + 3] - _rects[j + 1],
        ),
      );
    }
  }

  List<CellRect> toRects() => [
    for (var i = 0; i < _count; i++)
      CellRect.fromLTWH(
        _rects[i * 4],
        _rects[i * 4 + 1],
        _rects[i * 4 + 2] - _rects[i * 4],
        _rects[i * 4 + 3] - _rects[i * 4 + 1],
      ),
  ];
}

/// The first cell at which [incremental] differs from [reference], described
/// for a failure message, or null when the two buffers are identical.
///
/// Used by [IncrementalPaint.verifyAgainstFullRepaint].
@internal
String? describeFirstCellDifference(
  CellBuffer incremental,
  CellBuffer reference,
) {
  if (incremental.size != reference.size) {
    return 'size ${incremental.size} vs ${reference.size}';
  }
  // Placements first, and not as an afterthought: they are the one thing a
  // carried frame can get wrong that comparing cells never reveals, because
  // the cells under an image are payload-free overlays.
  final got = incremental.imagePlacements;
  final want = reference.imagePlacements;
  if (got.length != want.length) {
    return 'image placements: ${got.length} carried, '
        '${want.length} from a full repaint';
  }
  for (var i = 0; i < got.length; i++) {
    if (got[i] != want[i]) {
      return 'image placement $i: carried ${got[i]}, '
          'a full repaint places ${want[i]}';
    }
  }
  for (var row = 0; row < incremental.size.rows; row++) {
    for (var col = 0; col < incremental.size.cols; col++) {
      final got = incremental.atColRow(col, row);
      final want = reference.atColRow(col, row);
      if (got == want) continue;
      return 'at col $col, row $row: carried ${_describeCell(got)}, '
          'a full repaint paints ${_describeCell(want)}';
    }
  }
  return null;
}

String _describeCell(Cell cell) {
  final grapheme = cell.grapheme;
  if (grapheme == null) return cell.role.name;
  final shown = grapheme.codeUnits
      .map(
        (u) => u < 32 || u > 126
            ? 'U+${u.toRadixString(16).toUpperCase().padLeft(4, '0')}'
            : String.fromCharCode(u),
      )
      .join();
  return '${cell.role.name} "$shown" ${cell.style}';
}
