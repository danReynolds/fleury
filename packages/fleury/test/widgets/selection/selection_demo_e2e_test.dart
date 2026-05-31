// End-to-end smoke test for example/selection_demo.dart driven
// through runTui. Proves the demo (and the SelectionArea stack
// behind it) actually boots, paints, and processes mouse +
// keyboard events in a realistic event-loop context — the unit
// tests use a synchronous tester that bypasses most of the
// runtime.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../../../example/selection_demo.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  group('selection_demo (e2e through runTui)', () {
    test('boots, renders a frame, and exits cleanly on Ctrl+C', () async {
      final driver = FakeTerminalDriver(size: const CellSize(60, 12));
      final future = runTui(
        const SelectionDemo(),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();

      // The first paint emitted the title bar and the status row.
      expect(driver.output, contains('fleury selection demo'));
      expect(driver.output, contains('drag, double-click, triple-click'));

      // Ctrl+C with nothing selected — SelectionArea's onCopy bubbles,
      // the framework-level binding exits.
      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;

      expect(
        driver.isActive,
        isFalse,
        reason: 'terminal restored after a clean exit',
      );
      await driver.dispose();
    });

    test(
      'a mouse drag through the demo highlights cells and reports text',
      () async {
        final driver = FakeTerminalDriver(size: const CellSize(80, 14));
        final future = runTui(
          const SelectionDemo(),
          driver: driver,
          enableHotReload: false,
        );
        await _settle();
        driver.clearOutput();

        // Drag inside the first paragraph (which starts on screen row 2
        // because of the title bar + border). Pick a stable substring
        // that lives mid-line.
        driver.enqueue(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 1,
            row: 3,
          ),
        );
        driver.enqueue(
          const MouseEvent(
            kind: MouseEventKind.drag,
            button: MouseButton.left,
            col: 5,
            row: 3,
          ),
        );
        driver.enqueue(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 5,
            row: 3,
          ),
        );
        await _settle();

        // Inverse-video sequence appears in the post-drag output ->
        // the selection painted something.
        expect(
          driver.output.contains('\x1B[7m'),
          isTrue,
          reason: 'inverse-video should be emitted for the highlighted cells',
        );

        // The status row mirrors selection text via onSelectionChanged.
        // After the drag, the bottom panel shows `selected: "..."`.
        // Frame diffing fragments contiguous strings so look for the
        // distinctive `: "` suffix the demo's `_renderForStatus` emits.
        expect(
          driver.output,
          contains(': "'),
          reason:
              "status row should have repainted with the demo's "
              "_renderForStatus output `selected: \"…\"`",
        );

        // Esc clears, then Ctrl+C exits.
        driver.enqueue(const KeyEvent(keyCode: KeyCode.escape));
        await _settle();
        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future;
        await driver.dispose();
      },
    );
  });
}
