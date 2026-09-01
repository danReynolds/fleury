// AnimationBuilder<T>: the declarative value-tracks-state widget.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

class _BuildProbe extends StatelessWidget {
  const _BuildProbe(this.onBuild);

  final void Function() onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const Text('static');
  }
}

void main() {
  testWidgets('first build snaps to the value (no animation)', (tester) {
    tester.pumpWidget(
      AnimationBuilder<int>(5, builder: (_, v, child) => Text('$v')),
    );
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
        builder: (_, v, child) => Text('$v'),
      ),
    );
    expect(tester.renderToString(size: const CellSize(4, 1)), '0\n');

    // Rebuild with a new target.
    tester.pumpWidget(
      AnimationBuilder<int>(
        10,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, v, child) => Text('$v'),
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
    tester.pumpWidget(
      AnimationBuilder<int>(7, builder: (_, v, child) => Text('$v')),
    );
    tester.pumpWidget(
      AnimationBuilder<int>(7, builder: (_, v, child) => Text('$v')),
    );
    expect(tester.scheduler.activeTickerCount, 0);
    expect(tester.renderToString(size: const CellSize(4, 1)), '7\n');
  });

  testWidgets('releases its ticker once settled (auto-managed)', (tester) {
    tester.pumpWidget(
      AnimationBuilder<int>(
        0,
        spring: Spring.snappy,
        builder: (_, v, child) => Text('$v'),
      ),
    );
    tester.pumpWidget(
      AnimationBuilder<int>(
        100,
        spring: Spring.snappy,
        builder: (_, v, child) => Text('$v'),
      ),
    );
    expect(tester.scheduler.activeTickerCount, 1);
    tester.pump(const Duration(seconds: 1));
    expect(tester.scheduler.activeTickerCount, 0);
  });

  testWidgets('unmounting disposes the owned animation (no leak)', (tester) {
    tester.pumpWidget(
      AnimationBuilder<int>(0, builder: (_, v, child) => Text('$v')),
    );
    tester.pumpWidget(
      AnimationBuilder<int>(50, builder: (_, v, child) => Text('$v')),
    );
    tester.pump(const Duration(milliseconds: 16));
    // Replace with something that has no animation; old AnimationBuilder
    // unmounts and must release its ticker.
    tester.pumpWidget(const Text('gone'));
    expect(tester.scheduler.activeTickerCount, 0);
    expect(() => tester.pump(const Duration(seconds: 1)), returnsNormally);
  });

  testWidgets('under TickerMode(enabled: false) the animation freezes '
      '(hidden subtree does not animate or rebuild)', (tester) {
    Widget build(int target) => TickerMode(
      enabled: false,
      child: AnimationBuilder<int>(
        target,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, v, child) => Text('$v'),
      ),
    );

    tester.pumpWidget(build(0));
    expect(tester.renderToString(size: const CellSize(4, 1)), '0\n');

    // Retarget inside the muted subtree: the ticker starts but its
    // callback must be muted, so the value stays pinned at the
    // pre-retarget position instead of interpolating toward 10.
    tester.pumpWidget(build(10));
    tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.renderToString(size: const CellSize(4, 1)),
      '0\n',
      reason: 'muted subtree: value frozen mid-flight',
    );
    tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.renderToString(size: const CellSize(4, 1)),
      '0\n',
      reason: 'muted subtree: still frozen after the full duration',
    );
  });

  testWidgets('flipping TickerMode back to enabled resumes the animation', (
    tester,
  ) {
    Widget build({required bool enabled, required int target}) => TickerMode(
      enabled: enabled,
      child: AnimationBuilder<int>(
        target,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, v, child) => Text('$v'),
      ),
    );

    tester.pumpWidget(build(enabled: false, target: 0));
    tester.pumpWidget(build(enabled: false, target: 10));
    tester.pump(const Duration(milliseconds: 50));
    expect(tester.renderToString(size: const CellSize(4, 1)), '0\n');

    // Un-mute: the retarget that was frozen must now play out. Elapsed
    // time kept tracking the clock while muted, so on resume the curve
    // lands at its clock-relative position (no replay of missed frames).
    tester.pumpWidget(build(enabled: true, target: 10));
    tester.pump(const Duration(milliseconds: 100));
    expect(tester.renderToString(size: const CellSize(4, 1)), '10\n');
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
        builder: (_, c, child) => Text('x', style: CellStyle(foreground: c)),
      ),
    );
    expect(isBlack(tester), isTrue);

    tester.pumpWidget(
      AnimationBuilder<RgbColor>(
        const RgbColor(255, 255, 255),
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        builder: (_, c, child) => Text('x', style: CellStyle(foreground: c)),
      ),
    );
    tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.render(size: const CellSize(1, 1)).atColRow(0, 0).style.foreground,
      const RgbColor(255, 255, 255),
    );
  });

  testWidgets('passes a static child through without rebuilding it', (tester) {
    var childBuilds = 0;
    final child = _BuildProbe(() => childBuilds++);

    Widget build(int target) => AnimationBuilder<int>(
      target,
      curve: Curves.linear,
      duration: const Duration(milliseconds: 100),
      child: child,
      builder: (_, value, child) => Row(children: [Text('$value '), child!]),
    );

    tester.pumpWidget(build(0));
    expect(childBuilds, 1);

    tester.pumpWidget(build(10));
    tester.pump(const Duration(milliseconds: 50));
    tester.pump(const Duration(milliseconds: 50));
    expect(childBuilds, 1, reason: 'the unchanged child subtree is reused');
  });

  testWidgets('onEnd fires only for the latest completed target', (
    tester,
  ) async {
    var completions = 0;

    Widget build(int target) => AnimationBuilder<int>(
      target,
      curve: Curves.linear,
      duration: const Duration(milliseconds: 100),
      onEnd: () => completions++,
      builder: (_, value, child) => Text('$value'),
    );

    tester.pumpWidget(build(0));
    expect(completions, 0, reason: 'the initial value does not animate');

    tester.pumpWidget(build(10));
    tester.pump(const Duration(milliseconds: 50));
    tester.pumpWidget(build(20));
    await Future<void>.delayed(Duration.zero);
    expect(completions, 0, reason: 'the superseded target was canceled');

    tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(Duration.zero);
    expect(completions, 1);
  });

  testWidgets('onEnd does not fire after disposal', (tester) async {
    var completions = 0;

    tester.pumpWidget(
      AnimationBuilder<int>(
        0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        onEnd: () => completions++,
        builder: (_, value, child) => Text('$value'),
      ),
    );
    tester.pumpWidget(
      AnimationBuilder<int>(
        10,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        onEnd: () => completions++,
        builder: (_, value, child) => Text('$value'),
      ),
    );
    tester.pumpWidget(const Text('gone'));
    await Future<void>.delayed(Duration.zero);

    expect(completions, 0);
  });

  test('rejects timing options that would otherwise be ignored', () {
    expect(
      () => AnimationBuilder<double>(
        1,
        spring: Spring.snappy,
        curve: Curves.linear,
        builder: (_, value, child) => Text('$value'),
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => AnimationBuilder<double>(
        1,
        duration: const Duration(milliseconds: 100),
        builder: (_, value, child) => Text('$value'),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('rejects invalid timing before the first target change', (
    tester,
  ) {
    expect(
      () => tester.pumpWidget(
        AnimationBuilder<double>(
          1,
          curve: Curves.linear,
          duration: const Duration(milliseconds: -1),
          builder: (_, value, child) => Text('$value'),
        ),
      ),
      throwsArgumentError,
    );

    expect(
      () => tester.pumpWidget(
        AnimationBuilder<double>(
          1,
          spring: const Spring(response: Duration.zero),
          builder: (_, value, child) => Text('$value'),
        ),
      ),
      throwsArgumentError,
    );
  });
}
