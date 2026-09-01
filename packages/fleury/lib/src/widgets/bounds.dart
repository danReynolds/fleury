// Painted-bounds observation — the primitive.
//
// Three pieces, one reactive pattern:
//
//   BoundsObserver  (widget)  observes its child's painted screen-space
//                             bounds and publishes them
//   BoundsNotifier  (state)   holds the observation — `bounds` and
//                             `visibleBounds` — and notifies on change
//   consumers                 react: `BoundsAnchor` anchors its child to the
//                             bounds the SAME frame (render-tier); any
//                             `ListenableBuilder` rebuilds the NEXT frame
//                             (build-tier, readouts and derived UI)
//
// Anchoring is this primitive's first use case, not its definition — see
// `anchored.dart` for `Anchored` and the alignment placement math. Anything
// that needs to know where a widget landed on screen (an inspector
// highlight, a test, a derived readout) starts here rather than inventing
// another paint-geometry channel.

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import 'align.dart' show Alignment;
import 'framework.dart';

/// The observable: one widget's painted screen-space bounds, live.
///
/// Written by exactly one [BoundsObserver] (debug-asserted); read and
/// listened to by anything. [BoundsAnchor] listens at the render tier and
/// repositions the same frame; a `ListenableBuilder` reacts at the build
/// tier on the following frame.
///
/// Publishing a *different* value notifies listeners, so a consumer whose
/// own subtree is clean still reacts when the observed widget moves.
/// Equal values are dropped, so a static widget re-publishing identical
/// bounds every paint costs one comparison.
class BoundsNotifier with ChangeNotifier {
  CellRect? _bounds;
  CellRect? _visible;
  Object? _writer;

  /// The full painted bounds in absolute cell coordinates — including any
  /// portion scrolled out of view — or null before the widget first paints
  /// and after it leaves the tree.
  CellRect? get bounds => _bounds;

  /// The on-screen portion of [bounds] (its intersection with the clip in
  /// effect when it painted), or null when the widget is fully scrolled or
  /// clipped out of view. [BoundsAnchor] hides while this is null.
  CellRect? get visibleBounds => _visible;

  /// Publishes a new observation. Called by the owning [BoundsObserver];
  /// not intended for app code.
  void publish(CellRect? bounds, {CellRect? clip}) {
    final visible = bounds == null
        ? null
        : (clip == null ? bounds : clip.intersect(bounds));
    if (bounds == _bounds && visible == _visible) return;
    _bounds = bounds;
    _visible = visible;
    notifyListeners();
  }

  /// Debug-enforces the single-writer contract: a notifier observed by two
  /// [BoundsObserver]s would silently carry whichever painted last.
  void claimWriter(Object writer) {
    assert(() {
      if (_writer != null && !identical(_writer, writer)) {
        throw StateError(
          'This BoundsNotifier already has a BoundsObserver. A notifier '
          'carries ONE widget\'s bounds — create one per observed widget.',
        );
      }
      return true;
    }());
    _writer = writer;
  }

  /// Releases the writer claim (observer unmounted or switched notifier).
  void releaseWriter(Object writer) {
    if (identical(_writer, writer)) _writer = null;
  }
}

/// The observer: publishes its child's painted bounds into [notifier]
/// every paint. Layout- and paint-transparent — the child renders unchanged.
class BoundsObserver extends SingleChildRenderObjectWidget {
  const BoundsObserver({
    super.key,
    required this.notifier,
    required Widget super.child,
  });

  /// The notifier this observer publishes into. One observer per notifier
  /// (debug-asserted).
  final BoundsNotifier notifier;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBoundsObserver(notifier);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBoundsObserver renderObject,
  ) {
    renderObject.notifier = notifier;
  }

  @override
  SingleChildRenderObjectElement createElement() =>
      _BoundsObserverElement(this);
}

