import 'package:fleury/fleury_host.dart';

typedef SemanticActionRequestHandler =
    void Function(SemanticNodeId id, SemanticAction action);

/// Presents a Fleury semantic snapshot to a host-owned accessibility surface.
///
/// The presenter contract intentionally consumes [SemanticTree], not the
/// current element-walk producer. That keeps the browser host boundary stable
/// when Phase 4 replaces full snapshots with a retained semantics owner.
abstract interface class SemanticFramePresenter {
  /// Presents the current semantic tree for the just-rendered frame.
  SemanticPresentationStats present(
    SemanticTree tree, {
    SemanticTreeUpdate? update,
  });

  /// Releases host resources owned by this presenter.
  Future<void> dispose();
}

/// Optional presenter contract for host-routed semantic action requests.
abstract interface class SemanticActionRequestSink {
  set onSemanticActionRequest(SemanticActionRequestHandler? handler);
}

/// Count data reported by a semantic presenter after one presentation.
final class SemanticPresentationStats {
  const SemanticPresentationStats({
    required this.nodeCount,
    required this.addedNodeCount,
    required this.removedNodeCount,
    required this.updatedNodeCount,
    required this.createdElementCount,
    required this.reusedElementCount,
    required this.replacedElementCount,
    required this.attributesSetCount,
    required this.attributesRemovedCount,
  });

  static const none = SemanticPresentationStats(
    nodeCount: 0,
    addedNodeCount: 0,
    removedNodeCount: 0,
    updatedNodeCount: 0,
    createdElementCount: 0,
    reusedElementCount: 0,
    replacedElementCount: 0,
    attributesSetCount: 0,
    attributesRemovedCount: 0,
  );

  factory SemanticPresentationStats.retained({required int nodeCount}) {
    return SemanticPresentationStats(
      nodeCount: nodeCount,
      addedNodeCount: 0,
      removedNodeCount: 0,
      updatedNodeCount: 0,
      createdElementCount: 0,
      reusedElementCount: 0,
      replacedElementCount: 0,
      attributesSetCount: 0,
      attributesRemovedCount: 0,
    );
  }

  final int nodeCount;
  final int addedNodeCount;
  final int removedNodeCount;
  final int updatedNodeCount;
  final int createdElementCount;
  final int reusedElementCount;
  final int replacedElementCount;
  final int attributesSetCount;
  final int attributesRemovedCount;
}
