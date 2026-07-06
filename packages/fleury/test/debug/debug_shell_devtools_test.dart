import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('DebugConfig is public API and defaults to enabled under JIT', () {
    // Constructing via package:fleury/fleury.dart is itself the export
    // assertion — this file has no src/ imports.
    const config = DebugConfig(
      startMode: DebugMode.docked,
      side: DebugPanelSide.bottom,
      panelWidth: 40,
    );
    expect(config.enabled, isTrue,
        reason: 'JIT runs are development runs (dart.vm.product is false); '
            'release AOT builds flip the default off');
    expect(config.startMode, DebugMode.docked);
  });

  test('Tab cycles the shell tabs; Shift+Tab cycles back', () async {
    final driver = FakeTerminalDriver(size: const CellSize(90, 18));
    final future = runApp(
      const Text('app'),
      driver: driver,
      enableHotReload: false,
    );
    await _settle();
    driver.enqueue(const KeyEvent(char: 'g', modifiers: {KeyModifier.ctrl}));
    await _settle();

    // Live -> Tree: the Tree tab renders semantic-tree content.
    driver.clearOutput();
    driver.enqueue(const KeyEvent(keyCode: KeyCode.tab));
    await _settle();
    expect(driver.output, contains('terminal profile'));

    // Shift+Tab returns to Live (frame stats).
    driver.clearOutput();
    driver.enqueue(
      const KeyEvent(keyCode: KeyCode.tab, modifiers: {KeyModifier.shift}),
    );
    await _settle();
    expect(driver.output, contains('Frame'));

    driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await future;
    await driver.dispose();
  });

  test('Errors tab lists uncaught handler errors from the bounded history',
      () async {
    final driver = FakeTerminalDriver(size: const CellSize(90, 18));
    final future = runApp(
      const Text('app'),
      driver: driver,
      enableHotReload: false,
      onEvent: (e) {
        if (e is KeyEvent && e.keyCode == KeyCode.enter) {
          throw StateError('handler-kaboom');
        }
        return null;
      },
    );
    await _settle();

    driver.enqueue(const KeyEvent(keyCode: KeyCode.enter)); // throw + banner
    await _settle();
    driver.enqueue(const KeyEvent(char: 'g', modifiers: {KeyModifier.ctrl}));
    await _settle();
    // Live -> Tree -> Rebuilds -> Logs -> Errors.
    for (var i = 0; i < 4; i++) {
      driver.enqueue(const KeyEvent(keyCode: KeyCode.tab));
      await _settle();
    }
    driver.clearOutput();
    driver.enqueue(const KeyEvent(keyCode: KeyCode.tab)); // wrap to Live…
    driver.enqueue(
      const KeyEvent(keyCode: KeyCode.tab, modifiers: {KeyModifier.shift}),
    ); // …and back, forcing an Errors repaint
    await _settle();
    expect(driver.output, contains('handler-kaboom'),
        reason: 'the Errors tab renders the recorded error summary');

    driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await future;
    await driver.dispose();
  });
}