/// Clears the observation and releases the writer claim when the observer
/// leaves the tree, so a notifier that outlives it reports "unpainted"
/// instead of a stale rect.
class _BoundsObserverElement extends SingleChildRenderObjectElement {
  _BoundsObserverElement(BoundsObserver super.widget);

  @override
  void unmount() {
    // `maybeRenderObject`, not `renderObject`: an element whose inflate threw
    // in `createRenderObject` never got one, and the throwing getter would
    // raise a second, misleading error on top of the first while the tree is
    // already unwinding.
    (maybeRenderObject as RenderBoundsObserver?)?.detachFromBounds();
    super.unmount();
  }
}

/// Publishes its child's painted bounds; see [BoundsObserver].
class RenderBoundsObserver extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderBoundsObserver(this._notifier) {
    _notifier.claimWriter(this);
    _live.add(this);
    if (!_sweepRegistered) {
      _sweepRegistered = true;
      PaintPass.addCloser(_sweepUnpainted);
    }
  }

  // Every observer with a live claim. When a root paint pass ends, one that
  // neither painted nor replayed in it belongs to a subtree that stopped
  // painting while staying mounted — the other IndexedStack tab, a route
  // beneath an opaque one, an Offstage — and its observation is retracted,
  // so a float anchored to it hides instead of hovering over whatever now
  // paints there. Unmount retracts through [detachFromBounds] as before.
  static final Set<RenderBoundsObserver> _live =
      Set<RenderBoundsObserver>.identity();
  static bool _sweepRegistered = false;

  static void _sweepUnpainted(int pass) {
    for (final observer in _live) {
      if (observer._publishedPass != pass) observer._notifier.publish(null);
    }
  }

  /// The [PaintPass] this observer last published in (paint or replay).
  int _publishedPass = -1;

  BoundsNotifier _notifier;
  set notifier(BoundsNotifier value) {
    if (identical(_notifier, value)) return;
    _notifier.publish(null);
    _notifier.releaseWriter(this);
    _notifier = value;
    _notifier.claimWriter(this);
    markNeedsPaintOnly();
  }

  /// Called on unmount: the widget is gone, so the observation is too.
  void detachFromBounds() {
    _live.remove(this);
    _notifier.publish(null);
    _notifier.releaseWriter(this);
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
    // Screen coordinates: a BoundsAnchor places overlay content from this rect
    // in root/absolute space, so a scratch-local offset would misplace floats
    // anchored inside composited subtrees.
    final bounds = CellRect(offset: screenOffset ?? offset, size: size);
    _publishedPass = PaintPass.current;
    _notifier.publish(bounds, clip: clipRect);
    if (RetainedPaintGeometryCapture.isActive) {
      RetainedPaintGeometryCapture.record(
        _replayBounds,
        bounds,
        clipRect: clipRect,
      );
    }
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }

  // Stable callback retained by repaint boundaries. It deliberately reads the
  // current notifier so swapping notifiers invalidates once without keeping
  // the old one alive in a cached closure. The clip rides along so
  // visibleBounds stays truthful under cached paints.
  // ignore: prefer_function_declarations_over_variables
  late final RetainedPaintGeometryCallback _replayBounds = (bounds, clip) {
    _publishedPass = PaintPass.current;
    _notifier.publish(bounds, clip: clip);
  };
}

/// Anchors its [child] to bounds observed elsewhere: it repositions the same
/// frame they move, flips and clamps at the screen edge, and hides entirely
/// while [BoundsNotifier.visibleBounds] is null — so a float never hovers
/// over unrelated content after its target scrolls away.
///
/// This is the raw, render-tier consumer. For the common case — a float next
/// to a trigger in the same subtree — use [Anchored], which is a
/// [BoundsAnchor] with the notifier, observer, and overlay entry pre-wired.
class BoundsAnchor extends SingleChildRenderObjectWidget {
  const BoundsAnchor({
    super.key,
    required this.notifier,
    this.gap = 0,
    this.alignment = Alignment.bottomLeft,
    this.anchorAlignment,
    required Widget super.child,
  });

