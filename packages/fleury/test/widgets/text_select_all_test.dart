import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:test/test.dart';

void main() {
  for (final multiline in [false, true]) {
    for (final primary in [KeyModifier.ctrl, KeyModifier.superKey]) {
      for (final readOnly in [false, true]) {
        test(
          'select all in ${multiline ? 'TextArea' : 'TextInput'} with $primary, readOnly=$readOnly',
          () async {
            final tester = FleuryTester(viewportSize: const CellSize(40, 8));
            final original = multiline ? 'hello 界\nsecond' : 'https://dart.dev';
            final controller = TextEditingController(text: original);
            addTearDown(() {
              tester.dispose();
              controller.dispose();
            });
            tester.pumpWidget(
              multiline
                  ? TextArea(
                      controller: controller,
                      autofocus: true,
                      readOnly: readOnly,
                    )
                  : TextInput(
                      controller: controller,
                      autofocus: true,
                      readOnly: readOnly,
                    ),
            );
            tester.render();
            tester.sendKey(KeyEvent(KeyCode.a, modifiers: {primary}));
            expect(
              controller.selection,
              TextSelection(baseOffset: 0, extentOffset: original.length),
            );
            expect(tester.render().atColRow(0, 0).style.inverse, isTrue);
            tester.sendKey(KeyEvent(KeyCode.c, modifiers: {primary}));
            await tester.settle();
            expect(
              (tester.clipboard as InProcessClipboard).lastWritten,
              original,
            );
            tester.type('replacement');
            expect(controller.text, readOnly ? original : 'replacement');
            expect(
              tester.renderToString(),
              contains(readOnly ? original.split('\n').first : 'replacement'),
            );
            if (!readOnly) {
              tester.sendKey(KeyEvent(KeyCode.z, modifiers: {primary}));
              expect(controller.text, original);
              tester.sendKey(
                KeyEvent(KeyCode.z, modifiers: {primary, KeyModifier.shift}),
              );
              expect(controller.text, 'replacement');
            }
          },
        );
      }
    }
  }

  test(
    'Emacs Ctrl-A keeps its explicit movement binding; key-up is ignored',
    () {
      const keymap = TextEditingKeymap.emacsSingleLine;
      expect(
        keymap.resolve(
          const KeyEvent(KeyCode.a, modifiers: {KeyModifier.ctrl}),
        ),
        TextEditingKeyAction.moveDocumentStart,
      );
      expect(
        keymap.resolve(
          const KeyEvent(KeyCode.a, modifiers: {KeyModifier.superKey}),
        ),
        TextEditingKeyAction.selectAll,
      );
      expect(
        keymap.resolve(
          const KeyEvent(
            KeyCode.a,
            type: KeyEventType.up,
            modifiers: {KeyModifier.superKey},
          ),
        ),
        isNull,
      );
    },
  );
}
