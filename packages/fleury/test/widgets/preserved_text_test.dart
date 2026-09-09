import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

const secret = 'a\x1b[31mb\r\n\t🔑\u202e';

void main() {
  test(
    'exact values survive construction, replacement, history and disposal',
    () {
      final controller = TextEditingController(
        text: secret,
        preserveText: true,
      );
      expect(controller.text, secret);
      expect(controller.value.copyWith().text, secret);
      controller.caretOffset = controller.text.length;
      controller.insert('\r\n\x07', singleLine: true);
      expect(controller.text, '$secret\r\n\x07');
      controller.undo();
      expect(controller.text, secret);
      controller.redo();
      expect(controller.text, '$secret\r\n\x07');
      controller.clear();
      controller.paste(secret, singleLine: true);
      expect(controller.text, secret);
      controller.value = TextEditingValue.empty();
      controller.paste(secret);
      expect(
        controller.text,
        secret,
        reason: 'controller policy survives assignment',
      );
      controller.text = '';
      expect(controller.canUndo, isFalse);
      controller.text = secret;
      controller.dispose();
      expect(controller.text, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      expect(() => controller.insert('x'), throwsStateError);
    },
  );

  test(
    'normal controller cannot acquire preservation through value assignment',
    () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      controller.value = TextEditingValue(text: secret, preserveText: true);
      expect(controller.text, TextEditingValue(text: secret).text);
      expect(controller.value.preserveText, isFalse);
    },
  );

  test('composition commit, cancel and undo preserve exact text', () {
    final controller = TextEditingController(text: secret, preserveText: true);
    addTearDown(controller.dispose);
    controller.updateComposingText('\r\n\x1b', singleLine: true);
    expect(controller.text, '$secret\r\n\x1b');
    controller.cancelComposing();
    expect(controller.text, secret);
    controller.updateComposingText('temporary');
    controller.commitComposing(text: '\r\n\x1b', singleLine: true);
    expect(controller.text, '$secret\r\n\x1b');
    controller.undo();
    expect(controller.text, secret);
  });

  test('history restores literal entries and the captured draft', () {
    final history = TextHistoryController(entries: ['old\t\x1b']);
    addTearDown(history.dispose);
    final draft = TextEditingValue(text: secret, preserveText: true);
    expect(history.navigatePrevious(draft)!.text, 'old\t\x1b');
    expect(history.navigateNext()!.text, secret);
  });

  test('CRLF line motion and kills preserve the original line endings', () {
    final controller = TextEditingController(
      text: 'abc\r\ndef\r\nghi',
      preserveText: true,
    );
    addTearDown(controller.dispose);
    controller.caretOffset = 1;
    controller.moveCursorLineDown();
    expect(controller.caretOffset, 6);
    controller.moveCursorLineDown();
    expect(controller.caretOffset, 11);
    controller.moveCursorLineUp();
    expect(controller.caretOffset, 6);
    controller.moveCursorToLineStart();
    expect(controller.caretOffset, 5);
    controller.moveCursorToLineEnd();
    expect(controller.caretOffset, 8);
    controller.caretOffset = 0;
    controller.killToLineEnd(captureToKillRing: false);
    expect(controller.text, '\r\ndef\r\nghi');
    controller.killToLineEnd(captureToKillRing: false);
    expect(controller.text, 'def\r\nghi');
  });

  for (final multiline in [false, true]) {
    for (final masked in [false, true]) {
      testWidgets(
        'literal paste, mask and undo; multiline=$multiline masked=$masked',
        (tester) {
          final controller = TextEditingController(preserveText: true);
          addTearDown(controller.dispose);
          tester.pumpWidget(
            multiline
                ? TextArea(
                    controller: controller,
                    autofocus: true,
                    obscureText: masked,
                    clipboardPolicy: TextClipboardPolicy.redacted,
                    semanticLabel: 'Secret',
                  )
                : TextInput(
                    controller: controller,
                    autofocus: true,
                    obscureText: masked,
                    clipboardPolicy: TextClipboardPolicy.redacted,
                    semanticLabel: 'Secret',
                  ),
          );
          // Deliberately split ESC sequence and CRLF across paste batches.
          final content =
              '${'a' * 2047}\x1b[31m${'b' * 2043}\r\n$secret${'z' * 5000}';
          tester.paste(content);
          for (
            var i = 0;
            i < 64 && controller.text.length < content.length;
            i++
          ) {
            tester.pump();
          }
          expect(controller.text, content);
          expect(tester.semantics().single(label: 'Secret').value, isNull);
          final rendered = tester.renderToString();
          expect(rendered, isNot(contains('\x1b')));
          expect(rendered, isNot(contains('\r')));
          if (masked) expect(rendered, isNot(contains('zzz')));
          tester.press(.ctrl.z);
          expect(controller.text, isEmpty);
          tester.press(.ctrl.y);
          expect(controller.text, content);
        },
      );
    }

    testWidgets(
      'safe glyphs keep caret, pointer and deletion offsets; multiline=$multiline',
      (tester) {
        final controller = TextEditingController(
          text: 'a\x1b[31mb',
          preserveText: true,
        );
        addTearDown(controller.dispose);
        tester.pumpWidget(
          multiline
              ? TextArea(controller: controller, autofocus: true)
              : TextInput(controller: controller, autofocus: true),
        );
        controller.caretOffset = 2;
        tester.pump();
        final buffer = tester.render(size: const CellSize(12, 2));
        expect(buffer.atColRow(1, 0).grapheme, '�');
        expect(buffer.atColRow(2, 0).grapheme, '[');
        expect(buffer.atColRow(2, 0).style.inverse, isTrue);
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 6,
            row: 0,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 6,
            row: 0,
          ),
        );
        expect(controller.caretOffset, 6);
        tester.press(.backspace);
        expect(controller.text, 'a\x1b[31b');
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 2,
        );
        tester.press(.backspace);
        expect(controller.text, 'a[31b');
      },
    );
  }
}
