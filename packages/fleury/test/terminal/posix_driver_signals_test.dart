import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// The driver side of app-owned shutdown: signal delivery, the grace
/// deadline, the second-signal force path, and restore() disarming.
///
/// deliverSignal() is exercised directly (@visibleForTesting) — real
/// ProcessSignal.watch delivery is covered by the PTY integration tier.
/// forceExitOverride replaces exit() so force behavior is assertable
/// without killing the test process.
void main() {
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  group('PosixTerminalDriver signal delivery', () {
    test('replays a startup signal to the first event listener', () async {
      final codes = <int>[];
      final driver = PosixTerminalDriver(
        signalGrace: const Duration(seconds: 30),
        forceExitOverride: codes.add,
      );

      // enter() installs the OS watchers before runApp can listen. Model a
      // signal landing in that startup gap and then attach runApp's listener.
      driver.deliverSignal(AppSignal.terminate);
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);
      await wait(10);

      expect(events, [const SignalEvent(AppSignal.terminate)]);
      expect(codes, isEmpty);
      await sub.cancel();
      await driver.restore();
    });

    test(
      'delivers a SignalEvent and force-exits after the grace deadline',
      () async {
        final codes = <int>[];
        final driver = PosixTerminalDriver(
          signalGrace: const Duration(milliseconds: 50),
          forceExitOverride: codes.add,
        );
        final events = <TuiEvent>[];
        final sub = driver.events.listen(events.add);

        driver.deliverSignal(AppSignal.terminate);
        await wait(10);
        expect(events, [const SignalEvent(AppSignal.terminate)]);
        expect(codes, isEmpty, reason: 'grace not elapsed yet');

        await wait(120);
        expect(codes, [143], reason: '128 + SIGTERM after the grace deadline');
        await sub.cancel();
      },
    );

    test('a second same-signal forces immediately', () async {
      final codes = <int>[];
      final driver = PosixTerminalDriver(
        signalGrace: const Duration(seconds: 30),
        forceExitOverride: codes.add,
      );

      driver.deliverSignal(AppSignal.interrupt);
      expect(codes, isEmpty);
      driver.deliverSignal(AppSignal.interrupt);
      await wait(20); // force path restores (async) before exiting
      expect(codes, [130], reason: '128 + SIGINT, without waiting out grace');
    });

    test('restore() disarms the grace deadline (orderly shutdown)', () async {
      final codes = <int>[];
      final driver = PosixTerminalDriver(
        signalGrace: const Duration(milliseconds: 40),
        forceExitOverride: codes.add,
      );

      driver.deliverSignal(AppSignal.terminate);
      await driver.restore(); // what runApp's cleanup does
      await wait(120);
      expect(
        codes,
        isEmpty,
        reason: 'an app that shut down cleanly must not be shot afterwards',
      );
    });

    test('a different signal re-delivers and re-arms', () async {
      final codes = <int>[];
      final driver = PosixTerminalDriver(
        signalGrace: const Duration(milliseconds: 60),
        forceExitOverride: codes.add,
      );
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);

      driver.deliverSignal(AppSignal.interrupt);
      await wait(10);
      driver.deliverSignal(AppSignal.terminate);
      await wait(10);
      expect(events, const [
        SignalEvent(AppSignal.interrupt),
        SignalEvent(AppSignal.terminate),
      ]);
      expect(codes, isEmpty, reason: 'different signal re-arms, no force yet');

      await wait(150);
      expect(codes, [143], reason: 'the latest signal owns the deadline');
      await sub.cancel();
    });
  });
}
