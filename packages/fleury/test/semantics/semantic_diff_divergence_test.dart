// Two semantic diff implementations must agree: SemanticsOwner's node
// equality (drives the embed DOM patch) and the wire encoder's JSON equality
// (drives the serve patch). Both consume the same snapshot, so their
// changed-node verdicts must agree, or the two surfaces notify different node
// sets for the same mutation.
//
// The wire encoder now UNIFIES the two (backlog A1): given the owner's
// changed-set as a SemanticWireDelta, it re-serializes only those nodes
// instead of re-flattening the whole tree. `delta path == full path`
// byte-for-byte is the load-bearing invariant that makes this safe — pinned
// below across the same mutations, on top of the verdict-agreement checks.

import 'dart:convert';

import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

SemanticTree _tree({
  String rootLabel = 'app',
  String aLabel = 'alpha',
  String aValue = 'one',
  String bLabel = 'beta',
  bool includeC = false,
}) {
  return SemanticTree(
    root: SemanticNode(
      id: const SemanticNodeId('root'),
      role: SemanticRole.app,
      label: rootLabel,
      children: [
        SemanticNode(
          id: const SemanticNodeId('a'),
          role: SemanticRole.text,
          label: aLabel,
          value: aValue,
          bounds: CellRect.fromLTWH(0, 0, 5, 1),
        ),
        SemanticNode(
          id: const SemanticNodeId('b'),
          role: SemanticRole.button,
          label: bLabel,
          actions: const {SemanticAction.activate},
          bounds: CellRect.fromLTWH(0, 1, 5, 1),
        ),
        if (includeC)
          SemanticNode(
            id: const SemanticNodeId('c'),
            role: SemanticRole.text,
            label: 'gamma',
            bounds: CellRect.fromLTWH(0, 2, 5, 1),
          ),
      ],
    ),
  );
}

/// The wire's verdict: ids in the patch's `set` (added or changed) and
/// `removed` lists for the transition prev → next.
({Set<String> set_, Set<String> removed}) _wireVerdict(
  SemanticTree prev,
  SemanticTree next,
) {
  final encoder = SemanticsWireEncoder();
  expect(encoder.encode(SemanticInspectionSnapshot.fromTree(prev)), isNotNull);
  final patchBytes = encoder.encode(SemanticInspectionSnapshot.fromTree(next));
  if (patchBytes == null) {
    return (set_: const <String>{}, removed: const <String>{});
  }
  final envelope = jsonDecode(utf8.decode(patchBytes)) as Map<String, Object?>;
  expect(envelope['mode'], 'patch');
  return (
    set_: {
      for (final node in (envelope['set'] as List? ?? const []))
        (node as Map)['id'] as String,
    },
    removed: {
      for (final id in (envelope['removed'] as List? ?? const [])) id as String,
    },
  );
}

/// The owner's verdict: added ∪ updated, and removed, for prev → next.
({Set<String> set_, Set<String> removed}) _ownerVerdict(
  SemanticTree prev,
  SemanticTree next,
) {
  final owner = SemanticsOwner();
  owner.update(prev);
  final update = owner.update(next);
  return (
    set_: {
      for (final id in update.added) id.value,
      for (final id in update.updated) id.value,
    },
    removed: {for (final id in update.removed) id.value},
  );
}

