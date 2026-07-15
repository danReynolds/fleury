// The serve render loop must PRODUCE the O(changed) semantic wire patch by
// redacting only the changed nodes — not by rebuilding a full redacted snapshot
// of the whole tree every frame. That CPU invariant is what backs the O(changed)
// wire; a regression toward full-tree redaction leaves the wire flat but blows
// the per-frame CPU/allocation back up to O(tree). This is the deterministic,
// production-routed gate for it (SemanticsWireEncoder.encodeTree drives the same
// path the serve driver uses), plus a byte-parity check that the on-demand path
// is indistinguishable from the snapshot path on the wire.
@TestOn('vm')
library;

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A realistic agent tree: status + a message list + an input. [tick] perturbs
/// only the status counter and the last message body — the streaming case where
/// nearly everything is identical frame-to-frame.
SemanticTree _tree({required int messages, required int tick}) {
  return SemanticTree(
    root: SemanticNode(
      id: const SemanticNodeId('root'),
      role: SemanticRole.app,
      children: [
        SemanticNode(
          id: const SemanticNodeId('status'),
          role: SemanticRole.status,
          label: 'streaming — $tick tokens',
        ),
        SemanticNode(
          id: const SemanticNodeId('messages'),
          role: SemanticRole.messageList,
          children: [
            for (var m = 0; m < messages; m++)
              SemanticNode(
                id: SemanticNodeId('msg:$m'),
                role: SemanticRole.message,
                label: m == messages - 1
                    ? 'assistant: step $tick'
                    : 'turn $m: a settled line',
                state: SemanticState({'index': m}),
              ),
          ],
        ),
        SemanticNode(
          id: const SemanticNodeId('input'),
          role: SemanticRole.textField,
          label: 'Message',
          value: '',
        ),
      ],
    ),
  );
}

void main() {
  test('encodeTree redacts O(changed) nodes on a steady-state patch', () {
    final encoder = SemanticsWireEncoder();
    final owner = SemanticsOwner();

    final t0 = _tree(messages: 80, tick: 0); // 84 nodes
    encoder.encodeTree(t0, update: owner.update(t0)); // full frame
    final nodeCount = t0.nodeCount;
    expect(nodeCount, greaterThan(80));
    expect(
      encoder.lastFlattenedNodeCount,
      nodeCount,
      reason: 'the first (full) frame redacts the whole tree',
    );

    // One steady-state patch: only `status` and the last message change (2
    // nodes), everything else is identical.
    final t1 = _tree(messages: 80, tick: 1);
    final patch = encoder.encodeTree(t1, update: owner.update(t1));
    expect(patch, isNotNull);
    expect(
      encoder.lastFlattenedNodeCount,
      2,
      reason: 'a 2-node change must redact exactly the 2 changed nodes — a '
          'revert to full-tree redaction every frame (O(tree)) trips this',
    );
    // Guard the asymptote too, independent of the exact count: nowhere near the
    // whole tree.
    expect(encoder.lastFlattenedNodeCount, lessThan(nodeCount ~/ 4));
  });

  test('encodeTree is byte-identical to the snapshot path on the wire', () {
    // The on-demand patch path must be indistinguishable from full-snapshot
    // encoding: for every frame, the bytes from encodeTree(tree, update) equal
    // the bytes from encode(tree.toInspectionSnapshot()). If the owner's update
    // ever misses a changed node, this diverges (and the encoder's debug oracle
    // fires) — so it doubles as a correctness check on the changed-set.
    final treeEnc = SemanticsWireEncoder();
    final snapEnc = SemanticsWireEncoder();
    final owner = SemanticsOwner();

    // Vary the message count between frames to exercise added/removed subtrees,
    // not just label churn — the update path (added/removed sets) and the
    // no-delta snapshot path (structural compare) must still agree byte-for-byte.
    const counts = [40, 40, 60, 55, 20, 40, 40];
    for (var tick = 0; tick < counts.length; tick++) {
      final t = _tree(messages: counts[tick], tick: tick);
      final viaTree = treeEnc.encodeTree(t, update: owner.update(t));
      final viaSnap = snapEnc.encode(t.toInspectionSnapshot());
      expect(
        viaTree,
        viaSnap,
        reason: 'encodeTree and encode diverged on the wire at frame $tick',
      );
    }
  });

  test('duplicate node ids stay self-consistent (the debug oracle holds)', () {
    SemanticTree dupTree({required int tick, required bool bothPresent}) {
      return SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: const SemanticNodeId('dup'),
              role: SemanticRole.status,
              label: 'A$tick',
            ),
            if (bothPresent)
              SemanticNode(
                id: const SemanticNodeId('dup'),
                role: SemanticRole.status,
                label: 'B$tick',
              ),
            SemanticNode(
              id: const SemanticNodeId('tail'),
              role: SemanticRole.text,
              label: 'tail',
            ),
          ],
        ),
      );
    }

    final encoder = SemanticsWireEncoder();
    final owner = SemanticsOwner();
    // A duplicate `dup` id is a degraded state, but the on-demand patch path
    // must still resolve it the way the full flatten and the debug oracle do
    // (last-wins). Each encodeTree runs its oracle — a full re-flatten compared
    // to `_sent` — and THROWS if the patch diverged. Drive full → label churn →
    // drop one of the duplicates. (Fails the pre-fix first-wins full path, whose
    // oracle would fire the moment the last `dup` node changes.)
    const frames = [(0, true), (1, true), (2, true), (3, false)];
    for (final frame in frames) {
      final t = dupTree(tick: frame.$1, bothPresent: frame.$2);
      expect(
        () => encoder.encodeTree(t, update: owner.update(t)),
        returnsNormally,
        reason: 'the O(changed) patch diverged from the full flatten on a '
            'duplicate id (the oracle fired)',
      );
    }
  });
}
