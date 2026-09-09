import 'dart:async';
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 25));
void main() {
  for (final supported in [true, false]) {
    test(
      'native runtime gates cursor output on negotiated support=$supported',
      () async {
        final driver = FakeTerminalDriver(pointerShapes: supported);
        final app = runApp(
          Align(
            alignment: Alignment.topLeft,
            child: Button(label: 'Save', onPressed: () {}),
          ),
          driver: driver,
          mode: const TerminalMode(mouseMotion: true),
          enableHotReload: false,
        );
        try {
          await settle();
          driver.clearOutput();
          driver.enqueue(
            const MouseEvent(
              kind: MouseEventKind.moved,
              button: MouseButton.none,
              col: 2,
              row: 0,
            ),
          );
          await settle();
          expect(driver.output.contains('\x1b]22;pointer\x1b\\'), supported);
          driver.clearOutput();
          driver.enqueue(
            const MouseEvent(
              kind: MouseEventKind.moved,
              button: MouseButton.none,
              col: 3,
              row: 0,
            ),
          );
          await settle();
          expect(driver.output, isNot(contains('\x1b]22;')));
          driver.enqueue(const TerminalFocusEvent(focused: false));
          await settle();
          expect(driver.output.contains('\x1b]22;default\x1b\\'), supported);
        } finally {
          driver.enqueue(
            const KeyEvent(KeyCode.c, modifiers: {KeyModifier.ctrl}),
          );
          await app.timeout(const Duration(seconds: 2));
          await driver.dispose();
        }
      },
    );
  }
}
