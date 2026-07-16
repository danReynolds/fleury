// Semantic wire diff for the structured serve path.
//
// The serve host ships the app's accessible semantic tree to the browser so a
// served session stays screen-reader- and agent-readable. Shipping a *full*
// redacted snapshot on every change does not scale: once the serialized tree
// exceeds DEFLATE's 32 KiB sliding window (~160+ nodes), permessage-deflate's
// context takeover can no longer reference the near-identical previous frame,
// and per-frame deflated cost jumps ~20x (measured: 163 -> 2180 bytes/frame at
// the cliff; see profiling/bin/serve_semantics_profile.dart). DEFLATE's window
// is the hard ceiling, so the compressor cannot be the fix — the wire must
// carry less.
//
// This encodes each emission as either a FULL flat node list (first frame of a
// connection) or a PATCH (only the nodes whose serialized form changed, plus
// removed ids). The tree is flattened to id-keyed nodes carrying `childIds`
// instead of nested `children`, so a localized change touches O(changed) nodes
// regardless of tree size. The client keeps the flat map, applies the patch,
// and rebuilds the nested tree. Redaction is inherited from the snapshot (which
// redacts on construction) and re-applied on decode, so no plaintext crosses
// the wire even via a patch.
//
// Correctness rests on the transport being ordered and lossless (a WebSocket
// over TCP): patch N applies to the state left by patch N-1. A fresh
// connection always begins with a FULL frame, so a reconnecting client
// resynchronizes without any out-of-band negotiation.

import 'dart:convert';
import 'dart:typed_data';

import '../rendering/text_sanitizer.dart' show sanitizeForDisplay;
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import '../semantics/semantics_owner.dart' show SemanticTreeUpdate;
import 'remote_codec.dart' show maxRemoteSemanticNodeIdBytes;
import 'remote_protocol.dart' show maxRemoteDocumentFramePayloadLength;

/// Wire envelope schema version. Bumped only on a breaking shape change; the
/// decoder rejects an unknown version rather than misreading it.
const int semanticsWireVersion = 1;

/// Maximum tree depth the decoder will reconstruct. The frame payload cap
/// already bounds total bytes (and thus node count), but a hostile or corrupt
/// patch could still encode a very deep `childIds` chain; capping recursion
/// depth turns that into a pruned subtree instead of a stack overflow. Far
/// beyond any real UI nesting.
const int maxSemanticTreeDepth = 1024;

/// Maximum retained nodes in one decoded semantic mirror.
///
/// A real terminal exposes a windowed visible tree that is normally orders of
/// magnitude smaller. This cap is deliberately generous while preventing a
/// sequence of individually-valid patches from accumulating unbounded
/// unreachable state across the lifetime of a connection.
const int maxSemanticWireNodes = 16 * 1024;

/// Maximum child references in one decoded semantic mirror.
///
/// The semantic wire describes a tree, not a general graph. Bounding edges in
/// addition to nodes limits both reconstruction work and adversarial wide
/// `childIds` lists before the inspection parser allocates nested children.
const int maxSemanticWireEdges = 64 * 1024;

/// Scalar fields retained from one flat semantic wire node.
///
/// `children` is intentionally absent: the semantic wire is flat and may only
/// express structure through `childIds`. Passing a raw nested `children` field
/// through to [SemanticInspectionSnapshot.fromJson] would bypass the node,
/// edge, depth, and cycle bounds applied to the flat graph. Unknown additive
/// fields are ignored, matching the inspection schema's reader contract.
const Set<String> _semanticWireScalarFields = <String>{
  'id',
  'role',
  'label',
  'value',
  'hint',
  'enabled',
  'focused',
  'selected',
  'checked',
  'expanded',
  'busy',
  'validationError',
  'bounds',
  'actions',
  'state',
};

/// The set of node ids whose wire form may have changed since the last
/// present, in WIRE-id space (already sanitized). Derived from
/// `SemanticsOwner`'s per-frame diff: [changed] is added ∪ updated, [removed]
/// is removed. The owner's node equality compares exactly the fields the wire
/// serializes — including `bounds` and child order — so a node lands in
/// [changed] iff its wire form could differ. Passing this lets the encoder
/// re-serialize only the changed nodes instead of re-flattening the whole tree
/// every frame.
final class SemanticWireDelta {
  const SemanticWireDelta({required this.changed, required this.removed});

  final Set<String> changed;
  final Set<String> removed;
}

