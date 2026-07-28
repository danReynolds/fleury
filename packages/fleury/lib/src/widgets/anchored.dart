// Anchoring — placement built on the bounds primitive (`bounds.dart`).
//
//   Anchored      the everyday composite: wrap the trigger, hand it the
//                 overlay, flip `visible`. Owns its BoundsNotifier, its
//                 BoundsObserver, and the overlay entry privately — a
//                 BoundsAnchor with the wiring done.
//   BoundsAnchor  (in bounds.dart) the raw float, for cross-tree cases: a
//                 global command opening a flyout on a distant chip, or one
//                 observed widget driving several floats.
//
// Placement is a pair of [Alignment]s: `alignment` names the point on the
// observed bounds, `anchorAlignment` the point on the float glued to it
// (defaulting to the complement — below/left-flush for `bottomLeft`, the
// dropdown). If the float doesn't fit on screen, the PLACEMENT axis flips to
// the mirrored side (below -> above) while the alignment axis only clamps —
// flipping it would silently change the requested look.

import 'align.dart' show Alignment;
import 'bounds.dart';
import 'framework.dart';
import 'overlay.dart';

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
