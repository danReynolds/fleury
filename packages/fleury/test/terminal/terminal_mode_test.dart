import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/terminal_driver.dart'
    show terminalModeWithKeyboardProtocol;
import 'package:fleury/src/terminal/terminal_sequences.dart';
import 'package:test/test.dart';

void main() {
  test('inline constructor selects bounded main-screen rendering', () {
    const fullScreen = TerminalMode();
    const inline = TerminalMode.inline(rows: 10, mouse: true);
    expect(fullScreen.isFullScreen, isTrue);
    expect(fullScreen.inlineRows, isNull);
    expect(inline.isFullScreen, isFalse);
    expect(inline.rawInput, isTrue);
    expect(buildTerminalEnterSequences(inline), isNot(contains('1049')));
    expect(buildTerminalExitSequences(inline), isNot(contains('1049')));

    final fallback = terminalModeWithKeyboardProtocol(
      inline,
      KeyboardProtocolMode.legacy,
    );
    expect(fallback.inlineRows, 10);
    expect(fallback.isFullScreen, isFalse);
    expect(fallback.mouse, isTrue);
    expect(fallback.keyboardProtocol, KeyboardProtocolMode.legacy);
  });

  test('full-screen is the explicit and default mode', () {
    for (final mode in [
      const TerminalMode(),
      const TerminalMode.fullScreen(),
      TerminalMode.interactive,
    ]) {
      expect(mode.isFullScreen, isTrue);
      expect(mode.isInline, isFalse);
      expect(mode.inlineRows, isNull);
      expect(buildTerminalEnterSequences(mode), contains('\x1B[?1049h'));
      expect(buildTerminalExitSequences(mode), contains('\x1B[?1049l'));
    }
  });

  test('inline height must be positive', () {
    expect(() => TerminalMode.inline(rows: 0), throwsA(isA<AssertionError>()));
    expect(() => TerminalMode.inline(rows: -1), throwsA(isA<AssertionError>()));
  });
}