/// Server side: turns semantic frames into compact wire payloads, emitting a
/// full frame once per connection and patches thereafter. One instance per
/// served session (it holds the last-sent state). Two entry points share that
/// state: [encodeTree] (the serve render loop's path — redacts only the changed
/// nodes on demand, O(changed)) and [encode] (for consumers that already hold a
/// pre-redacted [SemanticInspectionSnapshot], e.g. inspection/agent bridges).
final class SemanticsWireEncoder {
  SemanticsWireEncoder({
    int maxWirePayloadLength = maxRemoteDocumentFramePayloadLength,
  }) : maxWirePayloadLength = _checkedSemanticPayloadLimit(
         maxWirePayloadLength,
       );

  /// Maximum bytes for both an emitted frame and the equivalent retained FULL.
  ///
  /// The retained mirror must always fit in one FULL frame: otherwise a fresh
  /// peer could never synchronize after reconnect even though a sequence of
  /// individually-small PATCH frames built the state successfully.
  final int maxWirePayloadLength;

  /// id -> the node's flat wire form (own fields + childIds) as last sent to the
  /// peer, maintained incrementally: a patch re-serializes only the changed
  /// nodes (named by a [SemanticTreeUpdate] or [SemanticWireDelta]) and applies
  /// them here. The production [encodeTree] update path is O(changed); the
  /// snapshot path avoids a second flatten/redaction pass but may lazily build
  /// that snapshot's O(tree) id index on its first lookup. Without a change-set
  /// (first frame, or a caller that doesn't supply one) the encoder falls back
  /// to flattening the whole frame and comparing against this map.
  Map<String, Map<String, Object?>> _sent = const {};
  Map<String, int> _sentNodeByteLengths = const {};
  int _sentNodeBytes = 0;
  String? _sentRootId;
  bool _sentFull = false;
  int _lastFlattenedNodes = 0;

  /// How many nodes the most recent [encodeTree] redacted and flattened. On a
  /// steady-state [encodeTree] patch this is O(changed) — the very count a
  /// regression back to full-tree redaction blows up to O(tree); the first
  /// (full) frame flattens the whole tree. Drives the serve-semantics
  /// redaction-cost gate; it does not describe a snapshot's lazy index cost.
  int get lastFlattenedNodeCount => _lastFlattenedNodes;

  /// Encodes [tree] for the wire, or returns null when the exposed semantics are
  /// unchanged since the last send (so a dirty frame that didn't actually alter
  /// the accessible tree costs zero bytes).
  ///
  /// [update] names the nodes whose wire form may have changed AND carries the
  /// live nodes themselves (`nextNodesById`); on a patch frame the encoder
  /// redacts and re-serializes ONLY those, straight from the live tree — never
  /// building a full [SemanticInspectionSnapshot]. The owner's node equality
  /// compares exactly the fields the wire carries — including `bounds` and child
  /// order — so a node pushed to a new position (bounds shift, no model rebuild)
  /// still lands in the update. A debug-only oracle re-runs the full flatten
  /// every frame and asserts the incrementally-maintained `_sent` still equals
  /// the ground truth, so any gap between the update and the wire form fails
  /// loudly in tests.
  Uint8List? encodeTree(SemanticTree tree, {SemanticTreeUpdate? update}) {
    final rootId = sanitizeForDisplay(tree.root.id.value);
    if (!_sentFull) {
      final flat = _flattenTree(tree);
      return _encodeFull(flat, rootId: rootId, flattenedNodes: flat.length);
    }

    if (update == null) {
      // No update: fall back to the full flatten + structural compare.
      final flat = _flattenTree(tree);
      final encoded = _encodeFlattenedPatch(
        flat,
        rootId: rootId,
        flattenedNodes: flat.length,
      );
      if (_sentFull) _assertTreeOracle(tree);
      return encoded;
    }

    // O(changed): redact + serialize only the nodes the update names. Stage the
    // edits without touching [_sent]; validation and byte accounting happen
    // before commit so a rejected state can only force the NEXT send to FULL,
    // never leave a PATCH base the peer did not receive.
    var flattened = 0;
    final staged = <String, Map<String, Object?>>{};
    final touched = <String>{};
    for (final id in update.added.followedBy(update.updated)) {
      final node = update.nextNodesById[id];
      if (node == null) continue; // named-changed but gone from the tree.
      flattened++;
      final json = SemanticInspectionNode.flattenLiveNode(node);
      final wireId = json['id']! as String;
      touched.add(wireId);
      final prior = staged[wireId] ?? _sent[wireId];
      if (prior == null || !_jsonEquals(prior, json)) {
        staged[wireId] = json;
      }
    }
    final removed = <String>{};
    for (final id in update.removed) {
      final wireId = sanitizeForDisplay(id.value);
      // A changed node may carry this same wire id — a duplicate, or two raw
      // ids that sanitize alike — in which case it is LIVE. Do not delete it.
      if (touched.contains(wireId)) continue;
      if (_sent.containsKey(wireId)) removed.add(wireId);
    }
    final encoded = _finishPatch(
      rootId: rootId,
      staged: staged,
      removed: removed,
      flattenedNodes: flattened,
    );
    if (_sentFull) _assertTreeOracle(tree);
    return encoded;
  }

