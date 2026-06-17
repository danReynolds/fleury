import 'semantics.dart';

/// Retains the last semantic snapshot and reports node-level changes.
///
/// The current producer can still be `SemanticTree.fromElement`, but callers
/// that route snapshots through this owner get the same incremental update
/// shape a future retained semantics pipeline can produce directly.
final class SemanticsOwner {
  SemanticTree? _currentTree;
  Map<SemanticNodeId, SemanticNode> _currentNodes =
      const <SemanticNodeId, SemanticNode>{};

  /// The most recent tree passed to [update], or null before the first update.
  SemanticTree? get currentTree => _currentTree;

  /// Updates the retained tree and returns the semantic node ids that changed.
  SemanticTreeUpdate update(SemanticTree next) {
    final previous = _currentTree;
    final previousNodes = _currentNodes;
    final update = SemanticTreeUpdate._diffFromNextNodes(
      previous: previous,
      next: next,
      previousNodes: previousNodes,
    );
    _currentTree = next;
    _currentNodes = update.nextNodesById;
    return update;
  }

  /// Updates the retained tree from known node replacements.
  ///
  /// Returns null when the owner cannot prove the replacement is incremental,
  /// which tells callers to run the normal full-tree [update] path instead.
  SemanticTreeUpdate? updateRetainedNodes({
    required SemanticTree next,
    required Map<SemanticNodeId, SemanticNode> replacements,
  }) {
    final previous = _currentTree;
    if (previous == null) return null;
    if (replacements.isEmpty) {
      final update = SemanticTreeUpdate._(
        previous: previous,
        next: next,
        previousNodesById: _currentNodes,
        nextNodesById: _currentNodes,
        added: const <SemanticNodeId>{},
        removed: const <SemanticNodeId>{},
        updated: const <SemanticNodeId>{},
      );
      _currentTree = next;
      return update;
    }

    final previousNodes = _currentNodes;
    for (final id in replacements.keys) {
      if (!previousNodes.containsKey(id)) return null;
    }

    final nextNodes = Map<SemanticNodeId, SemanticNode>.of(previousNodes);
    final updated = <SemanticNodeId>{};
    for (final entry in replacements.entries) {
      final previousNode = previousNodes[entry.key];
      if (previousNode == null) return null;
      final nextNode = entry.value;
      nextNodes[entry.key] = nextNode;
      if (!_semanticNodeEquals(previousNode, nextNode)) {
        updated.add(entry.key);
      }
    }

    final update = SemanticTreeUpdate._(
      previous: previous,
      next: next,
      previousNodesById: previousNodes,
      nextNodesById: nextNodes,
      added: const <SemanticNodeId>{},
      removed: const <SemanticNodeId>{},
      updated: updated,
    );
    _currentTree = next;
    _currentNodes = update.nextNodesById;
    return update;
  }

  /// Clears retained semantic state.
  void dispose() {
    _currentTree = null;
    _currentNodes = const <SemanticNodeId, SemanticNode>{};
  }
}

/// Node-level delta between two semantic tree snapshots.
final class SemanticTreeUpdate {
  SemanticTreeUpdate._({
    required this.previous,
    required this.next,
    required Map<SemanticNodeId, SemanticNode> previousNodesById,
    required Map<SemanticNodeId, SemanticNode> nextNodesById,
    required Set<SemanticNodeId> added,
    required Set<SemanticNodeId> removed,
    required Set<SemanticNodeId> updated,
  }) : previousNodesById = Map<SemanticNodeId, SemanticNode>.unmodifiable(
         previousNodesById,
       ),
       nextNodesById = Map<SemanticNodeId, SemanticNode>.unmodifiable(
         nextNodesById,
       ),
       added = Set<SemanticNodeId>.unmodifiable(added),
       removed = Set<SemanticNodeId>.unmodifiable(removed),
       updated = Set<SemanticNodeId>.unmodifiable(updated);

  factory SemanticTreeUpdate.diff({
    required SemanticTree? previous,
    required SemanticTree next,
  }) {
    final previousNodes = previous == null
        ? const <SemanticNodeId, SemanticNode>{}
        : previous.nodesById;
    final nextNodes = next.nodesById;
    return SemanticTreeUpdate._diffFromNodeMaps(
      previous: previous,
      next: next,
      previousNodes: previousNodes,
      nextNodes: nextNodes,
    );
  }

