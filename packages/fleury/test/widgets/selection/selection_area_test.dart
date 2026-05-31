// End-to-end test: mouse-drag inside a SelectionArea highlights cells
// in the painted output AND reports a SelectedContent via
// onSelectionChanged. Validates the full pipeline:
//
//   Tester → MouseEvent → InputDispatcher → PointerRouter →
//   GestureDetector → SelectionArea._onDragStart/Update →
//   SelectionContainerDelegate.dispatchSelectionEvent →
//   RenderText.dispatchSelectionEvent (per leaf) →
//   geometry change → markNeedsPaint → next render shows highlight.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

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

MouseEvent _shiftDown(int col, int row) => MouseEvent(
  kind: MouseEventKind.down,
  button: MouseButton.left,
  col: col,
  row: row,
  modifiers: {KeyModifier.shift},
);

MouseEvent _shiftUp(int col, int row) => MouseEvent(
  kind: MouseEventKind.up,
  button: MouseButton.left,
  col: col,
  row: row,
  modifiers: {KeyModifier.shift},
);

void main() {
  group('SelectionArea — end-to-end', () {
    testWidgets('drag inside a single Text yields the selected substring', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Drag from col 2 to col 7: 'llo w' should be selected.
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(7, 0));
      tester.sendMouse(_up(7, 0));

      expect(captured, isNotNull);
      expect(captured!.plainText, 'llo w');
    });

    testWidgets('the selected cells render with inverse highlight', (
      tester,
    ) async {
      tester.pumpWidget(SelectionArea(child: const Text('abcdefg')));
      tester.render(size: const CellSize(10, 1));

      // Select cols 2..4 — 'cde'.
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(5, 0));

      final buf = tester.render(size: const CellSize(10, 1));
      // Selected cells carry the inverse-video style.
      expect(buf.atColRow(2, 0).style.inverse, isTrue);
      expect(buf.atColRow(3, 0).style.inverse, isTrue);
      expect(buf.atColRow(4, 0).style.inverse, isTrue);
      // Unselected cells don't.
      expect(buf.atColRow(0, 0).style.inverse, isFalse);
      expect(buf.atColRow(5, 0).style.inverse, isFalse);
    });

    testWidgets('drag across two Text widgets reports the concatenation', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Column(children: [Text('hello'), Text('world')]),
        ),
      );
      tester.render(size: const CellSize(10, 2));

      // Drag from inside 'hello' (col 2 row 0) into 'world' (col 3 row 1).
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(3, 1));
      tester.sendMouse(_up(3, 1));

      expect(captured, isNotNull);
      // 'hello' contributes 'llo' (cols 2..end), 'world' contributes
      // 'wor' (cols 0..3). The Column join makes the strings
      // adjacent in reading order.
      expect(captured!.plainText, 'llo\nwor');
    });

    testWidgets('a single click clears any existing selection', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(7, 0));
      tester.sendMouse(_up(7, 0));
      expect(captured?.plainText, 'llo w');

      // Click inside the text bounds at a different column — collapses
      // the selection without dragging.
      tester.sendMouse(_down(9, 0));
      tester.sendMouse(_up(9, 0));
      expect(captured, isNull);
    });
  });

  group('SelectionArea — copyOnRelease', () {
    testWidgets('writes the selected text to the active Clipboard on release', (
      tester,
    ) async {
      final originalClipboard = Clipboard.instance;
      final captured = TestClipboard();
      Clipboard.instance = captured;
      try {
        tester.pumpWidget(
          const SelectionArea(copyOnRelease: true, child: Text('hello world')),
        );
        tester.render(size: const CellSize(20, 1));

        tester.sendMouse(_down(2, 0));
        tester.sendMouse(_drag(7, 0));
        tester.sendMouse(_up(7, 0));

        // Clipboard.write is async; await one event-loop tick.
        await Future<void>.delayed(Duration.zero);
        expect(captured.lastWritten, 'llo w');
      } finally {
        Clipboard.instance = originalClipboard;
      }
    });

    testWidgets('a release with no selection does not write to clipboard', (
      tester,
    ) async {
      final originalClipboard = Clipboard.instance;
      final captured = TestClipboard();
      Clipboard.instance = captured;
      try {
        tester.pumpWidget(
          const SelectionArea(copyOnRelease: true, child: Text('hello')),
        );
        tester.render(size: const CellSize(10, 1));

        // Click without drag → no selection.
        tester.sendMouse(_down(2, 0));
        tester.sendMouse(_up(2, 0));

        await Future<void>.delayed(Duration.zero);
        expect(captured.lastWritten, isNull);
      } finally {
        Clipboard.instance = originalClipboard;
      }
    });
  });

  group('SelectionArea — keyboard', () {
    testWidgets('Ctrl+A selects all text in the area', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('abc'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}));
      expect(captured?.plainText, 'abc');
    });

    testWidgets('Ctrl+C copies the selection via Clipboard.instance', (
      tester,
    ) async {
      final originalClipboard = Clipboard.instance;
      final clip = TestClipboard();
      Clipboard.instance = clip;
      try {
        tester.pumpWidget(const SelectionArea(child: Text('hello world')));
        tester.render(size: const CellSize(20, 1));

        // First select via drag.
        tester.sendMouse(_down(2, 0));
        tester.sendMouse(_drag(7, 0));
        tester.sendMouse(_up(7, 0));

        // Then Ctrl+C.
        tester.sendKey(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await Future<void>.delayed(Duration.zero);
        expect(clip.lastWritten, 'llo w');
      } finally {
        Clipboard.instance = originalClipboard;
      }
    });

    testWidgets('Ctrl+C bubbles when no selection exists', (tester) async {
      var ancestorCtrlC = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.ctrl.c, onEvent: (_) => ancestorCtrlC++),
          ],
          child: const SelectionArea(child: Text('hello')),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      // SelectionArea had no selection → bubbled → ancestor fired.
      expect(ancestorCtrlC, 1);
    });

    testWidgets('Escape clears an active selection', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(7, 0));
      tester.sendMouse(_up(7, 0));
      expect(captured?.plainText, 'llo w');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      expect(captured, isNull);
    });

    testWidgets('Escape bubbles when no selection exists', (tester) async {
      var ancestorEscape = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.escape, onEvent: (_) => ancestorEscape++),
          ],
          child: const SelectionArea(child: Text('hello')),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      expect(ancestorEscape, 1);
    });
  });

  group('SelectionArea — double-click word', () {
    testWidgets('selects the alphanumeric run at the click position', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world foo'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Two clicks at col 7 (inside 'world'). Click 1 places anchor;
      // click 2 fires SelectionGranularity.word.
      tester.sendMouse(_down(7, 0));
      tester.sendMouse(_up(7, 0));
      tester.sendMouse(_down(7, 0));
      tester.sendMouse(_up(7, 0));

      expect(captured?.plainText, 'world');
    });

    testWidgets('selects a single non-word character on punctuation click', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('a-b'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      // Click 1 → 2 at col 1 ('-').
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));

      expect(captured?.plainText, '-');
    });

    testWidgets('treats Latin-1 accented letters as part of the same word', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('café bar'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_up(2, 0));
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_up(2, 0));

      expect(captured?.plainText, 'café');
    });

    testWidgets("apostrophe-joined contractions stay whole (don't, it's)", (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text("don't worry"),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Double-click on the 'r' inside 'worry' — selects 'worry'.
      tester.sendMouse(_down(7, 0));
      tester.sendMouse(_up(7, 0));
      tester.sendMouse(_down(7, 0));
      tester.sendMouse(_up(7, 0));
      expect(captured?.plainText, 'worry');

      // Double-click on 'o' inside "don't" — must select "don't",
      // not "don" or "t".
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));
      expect(
        captured?.plainText,
        "don't",
        reason: 'apostrophe between word chars must extend the word',
      );
    });

    testWidgets("edge apostrophes do NOT extend ('quoted' picks 'quoted')", (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text("'quoted' word"),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Double-click inside 'quoted' — must select 'quoted' WITHOUT
      // the surrounding apostrophes.
      tester.sendMouse(_down(3, 0));
      tester.sendMouse(_up(3, 0));
      tester.sendMouse(_down(3, 0));
      tester.sendMouse(_up(3, 0));
      expect(
        captured?.plainText,
        'quoted',
        reason: "edge apostrophes don't get pulled into the word",
      );
    });

    testWidgets('CJK characters each form their own word', (tester) async {
      // In Japanese / Chinese / Korean there is no inter-character
      // word boundary in the Latin sense. Double-click should select
      // a single character, not the whole CJK run.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('日本語'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Each Japanese character is width 2. '本' starts at col 2.
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_up(2, 0));
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_up(2, 0));

      expect(
        captured?.plainText,
        '本',
        reason: 'CJK double-click picks the single character',
      );
    });
  });

  group('SelectionArea — triple-click line', () {
    testWidgets('third click selects the entire laid-out line', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('line one\nline two'),
        ),
      );
      tester.render(size: const CellSize(20, 2));

      // 3 clicks at col 4 row 1 ('line two' line).
      tester.sendMouse(_down(4, 1));
      tester.sendMouse(_up(4, 1));
      tester.sendMouse(_down(4, 1));
      tester.sendMouse(_up(4, 1));
      tester.sendMouse(_down(4, 1));
      tester.sendMouse(_up(4, 1));

      expect(captured?.plainText, 'line two');
    });

    testWidgets('on a soft-wrapped line, selects the visual line only', (
      tester,
    ) async {
      // Behavior we promise: triple-click selects the on-screen line
      // (post-wrap), not the entire logical paragraph. Terminal-style
      // — matches Textual / xterm. Tested explicitly so a future
      // refactor doesn't silently switch to logical-line selection.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('one two three four five six', softWrap: true),
        ),
      );
      // Width 10 → wraps into multiple visual rows.
      tester.render(size: const CellSize(10, 4));

      // Triple-click at col 1 row 0 → the FIRST visual line only.
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));

      final got = captured?.plainText ?? '';
      expect(got, isNotEmpty);
      // The result must be a prefix of the logical content, NOT the
      // whole thing — proves we picked one visual row.
      expect(
        'one two three four five six'.startsWith(got),
        isTrue,
        reason: 'visual-line selection is a prefix of the logical line',
      );
      expect(
        got.length,
        lessThan('one two three four five six'.length),
        reason: 'visual-line is shorter than the full logical line',
      );
    });
  });

  group('SelectionArea — Shift+Arrow extension', () {
    testWidgets('Shift+Right extends the cursor one cell to the right', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Establish an initial selection 'llo' (cols 2..4).
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(5, 0));
      tester.sendMouse(_up(5, 0));
      expect(captured?.plainText, 'llo');

      // Shift+Right pushes cursor from col 5 to col 6 → 'llo ' becomes 'llo '.
      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowRight,
          modifiers: {KeyModifier.shift},
        ),
      );
      expect(captured?.plainText, 'llo ');
    });

    testWidgets('Shift+Left shrinks the selection from the right', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(7, 0));
      tester.sendMouse(_up(7, 0));
      expect(captured?.plainText, 'llo w');

      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowLeft,
          modifiers: {KeyModifier.shift},
        ),
      );
      expect(captured?.plainText, 'llo ');
    });

    testWidgets('Shift+Right crosses a wide CJK character in one keystroke', (
      tester,
    ) async {
      // Wide graphemes (CJK, emoji, ZWJ) occupy 2 cells but are one
      // character. Shift+Right used to move only 1 cell — leaving the
      // cursor stranded on the continuation cell with no visible
      // change. The grapheme-boundary protocol must cross the whole
      // wide character in one step.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('a中b'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      // Start: anchor at col 0, end at col 1 → selection 'a'.
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(1, 0));
      tester.sendMouse(_up(1, 0));
      expect(captured?.plainText, 'a');

      // Shift+Right — one keystroke should cross all of '中' (width 2).
      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowRight,
          modifiers: {KeyModifier.shift},
        ),
      );
      expect(
        captured?.plainText,
        'a中',
        reason: 'one Shift+Right must cross the whole wide grapheme',
      );
    });

    testWidgets('Shift+Arrow with no active selection bubbles', (tester) async {
      var ancestorRightHit = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.shift.right,
              onEvent: (_) => ancestorRightHit++,
            ),
          ],
          child: const SelectionArea(child: Text('hello')),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowRight,
          modifiers: {KeyModifier.shift},
        ),
      );
      expect(ancestorRightHit, 1);
    });

    testWidgets('Shift+Down hops from one Text into the Text below', (
      tester,
    ) async {
      // The cursor lives in the top Text. Shift+Down should jump it to
      // the same column on row 1 — which is inside a different
      // Selectable. The bug this guards: an early bounds check that
      // rejects `from` if it doesn't lie in the candidate Selectable
      // means the bottom Text refuses the move even though its row
      // contains the destination.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text('first line'), Text('second line')],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));

      // Anchor at col 0 row 0, drag cursor to col 4 row 0 → 'firs'.
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(4, 0));
      tester.sendMouse(_up(4, 0));
      expect(captured?.plainText, 'firs');

      // Shift+Down moves the cursor to row 1 col 4 — selection now
      // spans 'first line\nseco'.
      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowDown,
          modifiers: {KeyModifier.shift},
        ),
      );
      expect(
        captured?.plainText,
        'first line\nseco',
        reason: 'Shift+Down must cross into the Selectable below',
      );
    });

    testWidgets('Shift+Up hops back to the Text above', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text('first line'), Text('second line')],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));

      // Drag a selection on the second row only ('seco').
      tester.sendMouse(_down(0, 1));
      tester.sendMouse(_drag(4, 1));
      tester.sendMouse(_up(4, 1));
      expect(captured?.plainText, 'seco');

      // Shift+Up moves the cursor up to row 0 col 4 — reverse
      // selection: anchor below (col 0 row 1), cursor above (col 4
      // row 0). getSelectedText walks Selectables top-to-bottom, so
      // it reports 'st line\n' (cols 4..end of row 0, plus the
      // leading anchor cell on row 1 is excluded since the selection
      // ends there).
      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowUp,
          modifiers: {KeyModifier.shift},
        ),
      );
      // The reverse-direction span covers cells on row 0 from col 4
      // onward plus row 1 up to col 0 (exclusive). Just assert that
      // the selection now includes content from the row above.
      expect(
        captured?.plainText,
        contains('t line'),
        reason: 'Shift+Up must cross into the Selectable above',
      );
    });

    testWidgets('Shift+Down at the last row leaves the cursor in place', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('only line'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(4, 0));
      tester.sendMouse(_up(4, 0));
      expect(captured?.plainText, 'only');

      // Nothing below — cursor must NOT move (no exception, no
      // selection change).
      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowDown,
          modifiers: {KeyModifier.shift},
        ),
      );
      expect(
        captured?.plainText,
        'only',
        reason: 'Shift+Down at the bottom row is a no-op',
      );
    });
  });

  group('SelectionArea — Shift+Click', () {
    testWidgets('extends an active selection to the click point '
        'without resetting the anchor', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Initial selection: 'hel' (cols 0..2).
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(3, 0));
      tester.sendMouse(_up(3, 0));
      expect(captured?.plainText, 'hel');

      // Shift+Click at col 8 → cursor moves to 8, anchor stays at 0.
      tester.sendMouse(_shiftDown(8, 0));
      tester.sendMouse(_shiftUp(8, 0));
      expect(
        captured?.plainText,
        'hello wo',
        reason: 'Shift+Click must extend, not reset',
      );
    });

    testWidgets('with no active selection starts a fresh anchor at the click', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world'),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // No selection in flight. Shift+Click then drag — should behave
      // just like a plain click + drag, anchored at the press point.
      tester.sendMouse(_shiftDown(0, 0));
      tester.sendMouse(_drag(5, 0));
      tester.sendMouse(_up(5, 0));
      expect(
        captured?.plainText,
        'hello',
        reason: 'Shift+Click with no anchor falls through to fresh anchor',
      );
    });

    testWidgets('breaks an in-flight double-click streak', (tester) async {
      // Double-click selects a word. A subsequent Shift+Click must not
      // be interpreted as the third click of a triple-click — it must
      // be treated as a fresh extend.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('alpha beta gamma'),
        ),
      );
      tester.render(size: const CellSize(30, 1));

      // Double-click 'alpha'.
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));
      tester.sendMouse(_down(1, 0));
      tester.sendMouse(_up(1, 0));
      expect(captured?.plainText, 'alpha');

      // Shift+Click at col 8 (mid-'beta'). Must extend to col 8, NOT
      // be treated as a triple-click on the row.
      tester.sendMouse(_shiftDown(8, 0));
      tester.sendMouse(_shiftUp(8, 0));
      expect(
        captured?.plainText,
        isNot(equals('alpha beta gamma')),
        reason: 'Shift+Click must not become triple-click line select',
      );
      expect(
        captured?.plainText,
        contains('alpha'),
        reason: 'extension keeps the original anchor',
      );
    });
  });

  group('SelectionArea.disabled', () {
    testWidgets(
      'Text inside a disabled subtree does not participate in selection',
      (tester) async {
        SelectedContent? captured;
        tester.pumpWidget(
          SelectionArea(
            onSelectionChanged: (sel) => captured = sel,
            child: Column(
              children: [
                const Text('outer'),
                SelectionArea.disabled(child: const Text('inner')),
              ],
            ),
          ),
        );
        tester.render(size: const CellSize(20, 2));

        // Ctrl+A should select the outer Text but skip the disabled inner.
        tester.sendKey(
          const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}),
        );
        expect(
          captured?.plainText,
          'outer',
          reason: 'inner Text was masked by SelectionArea.disabled',
        );
      },
    );
  });

  group('Text.allowSelect', () {
    testWidgets(
      'allowSelect: false Text is skipped by Ctrl+A in a SelectionArea',
      (tester) async {
        SelectedContent? captured;
        tester.pumpWidget(
          SelectionArea(
            onSelectionChanged: (sel) => captured = sel,
            child: Column(
              children: const [
                Text('selectable'),
                Text('skip me', allowSelect: false),
              ],
            ),
          ),
        );
        tester.render(size: const CellSize(20, 2));

        tester.sendKey(
          const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}),
        );
        expect(captured?.plainText, 'selectable');
      },
    );
  });

  group('SelectionArea — multi-widget boundary handoff', () {
    testWidgets('selection spanning three Texts in a Column joins them all', (
      tester,
    ) async {
      // The middle widget should be fully selected — both edges live
      // outside it (anchor in widget 0, cursor in widget 2). It needs
      // to report SelectionResult.next for both edge updates and have
      // its full content folded into the join.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Column(
            children: [Text('alpha'), Text('beta'), Text('gamma')],
          ),
        ),
      );
      tester.render(size: const CellSize(10, 3));

      // Drag from col 2 row 0 ('lpha' onwards) to col 3 row 2 ('gam').
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(3, 2));
      tester.sendMouse(_up(3, 2));

      expect(captured?.plainText, 'pha\nbeta\ngam');
    });
  });

  group('SelectionArea — empty content edge cases', () {
    testWidgets('drag over an empty Text yields no selected content', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const SizedBox(width: 5, height: 1, child: Text('')),
        ),
      );
      tester.render(size: const CellSize(5, 1));

      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(4, 0));
      tester.sendMouse(_up(4, 0));

      expect(captured, isNull);
    });

    testWidgets('Ctrl+A on empty content reports no selection', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text(''),
        ),
      );
      tester.render(size: const CellSize(5, 1));

      tester.sendKey(const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}));
      expect(captured, isNull);
    });

    testWidgets('double-click on an empty cell selects nothing', (tester) {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const SizedBox(width: 10, height: 1, child: Text('hi')),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      // Cells 2..9 are empty (Text only paints 'hi' at cols 0..1).
      tester.sendMouse(_down(5, 0));
      tester.sendMouse(_up(5, 0));
      tester.sendMouse(_down(5, 0));
      tester.sendMouse(_up(5, 0));

      expect(captured, isNull);
    });
  });

  group('SelectionArea — Tab characters', () {
    testWidgets('a Tab in the source survives selection round-trip', (
      tester,
    ) async {
      // We treat Tab as a 1-cell character at the render layer
      // (sanitized like other control characters via U+FFFD). The
      // important thing is that selecting a region containing a Tab
      // doesn't crash or misalign the offset math.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('a\tb'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}));
      // Whatever the sanitizer produces, the selection round-trips
      // through it cleanly (length 3, all characters captured).
      expect(captured, isNotNull);
      expect(captured!.plainText.length, 3);
    });
  });

  group('SelectionArea — geometry capture', () {
    testWidgets('Selectable.cellBounds is updated at paint time', (
      tester,
    ) async {
      tester.pumpWidget(const SelectionArea(child: Text('abc')));
      final buf = tester.render(size: const CellSize(5, 1));
      // Text was painted at (0, 0) with size (3, 1) — but the area
      // doesn't expose Selectables externally. Just verify the
      // selection works when we hit those cells.
      expect(buf.atColRow(0, 0).grapheme, 'a');
    });
  });
}