  void _assertTreeOracle(SemanticTree tree) {
    assert(
      _oracleHoldsForTree(tree),
      'On-demand redaction diverged from a full flatten — a changed node was '
      'missing from the update. This is a correctness bug in the changed-set '
      'plumbing, not the encoder.',
    );
  }

  /// Debug ground-truth check for [encodeTree]: the incrementally-maintained
  /// [_sent] must equal a from-scratch flatten of the current tree. If it
  /// doesn't, the update missed a node whose wire form changed — caught here in
  /// tests/CI, never shipped. Stripped from release builds (runs under
  /// `assert`).
  bool _oracleHoldsForTree(SemanticTree tree) {
    final truth = _flattenTree(tree);
    if (truth.length != _sent.length) return false;
    for (final entry in truth.entries) {
      final have = _sent[entry.key];
      if (have == null || !_jsonEquals(have, entry.value)) return false;
    }
    return true;
  }

  /// Encodes a pre-redacted [snapshot] for the wire — the snapshot-based path for
  /// inspection/agent consumers that already hold a [SemanticInspectionSnapshot]
  /// (the serve render loop instead uses [encodeTree], which redacts on demand).
  /// Returns null when the exposed semantics are unchanged since the last send.
  ///
  /// [delta] names the changed nodes (in wire-id space); on a patch frame the
  /// encoder re-serializes only those instead of flattening the whole snapshot.
  /// A fresh snapshot may still build its lazy O(tree) id index on the first
  /// lookup. A debug-only oracle asserts the incrementally-maintained `_sent`
  /// still equals a full flatten, so any gap fails loudly in tests.
  Uint8List? encode(
    SemanticInspectionSnapshot snapshot, {
    SemanticWireDelta? delta,
  }) {
    final rootId = snapshot.root.id;
    if (!_sentFull) {
      final flat = _flatten(snapshot.root);
      return _encodeFull(flat, rootId: rootId, flattenedNodes: flat.length);
    }

    if (delta == null) {
      // No changed-set: fall back to the full flatten + structural compare.
      final flat = _flatten(snapshot.root);
      final encoded = _encodeFlattenedPatch(
        flat,
        rootId: rootId,
        flattenedNodes: flat.length,
      );
      if (_sentFull) _assertSnapshotOracle(snapshot);
      return encoded;
    }

    final staged = <String, Map<String, Object?>>{};
    var flattened = 0;
    for (final id in delta.changed) {
      final node = snapshot.nodeById(id);
      if (node == null) continue; // named-changed but not in the tree.
      flattened++;
      final json = _flattenNode(node);
      final prior = staged[id] ?? _sent[id];
      if (prior == null || !_jsonEquals(prior, json)) staged[id] = json;
    }
    final removed = <String>{};
    for (final id in delta.removed) {
      // A contradictory delta is invalid. Removal wins in the staged candidate;
      // the debug oracle below still makes the producer bug loud in tests.
      staged.remove(id);
      if (_sent.containsKey(id)) removed.add(id);
    }
    final encoded = _finishPatch(
      rootId: rootId,
      staged: staged,
      removed: removed,
      flattenedNodes: flattened,
    );
    if (_sentFull) _assertSnapshotOracle(snapshot);
    return encoded;
  }

  void _assertSnapshotOracle(SemanticInspectionSnapshot snapshot) {
    assert(
      _oracleHolds(snapshot),
      'SemanticWireDelta diverged from a full flatten — a changed node was '
      'missing from the delta. This is a correctness bug in the changed-set '
      'plumbing, not the encoder.',
    );
  }

