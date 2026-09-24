// The numeric keypad on a Kitty-protocol terminal (the default setup) and in
// application-keypad mode: the parser reports each keypad key by what it
// means, as the DOM does, so a keypad digit types, KP Enter submits and
// activates, and the NumLock-off keys edit and navigate. Each test drives
// real terminal bytes through InputParser into real widgets.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

final class _Sink implements TuiEventSink {
  final events = <TuiEvent>[];

  @override
  void add(TuiEvent event) => events.add(event);
}

/// Parses [bytes] as a terminal would deliver them and dispatches every
/// event the parser emits.
void _pressBytes(FleuryTester tester, String bytes) {
  final sink = _Sink();
  InputParser()
    ..feed(bytes.codeUnits, sink)
    ..flush(sink);
  for (final event in sink.events) {
    switch (event) {
      case InputBatch():
        tester.sendBatch(event);
      case KeyEvent():
        tester.sendKey(event);
      case TextInputEvent(:final text):
        tester.type(text);
      default:
        fail('unexpected event $event');
    }
  }
}

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

    _pressBytes(tester, '$_kp1$_kpAdd$_kp2');

    expect(controller.text, '1+2');
  });

  testWidgets('application-keypad digits type too', (tester) {
    final controller = TextEditingController();
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    _pressBytes(tester, '\x1bOq\x1bOk\x1bOr');

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

    _pressBytes(tester, _kpEnter);

    expect(submitted, ['42']);
  });

  testWidgets('NumLock-off keypad keys edit and move the caret', (tester) {
    final controller = TextEditingController();
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));
    tester.type('abc');

    _pressBytes(tester, _kpLeft);
    tester.type('x');
    expect(controller.text, 'abxc');

    _pressBytes(tester, '$_kpHome$_kpDelete');
    expect(controller.text, 'bxc');
  });

  testWidgets('KP Enter activates a focused button', (tester) {
    var pressed = 0;
    tester.pumpWidget(
      Button(text: 'OK', autofocus: true, onPressed: () => pressed++),
    );

    _pressBytes(tester, _kpEnter);

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

    _pressBytes(tester, '\x1b[57420u$_kpEnter'); // KP_2 (NumLock off): Down

    expect(selected, [1]);
  });
}
