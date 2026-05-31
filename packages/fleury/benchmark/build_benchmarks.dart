// Build-phase microbenchmarks. Measures setState → flushBuild cost,
// reassembleApplication cost, and the find-min loop in flushBuild's
// dirty processing (which RFC 0009 H6 proposes to replace with a
// sort-once strategy).

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';

import '_support.dart';

/// Marks 1 element dirty, flushes. Measures the single-setState
/// fast path.
class FlushBuild1DirtyBenchmark extends BenchmarkBase {
  FlushBuild1DirtyBenchmark() : super('flushbuild_1_dirty');
  late final BuildOwner owner;
  late final List<BenchmarkCounterState> counters;

  @override
  void setup() {
    owner = BuildOwner();
    final root = owner.mountRoot(const CounterColumn(count: 100));
    counters = collectCounters(root);
  }

  @override
  void run() {
    counters[42].poke(() => counters[42].value += 1);
    owner.flushBuild();
  }
}

/// Marks 10 elements dirty, flushes.
class FlushBuild10DirtyBenchmark extends BenchmarkBase {
  FlushBuild10DirtyBenchmark() : super('flushbuild_10_dirty');
  late final BuildOwner owner;
  late final List<BenchmarkCounterState> counters;

  @override
  void setup() {
    owner = BuildOwner();
    final root = owner.mountRoot(const CounterColumn(count: 200));
    counters = collectCounters(root);
  }

  @override
  void run() {
    for (var i = 0; i < 10; i++) {
      counters[i * 17].poke(() => counters[i * 17].value += 1);
    }
    owner.flushBuild();
  }
}

/// Marks 100 elements dirty, flushes. RFC 0009 H6 expects the
/// quadratic find-min to start showing up here.
class FlushBuild100DirtyBenchmark extends BenchmarkBase {
  FlushBuild100DirtyBenchmark() : super('flushbuild_100_dirty');
  late final BuildOwner owner;
  late final List<BenchmarkCounterState> counters;

  @override
  void setup() {
    owner = BuildOwner();
    final root = owner.mountRoot(const CounterColumn(count: 200));
    counters = collectCounters(root);
  }

  @override
  void run() {
    for (var i = 0; i < 100; i++) {
      counters[i].poke(() => counters[i].value += 1);
    }
    owner.flushBuild();
  }
}

/// Reassemble a 200-element tree. Stresses the same find-min loop
/// plus the reassemble walk itself.
class ReassembleWalkBenchmark extends BenchmarkBase {
  ReassembleWalkBenchmark() : super('reassemble_walk[200 elements]');
  late final BuildOwner owner;

  @override
  void setup() {
    owner = BuildOwner();
    owner.mountRoot(const CounterColumn(count: 200));
  }

  @override
  void run() {
    owner.reassembleApplication();
  }
}

class MountTearDownBenchmark extends BenchmarkBase {
  MountTearDownBenchmark() : super('mount+unmount[100 counters]');

  @override
  void run() {
    final owner = BuildOwner();
    final root = owner.mountRoot(const CounterColumn(count: 100));
    root.unmount();
  }
}

void main() {
  FlushBuild1DirtyBenchmark().report();
  FlushBuild10DirtyBenchmark().report();
  FlushBuild100DirtyBenchmark().report();
  ReassembleWalkBenchmark().report();
  MountTearDownBenchmark().report();
}