  /// Debug ground-truth check for [encode]: [_sent] must equal a from-scratch
  /// flatten of the current snapshot. Stripped from release (runs under
  /// `assert`).
  bool _oracleHolds(SemanticInspectionSnapshot snapshot) {
    final truth = _flatten(snapshot.root);
    if (truth.length != _sent.length) return false;
    for (final entry in truth.entries) {
      final have = _sent[entry.key];
      if (have == null || !_jsonEquals(have, entry.value)) return false;
    }
    return true;
  }

  Uint8List? _encodeFull(
    Map<String, Map<String, Object?>> flat, {
    required String rootId,
    required int flattenedNodes,
  }) {
    _lastFlattenedNodes = flattenedNodes;
    if (!_semanticFlatGraphIsValid(flat, rootId)) {
      _rejectCandidate(flattenedNodes);
      return null;
    }
    final bytes = _fullBytes(rootId, flat);
    if (bytes.length > maxWirePayloadLength) {
      _rejectCandidate(flattenedNodes);
      return null;
    }

    final nodeByteLengths = <String, int>{};
    var nodeBytes = 0;
    for (final entry in flat.entries) {
      final length = _semanticNodeWireLength(entry.value);
      nodeByteLengths[entry.key] = length;
      nodeBytes += length;
    }
    _sent = flat;
    _sentNodeByteLengths = nodeByteLengths;
    _sentNodeBytes = nodeBytes;
    _sentRootId = rootId;
    _sentFull = true;
    return bytes;
  }

  Uint8List? _encodeFlattenedPatch(
    Map<String, Map<String, Object?>> flat, {
    required String rootId,
    required int flattenedNodes,
  }) {
    final staged = <String, Map<String, Object?>>{};
    for (final entry in flat.entries) {
      final prior = _sent[entry.key];
      if (prior == null || !_jsonEquals(prior, entry.value)) {
        staged[entry.key] = entry.value;
      }
    }
    final removed = <String>{
      for (final id in _sent.keys)
        if (!flat.containsKey(id)) id,
    };
    return _finishPatch(
      rootId: rootId,
      staged: staged,
      removed: removed,
      flattenedNodes: flattenedNodes,
    );
  }

  Uint8List? _finishPatch({
    required String rootId,
    required Map<String, Map<String, Object?>> staged,
    required Set<String> removed,
    required int flattenedNodes,
  }) {
    _lastFlattenedNodes = flattenedNodes;
    final rootChanged = rootId != _sentRootId;
    if (staged.isEmpty && removed.isEmpty && !rootChanged) return null;

    final stagedByteLengths = <String, int>{};
    var candidateNodeBytes = _sentNodeBytes;
    var candidateNodeCount = _sent.length;
    for (final id in removed) {
      final oldLength = _sentNodeByteLengths[id];
      if (oldLength == null) continue;
      candidateNodeBytes -= oldLength;
      candidateNodeCount--;
    }
    var structureChanged = rootChanged || removed.isNotEmpty;
    for (final entry in staged.entries) {
      final length = _semanticNodeWireLength(entry.value);
      stagedByteLengths[entry.key] = length;
      final prior = _sent[entry.key];
      if (prior == null) {
        candidateNodeCount++;
        candidateNodeBytes += length;
        structureChanged = true;
      } else {
        candidateNodeBytes += length - _sentNodeByteLengths[entry.key]!;
        if (!_jsonEquals(prior['childIds'], entry.value['childIds'])) {
          structureChanged = true;
        }
      }
    }

    if (candidateNodeCount > maxSemanticWireNodes ||
        _semanticFullPayloadLength(
              rootId,
              nodeBytes: candidateNodeBytes,
              nodeCount: candidateNodeCount,
            ) >
            maxWirePayloadLength) {
      _rejectCandidate(flattenedNodes);
      return null;
    }

    Map<String, Map<String, Object?>>? candidate;
    if (structureChanged) {
      candidate = _candidateAfter(staged, removed);
      if (!_semanticFlatGraphIsValid(candidate, rootId)) {
        _rejectCandidate(flattenedNodes);
        return null;
      }
    }

    final set = staged.values.toList(growable: false)
      ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    final removedList = removed.toList(growable: false)..sort();
    var bytes = _bytes(<String, Object?>{
      'v': semanticsWireVersion,
      'mode': 'patch',
      'root': rootId,
      if (set.isNotEmpty) 'set': set,
      if (removedList.isNotEmpty) 'removed': removedList,
    });
    if (bytes.length > maxWirePayloadLength) {
      // The next state is representable, but this transition is not (for
      // example a replace-all PATCH carrying both new nodes and removed ids).
      // A FULL is a valid in-stream resync and is smaller than losing the base.
      candidate ??= _candidateAfter(staged, removed);
      bytes = _fullBytes(rootId, candidate);
      if (bytes.length > maxWirePayloadLength) {
        _rejectCandidate(flattenedNodes);
        return null;
      }
    }

    for (final id in removed) {
      _sent.remove(id);
      _sentNodeByteLengths.remove(id);
    }
    for (final entry in staged.entries) {
      _sent[entry.key] = entry.value;
      _sentNodeByteLengths[entry.key] = stagedByteLengths[entry.key]!;
    }
    _sentNodeBytes = candidateNodeBytes;
    _sentRootId = rootId;
    return bytes;
  }

