// WireSemanticFramePresenter: the serve binding of the shared semantics
// pipeline. The pipeline hands it the presented tree — coverage fallback
// and retained-leaf updates already applied — and this presenter encodes
// it onto the wire through the sink's snapshot differ (full frame once
// per peer, patches after; an unchanged snapshot sends nothing).

import '../rendering/text_sanitizer.dart' show sanitizeForDisplay;
import '../runtime/remote_surface_sink.dart';
import '../semantics/inspection.dart';
import '../semantics/semantic_presenter.dart';
import '../semantics/semantics.dart';
import '../semantics/semantics_owner.dart';
import 'remote_semantics.dart' show SemanticWireDelta;

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
    _sink.presentSemantics(
      SemanticInspectionSnapshot.fromTree(tree),
      delta: _deltaFrom(update),
    );
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

  /// Maps the owner's per-frame diff (raw node ids) to the wire's changed-set
  /// (sanitized ids — the same transform [SemanticInspectionSnapshot] applies
  /// on construction). `added ∪ updated` are the possibly-changed nodes;
  /// `removed` are dropped. Null when there's no update (the encoder then does
  /// a full flatten). The wire id transform must match the snapshot's exactly,
  /// or the encoder's debug oracle will flag the divergence in tests.
  SemanticWireDelta? _deltaFrom(SemanticTreeUpdate? update) {
    if (update == null) return null;
    final changed = <String>{
      for (final id in update.added) sanitizeForDisplay(id.value),
      for (final id in update.updated) sanitizeForDisplay(id.value),
    };
    final removed = <String>{
      for (final id in update.removed) sanitizeForDisplay(id.value),
    };
    return SemanticWireDelta(changed: changed, removed: removed);
  }

  @override
  Future<void> dispose() async {}
}
