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
/// The [builder] runs during the layout pass (and the whole tree lays out
/// every frame), so it always sees current constraints. Reading an
/// inherited widget (e.g. [MediaQuery]) inside it works and re-runs when
/// that ancestor changes.
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
    renderObject.markNeedsLayout();
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
    // so marking the spine dirty is sufficient. Guard on !dirty: a repeat
    // invalidation before the flush (several inherited deps notifying
    // together) would otherwise re-walk the spine to the root each time,
    // though the first mark already dirtied it. `mounted` covers the window
    // before mount / after unmount, where super.markNeedsBuild no-ops anyway.
    if (mounted && !dirty) _ro.markNeedsLayout();
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
    _child = updateChild(_child, widget.builder(this, constraints));
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
class RenderLayoutBuilder extends RenderObject
    implements RenderObjectWithSingleChild {
  void Function(CellConstraints)? _callback;
  set callback(void Function(CellConstraints)? value) {
    if (identical(_callback, value)) return;
    _callback = value;
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
    _callback?.call(
      constraints,
    ); // builds/updates the child for these constraints
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
