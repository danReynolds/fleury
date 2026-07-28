// Anchored floats — one root, three grammatical forms, each form a role:
//
//   Anchor      (noun)        marks the FIXED widget floats attach to
//   Anchored    (participle)  the composite: child + overlay, self-contained
//   AnchoredTo  (+ `to`)      the raw floating side; `to` points at `link:`
//
// `Anchored` is the everyday widget: wrap the trigger, hand it the overlay,
// flip `visible`. It owns the [AnchorLink] internally.
//
// The raw pair exists for when the two ends have no common parent (a global
// command opening a flyout on some distant chip, one anchor driving several
// floats): put [Anchor] around the fixed widget, [AnchoredTo] around the
// float — usually inside an [OverlayEntry] — and share an [AnchorLink].
// The link carries the anchor's painted rect and notifies when it moves, so
// a mounted float tracks its anchor across reflows.
//
// Placement is a pair of [Alignment]s: `alignment` names the point on the
// anchor, `anchorAlignment` the point on the float glued to it (defaulting
// to the complement — below/left-flush for `bottomLeft`, the dropdown).
// If the float doesn't fit on screen, the PLACEMENT axis flips to the
// mirrored side (below -> above) while the alignment axis only clamps —
// flipping it would silently change the requested look. Mirrors Flutter's LayerLink/CompositedTransform*, at cell
// resolution, under one vocabulary.

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import 'align.dart' show Alignment;
import 'framework.dart';
import 'overlay.dart';

/// Shared handle linking an [Anchor] to its [AnchoredTo]. The anchor writes
/// its absolute painted [rect] each paint; the follower reads it.
class AnchorLink with ChangeNotifier {
  CellRect? _rect;

  /// The anchor's painted bounds in absolute cell coordinates, or null
  /// before the anchor has painted (or after it leaves the tree).
  ///
  /// Assigning a *different* rect notifies listeners, so an [AnchoredTo] whose
  /// own subtree is clean still repaints when the thing it is pinned to
  /// moves. Without that, a mounted follower keeps its cached paint at the
  /// old position — visible whenever an anchor reflows while a float is
  /// open, and invisible to a whole-tree re-render (which repaints the
  /// follower anyway). Equal rects are dropped, so a static anchor
  /// re-recording the same bounds each paint costs nothing.
  CellRect? get rect => _rect;
  set rect(CellRect? value) {
    if (value == _rect) return;
    _rect = value;
    notifyListeners();
  }
}

/// Records its [child]'s painted rect into [link] — the trigger a
/// [AnchoredTo] positions against (a button, a list row, a text span).
/// Layout-transparent: reports the child's size unchanged.
class Anchor extends SingleChildRenderObjectWidget {
  const Anchor({super.key, required this.link, required Widget super.child});

  final AnchorLink link;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderAnchor(link);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderAnchor renderObject,
  ) {
    renderObject.link = link;
  }
}

/// Records its child's painted rect into an [AnchorLink]; see [Anchor].
class RenderAnchor extends RenderObject implements RenderObjectWithSingleChild {
  RenderAnchor(this._link);

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
    // Screen coordinates: an AnchoredTo positions overlay content from this
    // rect in root/absolute space, so a scratch-local offset would misplace
    // dropdowns anchored inside composited subtrees.
    final bounds = CellRect(offset: screenOffset ?? offset, size: size);
    _link.rect = bounds;
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
  // current link so swapping AnchorLink invalidates once without keeping the
  // old link alive in a cached closure.
  // ignore: prefer_function_declarations_over_variables
  late final RetainedPaintGeometryCallback _replayBounds = (bounds, _) {
    _link.rect = bounds;
  };
}

class AnchoredTo extends SingleChildRenderObjectWidget {
  const AnchoredTo({
    super.key,
    required this.link,
    this.gap = 0,
    this.alignment = Alignment.bottomLeft,
    this.anchorAlignment,
    required Widget super.child,
  });

  final AnchorLink link;

  /// Cells of separation along the placement axis.
  final int gap;

  /// The point on the anchor this layer attaches to.
  final Alignment alignment;

  /// The point on this layer that meets [alignment]; defaults to
  /// [defaultAnchorAlignment].
  final Alignment? anchorAlignment;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderAnchoredTo(link, gap, alignment, anchorAlignment)
        ..startTrackingAnchor();

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderAnchoredTo renderObject,
  ) {
    renderObject
      ..link = link
      ..gap = gap
      ..alignment = alignment
      ..anchorAlignment = anchorAlignment;
  }

  @override
  SingleChildRenderObjectElement createElement() => _AnchoredToElement(this);
}

