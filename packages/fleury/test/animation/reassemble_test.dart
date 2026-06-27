// Hot-reload reassemble tests.
//
// Verifies that:
//   - TickerScheduler.reassemble() fires every registered callback.
//   - Animation self-registers and settles at its target on reassemble,
//     cancelling any in-flight animation.
//   - FrameTicker self-registers and resets its frame counter.
//   - dispose unregisters cleanly (no callbacks after dispose).

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// Reads a animation's value (implicit reactivity) so it attaches to the
/// tester's binding and animates.
class _Show extends StatelessWidget {
  const _Show(this.animation);
  final Animation<Object?> animation;
  @override
  Widget build(BuildContext context) => Text('${animation.value}');
}

void main() {
  group('TickerScheduler.reassemble', () {
    test('fires every registered callback', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      var aCount = 0;
      var bCount = 0;
      scheduler.registerReassembleCallback(() => aCount++);
      scheduler.registerReassembleCallback(() => bCount++);

      scheduler.reassemble();
      expect(aCount, 1);
      expect(bCount, 1);

      scheduler.reassemble();
      expect(aCount, 2);
      expect(bCount, 2);
    });

    test('unregister removes a callback from the registry', () {
      final scheduler = FakeTickerScheduler(clock: FakeClock());
      var fires = 0;
      void cb() => fires++;
      scheduler.registerReassembleCallback(cb);
      scheduler.reassemble();
      expect(fires, 1);

      scheduler.unregisterReassembleCallback(cb);
      scheduler.reassemble();
      expect(fires, 1, reason: 'unregistered callback should not fire');
    });

    test('safe against unregister during iteration', () {
      final scheduler = FakeTickerScheduler(clock: FakeClock());
      var aFired = false;
      var bFired = false;
      late VoidCallback b;
      void a() {
        aFired = true;
        scheduler.unregisterReassembleCallback(b);
      }

      b = () => bFired = true;
      scheduler.registerReassembleCallback(a);
      scheduler.registerReassembleCallback(b);
      // a unregisters b mid-iteration; the snapshot means b still
      // fires on this cycle.
      scheduler.reassemble();
      expect(aFired, isTrue);
      expect(bFired, isTrue);

      // Second cycle: b should not fire (was unregistered).
      bFired = false;
      scheduler.reassemble();
      expect(bFired, isFalse);
    });
  });

  group('Animation hot reload', () {
    testWidgets('settles at its target after scheduler.reassemble()', (tester) {
      final m = Animation(0.0);
      tester.pumpWidget(_Show(m));
      m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 50));
      expect(m.value, closeTo(0.5, 0.05));
      expect(m.isMoving, isTrue);

      tester.binding.tickerScheduler.reassemble();

      expect(m.value, 1.0, reason: 'reassemble settles at the target');
      expect(m.isMoving, isFalse);
    });

    testWidgets('cancels the in-flight future on reassemble', (tester) async {
      final m = Animation(0.0);
      tester.pumpWidget(_Show(m));
      final future = m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 30));
      expect(m.value, greaterThan(0.0));

      tester.binding.tickerScheduler.reassemble();

      await expectLater(future.orCancel, throwsA(isA<TickerCanceled>()));
    });

    testWidgets('unregisters on dispose', (tester) {
      final m = Animation(0.0);
      tester.pumpWidget(_Show(m));
      m.snap(0.5);
      m.dispose();
      // Should not throw — disposed animation's callback is gone.
      expect(
        () => tester.binding.tickerScheduler.reassemble(),
        returnsNormally,
      );
    });
  });

  group('FrameTicker hot reload', () {
    test('resets the frame counter on reassemble', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 100),
        scheduler: scheduler,
      );
      ticker.start();
      scheduler.advance(const Duration(milliseconds: 250));
      expect(ticker.frame, greaterThan(0));

      scheduler.reassemble();
      expect(ticker.frame, 0);
      expect(ticker.elapsed, Duration.zero);
    });

    test('re-anchors start time so next frame is one full '
        'interval away', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 100),
        scheduler: scheduler,
      );
      ticker.start();
      scheduler.advance(const Duration(milliseconds: 250));
      final framesBefore = ticker.frame;
      scheduler.reassemble();
      expect(ticker.frame, 0);

      // Half an interval — no advance yet.
      scheduler.advance(const Duration(milliseconds: 50));
      expect(ticker.frame, 0, reason: 'half-interval should not advance');

      // Full interval — one advance.
      scheduler.advance(const Duration(milliseconds: 60));
      expect(ticker.frame, 1);
      expect(framesBefore, greaterThan(0));
    });

    test('unregisters on dispose', () {
      final scheduler = FakeTickerScheduler(clock: FakeClock());
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 100),
        scheduler: scheduler,
      );
      ticker.dispose();
      expect(() => scheduler.reassemble(), returnsNormally);
    });
  });

  group('BuildOwner + scheduler reassemble interaction', () {
    testWidgets('reassemble after the build-owner walk settles motions '
        'so widgets rebuild under fresh code from a defined state', (tester) {
      final m = Animation(0.0);
      tester.pumpWidget(_Show(m));
      m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 40));
      expect(m.value, greaterThan(0.0));

      // runApp's order: owner.reassembleApplication() then
      // binding.tickerScheduler.reassemble().
      tester.owner.reassembleApplication();
      tester.binding.tickerScheduler.reassemble();
      expect(m.value, 1.0);
    });
  });
}
