// Anchoring — placement built on the bounds primitive (`bounds.dart`).
//
//   Anchored       the everyday composite: wrap the trigger, hand it the
//                  overlay, flip `visible`. Owns its BoundsNotifier, its
//                  BoundsObserver, and the overlay entry privately — a
//                  BoundsAnchor with the wiring done.
//   AnchoredFloat  the body of a hand-rolled float's OverlayEntry: a
//                  full-slot pointer barrier UNDER a BoundsAnchor, for a
//                  dropdown/menu that manages its own entry lifecycle.
//   BoundsAnchor   (in bounds.dart) the raw float, for cross-tree cases: a
//                  global command opening a flyout on a distant chip, or one
//                  observed widget driving several floats.
//
// Placement is a pair of [Alignment]s: `alignment` names the point on the
// observed bounds, `anchorAlignment` the point on the float glued to it
// (defaulting to the complement — below/left-flush for `bottomLeft`, the
// dropdown). If the float doesn't fit on screen, the PLACEMENT axis flips to
// the mirrored side (below -> above) while the alignment axis only clamps —
// flipping it would silently change the requested look.

import 'align.dart' show Alignment;
import 'basic.dart' show SizedBox, Stack;
import 'bounds.dart';
import 'framework.dart';
import 'overlay.dart';
import 'pointer.dart' show AbsorbPointer, PointerTapCallback;

// ---------------------------------------------------------------------------
// AnchoredFloat
// ---------------------------------------------------------------------------

/// The standard body of a float's [OverlayEntry]: [child] anchored to
/// [notifier]'s observed bounds, sitting on a pointer barrier that covers the
/// whole overlay slot.
///
/// The barrier is the half that is easy to forget, and forgetting it is
/// invisible until someone clicks: an open dropdown paints over the app, but
/// the app's pointer regions are still registered underneath, so a click on
/// the float's backdrop silently fires whatever is painted there. Barrier
/// first, anchored content second — descendants of the float paint later and
/// still win, so its own rows and buttons keep working.
///
/// ```dart
/// OverlayEntry(
///   builder: (_) => AnchoredFloat(
///     notifier: _bounds,
///     onTapOutside: _dismiss,
///     child: _Panel(...),
///   ),
/// )
/// ```
///
/// Use it wherever a float manages its own entry lifecycle (a `Select`, a
/// `Menu`). [Anchored] already owns its entry and is the simpler choice when
/// the float is just "visible or not"; reach for a bare [BoundsAnchor] only
/// for a layer that deliberately lets clicks through — a nested panel over an
/// ancestor float that already put a barrier down, or a passive readout.
class AnchoredFloat extends StatelessWidget {
  const AnchoredFloat({
    super.key,
    required this.notifier,
    this.onTapOutside,
    this.gap = 0,
    this.alignment = Alignment.bottomLeft,
    this.anchorAlignment,
    required this.child,
  });

  /// The observed bounds [child] is placed against.
  final BoundsNotifier notifier;

  /// Called when a tap lands on the barrier — i.e. outside [child]. Leave null
  /// for a float that stays open (the click is still absorbed, just inert).
  final PointerTapCallback? onTapOutside;

  /// Cells of separation along the placement axis.
  final int gap;

  /// The point on the observed bounds [child] attaches to.
  final Alignment alignment;

  /// The point on [child] that meets [alignment]; defaults to
  /// [defaultAnchorAlignment].
  final Alignment? anchorAlignment;

  /// The floating content.
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      AbsorbPointer(onTap: onTapOutside, child: const SizedBox.expand()),
      BoundsAnchor(
        notifier: notifier,
        gap: gap,
        alignment: alignment,
        anchorAlignment: anchorAlignment,
        child: child,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Anchored
// ---------------------------------------------------------------------------

/// Floats [overlay] against [child], declaratively.
///
/// The composite over [BoundsObserver] + [BoundsAnchor]: it owns the
/// [BoundsNotifier],
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
/// Reach past this to [BoundsObserver] + [BoundsAnchor] when the two ends have no
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
  final BoundsNotifier _notifier = BoundsNotifier();
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => BoundsAnchor(
      notifier: _notifier,
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
    return BoundsObserver(notifier: _notifier, child: widget.child);
  }
}