/// Fills its slot and paints its child at the anchor's rect; see [AnchoredTo].
class RenderAnchoredTo extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderAnchoredTo(
    this._link,
    this._gap,
    this._alignment,
    this._anchorAlignment,
  );

  AnchorLink _link;
  set link(AnchorLink value) {
    if (identical(_link, value)) return;
    _link.removeListener(_onAnchorMoved);
    _link = value;
    if (_listening) _link.addListener(_onAnchorMoved);
    markNeedsLayout();
  }

  bool _listening = false;

  /// Begin observing the anchor. Called when the widget mounts; released by
  /// [stopTrackingAnchor] on unmount so the link — which typically outlives
  /// any one follower — doesn't retain a dead render object.
  void startTrackingAnchor() {
    if (_listening) return;
    _listening = true;
    _link.addListener(_onAnchorMoved);
  }

  /// Stop observing the anchor.
  void stopTrackingAnchor() {
    if (!_listening) return;
    _listening = false;
    _link.removeListener(_onAnchorMoved);
  }

  /// The anchor moved (or first painted): our placement is stale, so the
  /// cached paint has to be redone. Position is resolved in [paint] via
  /// [_placeChild], so this is a visual-only invalidation.
  void _onAnchorMoved() => markNeedsPaintOnly();

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

/// Releases the [RenderAnchoredTo]'s anchor subscription when the widget leaves
/// the tree — the same shape as `_RawTextElement` detaching a Selectable.
class _AnchoredToElement extends SingleChildRenderObjectElement {
  _AnchoredToElement(AnchoredTo super.widget);

  @override
  void unmount() {
    (renderObject as RenderAnchoredTo).stopTrackingAnchor();
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

// ---------------------------------------------------------------------------
// Anchored
// ---------------------------------------------------------------------------

/// Floats [overlay] against [child], declaratively.
///
/// The composite over [Anchor] + [AnchoredTo]: it owns the [AnchorLink],
/// inserts and removes the overlay entry as [visible] flips, and releases it
/// when the widget leaves the tree — the bookkeeping every hand-rolled flyout
/// otherwise repeats (and occasionally leaks).
///
/// ```dart
/// Anchored(
///   visible: _showDetails,
///   alignment: Alignment.bottomLeft,   // below, left edges flush
///   overlay: Container.framed(child: Text('build 2214')),
///   child: Button(label: 'Details', onPressed: _toggle),
/// )
/// ```
///
/// [alignment] names the point on [child]; [anchorAlignment] names the point
/// on [overlay] that meets it, defaulting to [defaultAnchorAlignment].
///
/// Reach past this to [Anchor] + [AnchoredTo] when the two ends have no
/// common parent — a chip in a toolbar with a flyout opened by a global
/// command, or one anchor driving several overlays.
class Anchored extends StatefulWidget {
  const Anchored({
    super.key,
    required this.child,
    required this.overlay,
    this.visible = false,
    this.alignment = Alignment.bottomLeft,
    this.anchorAlignment,
    this.gap = 0,
  });

  /// The widget the overlay is anchored to.
  final Widget child;

  /// The floating content. Built only while [visible].
  final Widget overlay;

  /// Whether the overlay is currently shown.
  final bool visible;

  /// The point on [child] the overlay attaches to.
  final Alignment alignment;

  /// The point on [overlay] that meets [alignment]. Defaults to
  /// [defaultAnchorAlignment] of [alignment].
  final Alignment? anchorAlignment;

  /// Cells of separation along the placement axis.
  final int gap;

  @override
  State<Anchored> createState() => _AnchoredState();
}

class _AnchoredState extends State<Anchored> {
  final AnchorLink _link = AnchorLink();
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => AnchoredTo(
      link: _link,
      alignment: widget.alignment,
      anchorAlignment: widget.anchorAlignment,
      gap: widget.gap,
      child: widget.overlay,
    ),
  );
  late final OverlayMount _mount = OverlayMount(
    entry: _entry,
    overlay: () => Overlay.maybeOf(context),
    mountWhen: () => widget.visible,
  );

  @override
  void didUpdateWidget(covariant Anchored old) {
    super.didUpdateWidget(old);
    // Rebuild the floating content for any config change, and converge
    // mountedness when `visible` flips.
    _entry.markNeedsBuild();
    if (old.visible != widget.visible) _mount.update();
  }

  @override
  void dispose() {
    _mount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _mount.update();
    return Anchor(link: _link, child: widget.child);
  }
}
