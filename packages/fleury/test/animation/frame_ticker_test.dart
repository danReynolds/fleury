// FakeClock-driven tests for FrameTicker.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

({FakeClock clock, FakeTickerScheduler scheduler}) _fixture() {
  final clock = FakeClock();
  final scheduler = FakeTickerScheduler(clock: clock);
  return (clock: clock, scheduler: scheduler);
}

void main() {
  group('FrameTicker cadence', () {
    test('advances frame after each interval has fully elapsed', () {
      final f = _fixture();
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 80),
        scheduler: f.scheduler,
      )..start();
      var notifications = 0;
      ticker.addListener(() => notifications += 1);

      // Tick at 33 ms — not enough for a frame yet.
      f.scheduler.advance(const Duration(milliseconds: 33));
      expect(ticker.frame, 0);
      expect(notifications, 0);

      // Tick to 66 ms total — still not 80.
      f.scheduler.advance(const Duration(milliseconds: 33));
      expect(ticker.frame, 0);

      // Tick to 99 ms total — 99 - 0 >= 80, frame advances.
      f.scheduler.advance(const Duration(milliseconds: 33));
      expect(ticker.frame, 1);
      expect(notifications, 1);
      expect(ticker.delta, const Duration(milliseconds: 99));
    });

    test('multiple intervals elapse, multiple frames advance', () {
      // Cadence: 50 ms per frame. Big jump of 175 ms should
      // advance through frames at 50, 100, 150 — but in the
      // scheduler-tick model, a single tick only emits ONE frame
      // (it's the next tick that catches up). This is the
      // documented behavior.
      final f = _fixture();
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 50),
        scheduler: f.scheduler,
      )..start();
      var notifications = 0;
      ticker.addListener(() => notifications += 1);

      f.scheduler.advance(const Duration(milliseconds: 175));
      // First crossing happens at >=50ms; emits once.
      expect(ticker.frame, 1);
      expect(notifications, 1);

      // Next tick: enough time elapsed to advance again.
      f.scheduler.advance(const Duration(milliseconds: 50));
      expect(ticker.frame, 2);
    });

    test('start() resets frame and elapsed', () {
      final f = _fixture();
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 100),
        scheduler: f.scheduler,
      )..start();
      f.scheduler.advance(const Duration(milliseconds: 300));
      expect(ticker.frame, 1);

      ticker.stop();
      f.clock.advance(const Duration(seconds: 1));
      ticker.start();
      expect(ticker.frame, 0, reason: 'start() resets the frame counter');
      expect(ticker.elapsed, Duration.zero);

      f.scheduler.advance(const Duration(milliseconds: 150));
      expect(ticker.frame, 1);
    });

    test('muted ticker still advances frame counter; suppresses '
        'notifications', () {
      final f = _fixture();
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 80),
        scheduler: f.scheduler,
      )..start();
      var notifications = 0;
      ticker.addListener(() => notifications += 1);

      ticker.muted = true;
      f.scheduler.advance(const Duration(milliseconds: 200));
      expect(
        ticker.frame,
        1,
        reason:
            'frame counter advances even when muted '
            '(so re-enabling lands at the correct frame)',
      );
      expect(notifications, 0, reason: 'muted: listeners not invoked');

      ticker.muted = false;
      f.scheduler.advance(const Duration(milliseconds: 80));
      expect(ticker.frame, 2);
      expect(notifications, 1);
    });
  });

  group('FrameTicker lifecycle', () {
    test('starts inactive', () {
      final f = _fixture();
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 80),
        scheduler: f.scheduler,
      );
      expect(ticker.isActive, isFalse);
      expect(f.scheduler.activeTickerCount, 0);
    });

    test('start registers, stop unregisters', () {
      final f = _fixture();
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 80),
        scheduler: f.scheduler,
      );
      ticker.start();
      expect(ticker.isActive, isTrue);
      expect(f.scheduler.activeTickerCount, 1);

      ticker.stop();
      expect(ticker.isActive, isFalse);
      expect(f.scheduler.activeTickerCount, 0);
    });

    test('dispose unregisters and blocks reuse', () {
      final f = _fixture();
      final ticker = FrameTicker(
        interval: const Duration(milliseconds: 80),
        scheduler: f.scheduler,
      )..start();
      ticker.dispose();
      expect(f.scheduler.activeTickerCount, 0);
      expect(() => ticker.start(), throwsStateError);
      expect(() => ticker.stop(), throwsStateError);
    });

    test('ten concurrent FrameTickers share one scheduler timer', () {
      final f = _fixture();
      final tickers = [
        for (var i = 0; i < 10; i++)
          FrameTicker(
            interval: const Duration(milliseconds: 80),
            scheduler: f.scheduler,
          )..start(),
      ];
      // Even though each ticker has its own logical cadence, they
      // all register the same scheduler callback (one per ticker
      // instance) — the scheduler still drives them via its single
      // periodic source.
      expect(f.scheduler.activeTickerCount, 10);
      expect(f.scheduler.isActive, isTrue);

      for (final t in tickers) {
        t.dispose();
      }
      expect(f.scheduler.isActive, isFalse);
      expect(f.scheduler.activeTickerCount, 0);
    });
  });
}
