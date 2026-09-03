import 'package:fleury/fleury.dart';
// The phase enum is render-tier internal; reached like other internals.
import 'package:fleury/src/rendering/render_object.dart' show RenderFramePhase;
import 'package:test/test.dart';

/// A leaf whose layout throws: the frame dies in the layout phase.
class _Boom extends LeafRenderObjectWidget {
  const _Boom();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBoom();
}

class _RenderBoom extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) =>
      throw StateError('layout failed on purpose');

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {}
}

void main() {
  test('a frame that throws in layout leaves the damage tracker idle', () {
    // The phase used to be restored only by the finally around paint. A
    // throw in build or layout (a rebuild storm, an initState error, a
    // layout assertion) left it stuck, and a stuck phase absorbs every later
    // invalidation — the render tier could never ask for a frame again.
    final owner = BuildOwner();
    final root = owner.mountRoot(const _Boom());
    final buffer = CellBuffer(const CellSize(10, 2));
    expect(() => owner.renderFrame(root, buffer), throwsStateError);
    expect(owner.renderDamageTracker.phase, RenderFramePhase.idle);
  });
}
