import '../rendering/render_repaint_boundary.dart';
import 'framework.dart';

/// Marks [child]'s subtree as its own paint isolate.
///
/// On frames where nothing inside the boundary has changed, the framework
/// blits the boundary's cached cells into the frame buffer instead of
/// walking the subtree's paint methods — a single bulk copy instead of a
/// recursive paint chain.
///
/// Wrap subtrees that are expensive to paint and change rarely (a sidebar,
/// a static header, a backdrop). It's opt-in, just like Flutter's
/// `RepaintBoundary` — the framework doesn't insert these automatically.
///
/// The boundary's child paints into the cache the first time, and again
/// whenever a `RenderObjectElement` inside it is reconciled or any render
/// object's child list changes. Stable subtrees (`const` widgets, or
/// instances kept identical across builds) stay cached across many frames.
///
/// Do NOT combine boundaries with keys to "recycle" rows of moving
/// content (the keyed-list pattern from DOM frameworks). When content
/// scrolls or shifts, keyed boundaries make every moved row a reconciled
/// subtree — each one invalidates its cache, so the framework pays the
/// boundary bookkeeping AND the repaint. Measured on the scroll
/// benchmarks, that is about 2x slower than letting positional rebuild
/// repaint the rows, and it also defeats scroll detection (which turns
/// shifted rows into a single buffer move). Boundaries are for content
/// that is expensive and STAYS PUT; moving content is exactly what the
/// damage tracker and scroll reuse already handle.
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
