// TextArea: multi-line editing, line-aware cursor movement, and a
// vertically-scrolling viewport that keeps the cursor visible.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

List<String> _lines(FleuryTester tester, {int cols = 10, required int rows}) {
  final buf = tester.render(size: CellSize(cols, rows));
  return [
    for (var r = 0; r < rows; r++)
      [
        for (var c = 0; c < cols; c++)
          buf.atColRow(c, r).role == CellRole.leading
              ? buf.atColRow(c, r).grapheme!
              : ' ',
      ].join().trimRight(),
  ];
}

void main() {
  testWidgets('renders text across multiple rows', (tester) {
    final ctl = TextEditingController(text: 'one\ntwo\nthree');
    tester.pumpWidget(TextArea(controller: ctl));
    expect(_lines(tester, rows: 4), ['one', 'two', 'three', '']);
  });

  testWidgets('typing inserts; Enter starts a new line', (tester) {
    final ctl = TextEditingController();
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
    tester.type('ab');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.type('cd');
    expect(ctl.text, 'ab\ncd');
    expect(_lines(tester, rows: 3), ['ab', 'cd', '']);
  });

  testWidgets('Up/Down move between lines, preserving the column', (tester) {
    final ctl = TextEditingController(text: 'abcd\nxy\nwxyz');
    // Put the cursor at column 3 on the last line (index 8 + 3 = 11).
    ctl.selection = 11;
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
    // Middle line "xy" is only length 2 → column clamps to end (index 7).
    expect(ctl.selection, 7);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
    // First line "abcd": the preserved column came from "xy" (col 2) → 2.
    expect(ctl.selection, 2);
  });

  testWidgets('Home/End move within the current line', (tester) {
    final ctl = TextEditingController(text: 'hello\nworld');
    ctl.selection = 8; // "wo|rld"
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
    expect(ctl.selection, 6, reason: 'start of "world"');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
    expect(ctl.selection, 11, reason: 'end of "world"');
  });

  testWidgets('Backspace at a line start joins with the previous line', (
    tester,
  ) {
    final ctl = TextEditingController(text: 'ab\ncd');
    ctl.selection = 3; // just after the newline, before "cd"
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.backspace));
    expect(ctl.text, 'abcd');
  });

  testWidgets('Home/Up at the very start are safe no-ops', (tester) {
    final ctl = TextEditingController(text: 'abc');
    ctl.selection = 0; // cursor at index 0
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
    // These compute the line start from index 0 — must not throw.
    tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    expect(ctl.selection, isNonNegative);
  });

  testWidgets('scrolls to keep the cursor line visible', (tester) {
    final ctl = TextEditingController(text: 'r0\nr1\nr2\nr3\nr4');
    ctl.selection = ctl.text.length; // cursor on r4
    tester.pumpWidget(
      SizedBox(height: 3, child: TextArea(controller: ctl, autofocus: true)),
    );
    // 5 lines, 3-row viewport, cursor on the last line → shows r2..r4.
    expect(_lines(tester, rows: 3), ['r2', 'r3', 'r4']);
  });

  group('bracketed paste', () {
    testWidgets('a multi-line paste inserts verbatim across lines', (tester) {
      final ctl = TextEditingController();
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
      tester.paste('one\ntwo\nthree');
      expect(ctl.text, 'one\ntwo\nthree', reason: 'newlines preserved');
      expect(_lines(tester, rows: 3), ['one', 'two', 'three']);
    });
  });

  group('placeholder', () {
    testWidgets('shows a multi-line placeholder while empty', (tester) {
      tester.pumpWidget(const TextArea(placeholder: 'type\nhere'));
      expect(_lines(tester, rows: 2), ['type', 'here']);
    });

    testWidgets('the placeholder is dimmed and clears once typing starts', (
      tester,
    ) {
      final ctl = TextEditingController();
      tester.pumpWidget(
        TextArea(controller: ctl, autofocus: true, placeholder: 'hint'),
      );
      var buf = tester.render(size: const CellSize(10, 2));
      expect(buf.atColRow(1, 0).style.dim, isTrue, reason: 'placeholder dim');

      tester.type('x');
      buf = tester.render(size: const CellSize(10, 2));
      expect(buf.atColRow(0, 0).grapheme, 'x');
      expect(_lines(tester, rows: 1).first, 'x', reason: 'placeholder gone');
    });
  });
}
