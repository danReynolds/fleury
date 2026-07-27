// Popup: the floating-chrome composite. What's pinned here:
//   - it is OPAQUE: a wall of text behind it never shows inside its frame
//     (the contract every stock float delegates to it);
//   - the default frame is the theme border; Popup.bare draws none but
//     still fills;
//   - it is CHROME: its text is not part of the ambient selection, unless
//     selectableContent opts back in.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _cols = 30;
const _rows = 8;
const _size = CellSize(_cols, _rows);

Widget _overWall(Widget popup) => Stack(
  children: [
    Column(children: [for (var i = 0; i < _rows; i++) Text('X' * _cols)]),
    Align(alignment: Alignment.center, child: popup),
  ],
);

String _screen(FleuryTester tester) =>
    tester.renderToString(size: _size, emptyMark: ' ');

MouseEvent _mouse(MouseEventKind kind, int col, int row) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row);

void _dragAcrossRow(FleuryTester tester, int row) {
  tester.sendMouse(_mouse(MouseEventKind.down, 0, row));
  tester.sendMouse(_mouse(MouseEventKind.drag, _cols - 1, row));
  tester.sendMouse(_mouse(MouseEventKind.up, _cols - 1, row));
}

/// The screen row containing [needle], or -1.
int _rowOf(FleuryTester tester, String needle) {
  final lines = _screen(tester).split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains(needle)) return i;
  }
  return -1;
}

void main() {
  testWidgets('is opaque: the wall never shows inside the frame', (tester) {
    // Rows of different length, so the frame's interior has cells the
    // content itself never writes — the cells that bleed without the fill.
    tester.pumpWidget(
      _overWall(
        const Popup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('a much longer line'), Text('hi')],
          ),
        ),
      ),
    );
    tester.render(size: _size);

    final framed = _screen(tester)
        .split('\n')
        .where((line) => line.contains('│'))
        .map(
          (line) =>
              line.substring(line.indexOf('│') + 1, line.lastIndexOf('│')),
        );
    expect(framed, isNotEmpty, reason: 'the default frame rendered');
    for (final interior in framed) {
      expect(interior, isNot(contains('X')));
    }
  });

  testWidgets('Popup.bare fills without a frame', (tester) {
    tester.pumpWidget(_overWall(const Popup.bare(child: Text('hello'))));
    tester.render(size: _size);

    final out = _screen(tester);
    expect(out, isNot(contains('│')), reason: 'no frame drawn');
    final row = _rowOf(tester, 'hello');
    expect(row, isNot(-1));
    // The fill still owns the popup's cells: the line holding the content
    // shows the wall only OUTSIDE the popup's width, never adjacent to the
    // text (Surface pads the popup's full rect).
    final line = _screen(tester).split('\n')[row];
    expect(line, contains('hello'));
  });

  testWidgets('popup text is chrome — not ambient-selectable', (tester) {
    tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: const Popup.bare(child: Text('secret')),
      ),
    );
    tester.render(size: _size);

    _dragAcrossRow(tester, 0);
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), isNull);
  });

  testWidgets('selectableContent opts the text back in', (tester) {
    tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: const Popup.bare(selectableContent: true, child: Text('copyme')),
      ),
    );
    tester.render(size: _size);

    _dragAcrossRow(tester, 0);
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), 'copyme');
  });
}