  factory SemanticTreeUpdate._diffFromNodeMaps({
    required SemanticTree? previous,
    required SemanticTree next,
    required Map<SemanticNodeId, SemanticNode> previousNodes,
    required Map<SemanticNodeId, SemanticNode> nextNodes,
  }) {
    final added = <SemanticNodeId>{};
    final removed = <SemanticNodeId>{};
    final updated = <SemanticNodeId>{};

    for (final entry in nextNodes.entries) {
      final previousNode = previousNodes[entry.key];
      if (previousNode == null) {
        added.add(entry.key);
      } else if (!_semanticNodeEquals(previousNode, entry.value)) {
        updated.add(entry.key);
      }
    }
    for (final id in previousNodes.keys) {
      if (!nextNodes.containsKey(id)) removed.add(id);
    }

    return SemanticTreeUpdate._(
      previous: previous,
      next: next,
      previousNodesById: previousNodes,
      nextNodesById: nextNodes,
      added: added,
      removed: removed,
      updated: updated,
    );
  }

  factory SemanticTreeUpdate._diffFromNextNodes({
    required SemanticTree? previous,
    required SemanticTree next,
    required Map<SemanticNodeId, SemanticNode> previousNodes,
  }) {
    final nextNodes = <SemanticNodeId, SemanticNode>{};
    final added = <SemanticNodeId>{};
    final removed = <SemanticNodeId>{};
    final updated = <SemanticNodeId>{};

    for (final nextNode in next.nodes) {
      final id = nextNode.id;
      nextNodes[id] = nextNode;
      final previousNode = previousNodes[id];
      if (previousNode == null) {
        added.add(id);
      } else if (!_semanticNodeEquals(previousNode, nextNode)) {
        updated.add(id);
      }
    }
    for (final id in previousNodes.keys) {
      if (!nextNodes.containsKey(id)) removed.add(id);
    }

    return SemanticTreeUpdate._(
      previous: previous,
      next: next,
      previousNodesById: previousNodes,
      nextNodesById: nextNodes,
      added: added,
      removed: removed,
      updated: updated,
    );
  }

  final SemanticTree? previous;
  final SemanticTree next;
  final Map<SemanticNodeId, SemanticNode> previousNodesById;
  final Map<SemanticNodeId, SemanticNode> nextNodesById;
  final Set<SemanticNodeId> added;
  final Set<SemanticNodeId> removed;
  final Set<SemanticNodeId> updated;

  bool get hasChanges =>
      added.isNotEmpty || removed.isNotEmpty || updated.isNotEmpty;
}

/// Debug-only structural comparison between two semantic trees.
///
/// Returns a description of the first divergence (depth-first), or `null`
/// when the trees are equivalent. Hosts that take an incremental path
/// (such as retained leaf replacement) can assert against a full
/// [SemanticTree.fromElement] rebuild with this; a non-null result means
/// the incremental path missed a change the full walk would have produced —
/// an escalation gap in the dirty tracking, not presentation noise.
String? debugSemanticTreeDivergence(
  SemanticTree expected,
  SemanticTree actual,
) {
  return _semanticNodeDivergence(expected.root, actual.root, path: 'root');
}

String? _semanticNodeDivergence(
  SemanticNode expected,
  SemanticNode actual, {
  required String path,
}) {
  if (!_semanticNodeEquals(expected, actual)) {
    return '$path: expected $expected, got $actual';
  }
  // _semanticNodeEquals guarantees matching child count and id order here.
  for (var i = 0; i < expected.children.length; i++) {
    final divergence = _semanticNodeDivergence(
      expected.children[i],
      actual.children[i],
      path: '$path.children[$i](${expected.children[i].id})',
    );
    if (divergence != null) return divergence;
  }
  return null;
}

bool _semanticNodeEquals(SemanticNode a, SemanticNode b) {
  if (identical(a, b)) return true;
  return a.id == b.id &&
      a.role == b.role &&
      a.label == b.label &&
      _objectEquals(a.value, b.value) &&
      a.hint == b.hint &&
      a.enabled == b.enabled &&
      a.focused == b.focused &&
      a.selected == b.selected &&
      a.checked == b.checked &&
      a.expanded == b.expanded &&
      a.busy == b.busy &&
      a.validationError == b.validationError &&
      a.bounds == b.bounds &&
      _setEquals(a.actions, b.actions) &&
      a.state.hasSameValues(b.state) &&
      _hasSameChildOrder(a, b);
}

bool _hasSameChildOrder(SemanticNode a, SemanticNode b) {
  if (a.children.length != b.children.length) return false;
  for (var i = 0; i < a.children.length; i++) {
    if (a.children[i].id != b.children[i].id) return false;
  }
  return true;
}

bool _setEquals(Set<Object?> a, Set<Object?> b) {
  if (a.length != b.length) return false;
  for (final value in a) {
    if (!b.contains(value)) return false;
  }
  return true;
}

bool _objectEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_objectEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is Iterable && b is Iterable) {
    final left = a.iterator;
    final right = b.iterator;
    while (true) {
      final hasLeft = left.moveNext();
      final hasRight = right.moveNext();
      if (hasLeft != hasRight) return false;
      if (!hasLeft) return true;
      if (!_objectEquals(left.current, right.current)) return false;
    }
  }
  return a == b;
}
