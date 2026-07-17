// FakeClock-driven tests for Ticker. Discipline per RFC 0010 §21.1.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

({FakeClock clock, FakeTickerScheduler scheduler}) _fixture() {
  final clock = FakeClock();
  final scheduler = FakeTickerScheduler(clock: clock);
  return (clock: clock, scheduler: scheduler);
}

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

void main() {
  group('Ticker lifecycle', () {
    test('a freshly-constructed Ticker is inactive', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      expect(ticker.isActive, isFalse);
      expect(ticker.isDisposed, isFalse);
      expect(f.scheduler.activeTickerCount, 0);
    });

    test('start() registers with the scheduler', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      ticker.start();
      expect(ticker.isActive, isTrue);
      expect(f.scheduler.activeTickerCount, 1);
      expect(f.scheduler.isActive, isTrue);
    });

    test('stop() unregisters and leaves the scheduler idle', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      ticker.start();
      ticker.stop();
      expect(ticker.isActive, isFalse);
      expect(f.scheduler.activeTickerCount, 0);
      expect(f.scheduler.isActive, isFalse);
    });

    test('dispose() stops the ticker and prevents further start/stop', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      ticker.start();
      ticker.dispose();
      expect(ticker.isDisposed, isTrue);
      expect(f.scheduler.activeTickerCount, 0);
      expect(() => ticker.start(), throwsStateError);
      expect(() => ticker.stop(), throwsStateError);
    });

    test('start() is idempotent', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      ticker.start();
      ticker.start();
      expect(f.scheduler.activeTickerCount, 1);
    });

    test('stop() is idempotent', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      ticker.start();
      ticker.stop();
      ticker.stop();
      expect(ticker.isActive, isFalse);
    });

    test('dispose() is idempotent', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      ticker.start();
      ticker.dispose();
      ticker.dispose();
      expect(ticker.isDisposed, isTrue);
    });

    test('dispose keeps final state readable and blocks muted changes', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler)
        ..start()
        ..muted = true;
      f.scheduler.advance(const Duration(milliseconds: 120));

      ticker.dispose();

      expect(ticker.isDisposed, isTrue);
      expect(ticker.isActive, isFalse);
      expect(ticker.muted, isTrue);
      expect(ticker.lastElapsed, const Duration(milliseconds: 120));
      expect(
        () => ticker.muted = false,
        _stateError(
          'Ticker.muted set after dispose. Tickers cannot be reused once '
          'disposed; create a new one via TickerProvider.createTicker.',
        ),
      );
      expect(ticker.muted, isTrue);
    });
  });

  group('Ticker elapsed time', () {
    test('elapsed is zero on first tick (start anchor matches clock)', () {
      final f = _fixture();
      Duration? observed;
      final ticker = Ticker((e) => observed = e, scheduler: f.scheduler);
      ticker.start();
      f.scheduler.advanceFrame();
      expect(observed, Duration.zero);
    });

    test('elapsed equals clock advance after start', () {
      final f = _fixture();
      Duration? observed;
      final ticker = Ticker((e) => observed = e, scheduler: f.scheduler);
      ticker.start();
      f.scheduler.advance(const Duration(milliseconds: 100));
      expect(observed, const Duration(milliseconds: 100));
    });

    test('stop + start resets the elapsed-time anchor', () {
      final f = _fixture();
      Duration? observed;
      final ticker = Ticker((e) => observed = e, scheduler: f.scheduler);
      ticker.start();
      f.scheduler.advance(const Duration(milliseconds: 100));
      ticker.stop();
      f.clock.advance(const Duration(milliseconds: 500)); // bg time passes
      ticker.start();
      f.scheduler.advance(const Duration(milliseconds: 50));
      expect(
        observed,
        const Duration(milliseconds: 50),
        reason:
            'elapsed should reset on re-start, ignoring '
            'time that passed while stopped',
      );
    });

    test('elapsed is monotonically non-decreasing', () {
      final f = _fixture();
      final samples = <Duration>[];
      final ticker = Ticker((e) => samples.add(e), scheduler: f.scheduler);
      ticker.start();
      for (var i = 0; i < 10; i++) {
        f.scheduler.advance(const Duration(milliseconds: 33));
      }
      for (var i = 1; i < samples.length; i++) {
        expect(
          samples[i] >= samples[i - 1],
          isTrue,
          reason:
              'sample $i (${samples[i]}) < sample ${i - 1} '
              '(${samples[i - 1]})',
        );
      }
    });

    test('lastElapsed reflects the most recent tick value', () {
      final f = _fixture();
      final ticker = Ticker((_) {}, scheduler: f.scheduler);
      ticker.start();
      f.scheduler.advance(const Duration(milliseconds: 100));
      expect(ticker.lastElapsed, const Duration(milliseconds: 100));
      f.scheduler.advance(const Duration(milliseconds: 50));
      expect(ticker.lastElapsed, const Duration(milliseconds: 150));
    });

    test('callback fires only between start and stop', () {
      final f = _fixture();
      var fires = 0;
      final ticker = Ticker((_) => fires += 1, scheduler: f.scheduler);
      // No tick before start.
      f.scheduler.advanceFrame();
      expect(fires, 0);

      ticker.start();
      f.scheduler.advance(const Duration(milliseconds: 33));
      expect(fires, 1);

      ticker.stop();
      f.scheduler.advanceFrame();
      expect(fires, 1, reason: 'stop suppresses further callbacks');

      ticker.start();
      f.scheduler.advance(const Duration(milliseconds: 33));
      expect(fires, 2, reason: 'restart resumes callbacks');
    });
  });

  group('Ticker + scheduler coalescing', () {
    test('ten concurrent tickers share one scheduler tick', () {
      final f = _fixture();
      final fired = <int>[];
      final tickers = <Ticker>[];
      for (var i = 0; i < 10; i++) {
        final id = i;
        tickers.add(
          Ticker((_) => fired.add(id), scheduler: f.scheduler)..start(),
        );
      }
      expect(f.scheduler.activeTickerCount, 10);
      f.scheduler.advance(const Duration(milliseconds: 33));
      expect(fired.length, 10);
      expect(fired.toSet(), {for (var i = 0; i < 10; i++) i});
    });

    test('stopping all tickers returns the scheduler to idle', () {
      final f = _fixture();
      final tickers = [
        for (var i = 0; i < 5; i++)
          Ticker((_) {}, scheduler: f.scheduler)..start(),
      ];
      for (final t in tickers) {
        t.stop();
      }
      expect(
        f.scheduler.isActive,
        isFalse,
        reason: 'no active tickers => no active timer source',
      );
      expect(f.scheduler.activeTickerCount, 0);
    });
  });
}
