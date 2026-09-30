import 'dart:convert';
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';

void main() {
  for (final multiline in [false, true]) {
    for (final intervention in ['caret', 'typing', 'undo']) {
      test('streamed paste preserves $intervention, multiline=$multiline', () {
        final tester = FleuryTester(
          terminalParser: InputParser(maxPasteBytes: 2),
        );
        final c = TextEditingController();
        addTearDown(() {
          tester.dispose();
          c.dispose();
        });
        tester.pumpWidget(
          multiline
              ? TextArea(controller: c, autofocus: true)
              : TextInput(controller: c, autofocus: true),
        );
        tester.render();
        tester.sendTerminalBytes(utf8.encode('\x1b[200~ABCD'));
        expect(c.text, isNotEmpty);
        final accepted = c.text;
        switch (intervention) {
          case 'caret':
            tester.sendKey(const KeyEvent(KeyCode.home));
          case 'typing':
            tester.type('x');
          case 'undo':
            tester.sendKey(
              const KeyEvent(KeyCode.z, modifiers: {KeyModifier.ctrl}),
            );
        }
        tester.sendTerminalBytes(utf8.encode('EF\x1b[201~'));
        tester.pump();
        if (intervention == 'undo') {
          expect(c.text, '');
          c.redo();
          expect(c.text, accepted);
        } else {
          expect(c.text, intervention == 'typing' ? 'ABCDEFx' : 'ABCDEF');
          if (intervention == 'typing') {
            c.undo();
            expect(c.text, 'ABCDEF');
          } else {
            expect(c.caretOffset, 0);
          }
          c.undo();
          expect(c.text, '');
        }
      });
    }
  }

  test(
    'terminal byte helper preserves UTF-8 and CSI across read boundaries',
    () {
      final tester = FleuryTester();
      final c = TextEditingController();
      addTearDown(() {
        tester.dispose();
        c.dispose();
      });
      tester.pumpWidget(TextInput(controller: c, autofocus: true));
      for (final byte in utf8.encode('é\x1b[D!')) {
        tester.sendTerminalBytes([byte]);
      }
      expect(c.text, '!é');
    },
  );
}
