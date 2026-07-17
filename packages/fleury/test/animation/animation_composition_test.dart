// Animation composition: loop (repeat / ping-pong) and run (sequence).
// All clock-driven, so FakeClock advances them deterministically.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void _host<T>(FleuryTester tester, Animation<T> m) {
  tester.pumpWidget(_Show(m));
}

class _Show extends StatelessWidget {
  const _Show(this.animation);
  final Animation<Object?> animation;
  @override
  Widget build(BuildContext context) => Text('${animation.value}');
}

void main() {
  group('loop', () {
    testWidgets('ping-pong returns toward the start after a full '
        'cycle', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.loop(
        between: (0.0, 1.0),
        period: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      // Starts at a.
      expect(m.value, closeTo(0.0, 0.01));
      // Half a leg in: heading toward b.
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, closeTo(0.5, 0.1));
      // End of first leg: at b.
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, closeTo(1.0, 0.05));
      // Into the second (mirrored) leg: heading back toward a.
      tester.pump(const Duration(milliseconds: 100));
      expect(
        m.value,
        lessThan(0.9),
        reason: 'mirror leg moves back toward the start',
      );
    });

    testWidgets('keeps a ticker active (no natural end)', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.loop(between: (0.0, 1.0));
      tester.pump(const Duration(seconds: 2));
      expect(
        tester.scheduler.activeTickerCount,
        1,
        reason: 'a loop never settles on its own',
      );
    });

    testWidgets('to() supersedes a loop and cancels its future', (
      tester,
    ) async {
      final m = Animation(0.0);
      _host(tester, m);
      final looped = m.loop(between: (0.0, 1.0));
      tester.pump(const Duration(milliseconds: 100));
      m.to(0.5, spring: Spring.snappy);
      await expectLater(looped.orCancel, throwsA(isA<TickerCanceled>()));
      tester.pump(const Duration(seconds: 1));
      expect(m.value, closeTo(0.5, 0.01));
      expect(tester.scheduler.activeTickerCount, 0);
    });
  });

  group('run', () {
    testWidgets('executes steps back to back', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.run([
        AnimationStep.to(
          1.0,
          curve: Curves.linear,
          duration: const Duration(milliseconds: 100),
        ),
        AnimationStep.to(
          0.5,
          curve: Curves.linear,
          duration: const Duration(milliseconds: 100),
        ),
      ]);
      // After first leg.
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, closeTo(1.0, 0.05));
      // Through the second leg.
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, closeTo(0.5, 0.05));
    });

    testWidgets('hold waits between steps (clock-driven)', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.run([
        AnimationStep.to(
          1.0,
          curve: Curves.linear,
          duration: const Duration(milliseconds: 100),
        ),
        const AnimationStep.hold(Duration(milliseconds: 200)),
        AnimationStep.to(
          0.0,
          curve: Curves.linear,
          duration: const Duration(milliseconds: 100),
        ),
      ]);
      tester.pump(const Duration(milliseconds: 100)); // reach 1.0
      expect(m.value, closeTo(1.0, 0.05));
      tester.pump(const Duration(milliseconds: 100)); // mid-hold
      expect(m.value, closeTo(1.0, 0.05), reason: 'still holding at 1.0');
      tester.pump(
        const Duration(milliseconds: 150),
      ); // finish hold + start last
      tester.pump(const Duration(milliseconds: 100)); // finish last leg
      expect(m.value, closeTo(0.0, 0.05));
    });

    testWidgets('completion future fires after the last step', (tester) async {
      final m = Animation(0.0);
      _host(tester, m);
      var done = false;
      m
          .run([
            AnimationStep.to(
              1.0,
              curve: Curves.linear,
              duration: const Duration(milliseconds: 50),
            ),
            AnimationStep.to(
              2.0,
              curve: Curves.linear,
              duration: const Duration(milliseconds: 50),
            ),
          ])
          .then((_) => done = true);
      tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      expect(m.value, closeTo(2.0, 0.05));
      expect(tester.scheduler.activeTickerCount, 0);
    });
  });

  group('policy', () {
    testWidgets(
      'disabled: run snaps to the last target',
      (tester) {
        final m = Animation(0.0);
        _host(tester, m);
        m.run([
          AnimationStep.to(1.0, curve: Curves.linear),
          AnimationStep.to(0.7, curve: Curves.linear),
        ]);
        expect(m.value, 0.7);
        expect(m.isMoving, isFalse);
      },
      animationPolicy: AnimationPolicy.disabled,
    );

    testWidgets(
      'disabled: loop rests at the first value',
      (tester) {
        final m = Animation(0.0);
        _host(tester, m);
        m.loop(between: (0.2, 0.9));
        expect(m.value, 0.2);
        expect(m.isMoving, isFalse);
      },
      animationPolicy: AnimationPolicy.disabled,
    );
  });
}
