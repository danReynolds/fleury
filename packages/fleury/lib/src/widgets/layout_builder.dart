import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import 'framework.dart';

/// Builds a subtree from the [CellConstraints] its parent gives it.
typedef LayoutWidgetBuilder =
    Widget Function(BuildContext context, CellConstraints constraints);

/// Builds its child from the constraints it actually receives, so layout
/// can adapt to the available space — a sidebar that collapses below a
/// width, a list that switches to a grid when wide, etc.
///
/// The [builder] runs during the layout pass, so it always sees current
/// constraints — but NOT on every pass: it re-runs only when the incoming
/// constraints change or the element was invalidated (a parent rebuild
/// delivering a new widget, an inherited dependency changing, a setState
/// above). Reading an inherited widget (e.g. [MediaQuery]) inside it works
/// and re-runs when that ancestor changes. The memoization matters: layout
/// re-enters from the root every frame that renders, and an
/// unconditionally re-run builder re-instantiates its subtree per frame —
/// if that subtree isn't identity-stable, each re-run produces damage that
/// schedules the next frame, a self-sustaining rebuild loop.
class LayoutBuilder extends RenderObjectWidget {
  const LayoutBuilder({super.key, required this.builder});

  final LayoutWidgetBuilder builder;

  @override
  RenderObjectElement createElement() => _LayoutBuilderElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderLayoutBuilder();

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderLayoutBuilder renderObject,
  ) {
    // A new widget means a new builder closure (fresh captured state) —
    // the memoized child is stale even under identical constraints.
    renderObject.invalidateBuilder();
  }
}

class _LayoutBuilderElement extends RenderObjectElement {
  _LayoutBuilderElement(LayoutBuilder super.widget);

  Element? _child;

  @override
  LayoutBuilder get widget => super.widget as LayoutBuilder;

  RenderLayoutBuilder get _ro => renderObject as RenderLayoutBuilder;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    _ro.callback = _buildChild;
  }

  @override
  void markNeedsBuild() {
    // The builder only runs inside performLayout, and the layout pass
    // short-circuits a node whose constraints are unchanged — so an
    // element-level invalidation (an InheritedWidget dependency firing, a
    // setState-driven parent rebuild reaching us) must force a relayout or
    // the builder never re-runs and the subtree goes stale. Flutter's
    // equivalent is scheduleLayoutCallback() = markNeedsLayout() +
    // owner-registration; Fleury re-enters layout from the root every frame,
    // so marking the spine dirty is sufficient. invalidateBuilder both marks
    // needs-layout and flags the memoized child stale — the builder re-runs
    // on the pass that flushes this even under identical constraints. Mark
    // it unconditionally on every invalidation: `dirty` (an element-build
    // flag) and the render object's needs-layout are independent states, so
    // gating on `!dirty` could drop a relayout if the two ever diverge (a
    // mid-build geometry read, a manual render between marks). `mounted`
    // covers the window before mount / after unmount, where there is no
    // valid render object to reach.
    if (mounted) _ro.invalidateBuilder();
    super.markNeedsBuild();
  }

  @override
  void performRebuild() {
    // The child depends on constraints unknown until layout, so it's
    // (re)built from [_buildChild] during the render object's layout, not
    // here. markNeedsBuild forces the accompanying relayout, so a changed
    // builder or dependency is reflected on the frame that flushes it.
  }

  // Invoked by RenderLayoutBuilder.performLayout with the live constraints.
  void _buildChild(CellConstraints constraints) {
    // Run the builder with this element as the active build target (as
    // ComponentElement.performRebuild does) so ElementDependency sources
    // (e.g. Animation.value) read inside it auto-subscribe this element —
    // their notifications then invalidate the memoized child. Without this,
    // a listenable read in a layout-time builder never registers anywhere
    // and the memo would freeze it. Restored before updateChild so children
    // attribute their own reads.
    final built = runWithBuildTarget(() => widget.builder(this, constraints));
    _child = updateChild(_child, built);
  }

  @override
  void forgetChild(Element child) {
    // A GlobalKey reclaim of the built child must clear our reference, or
    // the next builder run would updateChild() an element that is now
    // active under another parent (double-adopt / subtree theft).
    if (identical(_child, child)) _child = null;
    super.forgetChild(child);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    final c = _child;
    if (c != null) visitor(c);
  }

  @override
  void insertChildRenderObject(
    RenderObject child,
    RenderObjectElement element,
  ) {
    _ro.child = child;
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    if (identical(_ro.child, child)) _ro.child = null;
  }
}

