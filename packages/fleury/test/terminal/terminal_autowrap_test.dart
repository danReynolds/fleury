import 'package:fleury/src/terminal/terminal_driver.dart';
import 'package:fleury/src/terminal/terminal_sequences.dart';
import 'package:test/test.dart';

void main() {
  group('autowrap (DECAWM) lifecycle', () {
    test('entering the alt screen disables autowrap', () {
      final enter = buildTerminalEnterSequences(TerminalMode.interactive);
      expect(
        enter,
        contains('\x1B[?7l'),
        reason:
            'the diff renderer assumes a last-column write does not wrap; '
            'autowrap must be off while we own the screen',
      );
      // It must come after the alt-screen switch (so it applies to our screen).
      expect(
        enter.indexOf('\x1B[?7l'),
        greaterThan(enter.indexOf('\x1B[?1049h')),
      );
    });

    test('exiting restores autowrap before leaving the alt screen', () {
      final exit = buildTerminalExitSequences(TerminalMode.interactive);
      expect(exit, contains('\x1B[?7h'), reason: 'restore the shell default');
      expect(
        exit.indexOf('\x1B[?7h'),
        lessThan(exit.indexOf('\x1B[?1049l')),
        reason: 'restore autowrap while still on the alt screen',
      );
    });

    test('a no-alt-screen mode leaves autowrap untouched', () {
      const inline = TerminalMode(
        rawInput: true,
        alternateScreen: false,
        hideCursor: false,
      );
      expect(buildTerminalEnterSequences(inline), isNot(contains('\x1B[?7')));
      expect(buildTerminalExitSequences(inline), isNot(contains('\x1B[?7')));
    });
  });
}
