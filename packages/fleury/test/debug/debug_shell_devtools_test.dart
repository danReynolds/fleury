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
    expect(
      config.enabled,
      isTrue,
      reason:
          'JIT runs are development runs (dart.vm.product is false); '
          'release AOT builds flip the default off',
    );
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
    driver.enqueue(
      const KeyEvent(KeyCode.char('g'), modifiers: {KeyModifier.ctrl}),
    );
    await _settle();

    // Live -> Tree: the Tree tab renders semantic-tree content.
    driver.clearOutput();
    driver.enqueue(const KeyEvent(KeyCode.tab));
    await _settle();
    expect(driver.output, contains('terminal profile'));

    // Shift+Tab returns to Live (frame stats).
    driver.clearOutput();
    driver.enqueue(const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}));
    await _settle();
    expect(driver.output, contains('Frame'));

    driver.enqueue(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await future;
    await driver.dispose();
  });

  test(
    'Errors tab lists uncaught handler errors from the bounded history',
    () async {
      final driver = FakeTerminalDriver(size: const CellSize(90, 18));
      final future = runApp(
        const Text('app'),
        driver: driver,
        enableHotReload: false,
        onEvent: (e) {
          if (e is KeyEvent && e.code == KeyCode.enter) {
            throw StateError('handler-kaboom');
          }
          return null;
        },
      );
      await _settle();

      driver.enqueue(const KeyEvent(KeyCode.enter)); // throw + banner
      await _settle();
      driver.enqueue(
        const KeyEvent(KeyCode.char('g'), modifiers: {KeyModifier.ctrl}),
      );
      await _settle();
      // Live -> Tree -> Rebuilds -> Logs -> Errors.
      for (var i = 0; i < 4; i++) {
        driver.enqueue(const KeyEvent(KeyCode.tab));
        await _settle();
      }
      driver.clearOutput();
      driver.enqueue(const KeyEvent(KeyCode.tab)); // wrap to Live…
      driver.enqueue(
        const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
      ); // …and back, forcing an Errors repaint
      await _settle();
      expect(
        driver.output,
        contains('handler-kaboom'),
        reason: 'the Errors tab renders the recorded error summary',
      );

      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await future;
      await driver.dispose();
    },
  );

  test('Logs search opens via the real TextInputEvent path', () async {
    // The parser delivers printable keys as TextInputEvent, not KeyEvent, so
    // '/' and the typed query must be consumed on the *text* arm of the debug
    // escape-hatch (run_app → tryConsumeDebugText). This drives them the way a
    // real keyboard does — the KeyEvent-only unit tests can't catch a broken
    // text route, which is exactly how the first cut of this shipped inert.
    final driver = FakeTerminalDriver(size: const CellSize(90, 18));
    final future = runApp(
      const Text('app'),
      driver: driver,
      enableHotReload: false,
    );
    await _settle();

    // Open straight to Logs (F12), then drive the search with text events.
    driver.enqueue(const KeyEvent(KeyCode.f12));
    await _settle();
    driver.enqueue(const TextInputEvent('/'));
    driver.enqueue(const TextInputEvent('a'));
    driver.enqueue(const TextInputEvent('b'));
    await _settle();

    // Force a full Logs re-render (tab away + back) so the search field lands
    // contiguously in the diff, then assert the query is there.
    driver.enqueue(const KeyEvent(KeyCode.tab)); // → Errors
    await _settle();
    driver.clearOutput();
    driver.enqueue(
      const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
    ); // → back to Logs, full repaint
    await _settle();
    expect(
      driver.output,
      contains('/ab'),
      reason: 'TextInputEvent routed to the Logs search field',
    );

    driver.enqueue(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await future;
    await driver.dispose();
  });
}
