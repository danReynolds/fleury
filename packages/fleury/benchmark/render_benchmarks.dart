// Diff-renderer microbenchmarks. Measure the cost of AnsiRenderer
// alone (not paint, not layout) for the four canonical cases:
//   - no change (best case)
//   - one cell change (typical interactive update)
//   - full repaint (worst case)
//   - typical content swap (one row of text changes)
//
// Each benchmark uses a NullAnsiSink so the timing reflects the
// renderer's own work, not the cost of the downstream sink.

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';

import '_support.dart';

const _size = CellSize(80, 24);

class DiffNoChangeBenchmark extends BenchmarkBase {
  DiffNoChangeBenchmark() : super('diff_no_change[80x24]');
  late final CellBuffer prev;
  late final CellBuffer next;
  late final NullAnsiSink sink;

  @override
  void setup() {
    prev = textBuffer(_size, 'hello world from the fleury benchmark');
    next = copyOf(prev);
    sink = const NullAnsiSink();
  }

  @override
  void run() {
    const AnsiRenderer().renderDiff(prev, next, sink);
  }
}

class DiffSingleCellBenchmark extends BenchmarkBase {
  DiffSingleCellBenchmark() : super('diff_single_cell[80x24]');
  late final CellBuffer prev;
  late final CellBuffer next;
  late final NullAnsiSink sink;

  @override
  void setup() {
    prev = textBuffer(_size, 'hello world from the fleury benchmark');
    next = copyOf(prev);
    next.writeGrapheme(const CellOffset(5, 12), 'X');
    sink = const NullAnsiSink();
  }

  @override
  void run() {
    const AnsiRenderer().renderDiff(prev, next, sink);
  }
}

class DiffFullRepaintBenchmark extends BenchmarkBase {
  DiffFullRepaintBenchmark() : super('diff_full_repaint[80x24]');
  late final CellBuffer prev;
  late final CellBuffer next;
  late final NullAnsiSink sink;

  @override
  void setup() {
    prev = CellBuffer(_size);
    next = denseBuffer(_size, '#');
    sink = const NullAnsiSink();
  }

  @override
  void run() {
    const AnsiRenderer().renderDiff(prev, next, sink);
  }
}

class DiffSingleRowChangeBenchmark extends BenchmarkBase {
  DiffSingleRowChangeBenchmark() : super('diff_row_change[80x24]');
  late final CellBuffer prev;
  late final CellBuffer next;
  late final NullAnsiSink sink;

  @override
  void setup() {
    prev = textBuffer(_size, 'hello world from the fleury benchmark');
    next = copyOf(prev);
    // Repaint one full row.
    for (var col = 0; col < _size.cols; col++) {
      next.writeGrapheme(CellOffset(col, 5), '*');
    }
    sink = const NullAnsiSink();
  }

  @override
  void run() {
    const AnsiRenderer().renderDiff(prev, next, sink);
  }
}

/// Larger viewport so we can see how the cost scales.
class DiffNoChangeLargeBenchmark extends BenchmarkBase {
  DiffNoChangeLargeBenchmark() : super('diff_no_change[200x60]');
  late final CellBuffer prev;
  late final CellBuffer next;
  late final NullAnsiSink sink;

  @override
  void setup() {
    prev = textBuffer(
      const CellSize(200, 60),
      'hello world from the fleury benchmark suite',
    );
    next = copyOf(prev);
    sink = const NullAnsiSink();
  }

  @override
  void run() {
    const AnsiRenderer().renderDiff(prev, next, sink);
  }
}

void main() {
  DiffNoChangeBenchmark().report();
  DiffSingleCellBenchmark().report();
  DiffSingleRowChangeBenchmark().report();
  DiffFullRepaintBenchmark().report();
  DiffNoChangeLargeBenchmark().report();
}
