import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/terminal_driver.dart'
    show terminalModeWithKeyboardProtocol;
import 'package:fleury/src/terminal/terminal_sequences.dart';
import 'package:test/test.dart';

void main() {
  test('inlineRows selects bounded main-screen rendering', () {
    const fullScreen = TerminalMode();
    const inline = TerminalMode(inlineRows: 10, mouse: true);
    expect(fullScreen.alternateScreen, isTrue);
    expect(fullScreen.inlineRows, isNull);
    expect(inline.alternateScreen, isFalse);
    expect(inline.rawInput, isTrue);
    expect(buildTerminalEnterSequences(inline), isNot(contains('1049')));
    expect(buildTerminalExitSequences(inline), isNot(contains('1049')));

    final fallback = terminalModeWithKeyboardProtocol(
      inline,
      KeyboardProtocolMode.legacy,
    );
    expect(fallback.inlineRows, 10);
    expect(fallback.alternateScreen, isFalse);
    expect(fallback.mouse, isTrue);
    expect(fallback.keyboardProtocol, KeyboardProtocolMode.legacy);
  });

  test('invalid inline configurations fail early', () {
    expect(() => TerminalMode(inlineRows: 0), throwsA(isA<AssertionError>()));
    expect(() => TerminalMode(inlineRows: -1), throwsA(isA<AssertionError>()));
    expect(
      () => TerminalMode(inlineRows: 10, alternateScreen: true),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => TerminalMode(inlineRows: 10, rawInput: false),
      throwsA(isA<AssertionError>()),
    );
    expect(const TerminalMode(alternateScreen: false).inlineRows, isNull);
  });
}
