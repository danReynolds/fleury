// Does `_nodeId` recomputation need the deferred structure-generation cache?
//
// `_nodeId` is recomputed on every read. For an UNKEYED node it calls
// `semanticAnchorOf`, which walks the element tree to the nearest key (or the
// root) and calls `_childIndexOf` at each level — and `_childIndexOf` is O(width)
// (it `visitChildren` to find the index). So a WIDE unkeyed parent makes the
// whole semantic build O(K²): each of K children scans all K siblings.
//
// This measures the real cost: `SemanticTree.fromElement` on a wide tree of
// UNKEYED semantic leaves (the O(K²) path) vs the same tree with explicit
// `Semantics(id:)` on each leaf (O(1) `_nodeId`, no anchor walk). The delta is
// what a cache would save. Run: dart run bin/semantic_id_probe.dart

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_host.dart';

// A wide Column of semantic leaves. When [withIds] the leaf carries an explicit
// id (the O(1) path); otherwise it's unkeyed (the anchor-walk path).
Widget _scene(int width, {required bool withIds}) => Column(
  children: [
    for (var i = 0; i < width; i++)
      withIds
          ? Semantics(
              id: SemanticNodeId('leaf-$i'),
              role: SemanticRole.button,
              label: 'row $i',
              child: const SizedBox(width: 10, height: 1),
            )
          : Semantics(
              role: SemanticRole.button,
              label: 'row $i',
              child: const SizedBox(width: 10, height: 1),
            ),
  ],
);

double _timeBuild({
  required int width,
  required bool withIds,
  required int iters,
  required int warmup,
}) {
  final owner = BuildOwner();
  final root = owner.mountRoot(_scene(width, withIds: withIds));
  // Force a layout so the element tree is fully mounted before we time the
  // semantic assembly.
  final size = CellSize(20, width + 2);
  var front = CellBuffer(size);
  owner.renderFrame(root, front);

  var totalUs = 0;
  final sw = Stopwatch();
  for (var i = 0; i < warmup + iters; i++) {
    sw
      ..reset()
      ..start();
    SemanticTree.fromElement(root);
    sw.stop();
    if (i >= warmup) totalUs += sw.elapsedMicroseconds;
  }
  return totalUs / iters;
}

void main() {
  print('SemanticTree.fromElement — unkeyed (anchor walk) vs explicit id:');
  print('${'width'.padLeft(6)}  ${'unkeyed µs'.padLeft(11)}  '
      '${'id: µs'.padLeft(9)}  ${'overhead'.padLeft(9)}');
  print('-' * 44);
  for (final width in [20, 50, 100, 200, 400]) {
    final iters = width >= 200 ? 300 : 800;
    final unkeyed = _timeBuild(
      width: width,
      withIds: false,
      iters: iters,
      warmup: 100,
    );
    final keyed = _timeBuild(
      width: width,
      withIds: true,
      iters: iters,
      warmup: 100,
    );
    print('${width.toString().padLeft(6)}  '
        '${unkeyed.toStringAsFixed(1).padLeft(11)}  '
        '${keyed.toStringAsFixed(1).padLeft(9)}  '
        '${(unkeyed - keyed).toStringAsFixed(1).padLeft(7)}µs');
  }
  print('');
  print('overhead = the _nodeId anchor-walk cost a structure-gen cache removes.');
  print('At 60fps a frame is 16667µs; the semantic build runs post-frame,');
  print('coalesced, only on a semantically-dirty frame.');
}
