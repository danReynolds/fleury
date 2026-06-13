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

/// Server side: turns a sequence of [SemanticInspectionSnapshot]s into compact
/// wire payloads, emitting a full frame once per connection and patches
/// thereafter. One instance per served session (it holds the last-sent state).
final class SemanticsWireEncoder {
  /// id -> canonical JSON of the node's flat form (own fields + childIds),
  /// reflecting what the peer currently holds.
  Map<String, String> _sent = const {};
  bool _sentFull = false;

  /// Encodes [snapshot] for the wire, or returns null when the exposed
  /// semantics are byte-for-byte unchanged since the last send (so a dirty
  /// frame that didn't actually alter the accessible tree costs zero bytes).
  Uint8List? encode(SemanticInspectionSnapshot snapshot) {
    final flat = _flatten(snapshot.root);
    final canonical = <String, String>{
      for (final entry in flat.entries) entry.key: jsonEncode(entry.value),
    };

    if (!_sentFull) {
      _sentFull = true;
      _sent = canonical;
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
      if (prior == null || prior != canonical[entry.key]) {
        set.add(flat[entry.key]!);
      }
    }
    final removed = <String>[
      for (final id in _sent.keys)
        if (!flat.containsKey(id)) id,
    ];
    if (set.isEmpty && removed.isEmpty) return null;

    _sent = canonical;
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

  /// Whether a full frame has been applied (so patches have a base to land on).
  bool get isPrimed => _hasState;

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
      case 'patch':
        if (!_hasState) return null;
        final set = decoded['set'];
        if (set is List) {
          for (final node in set) {
            if (node is Map) _put(node);
          }
        }
        final removed = decoded['removed'];
        if (removed is List) {
          for (final id in removed) {
            if (id is String) _flat.remove(id);
          }
        }
        _rootId = _stringOr(decoded['root'], _rootId);
      default:
        return null;
    }

    final nested = _nest(_rootId, <String>{});
    if (nested == null) return null;
    return SemanticInspectionSnapshot.fromJson(<String, Object?>{
      'schemaVersion': SemanticInspectionSnapshot.currentSchemaVersion,
      'root': nested,
    }).toSemanticTree();
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
  /// cycles and missing ids (a corrupt/partial patch yields a pruned subtree
  /// rather than an infinite loop).
  Map<String, Object?>? _nest(String id, Set<String> seen) {
    if (!seen.add(id)) return null;
    final flat = _flat[id];
    if (flat == null) return null;
    final json = <String, Object?>{
      for (final entry in flat.entries)
        if (entry.key != 'childIds') entry.key: entry.value,
    };
    final childIds = flat['childIds'];
    if (childIds is List) {
      final children = <Map<String, Object?>>[];
      for (final childId in childIds) {
        if (childId is! String) continue;
        final child = _nest(childId, seen);
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
