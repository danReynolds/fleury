// Derived screen geometry: the position and visibility of a render object,
// computed from layout state instead of recorded during paint. Every
// container declares where it put each child (`RenderObject.childOffsetOf`),
// what it clips (`childClipOf`), and whether it presents the child at all
// (`presentsChild`); `RenderObject.screenGeometry` composes them, memoized
// per invalidation epoch. This file re-exports the types and adds a subtree
// walker for tooling.

import 'render_object.dart';

export 'render_object.dart' show RenderGeometry, ScreenGeometrySource;

/// Every render object in the subtree of [root], in paint order.
Iterable<RenderObject> renderSubtree(RenderObject root) sync* {
  yield root;
  final children = <RenderObject>[];
  root.visitRenderChildren(children.add);
  for (final child in children) {
    yield* renderSubtree(child);
  }
}
