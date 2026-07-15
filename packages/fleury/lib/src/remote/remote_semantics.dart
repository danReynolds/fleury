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

/// Wire envelope schema version. Bumped only on a breaking shape change; the
/// decoder rejects an unknown version rather than misreading it.
const int semanticsWireVersion = 1;

/// Maximum tree depth the decoder will reconstruct. The frame payload cap
/// already bounds total bytes (and thus node count), but a hostile or corrupt
/// patch could still encode a very deep `childIds` chain; capping recursion
/// depth turns that into a pruned subtree instead of a stack overflow. Far
/// beyond any real UI nesting.
const int maxSemanticTreeDepth = 1024;

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
  /// id -> the node's flat wire form (own fields + childIds) as last sent to the
  /// peer, maintained incrementally: a patch re-serializes only the changed
  /// nodes (named by a [SemanticTreeUpdate] or [SemanticWireDelta]) and applies
  /// them here, so the per-frame CPU is O(changed) rather than O(tree). Without
  /// a change-set (first frame, or a caller that doesn't supply one) the encoder
  /// falls back to flattening the whole frame and comparing against this map.
  Map<String, Map<String, Object?>> _sent = const {};
  bool _sentFull = false;
  int _lastFlattenedNodes = 0;

  /// How many nodes the most recent [encodeTree] redacted and flattened. On a
  /// steady-state patch this is O(changed) — the very count a regression back to
  /// full-tree redaction blows up to O(tree); the first (full) frame flattens
  /// the whole tree. Drives the serve-semantics redaction-cost gate.
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
    if (!_sentFull) {
      final flat = _flattenTree(tree);
      _sentFull = true;
      _sent = flat;
      _lastFlattenedNodes = flat.length;
      return _bytes(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'full',
        'root': sanitizeForDisplay(tree.root.id.value),
        'nodes': flat.values.toList(growable: false),
      });
    }

    final set = <Map<String, Object?>>[];
    final removed = <String>[];
    if (update == null) {
      // No update: fall back to the full flatten + structural compare.
      final flat = _flattenTree(tree);
      for (final entry in flat.entries) {
        final prior = _sent[entry.key];
        if (prior == null || !_jsonEquals(prior, entry.value)) {
          set.add(entry.value);
        }
      }
      for (final id in _sent.keys) {
        if (!flat.containsKey(id)) removed.add(id);
      }
      _sent = flat;
      _lastFlattenedNodes = flat.length;
    } else {
      // O(changed): redact + serialize only the nodes the update names, taking
      // each live node straight from `nextNodesById`, compare against the sent
      // form (so a redaction-equal node still ships nothing), and drop the
      // removed ids. [_sent] is mutated in place — it's always a fresh mutable
      // map from the last [_flattenTree] (full frame or no-update patch), so
      // there's nothing to preserve; copying it would reintroduce the O(n)
      // per-frame cost this path exists to remove.
      var flattened = 0;
      final touched = <String>{};
      for (final id in update.added.followedBy(update.updated)) {
        final node = update.nextNodesById[id];
        if (node == null) continue; // named-changed but gone from the tree.
        flattened++;
        final json = SemanticInspectionNode.flattenLiveNode(node);
        final wireId = json['id']! as String;
        touched.add(wireId);
        final prior = _sent[wireId];
        if (prior == null || !_jsonEquals(prior, json)) {
          set.add(json);
          _sent[wireId] = json;
        }
      }
      for (final id in update.removed) {
        final wireId = sanitizeForDisplay(id.value);
        // A changed node may carry this same wire id — a duplicate, or two raw
        // ids that sanitize alike — in which case it is LIVE and was just
        // (re)written above. Don't drop it, or it would land in both `set` and
        // `removed` and the client would delete a present node.
        if (touched.contains(wireId)) continue;
        if (_sent.remove(wireId) != null) removed.add(wireId);
      }
      _lastFlattenedNodes = flattened;
      assert(
        _oracleHoldsForTree(tree),
        'On-demand redaction diverged from a full flatten — a changed node was '
        'missing from the update. This is a correctness bug in the changed-set '
        'plumbing, not the encoder.',
      );
    }

    if (set.isEmpty && removed.isEmpty) return null;
    // Canonical order by id: the client applies patch nodes by id (order is
    // immaterial to it), but a stable order makes the full and patch paths
    // byte-identical and keeps a given mutation's bytes deterministic
    // frame-to-frame (the full path emits in tree pre-order, the patch path in
    // changed-set order — sorting reconciles them).
    set.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    removed.sort();
    return _bytes(<String, Object?>{
      'v': semanticsWireVersion,
      'mode': 'patch',
      'root': sanitizeForDisplay(tree.root.id.value),
      if (set.isNotEmpty) 'set': set,
      if (removed.isNotEmpty) 'removed': removed,
    });
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
  /// A debug-only oracle asserts the incrementally-maintained `_sent` still
  /// equals a full flatten, so any gap fails loudly in tests.
  Uint8List? encode(
    SemanticInspectionSnapshot snapshot, {
    SemanticWireDelta? delta,
  }) {
    if (!_sentFull) {
      final flat = _flatten(snapshot.root);
      _sentFull = true;
      _sent = flat;
      _lastFlattenedNodes = flat.length;
      return _bytes(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'full',
        'root': snapshot.root.id,
        'nodes': flat.values.toList(growable: false),
      });
    }

    final set = <Map<String, Object?>>[];
    final removed = <String>[];
    if (delta == null) {
      // No changed-set: fall back to the full flatten + structural compare.
      final flat = _flatten(snapshot.root);
      for (final entry in flat.entries) {
        final prior = _sent[entry.key];
        if (prior == null || !_jsonEquals(prior, entry.value)) {
          set.add(entry.value);
        }
      }
      for (final id in _sent.keys) {
        if (!flat.containsKey(id)) removed.add(id);
      }
      _sent = flat;
      _lastFlattenedNodes = flat.length;
    } else {
      // O(changed): serialize only the named nodes, compare each against the
      // sent form, and drop the removed ids. [_sent] is mutated in place.
      var flattened = 0;
      for (final id in delta.changed) {
        final node = snapshot.nodeById(id);
        if (node == null) continue; // named-changed but not in the tree.
        flattened++;
        final json = _flattenNode(node);
        final prior = _sent[id];
        if (prior == null || !_jsonEquals(prior, json)) {
          set.add(json);
          _sent[id] = json;
        }
      }
      for (final id in delta.removed) {
        if (_sent.remove(id) != null) removed.add(id);
      }
      _lastFlattenedNodes = flattened;
      assert(
        _oracleHolds(snapshot),
        'SemanticWireDelta diverged from a full flatten — a changed node was '
        'missing from the delta. This is a correctness bug in the changed-set '
        'plumbing, not the encoder.',
      );
    }

    if (set.isEmpty && removed.isEmpty) return null;
    set.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    removed.sort();
    return _bytes(<String, Object?>{
      'v': semanticsWireVersion,
      'mode': 'patch',
      'root': snapshot.root.id,
      if (set.isNotEmpty) 'set': set,
      if (removed.isNotEmpty) 'removed': removed,
    });
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

  /// Forgets the peer's state so the next encode re-sends a full frame.
  /// Call when a new peer connects on a reused encoder.
  void reset() {
    _sent = const {};
    _sentFull = false;
    _lastFlattenedNodes = 0;
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
