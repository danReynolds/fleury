// Backspace, Delete and Enter with a modifier held, as a kitty-protocol
// terminal and the browser report them. A legacy terminal sends Shift+
// Backspace as a plain DEL, so the shifted forms only ever went missing on
// the terminals that can report them.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/terminal_input.dart';

const _shiftBackspace = '\x1b[127;2u';
const _shiftDelete = '\x1b[3;2~';
const _shiftEnter = '\x1b[13;2u';
const _ctrlBackspace = '\x1b[127;5u';
const _altBackspace = '\x1b\x7f'; // ESC DEL, from any terminal
const _left = '\x1b[D';

void main() {
  testWidgets('Shift+Backspace deletes like Backspace', (tester) {
    final controller = TextEditingController(text: 'HELLO');
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    pressTerminalBytes(tester, _shiftBackspace);
    expect(controller.text, 'HELL');

    // The browser's shape of the same press.
    tester.sendKey(
      const KeyEvent(KeyCode.backspace, modifiers: {KeyModifier.shift}),
    );
    expect(controller.text, 'HEL');
  });

  testWidgets('Shift+Delete deletes forward', (tester) {
    final controller = TextEditingController(text: 'HELLO');
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    pressTerminalBytes(tester, '$_left$_shiftDelete');

    expect(controller.text, 'HELL');
  });

  testWidgets('Shift+Enter submits a single-line field', (tester) {
    final submitted = <String>[];
    tester.pumpWidget(
      TextInput(
        controller: TextEditingController(text: 'Hi'),
        autofocus: true,
        onSubmit: submitted.add,
      ),
    );

    pressTerminalBytes(tester, _shiftEnter);

    expect(submitted, ['Hi']);
  });

  testWidgets('a multiline field edits the same way', (tester) {
    final controller = TextEditingController(text: 'AB');
    tester.pumpWidget(TextArea(controller: controller, autofocus: true));

    pressTerminalBytes(tester, _shiftBackspace);
    expect(controller.text, 'A');

    pressTerminalBytes(tester, _shiftEnter);
    expect(controller.text, 'A\n');
  });

  testWidgets('Ctrl+Backspace and Alt+Backspace delete the word before', (
    tester,
  ) {
    final controller = TextEditingController(text: 'one two three');
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    pressTerminalBytes(tester, _ctrlBackspace);
    expect(controller.text, 'one two ');

    pressTerminalBytes(tester, _altBackspace);
    expect(controller.text, 'one ');
  });
}
