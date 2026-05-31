// SystemClock + real Timer integration tests (RFC 0010 follow-up #4).
//
// Every other animation test in this package is FakeClock-driven so
// elapsed-time math is deterministic. These tests are the
// counterpart: they exercise the real wallclock + the real
// `Timer.periodic` so the SystemClock + TickerScheduler integration
// is also covered.
//
// Kept short on purpose — the entire group runs in well under a
// second so it doesn't slow the suite. We never assert exact timings
// (timer drift, GC pauses, CI noise); we assert ranges.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('SystemClock', () {
    test('monotonically increases across a real delay', () async {
      const clock = SystemClock();
      final t0 = clock.now;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final t1 = clock.now;
      expect(
        t1 - t0,
        greaterThanOrEqualTo(const Duration(milliseconds: 15)),
        reason: 'wallclock advance >= ~15ms after a 20ms delay',
      );
    });

    test('two SystemClock instances share the same epoch', () {
      // Documented contract: only deltas matter. The shared static
      // Stopwatch means two instances should never see a backward
      // jump between them either.
      const a = SystemClock();
      const b = SystemClock();
      final aThen = a.now;
      final bThen = b.now;
      expect(
        (bThen - aThen).abs(),
        lessThan(const Duration(milliseconds: 5)),
        reason:
            'shared Stopwatch: two SystemClocks read within a '
            'few microseconds of each other',
      );
    });
  });

  group('TickerScheduler with Timer.periodic', () {
    test('fires the registered callback at approximately the '
        'configured interval', () async {
      final scheduler = TickerScheduler(
        frameInterval: const Duration(milliseconds: 20),
      );
      addTearDown(scheduler.dispose);

      final received = <Duration>[];
      void cb(Duration now) => received.add(now);
      scheduler.register(cb);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      scheduler.unregister(cb);

      // 120ms / 20ms = up to ~6 ticks. Allow [3, 9] for CI noise.
      expect(
        received.length,
        inInclusiveRange(3, 9),
        reason: 'roughly 6 ticks expected within 120ms at 20ms cadence',
      );

      // Each tick's clock reading must be monotonically non-decreasing.
      for (var i = 1; i < received.length; i++) {
        expect(
          received[i] >= received[i - 1],
          isTrue,
          reason: 'tick clock readings must be monotonic',
        );
      }
    });

    test('unregister stops further callbacks', () async {
      final scheduler = TickerScheduler(
        frameInterval: const Duration(milliseconds: 15),
      );
      addTearDown(scheduler.dispose);

      var fires = 0;
      void cb(Duration _) => fires++;
      scheduler.register(cb);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      scheduler.unregister(cb);
      final firesAtUnregister = fires;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        fires,
        firesAtUnregister,
        reason: 'no further fires after unregister',
      );
    });

    test('isActive flips false when the last callback unregisters', () async {
      final scheduler = TickerScheduler(
        frameInterval: const Duration(milliseconds: 15),
      );
      addTearDown(scheduler.dispose);
      expect(scheduler.isActive, isFalse);

      void cb(Duration _) {}
      scheduler.register(cb);
      expect(scheduler.isActive, isTrue);

      scheduler.unregister(cb);
      expect(
        scheduler.isActive,
        isFalse,
        reason: 'no callbacks: timer should be cancelled',
      );
    });
  });

  group('Animation with the real scheduler', () {
    test('completes a short curve animation against wallclock', () async {
      final scheduler = TickerScheduler(
        frameInterval: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);
      final binding = TuiBinding(tickerScheduler: scheduler);
      addTearDown(binding.dispose);
      final m = Animation(0.0)..attach(binding);
      addTearDown(m.dispose);

      final future = m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 80),
      );
      // Wait well past duration to give CI noise headroom.
      await future.timeout(const Duration(seconds: 1));

      expect(m.value, 1.0);
      expect(m.isMoving, isFalse);
    });

    test('stop() rejects orCancel with TickerCanceled', () async {
      final scheduler = TickerScheduler(
        frameInterval: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);
      final binding = TuiBinding(tickerScheduler: scheduler);
      addTearDown(binding.dispose);
      final m = Animation(0.0)..attach(binding);
      addTearDown(m.dispose);

      final future = m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(seconds: 5),
      );
      // Let the animation start.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      m.stop();

      await expectLater(future.orCancel, throwsA(isA<TickerCanceled>()));
      expect(m.value, lessThan(1.0));
    });
  });
}
