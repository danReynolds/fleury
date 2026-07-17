// AnimationBuilder<T>: the declarative value-tracks-state widget.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('first build snaps to the value (no animation)', (tester) {
    tester.pumpWidget(AnimationBuilder<int>(5, builder: (_, v) => Text('$v')));
    expect(tester.renderToString(size: const CellSize(4, 1)), '5\n');
  });

  testWidgets('animates when the value prop changes across a rebuild', (
    tester,
  ) {
    tester.pumpWidget(
      AnimationBuilder<int>(
        0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, v) => Text('$v'),
      ),
    );
    expect(tester.renderToString(size: const CellSize(4, 1)), '0\n');

    // Rebuild with a new target.
    tester.pumpWidget(
      AnimationBuilder<int>(
        10,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, v) => Text('$v'),
      ),
    );
    tester.pump(const Duration(milliseconds: 50));
    final mid = int.parse(
      tester.renderToString(size: const CellSize(4, 1)).trim(),
    );
    expect(mid, inExclusiveRange(0, 10));

    tester.pump(const Duration(milliseconds: 100));
    expect(tester.renderToString(size: const CellSize(4, 1)), '10\n');
  });

  testWidgets('rebuilding with the same value does not animate', (tester) {
    tester.pumpWidget(AnimationBuilder<int>(7, builder: (_, v) => Text('$v')));
    tester.pumpWidget(AnimationBuilder<int>(7, builder: (_, v) => Text('$v')));
    expect(tester.scheduler.activeTickerCount, 0);
    expect(tester.renderToString(size: const CellSize(4, 1)), '7\n');
  });

  testWidgets('releases its ticker once settled (auto-managed)', (tester) {
    tester.pumpWidget(
      AnimationBuilder<int>(
        0,
        spring: Spring.snappy,
        builder: (_, v) => Text('$v'),
      ),
    );
    tester.pumpWidget(
      AnimationBuilder<int>(
        100,
        spring: Spring.snappy,
        builder: (_, v) => Text('$v'),
      ),
    );
    expect(tester.scheduler.activeTickerCount, 1);
    tester.pump(const Duration(seconds: 1));
    expect(tester.scheduler.activeTickerCount, 0);
  });

  testWidgets('unmounting disposes the owned animation (no leak)', (tester) {
    tester.pumpWidget(AnimationBuilder<int>(0, builder: (_, v) => Text('$v')));
    tester.pumpWidget(AnimationBuilder<int>(50, builder: (_, v) => Text('$v')));
    tester.pump(const Duration(milliseconds: 16));
    // Replace with something that has no animation; old AnimationBuilder
    // unmounts and must release its ticker.
    tester.pumpWidget(const Text('gone'));
    expect(tester.scheduler.activeTickerCount, 0);
    expect(() => tester.pump(const Duration(seconds: 1)), returnsNormally);
  });

  testWidgets('RgbColor value animates channel-wise', (tester) {
    bool isBlack(FleuryTester t) =>
        t.render(size: const CellSize(1, 1)).atColRow(0, 0).style.foreground ==
        const RgbColor(0, 0, 0);

    tester.pumpWidget(
      AnimationBuilder<RgbColor>(
        const RgbColor(0, 0, 0),
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, c) => Text('x', style: CellStyle(foreground: c)),
      ),
    );
    expect(isBlack(tester), isTrue);

    tester.pumpWidget(
      AnimationBuilder<RgbColor>(
        const RgbColor(255, 255, 255),
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, c) => Text('x', style: CellStyle(foreground: c)),
      ),
    );
    tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.render(size: const CellSize(1, 1)).atColRow(0, 0).style.foreground,
      const RgbColor(255, 255, 255),
    );
  });
}
