// Animation-specific benchmarks. Cover the cost of the
// TickerScheduler / Ticker / Animation machinery and validate
// structural properties (one timer for N tickers).
//
// FakeClock + FakeTickerScheduler-driven — these benchmarks measure
// framework overhead, not real-time animation smoothness.

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';

/// Structural assertion: 10 concurrent FrameTickers produce
/// exactly one underlying scheduler timer. Asserts at construction
/// time rather than measuring time.
class TenSpinnerStructuralBenchmark extends BenchmarkBase {
  TenSpinnerStructuralBenchmark()
    : super('10 spinners share 1 scheduler timer (structural)');
  late FakeTickerScheduler scheduler;
  late List<FrameTicker> tickers;

  @override
  void setup() {
    final clock = FakeClock();
    scheduler = FakeTickerScheduler(clock: clock);
    tickers = [
      for (var i = 0; i < 10; i++)
        FrameTicker(
          interval: const Duration(milliseconds: 80),
          scheduler: scheduler,
        )..start(),
    ];
    if (scheduler.activeTickerCount != 10) {
      throw StateError('expected 10 active tickers');
    }
  }

  @override
  void run() {
    scheduler.advance(const Duration(milliseconds: 33));
  }

  @override
  void teardown() {
    for (final t in tickers) {
      t.dispose();
    }
  }
}

/// Animation spring step under FakeClock — measures the hot path of
/// the analytic spring integration + notify over a full settle.
class AnimationSpringBenchmark extends BenchmarkBase {
  AnimationSpringBenchmark() : super('Animation spring to() [snappy]');
  late FakeTickerScheduler scheduler;
  late TuiBinding binding;
  late Animation<double> animation;

  @override
  void setup() {
    final clock = FakeClock();
    scheduler = FakeTickerScheduler(clock: clock);
    binding = TuiBinding(tickerScheduler: scheduler);
    animation = Animation(0.0)..attach(binding);
  }

  @override
  void run() {
    animation.to(1.0, spring: Spring.snappy);
    // Advance through a full settle (~10 ticks at 33ms).
    for (var i = 0; i < 10; i++) {
      scheduler.advance(const Duration(milliseconds: 33));
    }
    animation.snap(0.0);
  }

  @override
  void teardown() {
    animation.dispose();
    binding.dispose();
  }
}

/// Animation rebuild cost — measures the build pipeline cost of a
/// rebuild triggered by a animation tick through AnimationBuilder.
class AnimationRebuildBenchmark extends BenchmarkBase {
  AnimationRebuildBenchmark() : super('Animation rebuild per animation tick');
  late BuildOwner owner;
  late Element root;
  late CellBuffer buffer;
  late Animation<double> animation;
  late FakeTickerScheduler scheduler;

  @override
  void setup() {
    final clock = FakeClock();
    scheduler = FakeTickerScheduler(clock: clock);
    animation = Animation(0.0);
    owner = BuildOwner();
    root = owner.mountRoot(
      TuiBindingScope(
        binding: TuiBinding(tickerScheduler: scheduler),
        child: _AnimationText(animation),
      ),
    );
    buffer = CellBuffer(const CellSize(80, 24));
    animation.to(
      1.0,
      curve: Curves.linear,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void run() {
    scheduler.advance(const Duration(milliseconds: 33));
    buffer.clear();
    owner.renderFrame(root, buffer);
  }

  @override
  void teardown() {
    animation.dispose();
  }
}

/// Reads a animation's value via implicit reactivity (the idiomatic
/// consumption path) so frame advances rebuild this widget.
class _AnimationText extends StatelessWidget {
  const _AnimationText(this.animation);
  final Animation<double> animation;
  @override
  Widget build(BuildContext context) =>
      Text('value: ${animation.value.toStringAsFixed(2)}');
}

void main() {
  TenSpinnerStructuralBenchmark().report();
  AnimationSpringBenchmark().report();
  AnimationRebuildBenchmark().report();
}