  Map<String, Map<String, Object?>> _candidateAfter(
    Map<String, Map<String, Object?>> staged,
    Set<String> removed,
  ) {
    final candidate = Map<String, Map<String, Object?>>.of(_sent);
    for (final id in removed) {
      candidate.remove(id);
    }
    candidate.addAll(staged);
    return candidate;
  }

  void _rejectCandidate(int flattenedNodes) {
    reset();
    _lastFlattenedNodes = flattenedNodes;
  }

  /// Forgets the peer's state so the next encode re-sends a full frame.
  /// Call when a new peer connects on a reused encoder.
  void reset() {
    _sent = const {};
    _sentNodeByteLengths = const {};
    _sentNodeBytes = 0;
    _sentRootId = null;
    _sentFull = false;
    _lastFlattenedNodes = 0;
  }

  static Uint8List _bytes(Map<String, Object?> payload) =>
      Uint8List.fromList(utf8.encode(jsonEncode(payload)));

  static Uint8List _fullBytes(
    String rootId,
    Map<String, Map<String, Object?>> flat,
  ) => _bytes(<String, Object?>{
    'v': semanticsWireVersion,
    'mode': 'full',
    'root': rootId,
    'nodes': flat.values.toList(growable: false),
  });
}

int _checkedSemanticPayloadLimit(int value) {
  if (value <= 0 || value > maxRemoteDocumentFramePayloadLength) {
    throw ArgumentError.value(
      value,
      'maxWirePayloadLength',
      'must be within 1..$maxRemoteDocumentFramePayloadLength',
    );
  }
  return value;
}

int _semanticNodeWireLength(Map<String, Object?> node) =>
    utf8.encode(jsonEncode(node)).length;

bool _semanticWireIdIsValid(String id) {
  if (id.isEmpty) return false;
  var byteLength = 0;
  for (var i = 0; i < id.length; i++) {
    final unit = id.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= id.length) return false;
      final low = id.codeUnitAt(++i);
      if (low < 0xDC00 || low > 0xDFFF) return false;
      byteLength += 4;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    } else if (unit <= 0x7F) {
      byteLength++;
    } else if (unit <= 0x7FF) {
      byteLength += 2;
    } else {
      byteLength += 3;
    }
    if (byteLength > maxRemoteSemanticNodeIdBytes) return false;
  }
  return true;
}

/// Exact bytes of the equivalent FULL envelope from incrementally-maintained
/// node JSON lengths. The empty-list encoding already includes `[]`; filling it
/// adds each node plus one comma between adjacent entries.
int _semanticFullPayloadLength(
  String rootId, {
  required int nodeBytes,
  required int nodeCount,
}) {
  final emptyEnvelopeLength = utf8
      .encode(
        jsonEncode(<String, Object?>{
          'v': semanticsWireVersion,
          'mode': 'full',
          'root': rootId,
          'nodes': const <Object?>[],
        }),
      )
      .length;
  return emptyEnvelopeLength + nodeBytes + (nodeCount > 1 ? nodeCount - 1 : 0);
}

