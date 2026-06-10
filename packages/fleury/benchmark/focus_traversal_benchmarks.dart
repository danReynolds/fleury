// Microbenchmarks for directional focus traversal. These measure target
// selection over mounted focus nodes with real element ancestry, but without
// rendering a frame on every iteration. That isolates the arrow-navigation
// policy from layout and paint costs.

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';

class FocusTraversalGridBenchmark extends BenchmarkBase {
  FocusTraversalGridBenchmark({
    required this.rows,
    required this.cols,
    required String label,
  }) : super('focus_traversal_right[$label, ${rows * cols} nodes]');

  final int rows;
  final int cols;

  late final FocusManager manager;
  late final BuildOwner owner;
  late final Element root;
  late final List<FocusNode> nodes;
  late final FocusNode source;
  FocusNode? _lastTarget;

  @override
  void setup() {
    manager = FocusManager();
    owner = BuildOwner();
    nodes = List<FocusNode>.generate(
      rows * cols,
      (i) => FocusNode(debugLabel: 'cell $i'),
    );
    root = owner.mountRoot(
      FocusManagerScope(
        manager: manager,
        child: Column(
          children: List<Widget>.generate(rows, (row) {
            return Row(
              children: List<Widget>.generate(cols, (col) {
                final index = row * cols + col;
                return SizedBox(
                  width: 1,
                  height: 1,
                  child: Focus(
                    focusNode: nodes[index],
                    child: const Text('x', allowSelect: false),
                  ),
                );
              }),
            );
          }),
        ),
      ),
    );
    owner.renderFrame(root, CellBuffer(CellSize(cols, rows)));
    final sourceRow = rows ~/ 2;
    source = nodes[sourceRow * cols];
    source.requestFocus();
    _lastTarget = _target();
    final expected = nodes[sourceRow * cols + 1];
    if (!identical(_lastTarget, expected)) {
      throw StateError('Traversal benchmark target sanity check failed.');
    }
  }

  @override
  void run() {
    _lastTarget = _target();
  }

  FocusNode? _target() {
    return nearestFocusableInDirection(
      from: source.rect!,
      candidates: manager.traversalCandidates(),
      excluding: source,
      direction: TraversalDirection.right,
    );
  }
}

void main() {
  FocusTraversalGridBenchmark(rows: 10, cols: 20, label: 'reasonable').report();
  FocusTraversalGridBenchmark(rows: 50, cols: 100, label: 'large').report();
}
