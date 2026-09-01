// Animation composition: loop (repeat / ping-pong) and fluent chains.
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

  group('chained runs', () {
    testWidgets('executes targets back to back', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m
          .to(
            1.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 100),
          )
          .to(
            0.5,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 100),
          );
      // After first leg.
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, closeTo(1.0, 0.05));
      // Through the second leg.
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, closeTo(0.5, 0.05));
    });

    testWidgets('delay waits between steps (clock-driven)', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m
          .to(
            1.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 100),
          )
          .delay(const Duration(milliseconds: 200))
          .to(
            0.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 100),
          );
      tester.pump(const Duration(milliseconds: 100)); // reach 1.0
      expect(m.value, closeTo(1.0, 0.05));
      tester.pump(const Duration(milliseconds: 100)); // mid-delay
      expect(m.value, closeTo(1.0, 0.05), reason: 'still delayed at 1.0');
      tester.pump(
        const Duration(milliseconds: 150),
      ); // finish delay + start last
      tester.pump(const Duration(milliseconds: 100)); // finish last leg
      expect(m.value, closeTo(0.0, 0.05));
    });

    testWidgets('completion future fires after the last step', (tester) async {
      final m = Animation(0.0);
      _host(tester, m);
      var done = false;
      m
          .to(
            1.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 50),
          )
          .to(
            2.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 50),
          )
          .then((_) => done = true);
      tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      expect(m.value, closeTo(2.0, 0.05));
      expect(tester.scheduler.activeTickerCount, 0);
    });

    testWidgets('a direct retarget cancels the whole appended run', (
      tester,
    ) async {
      final m = Animation(0.0);
      _host(tester, m);
      final run = m
          .to(
            1.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 100),
          )
          .delay(const Duration(milliseconds: 200))
          .to(
            2.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 100),
          );

      tester.pump(const Duration(milliseconds: 50));
      m.to(
        0.25,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );

      await expectLater(run.orCancel, throwsA(isA<TickerCanceled>()));
      tester.pump(const Duration(milliseconds: 200));
      expect(m.value, closeTo(0.25, 0.01));
    });

    testWidgets('a completed run cannot be extended', (tester) async {
      final m = Animation(0.0);
      _host(tester, m);
      final run = m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 50),
      );
      tester.pump(const Duration(milliseconds: 100));
      await run;

      expect(
        () => run.delay(const Duration(milliseconds: 10)),
        throwsStateError,
      );
      expect(() => run.to(2.0), throwsStateError);
    });
  });

  group('policy', () {
    testWidgets(
      'disabled: a chained run snaps to the last target',
      (tester) {
        final m = Animation(0.0);
        _host(tester, m);
        m
            .to(1.0, curve: Curves.linear)
            .delay(const Duration(seconds: 1))
            .to(0.7, curve: Curves.linear);
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
