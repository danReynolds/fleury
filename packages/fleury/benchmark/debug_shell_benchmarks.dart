// Measures the per-frame cost the DebugShell adds in three configs:
//
//   - shell off (no DebugShell wrapping the tree)        — baseline
//   - shell wrapping + mode=off + no listeners            — what every
//                                                            production
//                                                            user pays
//   - shell wrapping + mode=docked + DebugPanel mounted   — what a
//                                                            developer
//                                                            pays
//
// The interesting comparison is baseline vs production: anything more
// than a few microseconds of overhead in mode=off is a regression
// against the "zero-cost when off" promise.

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_panel.dart';
import 'package:fleury/src/debug/debug_shell.dart';
import 'package:fleury/src/debug/debug_state.dart';

import '_support.dart';

const _size = CellSize(80, 24);

class _FrameBenchmark extends BenchmarkBase {
  _FrameBenchmark(super.label, this._buildRoot);

  final Widget Function() _buildRoot;
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(_buildRoot());
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

void main() {
  // 30 counters in a Column: enough to be a real tree, small enough
  // to not dominate the runtime cost.
  Widget tree() => const CounterColumn(count: 30);

  // 1. Baseline: no DebugShell at all.
  _FrameBenchmark('frame_no_shell[80x24,30 counters]', tree).report();

  // 2. Production-shape: DebugShell mounted, mode=off, NO listener
  //    on DebugEvents. This is what every user pays even with debug
  //    "compiled in." Should match baseline within noise.
  _FrameBenchmark('frame_shell_off_no_listener', () {
    final c = DebugController(const DebugConfig());
    return DebugShell(controller: c, child: tree());
  }).report();

  // 3. Dev-shape: docked panel actively rendering. Establishes the
  //    "what does debug cost when on?" upper bound.
  _FrameBenchmark('frame_shell_docked', () {
    final c = DebugController(const DebugConfig(startMode: DebugMode.docked));
    return DebugShell(controller: c, child: tree());
  }).report();

  // 4. Fully opted out via config: should match baseline exactly.
  _FrameBenchmark('frame_shell_disabled', () {
    final c = DebugController(const DebugConfig(enabled: false));
    return DebugShell(controller: c, child: tree());
  }).report();

  // Reference: ensure DebugPanel imports are not stripped — we use
  // DebugPanel transitively via DebugShell. Suppress unused-import
  // by referencing the type.
  // ignore: unused_local_variable
  final DebugPanel? _ = null;
}