/// Render object behind [LayoutBuilder]: runs the element's build callback
/// with the incoming constraints, then lays out and paints the resulting
/// child. Layout-transparent (sizes to the child).
///
/// The callback is memoized on the constraints it last built for: a layout
/// pass reaching this node re-invokes it only when the constraints differ
/// or [invalidateBuilder] flagged the built child stale (element
/// invalidation / a new widget). Layout itself still recurses into the
/// child every pass — only the BUILD is skipped.
class RenderLayoutBuilder extends RenderObject
    implements RenderObjectWithSingleChild {
  void Function(CellConstraints)? _callback;
  set callback(void Function(CellConstraints)? value) {
    if (identical(_callback, value)) return;
    _callback = value;
    invalidateBuilder();
  }

  /// Constraints the current child subtree was built for; null before the
  /// first build.
  CellConstraints? _builtFor;

  /// Whether the built child is stale regardless of constraints (element
  /// invalidated, new builder closure, callback swapped).
  bool _builderStale = true;

  /// Flags the built child stale and schedules the relayout that rebuilds
  /// it. Called by the element on invalidation and by the widget on update.
  void invalidateBuilder() {
    _builderStale = true;
    markNeedsLayout();
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
    // Build/update the child only when it's stale for these constraints —
    // an ancestor-driven relayout with unchanged constraints and a clean
    // element reuses the built subtree as-is. The stale flag is cleared
    // BEFORE the callback so an invalidation fired re-entrantly from within
    // the build itself survives (it re-sets the flag; the loop re-runs the
    // builder before this pass finishes — the re-entrant markNeedsLayout
    // alone would be wiped by layout()'s epilogue and the rebuild deferred
    // indefinitely). A throwing builder restores the flag so the next pass
    // retries instead of serving a half-built child. The attempt cap only
    // guards a builder that unconditionally self-invalidates: the flag
    // stays set, and the rebuild lands on the next natural pass rather
    // than spinning this one.
    var attempts = 0;
    while ((_builderStale || constraints != _builtFor) && attempts < 3) {
      attempts++;
      _builderStale = false;
      _builtFor = constraints;
      try {
        _callback?.call(constraints);
      } catch (_) {
        _builderStale = true;
        rethrow;
      }
    }
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    final size = c.layout(constraints);
    assert(() {
      // A width/height-keyed builder under an unbounded axis silently
      // computes zero (`constraints.maxCols ?? 0`) and blanks the subtree —
      // where Flutter's `infinity` would fail loudly downstream, Fleury's
      // null-as-unbounded just vanishes. Make it diagnosable in dev. Gated on
      // "zero on the unbounded axis but non-zero on the other" so an
      // intentionally empty child (0x0) doesn't trip it.
      // Fire only when the child CHOSE the non-zero cross extent
      // (size > the parent-imposed minimum): a stretch Row/Column or a
      // ScrollView forces min on the cross axis, which would otherwise make
      // a deliberately empty child (0 on the unbounded axis) look collapsed.
      final collapsedCols =
          constraints.maxCols == null &&
          size.cols == 0 &&
          size.rows > 0 &&
          size.rows > constraints.minRows;
      final collapsedRows =
          constraints.maxRows == null &&
          size.rows == 0 &&
          size.cols > 0 &&
          size.cols > constraints.minCols;
      if (collapsedCols || collapsedRows) {
        throw StateError(
          'LayoutBuilder collapsed to zero ${collapsedCols ? 'width' : 'height'} '
          'under an unbounded ${collapsedCols ? 'maxCols' : 'maxRows'} '
          '(an inflexible Row/Column child gets an unbounded main axis). '
          'A builder keyed off that axis (e.g. `constraints.maxCols ?? 0`) '
          'computes 0 here. Bound the axis instead: wrap the LayoutBuilder '
          'in Expanded/SizedBox, or size the child to its content.',
        );
      }
      return true;
    }());
    return size;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}