  /// The observed bounds this follower positions against.
  final BoundsNotifier notifier;

  /// Cells of separation along the placement axis.
  final int gap;

  /// The point on the observed bounds this follower attaches to.
  final Alignment alignment;

  /// The point on this follower that meets [alignment]; defaults to
  /// [defaultAnchorAlignment].
  final Alignment? anchorAlignment;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBoundsAnchor(notifier, gap, alignment, anchorAlignment)
        ..startTracking();

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBoundsAnchor renderObject,
  ) {
    renderObject
      ..notifier = notifier
      ..gap = gap
      ..alignment = alignment
      ..anchorAlignment = anchorAlignment;
  }

  @override
  SingleChildRenderObjectElement createElement() => _BoundsAnchorElement(this);
}

/// Fills its slot and paints its child against the observed bounds; see
/// [BoundsAnchor].
class RenderBoundsAnchor extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderBoundsAnchor(
    this._notifier,
    this._gap,
    this._alignment,
    this._anchorAlignment,
  );

  BoundsNotifier _notifier;
  set notifier(BoundsNotifier value) {
    if (identical(_notifier, value)) return;
    _notifier.removeListener(_onBoundsChanged);
    _notifier = value;
    if (_listening) _notifier.addListener(_onBoundsChanged);
    markNeedsLayout();
  }

  bool _listening = false;

  /// Begin tracking the observed bounds. Called when the widget mounts;
  /// released by [stopTracking] on unmount so the notifier — which typically
  /// outlives any one float — doesn't retain a dead render object.
  void startTracking() {
    if (_listening) return;
    _listening = true;
    _notifier.addListener(_onBoundsChanged);
  }

  /// Stop tracking the observed bounds.
  void stopTracking() {
    if (!_listening) return;
    _listening = false;
    _notifier.removeListener(_onBoundsChanged);
  }

  /// The observed bounds changed (or first arrived): our placement is stale,
  /// so the cached paint has to be redone. Position is resolved in [paint]
  /// via [_placeChild], so this is a visual-only invalidation.
  void _onBoundsChanged() => markNeedsPaintOnly();

  int _gap;
  set gap(int value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  Alignment _alignment;
  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsPaintOnly();
  }

  Alignment? _anchorAlignment;
  set anchorAlignment(Alignment? value) {
    if (_anchorAlignment == value) return;
    _anchorAlignment = value;
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
    // Bounds fully scrolled or clipped out of view: nothing to anchor to —
    // hide rather than float over unrelated content.
    if (_notifier.visibleBounds == null) return;
    // Resolve placement at paint time: the observer publishes during its own
    // paint, which runs before this float's (in-flow content paints below the
    // overlay), so we read the current frame's bounds.
    //
    // PAINT ORDER: that ordering is what makes tracking same-frame. A
    // BoundsAnchor painted BEFORE its observed widget (e.g. earlier in a
    // plain Stack) reads the previous frame's bounds and converges one frame
    // later — correct, just delayed. Overlays paint last, so the usual case
    // is always current.
    final placement = _placeChild(c.size);
    _child!.paint(
      buffer,
      offset + placement,
      screenOffset: (screenOffset ?? offset) + placement,
      clipRect: clipRect,
    );
  }

  CellOffset _placeChild(CellSize childSize) {
    final r = _notifier.bounds;
    if (r == null) return CellOffset.zero;
    // Gap pushes the layer away along whichever axis it sits outside on.
    final gapped = _gap == 0
        ? r
        : CellRect(
            offset: CellOffset(r.offset.col - _gap, r.offset.row - _gap),
            size: CellSize(r.size.cols + _gap * 2, r.size.rows + _gap * 2),
          );
    return resolveAnchoredOffset(
      anchor: gapped,
      overlaySize: childSize,
      alignment: _alignment,
      anchorAlignment: _anchorAlignment ?? defaultAnchorAlignment(_alignment),
      w: size.cols,
      h: size.rows,
    );
  }
}