/// Whether one producer-side flat mirror is exactly reconstructable under the
/// decoder's structural limits.
///
/// This runs for the initial FULL and only when a PATCH changes structure; a
/// scalar-only steady PATCH retains the already-validated graph and stays
/// O(changed). Duplicate leaves remain legal for ambiguity diagnostics, while a
/// repeated internal node is rejected before it can form an expanding DAG.
bool _semanticFlatGraphIsValid(
  Map<String, Map<String, Object?>> flat,
  String rootId,
) {
  if (flat.isEmpty ||
      flat.length > maxSemanticWireNodes ||
      !_semanticWireIdIsValid(rootId)) {
    return false;
  }
  var edgeCount = 0;
  for (final entry in flat.entries) {
    if (!_semanticWireIdIsValid(entry.key)) return false;
    final node = entry.value;
    final childIds = node['childIds'];
    if (childIds is List<String>) {
      edgeCount += childIds.length;
      if (edgeCount > maxSemanticWireEdges) return false;
      if (childIds.any((id) => !_semanticWireIdIsValid(id))) return false;
    }
  }

  final visited = <String>{};
  var occurrenceCount = 0;
  bool visit(String id, int depth) {
    if (depth >= maxSemanticTreeDepth) return false;
    final node = flat[id];
    if (node == null) return false;
    occurrenceCount++;
    if (occurrenceCount > maxSemanticWireNodes) return false;
    final childIds = node['childIds'];
    if (!visited.add(id)) {
      return childIds is! List<String> || childIds.isEmpty;
    }
    if (childIds is List<String>) {
      for (final childId in childIds) {
        if (!visit(childId, depth + 1)) return false;
      }
    }
    return true;
  }

  if (!visit(rootId, 0)) return false;
  // A legal producer tree has no orphaned flat nodes. Requiring exact reachability
  // also keeps its retained mirror identical to the decoder, which prunes raw
  // orphan nodes from hostile inputs.
  return visited.length == flat.length;
}

