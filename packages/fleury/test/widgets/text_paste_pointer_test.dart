// A large paste is applied over several frames. A click in the field while
// it is still being applied finishes it first, as every key does: the rest
// of the paste lands where the paste was, and the click places the caret on
// what the user clicked. Before, the rest landed at the click, ahead of the
// part already applied, and the paste took two undos.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

const _size = CellSize(40, 10);

final _paste = [
  for (var i = 0; i < 2000; i++) 'line ${i.toString().padLeft(4, '0')}\n',
].join();

void _click(FleuryTester tester, int col, int row) {
  for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
    tester.sendMouse(
      MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row),
    );
  }
}

void main() {
  for (final multiline in [false, true]) {
    testWidgets(
      'a click mid-paste keeps the paste whole, multiline=$multiline',
      (tester) {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        tester.pumpWidget(
          multiline
              ? TextArea(controller: controller, autofocus: true)
              : TextInput(controller: controller, autofocus: true),
        );
        tester.render(size: _size);
        tester.paste(_paste);
        tester.pump();
        final expected = multiline ? _paste : _paste.replaceAll('\n', ' ');
        expect(
          controller.text.length,
          lessThan(expected.length),
          reason: 'still being applied',
        );

        _click(tester, 0, 0);
        for (var i = 0; i < 20; i++) {
          tester.pump();
        }

        expect(controller.text, expected);
        tester.sendKey(
          const KeyEvent(KeyCode.z, modifiers: {KeyModifier.ctrl}),
        );
        expect(controller.text, isEmpty, reason: 'one undo for one paste');
      },
    );
  }

  testWidgets('a click past the paste point lands on what was clicked', (
    tester,
  ) {
    final controller = TextEditingController(text: 'END');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 0);
    tester.pumpWidget(TextArea(controller: controller, autofocus: true));
    tester.render(size: _size);
    tester.paste(_paste);

    // 'END' follows the caret, on the caret's row, in the frame drawn next.
    final buffer = tester.render(size: _size);
    CellOffset? end;
    for (var row = 0; row < _size.rows && end == null; row++) {
      for (var col = 0; col + 2 < _size.cols; col++) {
        if (buffer.atColRow(col, row).grapheme == 'E' &&
            buffer.atColRow(col + 1, row).grapheme == 'N' &&
            buffer.atColRow(col + 2, row).grapheme == 'D') {
          end = CellOffset(col, row);
          break;
        }
      }
    }
    expect(end, isNotNull, reason: 'the suffix is on screen');
    // A frame, then its post-frame paste step: the controller moves past
    // the text laid out, as it does between frames at runtime.
    final laidOut = controller.text.length;
    tester.pump();
    expect(controller.text.length, greaterThan(laidOut));

    _click(tester, end!.col, end.row);
    tester.pump();

    expect(controller.text, '${_paste}END');
    expect(
      controller.selection,
      TextSelection.collapsed(offset: _paste.length),
    );
  });
}
