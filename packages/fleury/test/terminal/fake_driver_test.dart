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

      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      driver.enqueue(const TextInputEvent('hi'));
      await Future<void>.delayed(Duration.zero);

      expect(events, [
        const KeyEvent(keyCode: KeyCode.enter),
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

      driver.enqueue(const KeyEvent(keyCode: KeyCode.arrowUp));
      await Future<void>.delayed(Duration.zero);

      expect(a, [const KeyEvent(keyCode: KeyCode.arrowUp)]);
      expect(b, [const KeyEvent(keyCode: KeyCode.arrowUp)]);
      await subA.cancel();
      await subB.cancel();
      await driver.dispose();
    });
  });
}
