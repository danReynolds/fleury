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
  void performRebuild() {
    // The child depends on constraints unknown until layout, so it's
    // (re)built from [_buildChild] during the render object's layout, not
    // here. Layout runs every frame, so a changed builder or dependency
    // is reflected on the next frame.
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
    return c.layout(constraints);
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