void _expectAgreement(SemanticTree prev, SemanticTree next, String label) {
  final wire = _wireVerdict(prev, next);
  final owner = _ownerVerdict(prev, next);
  expect(
    wire.set_,
    owner.set_,
    reason: '$label: changed/added node sets must agree across the two diffs',
  );
  expect(
    wire.removed,
    owner.removed,
    reason: '$label: removed node sets must agree across the two diffs',
  );

  // A1: the O(changed) delta path must produce the exact same wire bytes as
  // the full flatten+compare path. Both encoders start from the same full
  // frame, then patch prev→next — one re-flattening the whole tree, the other
  // trusting the owner's changed-set. Byte-equality proves the fast path loses
  // nothing (the encoder's debug oracle also runs inside the delta encode).
  final prevSnap = SemanticInspectionSnapshot.fromTree(prev);
  final nextSnap = SemanticInspectionSnapshot.fromTree(next);

  final fullEnc = SemanticsWireEncoder()..encode(prevSnap);
  final fullPatch = fullEnc.encode(nextSnap);

  final ownerDiff = SemanticsOwner()..update(prev);
  final update = ownerDiff.update(next);
  final delta = SemanticWireDelta(
    changed: {
      for (final id in update.added) id.value,
      for (final id in update.updated) id.value,
    },
    removed: {for (final id in update.removed) id.value},
  );
  final fastEnc = SemanticsWireEncoder()..encode(prevSnap);
  final fastPatch = fastEnc.encode(nextSnap, delta: delta);

  expect(
    fastPatch,
    fullPatch,
    reason: '$label: the delta path must equal the full path byte-for-byte',
  );
}

void main() {
  group('SemanticsOwner diff vs wire diff', () {
    test('no change → both report nothing', () {
      _expectAgreement(_tree(), _tree(), 'identity');
    });

    test('label change', () {
      _expectAgreement(_tree(), _tree(aLabel: 'ALPHA'), 'label change');
    });

    test('value change', () {
      _expectAgreement(_tree(), _tree(aValue: 'two'), 'value change');
    });

    test('node added', () {
      // The parent's child list changes too — both diffs must agree on
      // whether that counts as a root change.
      _expectAgreement(_tree(), _tree(includeC: true), 'node added');
    });

    test('node removed', () {
      _expectAgreement(_tree(includeC: true), _tree(), 'node removed');
    });

    test('compound mutation', () {
      _expectAgreement(
        _tree(),
        _tree(aValue: 'two', bLabel: 'BETA', includeC: true),
        'compound',
      );
    });

    test('duplicate ids: delta path stays byte-identical to the full path', () {
      // Duplicate ids are an out-of-contract degraded state, but the O(changed)
      // delta path must still agree with the full flatten — `_flatten` and
      // `nodeById` both pick the FIRST node for an id, so the two paths ship
      // the same body and the encoder's `_sent` never drifts. (Regression for
      // the first-vs-last selection mismatch: nodeById returns first, `_flatten`
      // must too.)
      SemanticTree dup(String firstLabel) => SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: const SemanticNodeId('dup'),
              role: SemanticRole.text,
              label: firstLabel,
              bounds: CellRect.fromLTWH(0, 0, 4, 1),
            ),
            SemanticNode(
              id: const SemanticNodeId('dup'),
              role: SemanticRole.text,
              label: 'second',
              bounds: CellRect.fromLTWH(0, 1, 4, 1),
            ),
          ],
        ),
      );

      // Mutate the FIRST dup (the one first-wins keeps) so both paths emit a
      // real, non-empty patch to compare byte-for-byte.
      final prev = dup('first');
      final next = dup('FIRST');
      final prevSnap = SemanticInspectionSnapshot.fromTree(prev);
      final nextSnap = SemanticInspectionSnapshot.fromTree(next);

      final full = SemanticsWireEncoder()..encode(prevSnap);
      final fullPatch = full.encode(nextSnap);

      final ownerDiff = SemanticsOwner()..update(prev);
      final update = ownerDiff.update(next);
      final delta = SemanticWireDelta(
        changed: {
          for (final id in update.added) id.value,
          for (final id in update.updated) id.value,
        },
        removed: {for (final id in update.removed) id.value},
      );
      final fast = SemanticsWireEncoder()..encode(prevSnap);
      final fastPatch = fast.encode(nextSnap, delta: delta);

      expect(
        fastPatch,
        fullPatch,
        reason:
            'delta and full must pick the same duplicate (first-wins) — '
            'no oracle fire, no _sent drift',
      );
    });
  });
}
