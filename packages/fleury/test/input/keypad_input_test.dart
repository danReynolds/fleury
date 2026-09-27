// The numeric keypad on a Kitty-protocol terminal (the default setup) and in
// application-keypad mode: the parser reports each keypad key by what it
// means, as the DOM does, so a keypad digit types, KP Enter submits and
// activates, and the NumLock-off keys edit and navigate. Each test drives
// real terminal bytes through InputParser into real widgets.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/terminal_input.dart';

// Kitty reports with the NumLock bit (mods 129) and associated text, as a
// lifecycle-tier session receives them.
const _kp1 = '\x1b[57400;129;49u';
const _kp2 = '\x1b[57401;129;50u';
const _kpAdd = '\x1b[57413;129;43u';
const _kpEnter = '\x1b[57414;129u';
const _kpLeft = '\x1b[57417u'; // KP_4 with NumLock off
const _kpHome = '\x1b[57423u'; // KP_7 with NumLock off
const _kpDelete = '\x1b[57426u'; // KP_. with NumLock off

void main() {
  testWidgets('keypad digits and operators type into a text field', (tester) {
    final controller = TextEditingController();
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    pressTerminalBytes(tester, '$_kp1$_kpAdd$_kp2');

    expect(controller.text, '1+2');
  });

  testWidgets('application-keypad digits type too', (tester) {
    final controller = TextEditingController();
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    pressTerminalBytes(tester, '\x1bOq\x1bOk\x1bOr');

    expect(controller.text, '1+2');
  });

  testWidgets('KP Enter submits a text field', (tester) {
    final submitted = <String>[];
    final controller = TextEditingController(text: '42');
    tester.pumpWidget(
      TextInput(
        controller: controller,
        autofocus: true,
        onSubmit: submitted.add,
      ),
    );

    pressTerminalBytes(tester, _kpEnter);

    expect(submitted, ['42']);
  });

  testWidgets('NumLock-off keypad keys edit and move the caret', (tester) {
    final controller = TextEditingController();
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));
    tester.type('abc');

    pressTerminalBytes(tester, _kpLeft);
    tester.type('x');
    expect(controller.text, 'abxc');

    pressTerminalBytes(tester, '$_kpHome$_kpDelete');
    expect(controller.text, 'bxc');
  });

  testWidgets('KP Enter activates a focused button', (tester) {
    var pressed = 0;
    tester.pumpWidget(
      Button(text: 'OK', autofocus: true, onPressed: () => pressed++),
    );

    pressTerminalBytes(tester, _kpEnter);

    expect(pressed, 1);
  });

  testWidgets('KP Enter selects the current list row', (tester) {
    final selected = <int>[];
    tester.pumpWidget(
      ListView(
        autofocus: true,
        onSelect: selected.add,
        children: const [Text('one'), Text('two')],
      ),
    );

    // KP_2 with NumLock off is Down.
    pressTerminalBytes(tester, '\x1b[57420u$_kpEnter');

    expect(selected, [1]);
  });

  testWidgets('a simulated keypad press is the press a terminal sends', (
    tester,
  ) {
    // A test pressing a keypad position gets the same folded event the
    // parser delivers, so a button takes KP Enter either way.
    var pressed = 0;
    tester.pumpWidget(
      Button(text: 'OK', autofocus: true, onPressed: () => pressed++),
    );

    tester.press(KeyPosition.numpadEnter);

    expect(pressed, 1);
    expect(KeyPosition.numpad1.hintLabel, 'KP1');
  });
}
