// FakeClock-driven tests for TickerScheduler. Discipline per RFC
// 0010 §21.1: no real time, no Future.delayed, no Timer.

import 'dart:math';

import '../support/harness.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

void main() {
  group('TickerScheduler idle behavior', () {
    test('scheduler is inactive with no registered callbacks', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      expect(scheduler.isActive, isFalse);
      expect(scheduler.activeTickerCount, 0);
    });

    test('registering the first callback activates the scheduler', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      scheduler.register((_) {});
      expect(scheduler.isActive, isTrue);
      expect(scheduler.activeTickerCount, 1);
    });

    test('unregistering the last callback deactivates the scheduler', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      void cb(Duration _) {}
      scheduler.register(cb);
      scheduler.unregister(cb);
      expect(
        scheduler.isActive,
        isFalse,
        reason: 'no callbacks => no active source',
      );
      expect(scheduler.activeTickerCount, 0);
    });

    test(
      'multiple callbacks: scheduler stays active until last unregisters',
      () {
        final clock = FakeClock();
        final scheduler = FakeTickerScheduler(clock: clock);
        void a(Duration _) {}
        void b(Duration _) {}
        void c(Duration _) {}
        scheduler.register(a);
        scheduler.register(b);
        scheduler.register(c);
        expect(scheduler.isActive, isTrue);

        scheduler.unregister(a);
        expect(scheduler.isActive, isTrue);
        scheduler.unregister(b);
        expect(scheduler.isActive, isTrue);
        scheduler.unregister(c);
        expect(scheduler.isActive, isFalse);
      },
    );

    test('register is idempotent', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      void cb(Duration _) {}
      scheduler.register(cb);
      scheduler.register(cb);
      expect(scheduler.activeTickerCount, 1);
    });
  });

  group('TickerScheduler ticking', () {
    test('advanceFrame invokes registered callback with current clock', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      Duration? observed;
      scheduler.register((now) => observed = now);
      clock.advance(const Duration(milliseconds: 100));
      scheduler.advanceFrame();
      expect(observed, const Duration(milliseconds: 100));
    });

    test('advance(delta) is sugar for clock.advance + advanceFrame', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      Duration? observed;
      scheduler.register((now) => observed = now);
      scheduler.advance(const Duration(milliseconds: 50));
      expect(observed, const Duration(milliseconds: 50));
    });

    test('multiple registered callbacks all fire on one frame', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final fired = <int>[];
      scheduler.register((_) => fired.add(1));
      scheduler.register((_) => fired.add(2));
      scheduler.register((_) => fired.add(3));
      scheduler.advance(const Duration(milliseconds: 33));
      expect(fired, [1, 2, 3]);
    });

    test('a callback that unregisters itself does not break iteration', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      late void Function(Duration) selfRemoving;
      var aFired = 0;
      var bFired = 0;
      selfRemoving = (_) {
        aFired += 1;
        scheduler.unregister(selfRemoving);
      };
      void b(Duration _) {
        bFired += 1;
      }

      scheduler.register(selfRemoving);
      scheduler.register(b);
      scheduler.advance(const Duration(milliseconds: 33));
      // Both should have fired this tick (snapshot iteration).
      expect(aFired, 1);
      expect(bFired, 1);
      // Second tick: self-removing is gone.
      scheduler.advance(const Duration(milliseconds: 33));
      expect(aFired, 1);
      expect(bFired, 2);
    });

    test('advanceFrame is a no-op when no callbacks are registered', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      // Doesn't throw.
      scheduler.advanceFrame();
      expect(scheduler.isActive, isFalse);
    });

    test('dispose deactivates the scheduler and drops callbacks', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      var fires = 0;
      scheduler.register((_) => fires += 1);
      scheduler.dispose();
      expect(scheduler.isActive, isFalse);
      expect(scheduler.activeTickerCount, 0);
      scheduler.advanceFrame();
      expect(fires, 0);
    });

    test('dispose is idempotent and blocks new scheduled work', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      void tick(Duration _) {}
      void reassemble() {}
      scheduler.register(tick);
      scheduler.registerReassembleCallback(reassemble);
      scheduler.addPostFrameCallback((_) {});

      scheduler.dispose();
      scheduler.dispose();

      expect(scheduler.isActive, isFalse);
      expect(scheduler.activeTickerCount, 0);
      expect(() => scheduler.unregister(tick), returnsNormally);
      expect(
        () => scheduler.unregisterReassembleCallback(reassemble),
        returnsNormally,
      );
      expect(() => scheduler.reassemble(), returnsNormally);
      expect(
        () => scheduler.flushPostFrameCallbacks(clock.now),
        returnsNormally,
      );
      expect(
        () => scheduler.register(tick),
        _stateError('TickerScheduler has been disposed.'),
      );
      expect(
        () => scheduler.registerReassembleCallback(reassemble),
        _stateError('TickerScheduler has been disposed.'),
      );
      expect(
        () => scheduler.addPostFrameCallback((_) {}),
        _stateError('TickerScheduler has been disposed.'),
      );
      expect(
        () => scheduler.onPostFrameCallbackRegistered = () {},
        _stateError('TickerScheduler has been disposed.'),
      );
    });
  });

  group('TickerScheduler stress', () {
    test('1000 random register/unregister: no leaks at end', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final rng = Random(42);
      final callbacks = <void Function(Duration)>[];
      for (var i = 0; i < 50; i++) {
        void cb(Duration _) {}
        callbacks.add(cb);
      }
      for (var i = 0; i < 1000; i++) {
        final cb = callbacks[rng.nextInt(callbacks.length)];
        if (rng.nextBool()) {
          scheduler.register(cb);
        } else {
          scheduler.unregister(cb);
        }
      }
      // Clean up — unregister everything.
      for (final cb in callbacks) {
        scheduler.unregister(cb);
      }
      expect(scheduler.activeTickerCount, 0);
      expect(scheduler.isActive, isFalse);
    });
  });
}
