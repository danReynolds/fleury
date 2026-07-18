// Animation<T> engine tests. FakeClock-driven via FleuryTester so the
// animation attaches to a real binding + scheduler.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Mounts a widget that reads [animation].value (implicit reactivity),
/// so the animation attaches to the tester's binding and animates.
void _host<T>(FleuryTester tester, Animation<T> animation) {
  tester.pumpWidget(_Show(animation));
}

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

class _Show extends StatelessWidget {
  const _Show(this.animation);
  final Animation<Object?> animation;
  @override
  Widget build(BuildContext context) => Text('${animation.value}');
}

void main() {
  group('construction + snap', () {
    testWidgets('starts at its initial value, not moving', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      expect(m.value, 0.0);
      expect(m.isMoving, isFalse);
    });

    testWidgets('snap jumps without animating', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.snap(0.5);
      expect(m.value, 0.5);
      expect(m.isMoving, isFalse);
    });
  });

  group('spring engine', () {
    testWidgets('settles at the target after enough time', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.to(1.0, spring: Spring.snappy);
      expect(m.isMoving, isTrue);

      tester.pump(const Duration(seconds: 1));
      expect(m.value, closeTo(1.0, 0.01));
      expect(m.isMoving, isFalse, reason: 'ticker stops once settled');
    });

    testWidgets('moves monotonically toward target for a critically '
        'damped spring (no overshoot)', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.to(1.0); // Spring.smooth, bounce 0 → critically damped
      var prev = m.value;
      var maxSeen = m.value;
      for (var i = 0; i < 40; i++) {
        tester.pump(const Duration(milliseconds: 16));
        expect(
          m.value,
          greaterThanOrEqualTo(prev - 1e-9),
          reason: 'should not move backward (no overshoot)',
        );
        maxSeen = m.value > maxSeen ? m.value : maxSeen;
        prev = m.value;
      }
      expect(
        maxSeen,
        lessThanOrEqualTo(1.0 + 1e-9),
        reason: 'critically damped: never exceeds target',
      );
    });

    testWidgets('velocity-preserving interruption: retarget mid-flight '
        'does not snap-restart', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.to(1.0);
      tester.pump(const Duration(milliseconds: 80));
      final midValue = m.value;
      expect(midValue, greaterThan(0.0));
      expect(midValue, lessThan(1.0));

      // Retarget to a new endpoint. The value should continue from
      // where it is (midValue), not jump back to 0.
      m.to(0.5);
      // One frame later it should still be near midValue, heading
      // toward 0.5 — not reset.
      tester.pump(const Duration(milliseconds: 16));
      expect(
        (m.value - midValue).abs(),
        lessThan(0.25),
        reason: 'retarget continues from current value, no restart',
      );

      tester.pump(const Duration(seconds: 1));
      expect(m.value, closeTo(0.5, 0.01));
    });
  });

  group('curve engine', () {
    testWidgets('reaches target at the end of the duration', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 300),
      );

      tester.pump(const Duration(milliseconds: 150));
      expect(m.value, closeTo(0.5, 0.1), reason: 'linear, halfway');

      tester.pump(const Duration(milliseconds: 200));
      expect(m.value, closeTo(1.0, 1e-9));
      expect(m.isMoving, isFalse);
    });
  });

  group('typed motions', () {
    testWidgets('Animation<int> rounds to whole cells', (tester) {
      final m = Animation(0);
      _host(tester, m);
      m.to(
        10,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 50));
      expect(m.value, isA<int>());
      expect(m.value, inInclusiveRange(3, 7));
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, 10);
    });

    testWidgets('Animation<RgbColor> interpolates channel-wise', (tester) {
      final m = Animation(const RgbColor(0, 0, 0));
      _host(tester, m);
      m.to(
        const RgbColor(255, 0, 0),
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 50));
      expect(m.value.r, inInclusiveRange(80, 180));
      expect(m.value.g, 0);
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, const RgbColor(255, 0, 0));
    });
  });

  group('AnimationPolicy', () {
    testWidgets(
      'disabled snaps to target instantly',
      (tester) {
        final m = Animation(0.0);
        _host(tester, m);
        m.to(1.0);
        // No pump — disabled policy means to() snapped synchronously.
        expect(m.value, 1.0);
        expect(m.isMoving, isFalse);
      },
      animationPolicy: AnimationPolicy.disabled,
    );
  });

  group('retarget from a settling-tick listener', () {
    testWidgets('a listener that retargets on settle animates to the new '
        'target instead of snapping', (tester) async {
      final m = Animation(0.0);
      _host(tester, m);

      // A chaining listener that flips direction the instant the value
      // reaches the top. Curves.linear lands exactly on 1.0 on the
      // settling tick, so this fires precisely then.
      var retargeted = false;
      Future<void>? chained;
      m.addListener(() {
        if (!retargeted && m.value >= 1.0) {
          retargeted = true;
          chained = m.to(
            0.0,
            curve: Curves.linear,
            duration: const Duration(milliseconds: 100),
          );
        }
      });

      m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 100)); // reach 1.0 → retarget

      expect(retargeted, isTrue, reason: 'listener fired on the settling tick');
      expect(
        m.isMoving,
        isTrue,
        reason: 'the retarget must animate, not snap-and-stop',
      );
      expect(
        m.value,
        closeTo(1.0, 1e-9),
        reason: 'still at the top; must ease back down, not teleport to 0',
      );

      // The freshly-issued future must not have completed instantly.
      var chainedDone = false;
      chained!.then((_) => chainedDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        chainedDone,
        isFalse,
        reason: 'new future completes only on the real settle',
      );

      tester.pump(const Duration(milliseconds: 50));
      expect(m.value, closeTo(0.5, 0.05), reason: 'easing back down');

      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, closeTo(0.0, 1e-9));
      expect(m.isMoving, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        chainedDone,
        isTrue,
        reason: 'completes when the retarget genuinely settles',
      );
    });

    testWidgets('a loop() started from a settling-tick listener plays out', (
      tester,
    ) async {
      final m = Animation(0.0);
      _host(tester, m);

      var started = false;
      m.addListener(() {
        if (!started && m.value >= 1.0) {
          started = true;
          m.loop(
            between: (0.0, 1.0),
            period: const Duration(milliseconds: 100),
          );
        }
      });

      m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 100)); // reach 1.0 → loop()

      expect(started, isTrue);
      // The loop restarts from its first value (0.0) and runs its first
      // leg 0 -> 1. It must not be consumed by the stale settle branch,
      // which re-arms the mirror with from/target swapped so the first
      // leg runs backwards (1 -> 0). Sample off the midpoint (0.25 of
      // the period) so the two directions are distinguishable: up-from-0
      // reads ~0.25, the swapped-down-from-1 bug reads ~0.75.
      expect(m.isMoving, isTrue, reason: 'loop keeps ticking');
      tester.pump(const Duration(milliseconds: 25));
      expect(
        m.value,
        closeTo(0.25, 0.1),
        reason: 'looping up from 0 toward 1 (not snapped/swapped)',
      );
    });
  });

  group('scheduler integration', () {
    testWidgets('a settled animation holds no active ticker', (tester) {
      final m = Animation(0.0);
      _host(tester, m);
      expect(tester.scheduler.activeTickerCount, 0);
      m.to(1.0, spring: Spring.snappy);
      expect(tester.scheduler.activeTickerCount, 1);
      tester.pump(const Duration(seconds: 1));
      expect(
        tester.scheduler.activeTickerCount,
        0,
        reason: 'settled animation releases the scheduler',
      );
    });

    testWidgets('completion future fires on settle', (tester) async {
      final m = Animation(0.0);
      _host(tester, m);
      var done = false;
      m.to(1.0, spring: Spring.snappy).then((_) => done = true);
      tester.pump(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });

    testWidgets('retarget cancels the prior future (orCancel throws)', (
      tester,
    ) async {
      final m = Animation(0.0);
      _host(tester, m);
      final first = m.to(1.0);
      tester.pump(const Duration(milliseconds: 40));
      m.to(0.5); // supersedes
      await expectLater(first.orCancel, throwsA(isA<TickerCanceled>()));
    });

    testWidgets('dispose freezes final state and blocks mutation', (
      tester,
    ) async {
      final m = Animation(0.0);
      _host(tester, m);
      final active = m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(seconds: 1),
      );
      tester.pump(const Duration(milliseconds: 250));
      final finalValue = m.value;

      m.dispose();

      expect(m.value, finalValue);
      expect(m.target, 1.0);
      expect(m.isMoving, isFalse);
      expect(tester.scheduler.activeTickerCount, 0);
      expect(
        () => m.snap(0.0),
        _stateError('Animation.snap() called after dispose.'),
      );
      expect(
        () => m.stop(),
        _stateError('Animation.stop() called after dispose.'),
      );
      expect(
        () => m.to(0.5),
        _stateError('Animation.to() called after dispose.'),
      );
      expect(
        () => m.loop(between: (0.0, 1.0)),
        _stateError('Animation.loop() called after dispose.'),
      );
      expect(
        () => m.run([AnimationStep.to(0.25)]),
        _stateError('Animation.run() called after dispose.'),
      );
      await expectLater(active.orCancel, throwsA(isA<TickerCanceled>()));
    });
  });
}