/// Releases the [RenderBoundsAnchor]'s anchor subscription when the widget leaves
/// the tree — the same shape as `_RawTextElement` detaching a Selectable.
class _BoundsAnchorElement extends SingleChildRenderObjectElement {
  _BoundsAnchorElement(BoundsAnchor super.widget);

  @override
  void unmount() {
    (renderObject as RenderBoundsAnchor).stopTracking();
    super.unmount();
  }
}

// ---------------------------------------------------------------------------
// Alignment-based placement
// ---------------------------------------------------------------------------

/// The point on the overlay that meets [alignment] when none is given.
///
/// Flips the named edge to the opposite one, keeping the perpendicular axis
/// aligned — so the overlay lands *outside* the anchor on one axis and stays
/// edge-aligned on the other. Corners flip vertically, the dropdown
/// convention: `bottomLeft` puts the overlay below, left edges flush.
///
///   bottomLeft  → topLeft      below, left-aligned   (dropdowns, menus)
///   bottomCenter→ topCenter    directly below, centred
///   centerRight → centerLeft   to the right, vertically centred
///   center      → center       centred over the anchor
///
/// Pass `anchorAlignment` explicitly for a mixed pairing the flip can't
/// express, e.g. a submenu that sits to the right with its top edge flush:
/// `alignment: .topRight, anchorAlignment: .topLeft`.
Alignment defaultAnchorAlignment(Alignment alignment) => switch (alignment) {
  Alignment.topLeft => Alignment.bottomLeft,
  Alignment.topCenter => Alignment.bottomCenter,
  Alignment.topRight => Alignment.bottomRight,
  Alignment.centerLeft => Alignment.centerRight,
  Alignment.center => Alignment.center,
  Alignment.centerRight => Alignment.centerLeft,
  Alignment.bottomLeft => Alignment.topLeft,
  Alignment.bottomCenter => Alignment.topCenter,
  Alignment.bottomRight => Alignment.topRight,
};

/// The cell offset of [alignment] within a box of [size] whose origin is
/// [origin]. Right/bottom edges are exclusive, so `topRight` is the cell just
/// past the last column — where a neighbouring box's left edge begins.
CellOffset _pointIn(CellOffset origin, CellSize size, Alignment alignment) {
  final left = origin.col;
  final top = origin.row;
  final midX = left + size.cols ~/ 2;
  final midY = top + size.rows ~/ 2;
  final right = left + size.cols;
  final bottom = top + size.rows;
  return switch (alignment) {
    Alignment.topLeft => CellOffset(left, top),
    Alignment.topCenter => CellOffset(midX, top),
    Alignment.topRight => CellOffset(right, top),
    Alignment.centerLeft => CellOffset(left, midY),
    Alignment.center => CellOffset(midX, midY),
    Alignment.centerRight => CellOffset(right, midY),
    Alignment.bottomLeft => CellOffset(left, bottom),
    Alignment.bottomCenter => CellOffset(midX, bottom),
    Alignment.bottomRight => CellOffset(right, bottom),
  };
}

/// Vertical band of [a]: 0 top, 1 centre, 2 bottom.
int _vBand(Alignment a) => switch (a) {
  Alignment.topLeft || Alignment.topCenter || Alignment.topRight => 0,
  Alignment.centerLeft || Alignment.center || Alignment.centerRight => 1,
  _ => 2,
};

/// Horizontal band of [a]: 0 left, 1 centre, 2 right.
int _hBand(Alignment a) => switch (a) {
  Alignment.topLeft || Alignment.centerLeft || Alignment.bottomLeft => 0,
  Alignment.topCenter || Alignment.center || Alignment.bottomCenter => 1,
  _ => 2,
};

