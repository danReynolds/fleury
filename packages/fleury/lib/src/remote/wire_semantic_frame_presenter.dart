// WireSemanticFramePresenter: the serve binding of the shared semantics
// pipeline. The pipeline hands it the presented tree — coverage fallback
// and retained-leaf updates already applied — and this presenter encodes
// it onto the wire through the sink's snapshot differ (full frame once
// per peer, patches after; an unchanged snapshot sends nothing).

import '../runtime/remote_surface_sink.dart';
import '../semantics/inspection.dart';
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
    _sink.presentSemantics(SemanticInspectionSnapshot.fromTree(tree));
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
