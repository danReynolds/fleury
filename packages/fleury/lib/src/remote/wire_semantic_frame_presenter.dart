// WireSemanticFramePresenter: the serve binding of the shared semantics
// pipeline. The pipeline hands it the presented tree — coverage fallback and
// retained-leaf updates already applied — and it forwards the tree plus the
// owner's per-frame diff to the sink's encoder, which redacts and serializes
// only the changed nodes onto the wire (full frame once per peer, patches
// after; an unchanged tree sends nothing). No full snapshot is built per frame.

import '../runtime/remote_surface_sink.dart';
import '../semantics/semantic_presenter.dart';
import '../semantics/semantics.dart';
import '../semantics/semantics_owner.dart';

/// Presents semantic trees as [SemanticsFrame]s through a
/// [RemoteSurfaceSink].
final class WireSemanticFramePresenter implements SemanticFramePresenter {
  WireSemanticFramePresenter(this._sink);

  final RemoteSurfaceSink _sink;

  @override
  SemanticPresentationStats present(
    SemanticTree tree, {
    SemanticTreeUpdate? update,
  }) {
    // Forward the live tree + the owner's diff; the sink's encoder redacts and
    // serializes only the changed nodes on demand — no full inspection snapshot
    // is rebuilt per semantically-dirty frame.
    _sink.presentSemantics(tree, update: update);
    return SemanticPresentationStats(
      nodeCount: tree.nodeCount,
      addedNodeCount: update?.added.length ?? 0,
      removedNodeCount: update?.removed.length ?? 0,
      updatedNodeCount: update?.updated.length ?? 0,
      createdElementCount: 0,
      reusedElementCount: 0,
      replacedElementCount: 0,
      attributesSetCount: 0,
      attributesRemovedCount: 0,
    );
  }

  @override
  Future<void> dispose() async {}
}
