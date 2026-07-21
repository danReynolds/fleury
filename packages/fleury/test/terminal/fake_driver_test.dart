import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('FakeTerminalDriver lifecycle', () {
    test('starts inactive and becomes active on enter()', () async {
      final driver = FakeTerminalDriver();
      expect(driver.isActive, isFalse);
      await driver.enter(TerminalMode.interactive);
      expect(driver.isActive, isTrue);
      expect(driver.enterCallCount, 1);
      expect(driver.currentMode, TerminalMode.interactive);
      await driver.dispose();
    });

    test('restore() goes back to inactive', () async {
      final driver = FakeTerminalDriver();
      await driver.enter(TerminalMode.interactive);
      await driver.restore();
      expect(driver.isActive, isFalse);
      expect(driver.restoreCallCount, 1);
      await driver.dispose();
    });

    test('restore on a never-entered driver is a no-op', () async {
      final driver = FakeTerminalDriver();
      await driver.restore();
      expect(driver.restoreCallCount, 0);
      await driver.dispose();
    });

    test('terminal handoff suspends, suppresses writes, and resumes', () async {
      final driver = FakeTerminalDriver();
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);
      await driver.enter(TerminalMode.interactive);

      final result = await withTerminalHandoff(driver, () {
        expect(driver.isActive, isFalse);
        driver.write('frame during handoff');
        return 'done';
      });
      await Future<void>.delayed(Duration.zero);

      expect(result, 'done');
      expect(driver.isActive, isTrue);
      expect(driver.output, isEmpty);
      expect(driver.handoffCallCount, 1);
      expect(driver.handoffSuspendCallCount, 1);
      expect(driver.handoffResumeCallCount, 1);
      expect(events, [const ResizeEvent(CellSize(80, 24))]);
      await sub.cancel();
      await driver.dispose();
    });

    test('terminal handoff falls through when driver is inactive', () async {
      final driver = FakeTerminalDriver();

      final result = await withTerminalHandoff(driver, () {
        driver.write('plain output');
        return 42;
      });

      expect(result, 42);
      expect(driver.output, 'plain output');
      expect(driver.handoffCallCount, 1);
      expect(driver.handoffSuspendCallCount, 0);
      expect(driver.handoffResumeCallCount, 0);
      await driver.dispose();
    });

    test('restore during terminal handoff prevents resume', () async {
      final driver = FakeTerminalDriver();
      await driver.enter(TerminalMode.interactive);

      final result = await withTerminalHandoff(driver, () async {
        await driver.restore();
        return 'closed';
      });

      expect(result, 'closed');
      expect(driver.isActive, isFalse);
      expect(driver.restoreCallCount, 1);
      expect(driver.handoffSuspendCallCount, 1);
      expect(driver.handoffResumeCallCount, 0);
      await driver.dispose();
    });

    test('dispose is idempotent and keeps final state readable', () async {
      final driver = FakeTerminalDriver();
      await driver.enter(TerminalMode.interactive);
      driver.write('final frame');
      expect(driver.isActive, isTrue);

      await driver.dispose();
      await driver.dispose();

      expect(driver.isActive, isFalse);
      expect(driver.output, 'final frame');
      expect(driver.enterCallCount, 1);
      expect(driver.currentMode, TerminalMode.interactive);
      await driver.restore();
    });

    test('terminal activity after dispose throws a lifecycle error', () async {
      final driver = FakeTerminalDriver();
      await driver.dispose();

      const message = 'FakeTerminalDriver has been disposed.';
      await expectLater(
        driver.enter(TerminalMode.interactive),
        throwsA(_stateError(message)),
      );
      await expectLater(
        withTerminalHandoff(driver, () {}),
        throwsA(_stateError(message)),
      );
      expect(() => driver.write('late frame'), throwsA(_stateError(message)));
      expect(driver.clearOutput, throwsA(_stateError(message)));
      expect(
        () => driver.enqueue(const KeyEvent(KeyCode.enter)),
        throwsA(_stateError(message)),
      );
      expect(
        () => driver.resize(const CellSize(120, 40)),
        throwsA(_stateError(message)),
      );
      expect(() => driver.isInteractive = false, throwsA(_stateError(message)));
      await driver.restore();
    });
  });

  group('FakeTerminalDriver output capture', () {
    test('write accumulates into output', () {
      final driver = FakeTerminalDriver();
      driver.write('hello ');
      driver.write('world');
      expect(driver.output, 'hello world');
    });

    test('clearOutput resets the captured bytes', () {
      final driver = FakeTerminalDriver();
      driver.write('frame 1');
      driver.clearOutput();
      driver.write('frame 2');
      expect(driver.output, 'frame 2');
    });
  });

  group('FakeTerminalDriver events', () {
    test('enqueue delivers events to listeners', () async {
      final driver = FakeTerminalDriver();
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);

      driver.enqueue(const KeyEvent(KeyCode.enter));
      driver.enqueue(const TextInputEvent('hi'));
      await Future<void>.delayed(Duration.zero);

      expect(events, [
        const KeyEvent(KeyCode.enter),
        const TextInputEvent('hi'),
      ]);
      await sub.cancel();
      await driver.dispose();
    });

    test('resize() updates size AND emits a ResizeEvent', () async {
      final driver = FakeTerminalDriver(size: const CellSize(80, 24));
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);

      driver.resize(const CellSize(120, 40));
      await Future<void>.delayed(Duration.zero);

      expect(driver.size, const CellSize(120, 40));
      expect(events, [const ResizeEvent(CellSize(120, 40))]);
      await sub.cancel();
      await driver.dispose();
    });

    test('events stream is broadcast (multiple listeners)', () async {
      final driver = FakeTerminalDriver();
      final a = <TuiEvent>[];
      final b = <TuiEvent>[];
      final subA = driver.events.listen(a.add);
      final subB = driver.events.listen(b.add);

      driver.enqueue(const KeyEvent(KeyCode.arrowUp));
      await Future<void>.delayed(Duration.zero);

      expect(a, [const KeyEvent(KeyCode.arrowUp)]);
      expect(b, [const KeyEvent(KeyCode.arrowUp)]);
      await subA.cancel();
      await subB.cancel();
      await driver.dispose();
    });
  });
}

Matcher _stateError(String message) =>
    isA<StateError>().having((error) => error.message, 'message', message);