/// Mirrors [a] top<->bottom, leaving a centred row alone.
Alignment _mirrorVertical(Alignment a) => switch (a) {
  Alignment.topLeft => Alignment.bottomLeft,
  Alignment.topCenter => Alignment.bottomCenter,
  Alignment.topRight => Alignment.bottomRight,
  Alignment.bottomLeft => Alignment.topLeft,
  Alignment.bottomCenter => Alignment.topCenter,
  Alignment.bottomRight => Alignment.topRight,
  _ => a,
};

/// Mirrors [a] left<->right, leaving a centred column alone.
Alignment _mirrorHorizontal(Alignment a) => switch (a) {
  Alignment.topLeft => Alignment.topRight,
  Alignment.centerLeft => Alignment.centerRight,
  Alignment.bottomLeft => Alignment.bottomRight,
  Alignment.topRight => Alignment.topLeft,
  Alignment.centerRight => Alignment.centerLeft,
  Alignment.bottomRight => Alignment.bottomLeft,
  _ => a,
};

CellOffset _rawOffset(
  CellRect anchor,
  CellSize overlaySize,
  Alignment alignment,
  Alignment anchorAlignment,
) {
  final target = _pointIn(anchor.offset, anchor.size, alignment);
  final own = _pointIn(CellOffset.zero, overlaySize, anchorAlignment);
  return CellOffset(target.col - own.col, target.row - own.row);
}

/// Places a box of [overlaySize] so its [anchorAlignment] point meets
/// [alignment] on [anchor].
///
/// When the result would run off an edge, the pair is MIRRORED on that axis
/// and retried — the flip that keeps a dropdown on screen by opening upward
/// near the bottom, or a submenu leftward near the right edge. Both points
/// mirror together, so the overlay stays outside the anchor rather than
/// sliding across it. Whatever survives is clamped into `w x h` as a floor.
CellOffset resolveAnchoredOffset({
  required CellRect anchor,
  required CellSize overlaySize,
  required Alignment alignment,
  required Alignment anchorAlignment,
  required int w,
  required int h,
}) {
  var a = alignment;
  var oa = anchorAlignment;
  var at = _rawOffset(anchor, overlaySize, a, oa);

  // Only the PLACEMENT axis flips — the one whose bands differ, i.e. the axis
  // the overlay sits outside the anchor on. The perpendicular axis is an
  // alignment (which edges line up), and mirroring that would silently change
  // the requested look, so it clamps instead. For `bottomLeft` that means
  // "open upward if it doesn't fit below, but stay left-aligned".
  final flipsVertically = _vBand(a) != _vBand(oa);
  final flipsHorizontally = _hBand(a) != _hBand(oa);

  // Vertical flip when it overflows and the mirror fits.
  if (flipsVertically && (at.row < 0 || at.row + overlaySize.rows > h)) {
    final flipped = _rawOffset(
      anchor,
      overlaySize,
      _mirrorVertical(a),
      _mirrorVertical(oa),
    );
    if (flipped.row >= 0 && flipped.row + overlaySize.rows <= h) {
      a = _mirrorVertical(a);
      oa = _mirrorVertical(oa);
      at = flipped;
    }
  }
  // Horizontal flip, same rule.
  if (flipsHorizontally && (at.col < 0 || at.col + overlaySize.cols > w)) {
    final flipped = _rawOffset(
      anchor,
      overlaySize,
      _mirrorHorizontal(a),
      _mirrorHorizontal(oa),
    );
    if (flipped.col >= 0 && flipped.col + overlaySize.cols <= w) {
      at = flipped;
    }
  }

  var left = at.col;
  var top = at.row;
  if (left + overlaySize.cols > w) left = w - overlaySize.cols;
  if (top + overlaySize.rows > h) top = h - overlaySize.rows;
  if (left < 0) left = 0;
  if (top < 0) top = 0;
  return CellOffset(left, top);
}
