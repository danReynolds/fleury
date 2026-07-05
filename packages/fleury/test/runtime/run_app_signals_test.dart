import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// App-owned shutdown (RFC: signals as events).
///
/// SIGINT/SIGTERM reach the app as [SignalEvent]s through the normal event
/// stream. An unclaimed signal keeps its POSIX meaning (terminate — runApp
/// resolves with [AppExit.signal]); a handler that returns [EventHandled]
/// claims it and finishes via [requestExit]. All orderly exits resolve
/// runApp's future so the caller's cleanup actually runs.
void main() {
  Future<void> pump([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('SignalEvent through runApp', () {
    test('an unclaimed signal terminates with AppExit.signal', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
      );
      await pump();
      expect(driver.isActive, isTrue);

      driver.enqueue(const SignalEvent(AppSignal.terminate));
      final exit = await future;

      expect(exit.signal, AppSignal.terminate);
      expect(driver.isActive, isFalse, reason: 'cleanup restored the driver');
      await driver.dispose();
    });

    test('a claimed signal hands shutdown to the app; requestExit finishes it',
        () async {
      final driver = FakeTerminalDriver();
      final seen = <AppSignal>[];
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
        onEvent: (event) {
          if (event is SignalEvent) {
            seen.add(event.signal);
            return const EventHandled();
          }
          return null;
        },
      );
      await pump();

      driver.enqueue(const SignalEvent(AppSignal.terminate));
      await pump();
      expect(seen, [AppSignal.terminate]);
      expect(driver.isActive, isTrue,
          reason: 'claimed signal must NOT exit the loop');

      expect(requestExit(), isTrue);
      final exit = await future;
      expect(exit.signal, isNull, reason: 'app-owned shutdown = requested');

      expect(requestExit(), isFalse,
          reason: 'no app running once cleanup has cleared the seam');
      await driver.dispose();
    });

    test('ExitRequested from onEvent still exits (regression)', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
        onEvent: (event) =>
            event is KeyEvent && event.char == 'q' ? const ExitRequested() : null,
      );
      await pump();

      driver.enqueue(const KeyEvent(char: 'q'));
      final exit = await future;
      expect(exit.signal, isNull);
      await driver.dispose();
    });

    test('unhandled Ctrl+C resolves AppExit.requested (regression)', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
      );
      await pump();

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      final exit = await future;
      expect(exit.signal, isNull);
      await driver.dispose();
    });

    test('a claimed signal leaves the loop alive (shutdown UI can render)',
        () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
        onEvent: (event) =>
            event is SignalEvent ? const EventHandled() : null,
      );
      await pump();

      // A claimed signal falls through to frame scheduling (unlike an
      // unclaimed one, which exits before scheduling) — the loop stays
      // alive so the app's "disconnecting…" state can paint.
      driver.enqueue(const SignalEvent(AppSignal.interrupt));
      await pump();
      expect(driver.isActive, isTrue);

      requestExit();
      await future;
      await driver.dispose();
    });
  });
}
