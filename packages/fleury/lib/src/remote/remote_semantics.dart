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

import '../semantics/inspection.dart';
import '../semantics/semantics.dart';

/// Wire envelope schema version. Bumped only on a breaking shape change; the
/// decoder rejects an unknown version rather than misreading it.
const int semanticsWireVersion = 1;

/// Maximum tree depth the decoder will reconstruct. The frame payload cap
/// already bounds total bytes (and thus node count), but a hostile or corrupt
/// patch could still encode a very deep `childIds` chain; capping recursion
/// depth turns that into a pruned subtree instead of a stack overflow. Far
/// beyond any real UI nesting.
const int maxSemanticTreeDepth = 1024;

/// Server side: turns a sequence of [SemanticInspectionSnapshot]s into compact
/// wire payloads, emitting a full frame once per connection and patches
/// thereafter. One instance per served session (it holds the last-sent state).
final class SemanticsWireEncoder {
  /// id -> the node's flat form (own fields + childIds) as last sent to the
  /// peer. Change detection compares structurally against this rather than
  /// re-serializing every node per frame: an unchanged node (the overwhelming
  /// majority each frame) early-exits the compare and allocates nothing, so
  /// computing the diff stays close to O(changed) instead of O(tree) in both
  /// CPU and garbage. Only the changed nodes are serialized, by the envelope.
  Map<String, Map<String, Object?>> _sent = const {};
  bool _sentFull = false;

  /// Encodes [snapshot] for the wire, or returns null when the exposed
  /// semantics are unchanged since the last send (so a dirty frame that didn't
  /// actually alter the accessible tree costs zero bytes).
  Uint8List? encode(SemanticInspectionSnapshot snapshot) {
    final flat = _flatten(snapshot.root);

    if (!_sentFull) {
      _sentFull = true;
      _sent = flat;
      return _bytes(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'full',
        'root': snapshot.root.id,
        'nodes': flat.values.toList(growable: false),
      });
    }

    final set = <Map<String, Object?>>[];
    for (final entry in flat.entries) {
      final prior = _sent[entry.key];
      if (prior == null || !_jsonEquals(prior, entry.value)) {
        set.add(entry.value);
      }
    }
    final removed = <String>[
      for (final id in _sent.keys)
        if (!flat.containsKey(id)) id,
    ];
    _sent = flat;
    if (set.isEmpty && removed.isEmpty) return null;

    return _bytes(<String, Object?>{
      'v': semanticsWireVersion,
      'mode': 'patch',
      'root': snapshot.root.id,
      if (set.isNotEmpty) 'set': set,
      if (removed.isNotEmpty) 'removed': removed,
    });
  }

  /// Forgets the peer's state so the next [encode] re-sends a full frame.
  /// Call when a new peer connects on a reused encoder.
  void reset() {
    _sent = const {};
    _sentFull = false;
  }

  static Uint8List _bytes(Map<String, Object?> payload) =>
      Uint8List.fromList(utf8.encode(jsonEncode(payload)));
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

/// Flattens a redacted inspection tree to an ordered id->node map. Each node
/// is its `toJson()` with `children` replaced by `childIds`, so the structure
/// is reconstructable from the flat set alone. Insertion order is a stable
/// pre-order, which keeps the full-frame `nodes` list deterministic.
Map<String, Map<String, Object?>> _flatten(SemanticInspectionNode root) {
  final out = <String, Map<String, Object?>>{};
  void visit(SemanticInspectionNode node) {
    final json = Map<String, Object?>.of(node.toJson())..remove('children');
    if (node.children.isNotEmpty) {
      json['childIds'] = <String>[for (final c in node.children) c.id];
    }
    out[node.id] = json;
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(root);
  return out;
}

/// Client side: replays the encoder's frames, holding the flat node state and
/// rebuilding a [SemanticTree] after each. One instance per session.
final class SemanticsWireDecoder {
  final Map<String, Map<String, Object?>> _flat = {};
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
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['v'] != semanticsWireVersion) return null;

    switch (decoded['mode']) {
      case 'full':
        final nodes = decoded['nodes'];
        if (nodes is! List) return null;
        _flat.clear();
        for (final node in nodes) {
          if (node is Map) _put(node);
        }
        _rootId = _stringOr(decoded['root'], _rootId);
        _hasState = true;
        _changedIds = _flat.keys.toList(growable: false);
        _removedIds = const <String>[];
        _wasFull = true;
      case 'patch':
        if (!_hasState) return null;
        final set = decoded['set'];
        final changed = <String>[];
        if (set is List) {
          for (final node in set) {
            if (node is Map) {
              _put(node);
              final id = node['id'];
              if (id is String) changed.add(id);
            }
          }
        }
        final removedList = <String>[];
        final removed = decoded['removed'];
        if (removed is List) {
          for (final id in removed) {
            if (id is String) {
              _flat.remove(id);
              removedList.add(id);
            }
          }
        }
        _rootId = _stringOr(decoded['root'], _rootId);
        _changedIds = changed;
        _removedIds = removedList;
        _wasFull = false;
      default:
        return null;
    }

    final nested = _nest(_rootId, <String>{}, 0);
    if (nested == null) return null;
    try {
      return SemanticInspectionSnapshot.fromJson(<String, Object?>{
        'schemaVersion': SemanticInspectionSnapshot.currentSchemaVersion,
        'root': nested,
      }).toSemanticTree();
    } on FormatException {
      // A reconstructed node was missing a required field (e.g. a corrupt or
      // hostile patch dropped a node's role). Reject this frame rather than
      // throw; the last good tree stays on screen.
      return null;
    }
  }

  void _put(Map<Object?, Object?> node) {
    final id = node['id'];
    if (id is! String) return;
    _flat[id] = <String, Object?>{
      for (final entry in node.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  /// Rebuilds the nested node JSON for [id] from the flat map, guarding against
  /// cycles (the [seen] path set), missing ids, and excessive depth (a corrupt
  /// or hostile patch yields a pruned subtree rather than an infinite loop or a
  /// stack overflow).
  Map<String, Object?>? _nest(String id, Set<String> seen, int depth) {
    if (depth >= maxSemanticTreeDepth) return null;
    if (!seen.add(id)) return null;
    final flat = _flat[id];
    if (flat == null) {
      seen.remove(id);
      return null;
    }
    final json = <String, Object?>{
      for (final entry in flat.entries)
        if (entry.key != 'childIds') entry.key: entry.value,
    };
    final childIds = flat['childIds'];
    if (childIds is List) {
      final children = <Map<String, Object?>>[];
      for (final childId in childIds) {
        if (childId is! String) continue;
        final child = _nest(childId, seen, depth + 1);
        if (child != null) children.add(child);
      }
      if (children.isNotEmpty) json['children'] = children;
    }
    seen.remove(id);
    return json;
  }

  static String _stringOr(Object? value, String fallback) =>
      value is String ? value : fallback;
}