/// Deep equality over JSON-shaped values (Map / List / scalars). Used to detect
/// an unchanged semantic node without re-serializing it. The compared values
/// come from `toJson()`, which emits deterministic key order, so structural
/// equality here matches canonical-string equality.
bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Flattens a live semantic tree to an id->wire-node map, redacting each node on
/// the way down via [SemanticInspectionNode.flattenLiveNode]. Each entry is a
/// node's own scalar fields plus `childIds` (not nested children), so the
/// structure is reconstructable from the flat set alone. Insertion order is a
/// stable pre-order, which keeps the full-frame `nodes` list deterministic.
///
/// LAST-wins on a duplicate wire id: ids are supposed to be unique, but the
/// framework tolerates duplicates (or two raw ids that sanitize alike) as a
/// degraded state, and some node must win. Last-wins matches the two other
/// maps this must agree with: the owner's `nextNodesById` that the O(changed)
/// patch path reads from, and the client decoder's flat map (`_put` overwrites)
/// — so the full frame, the patch, the debug oracle, and the client all resolve
/// a duplicate to the SAME (last, pre-order) node, rather than the full path
/// disagreeing with the incremental one.
Map<String, Map<String, Object?>> _flattenTree(SemanticTree tree) {
  final out = <String, Map<String, Object?>>{};
  void visit(SemanticNode node) {
    final json = SemanticInspectionNode.flattenLiveNode(node);
    out[json['id']! as String] = json;
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(tree.root);
  return out;
}

/// Flattens a pre-redacted inspection tree to an ordered id->node map — the
/// snapshot-based counterpart of [_flattenTree], used by [SemanticsWireEncoder.
/// encode]. Same shape and first-wins pre-order rule; produces byte-identical
/// output to flattening the equivalent live tree.
Map<String, Map<String, Object?>> _flatten(SemanticInspectionNode root) {
  final out = <String, Map<String, Object?>>{};
  void visit(SemanticInspectionNode node) {
    out.putIfAbsent(node.id, () => _flattenNode(node));
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(root);
  return out;
}

/// One inspection node's flat wire form: its own scalar fields plus `childIds`
/// (not the nested children). Byte-identical to
/// [SemanticInspectionNode.flattenLiveNode] for the same node, so the snapshot
/// and live-tree paths agree on the wire.
Map<String, Object?> _flattenNode(SemanticInspectionNode node) {
  final json = node.toScalarJson(includeBounds: true);
  if (node.children.isNotEmpty) {
    json['childIds'] = <String>[for (final c in node.children) c.id];
  }
  return json;
}

/// Client side: replays the encoder's frames, holding the flat node state and
/// rebuilding a [SemanticTree] after each. One instance per session.
final class SemanticsWireDecoder {
  SemanticsWireDecoder({
    int maxWirePayloadLength = maxRemoteDocumentFramePayloadLength,
  }) : maxWirePayloadLength = _checkedSemanticPayloadLimit(
         maxWirePayloadLength,
       );

  /// Maximum accepted frame and equivalent retained FULL payload bytes.
  final int maxWirePayloadLength;

  final Map<String, Map<String, Object?>> _flat = {};
  final Map<String, int> _flatNodeByteLengths = {};
  String _rootId = 'root';
  bool _hasState = false;
  List<String> _changedIds = const <String>[];
  List<String> _removedIds = const <String>[];
  bool _wasFull = false;

  /// Whether a full frame has been applied (so patches have a base to land on).
  bool get isPrimed => _hasState;

  /// Node ids whose serialized form changed in the most recently applied frame
  /// (every id on a full frame). The wire diff already carries exactly this, so
  /// surfacing it lets a consumer push a delta instead of the whole tree.
  List<String> get changedIds => _changedIds;

  /// Node ids removed by the most recently applied frame (empty on a full frame,
  /// which replaces the whole tree).
  List<String> get removedIds => _removedIds;

  /// Whether the most recently applied frame was a full (resync) frame — a
  /// consumer should treat [changedIds] as "re-read everything".
  bool get wasFull => _wasFull;

  /// Applies one wire payload and returns the reconstructed tree, or null if
  /// the payload is malformed or a patch arrives before any full frame (a
  /// desync the caller should ignore, keeping the last good tree).
  SemanticTree? apply(List<int> bytes) {
    if (bytes.length > maxWirePayloadLength) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['v'] != semanticsWireVersion) return null;

    late final Map<String, Map<String, Object?>> candidate;
    late final String candidateRootId;
    late final bool candidateWasFull;
    final candidateChangedIds = <String>{};
    final candidateRemovedIds = <String>{};

    switch (decoded['mode']) {
      case 'full':
        final nodes = decoded['nodes'];
        if (nodes is! List) return null;
        if (nodes.length > maxSemanticWireNodes) return null;
        final root = decoded['root'];
        if (root is! String || !_semanticWireIdIsValid(root)) return null;
        candidate = <String, Map<String, Object?>>{};
        for (final node in nodes) {
          final normalized = _normalizeNode(node);
          if (normalized == null) return null;
          candidate[normalized.id] = normalized.node;
        }
        candidateRootId = root;
        candidateWasFull = true;
      case 'patch':
        if (!_hasState) return null;
        candidate = Map<String, Map<String, Object?>>.of(_flat);
        final set = decoded['set'];
        if (set != null) {
          if (set is! List || set.length > maxSemanticWireNodes) return null;
          for (final node in set) {
            final normalized = _normalizeNode(node);
            if (normalized == null) return null;
            candidate[normalized.id] = normalized.node;
            candidateChangedIds.add(normalized.id);
          }
        }
        final removed = decoded['removed'];
        if (removed != null) {
          if (removed is! List || removed.length > maxSemanticWireNodes) {
            return null;
          }
          for (final id in removed) {
            if (id is! String || !_semanticWireIdIsValid(id)) return null;
            candidate.remove(id);
            candidateRemovedIds.add(id);
          }
        }
        final root = decoded['root'];
        if (root != null &&
            (root is! String || !_semanticWireIdIsValid(root))) {
          return null;
        }
        candidateRootId = root is String ? root : _rootId;
        candidateWasFull = false;
      default:
        return null;
    }

    if (candidate.length > maxSemanticWireNodes) return null;
    var edgeCount = 0;
    for (final node in candidate.values) {
      final childIds = node['childIds'];
      if (childIds is List<String>) {
        edgeCount += childIds.length;
        if (edgeCount > maxSemanticWireEdges) return null;
      }
    }

    // Build against the candidate map without touching the retained mirror.
    // [visited] is GLOBAL for this reconstruction and is never popped. A repeat
    // of a node that itself has children is a cycle or branching DAG, and is
    // rejected before it can expand exponentially under the old path-local
    // cycle guard. Repeated leaves remain representable: Fleury intentionally
    // tolerates duplicate semantic ids long enough for inspection tooling to
    // diagnose them as ambiguous, and a leaf cannot recurse. The occurrence
    // count below keeps even a very wide repeated-leaf fan-out bounded.
    final visited = <String>{};
    var invalidGraph = false;
    var nestedNodeCount = 0;
    Map<String, Object?>? nest(String id, int depth) {
      if (depth >= maxSemanticTreeDepth) return null;
      final flat = candidate[id];
      if (flat == null) return null;
      nestedNodeCount++;
      if (nestedNodeCount > maxSemanticWireNodes) {
        invalidGraph = true;
        return null;
      }
      final json = <String, Object?>{
        for (final entry in flat.entries)
          if (entry.key != 'childIds') entry.key: entry.value,
      };
      final childIds = flat['childIds'];
      if (!visited.add(id)) {
        if (childIds is List<String> && childIds.isNotEmpty) {
          invalidGraph = true;
          return null;
        }
        return json;
      }
      if (childIds is List<String>) {
        final children = <Map<String, Object?>>[];
        for (final childId in childIds) {
          final child = nest(childId, depth + 1);
          if (invalidGraph) return null;
          if (child != null) children.add(child);
        }
        if (children.isNotEmpty) json['children'] = children;
      }
      return json;
    }

    final nested = nest(candidateRootId, 0);
    if (nested == null || invalidGraph) return null;
    final reachableNodeByteLengths = <String, int>{};
    var reachableNodeBytes = 0;
    for (final id in visited) {
      final node = candidate[id]!;
      final retained = _flat[id];
      final length = identical(node, retained)
          ? _flatNodeByteLengths[id] ?? _semanticNodeWireLength(node)
          : _semanticNodeWireLength(node);
      reachableNodeByteLengths[id] = length;
      reachableNodeBytes += length;
    }
    if (_semanticFullPayloadLength(
          candidateRootId,
          nodeBytes: reachableNodeBytes,
          nodeCount: visited.length,
        ) >
        maxWirePayloadLength) {
      return null;
    }
    final SemanticTree tree;
    try {
      tree = SemanticInspectionSnapshot.fromJson(<String, Object?>{
        'schemaVersion': SemanticInspectionSnapshot.currentSchemaVersion,
        'root': nested,
      }).toSemanticTree();
    } on Object {
      // A reconstructed node was missing a required field (e.g. a corrupt or
      // hostile patch dropped a node's role) or had a field of the wrong shape.
      // Reject this frame rather than throw; no retained state has changed, so
      // the last good tree remains a valid base for the next patch.
      return null;
    }

    // Commit only after reconstruction AND inspection parsing both succeed.
    // Keeping reachable nodes only prevents an attacker from accumulating
    // orphaned nodes through a long stream of bounded patches.
    final previousIds = _flat.keys.toSet();
    final reachable = <String, Map<String, Object?>>{
      for (final id in visited) id: candidate[id]!,
    };
    _flat
      ..clear()
      ..addAll(reachable);
    _flatNodeByteLengths
      ..clear()
      ..addAll(reachableNodeByteLengths);
    final rootChanged = candidateRootId != _rootId;
    _rootId = candidateRootId;
    _hasState = true;
    _wasFull = candidateWasFull;
    if (candidateWasFull) {
      _changedIds = visited.toList(growable: false);
      _removedIds = const <String>[];
    } else {
      if (rootChanged) candidateChangedIds.add(candidateRootId);
      final removed = <String>{
        ...candidateRemovedIds,
        for (final id in previousIds)
          if (!visited.contains(id)) id,
      }..removeAll(visited);
      _changedIds = candidateChangedIds
          .where(visited.contains)
          .toList(growable: false);
      _removedIds = removed.toList(growable: false);
    }
    return tree;
  }

  static ({String id, Map<String, Object?> node})? _normalizeNode(
    Object? value,
  ) {
    if (value is! Map) return null;
    final id = value['id'];
    if (id is! String || !_semanticWireIdIsValid(id)) return null;
    final childIds = value['childIds'];
    List<String>? normalizedChildIds;
    if (childIds != null) {
      if (childIds is! List ||
          childIds.length > maxSemanticWireEdges ||
          childIds.any((child) => child is! String)) {
        return null;
      }
      normalizedChildIds = <String>[
        for (final child in childIds) child as String,
      ];
      if (normalizedChildIds.any((id) => !_semanticWireIdIsValid(id))) {
        return null;
      }
    }
    final node = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String &&
            _semanticWireScalarFields.contains(entry.key))
          entry.key as String: entry.value,
      'childIds': ?normalizedChildIds,
    };
    return (id: id, node: node);
  }
}
