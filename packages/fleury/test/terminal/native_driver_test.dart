import 'package:fleury/src/terminal/native_driver.dart';
import 'package:fleury/src/terminal/posix_driver.dart';
import 'package:fleury/src/terminal/terminal_driver.dart';
import 'package:fleury/src/terminal/windows_driver.dart';
import 'package:test/test.dart';

void main() {
  test('native driver factory selects Windows driver for Windows', () {
    final driver = createNativeTerminalDriverForPlatform(isWindows: true);
    expect(driver, isA<WindowsTerminalDriver>());
  });

  test('native driver factory selects POSIX driver otherwise', () {
    final driver = createNativeTerminalDriverForPlatform(isWindows: false);
    expect(driver, isA<PosixTerminalDriver>());
  });

  test('native Windows console controller is a no-op off Windows', () {
    final controller = NativeWindowsConsoleModeController();
    final state = controller.enter(TerminalMode.interactive);

    expect(state.changed, isFalse);
    expect(() => controller.restore(state), returnsNormally);
  });

  group('Windows console mode planning', () {
    test('enables raw virtual-terminal input and output', () {
      final plan = planWindowsConsoleModes(
        mode: TerminalMode.interactive,
        inputMode: 0x0007,
        outputMode: 0x0000,
      );

      expect(plan.inputChanged, isTrue);
      expect(plan.outputChanged, isTrue);
      expect(plan.desiredInputMode, 0x0280);
      expect(plan.desiredOutputMode, 0x000d);
    });

    test(
      'does not enable virtual terminal input when raw input is disabled',
      () {
        final plan = planWindowsConsoleModes(
          mode: const TerminalMode(rawInput: false),
          inputMode: 0x0007,
          outputMode: 0x0000,
        );

        expect(plan.inputChanged, isFalse);
        expect(plan.desiredInputMode, isNull);
        expect(plan.outputChanged, isTrue);
        expect(plan.desiredOutputMode, 0x000d);
      },
    );

    test('does not mark already-enabled flags as changed', () {
      final plan = planWindowsConsoleModes(
        mode: TerminalMode.interactive,
        inputMode: 0x0280,
        outputMode: 0x000d,
      );

      expect(plan.changed, isFalse);
      expect(plan.desiredInputMode, 0x0280);
      expect(plan.desiredOutputMode, 0x000d);
    });

    test('handles unavailable console modes independently', () {
      final noInput = planWindowsConsoleModes(
        mode: TerminalMode.interactive,
        inputMode: null,
        outputMode: 0x0000,
      );
      expect(noInput.inputChanged, isFalse);
      expect(noInput.outputChanged, isTrue);
      expect(noInput.desiredInputMode, isNull);
      expect(noInput.desiredOutputMode, 0x000d);

      final noOutput = planWindowsConsoleModes(
        mode: TerminalMode.interactive,
        inputMode: 0x0000,
        outputMode: null,
      );
      expect(noOutput.inputChanged, isTrue);
      expect(noOutput.outputChanged, isFalse);
      expect(noOutput.desiredInputMode, 0x0280);
      expect(noOutput.desiredOutputMode, isNull);
    });

    test('clears quick-edit together with processed, line, and echo input', () {
      final plan = planWindowsConsoleModes(
        mode: TerminalMode.interactive,
        inputMode: 0x00c7,
        outputMode: 0x000d,
      );

      expect(plan.inputChanged, isTrue);
      expect(plan.desiredInputMode, 0x0280);
      expect(plan.outputChanged, isFalse);
    });

    test('preserves unrelated input flags while applying the raw mask', () {
      final plan = planWindowsConsoleModes(
        mode: TerminalMode.interactive,
        inputMode: 0x02ff,
        outputMode: 0x000d,
      );

      expect(plan.inputChanged, isTrue);
      expect(plan.desiredInputMode, 0x02b8);
      expect(plan.outputChanged, isFalse);
    });
  });
}
