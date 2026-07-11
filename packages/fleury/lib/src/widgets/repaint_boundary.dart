import '../rendering/render_repaint_boundary.dart';
import 'framework.dart';

/// Marks [child]'s subtree as its own paint isolate.
///
/// On frames where nothing inside the boundary has changed, the framework
/// blits the boundary's cached cells into the frame buffer instead of
/// walking the subtree's paint methods — a single bulk copy instead of a
/// recursive paint chain.
///
/// Wrap a subtree whose paint you want isolated from a neighbour's churn (a
/// sidebar beside a live log, a static header above an animating body). Direct
/// use is opt-in, like Flutter's `RepaintBoundary`.
///
/// One place inserts them automatically: [ListView] wraps each item (its
/// `addRepaintBoundaries` flag, on by default), because a list is the canonical
/// "one row changes, the rest don't" shape. Measured on the paint-walk probe, a
/// localized update in an N-row list is ~3x faster even for trivially cheap
/// rows and 6-16x for styled full-width rows — the paint *walk* over N rows
/// costs more than blitting N-1 cached rows regardless of per-row cost. The
/// trade is one reused cache buffer per visible item (bounded by the viewport),
/// which for a TUI is a small, fixed memory cost for a large CPU win.
///
/// The boundary's child paints into the cache the first time, and again
/// whenever a `RenderObjectElement` inside it is reconciled or any render
/// object's child list changes. Stable subtrees (`const` widgets, or
/// instances kept identical across builds) stay cached across many frames.
/// A list row that merely SCROLLS keeps its content and only changes offset, so
/// it cache-hits and blits at the new row — the pruning survives scrolling.
///
/// The one anti-pattern: do NOT combine boundaries with KEYS to "recycle" rows
/// of *changing* content (the keyed-list pattern from DOM frameworks). Keyed
/// boundaries make every moved-and-mutated row a reconciled subtree — each
/// invalidates its cache, so you pay the boundary bookkeeping AND the repaint
/// (measured ~2x slower), and it defeats scroll detection (which turns shifted
/// rows into a single buffer move). ListView's per-item boundaries are
/// deliberately POSITIONAL (unkeyed), which is exactly why they cache-hit on
/// scroll instead of thrashing.
class RepaintBoundary extends SingleChildRenderObjectWidget
    implements WidgetUpdatePruner {
  const RepaintBoundary({super.key, super.child});

  @override
  bool hasEquivalentWidgetConfiguration(Widget other) {
    return other is RepaintBoundary &&
        key == other.key &&
        canSkipNullableWidgetUpdate(child, other.child);
  }

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      RenderRepaintBoundary();
}
