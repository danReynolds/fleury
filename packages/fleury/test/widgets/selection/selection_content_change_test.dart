// A live selection outlives the text it was made on.
//
// Selection is default-on at runApp, so this is every app's path: drag over a
// status line, a log row, a streaming message — and the text changes under
// the highlight. The edges are screen points; what they select must be
// whatever is on screen at those cells NOW, and copy must never hand a
// consumer an offset into text that no longer exists.
//
// Regression tests for a RangeError thrown out of copy and Escape when the
// text shrank (which also took the runtime's Ctrl+C quit guard down with it,
// leaving the app unquittable from the keyboard), and for the quieter
// sibling: when the text grew or its line breaks moved, stale flat offsets
// silently selected — and copied — the wrong characters.

import 'package:fleury/fleury.dart';
import '../../support/harness.dart';
import 'package:test/test.dart';

const _wide = CellSize(30, 3);

MouseEvent _down(int col, int row) => MouseEvent(
  kind: MouseEventKind.down,
  button: MouseButton.left,
  col: col,
  row: row,
);
MouseEvent _drag(int col, int row) => MouseEvent(
  kind: MouseEventKind.drag,
  button: MouseButton.left,
  col: col,
  row: row,
);
MouseEvent _up(int col, int row) => MouseEvent(
  kind: MouseEventKind.up,
  button: MouseButton.left,
  col: col,
  row: row,
);

void _dragSelect(
  FleuryTester tester, {
  required int fromCol,
  required int toCol,
  int row = 0,
}) {
  tester.sendMouse(_down(fromCol, row));
  tester.sendMouse(_drag(toCol, row));
  tester.sendMouse(_up(toCol, row));
}

void main() {
  group('a selection survives the text changing under it', () {
    testWidgets('copy after the text SHRANK copies what is on screen', (
      tester,
    ) {
      tester.pumpWidget(const Text('hello world this is long'));
      tester.render(size: _wide);
      _dragSelect(tester, fromCol: 0, toCol: 24);

      // Same widget, same slot: the RenderText is updated in place and its
      // lines are replaced. Threw `RangeError (end): … 0..2: 24` from copy.
      tester.pumpWidget(const Text('hi'));
      tester.render(size: _wide);
      tester.press(KeySequence.ctrl.c);

      expect(tester.clipboard.readInProcess(), 'hi');
    });

    testWidgets('Escape after the text shrank clears instead of throwing', (
      tester,
    ) {
      tester.pumpWidget(const Text('hello world this is long'));
      tester.render(size: _wide);
      _dragSelect(tester, fromCol: 0, toCol: 24);

      tester.pumpWidget(const Text('hi'));
      tester.render(size: _wide);
      tester.sendKey(const KeyEvent(KeyCode.escape));

      expect(
        tester.render(size: _wide).atColRow(0, 0).style.inverse,
        isFalse,
        reason: 'Escape cleared the (re-resolved) selection',
      );
    });

    testWidgets('a line-break change re-resolves at the same screen cells', (
      tester,
    ) {
      // Row 1 is "bbbb" at flat offsets 5..9.
      tester.pumpWidget(const Text('aaaa\nbbbb'));
      tester.render(size: _wide);
      _dragSelect(tester, fromCol: 0, toCol: 4, row: 1);

      // Row 1 is still "bbbb" on screen, now at flat offsets 2..6. Stale
      // offsets 5..9 would throw (length 6); merely clamping them would copy
      // a single "b". The screen points say row 1, cols 0–4.
      tester.pumpWidget(const Text('a\nbbbb'));
      tester.render(size: _wide);
      tester.press(KeySequence.ctrl.c);

      expect(tester.clipboard.readInProcess(), 'bbbb');
    });

    testWidgets('growth re-resolves rather than copying stale offsets', (
      tester,
    ) {
      // Row 1 is "cd" at flat offsets 3..5.
      tester.pumpWidget(const Text('ab\ncd'));
      tester.render(size: _wide);
      _dragSelect(tester, fromCol: 0, toCol: 2, row: 1);

      // Row 1 is still "cd" on screen. Stale offsets 3..5 now land inside
      // row 0 ("de") — no throw, no banner, silently the wrong clipboard.
      tester.pumpWidget(const Text('abcdef\ncd'));
      tester.render(size: _wide);
      tester.press(KeySequence.ctrl.c);

      expect(tester.clipboard.readInProcess(), 'cd');
    });

    testWidgets('a resize re-wrap re-resolves; copy does not throw', (tester) {
      // One line at 30 columns; the whole thing is selected (offsets 0..22).
      tester.pumpWidget(const Text('alpha beta gamma delta', maxLines: 2));
      tester.render(size: _wide);
      _dragSelect(tester, fromCol: 0, toCol: 22);

      // 8 columns: re-wraps to ["alpha", "beta"] and drops the rest, so the
      // flat content is 10 long. No app-side text change at all — the
      // terminal got narrower. Offsets 0..22 threw; the screen points say
      // row 0, from col 0 past the right edge — i.e. "alpha".
      tester.render(size: const CellSize(8, 3));
      tester.press(KeySequence.ctrl.c);

      expect(tester.clipboard.readInProcess(), 'alpha');
    });
  });
}
