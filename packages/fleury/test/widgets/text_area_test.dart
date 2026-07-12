// TextArea: multi-line editing, line-aware cursor movement, and a
// vertically-scrolling viewport that keeps the cursor visible.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
// The debug collector is deliberately not exported by the production barrels;
// the split-memo assertions reach it through the src import, like other
// render-internal tests.
import 'package:fleury/src/widgets/text_area.dart' show TextAreaDebugStats;
import 'package:test/test.dart';

KeyEvent _shiftCode(KeyCode keyCode) =>
    KeyEvent(keyCode: keyCode, modifiers: const {KeyModifier.shift});
KeyEvent _ctrlChar(String char) =>
    KeyEvent(char: char, modifiers: const {KeyModifier.ctrl});

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
    tester.type('a');
    tester.type('b');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.type('c');
    tester.type('d');
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

  testWidgets('keymap presets can add Emacs-style line movement', (tester) {
    final ctl = TextEditingController(text: 'one\ntwo')..selection = 7;
    tester.pumpWidget(
      TextArea(
        controller: ctl,
        autofocus: true,
        keymap: TextEditingKeymap.emacsMultiline,
      ),
    );

    tester.sendKey(_ctrlChar('a'));
    expect(ctl.selection, 4);

    tester.sendKey(_ctrlChar('e'));
    expect(ctl.selection, 7);
  });

  testWidgets('Shift+arrows extend and render a selection range', (tester) {
    final ctl = TextEditingController(text: 'ab\ncd')..selection = 0;
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

    tester.sendKey(_shiftCode(KeyCode.arrowRight));
    tester.sendKey(_shiftCode(KeyCode.arrowRight));

    expect(
      ctl.textSelection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    final buf = tester.render(size: const CellSize(4, 2));
    expect(buf.atColRow(0, 0).style.inverse, isTrue);
    expect(buf.atColRow(1, 0).style.inverse, isTrue);
    expect(buf.atColRow(0, 1).style.inverse, isFalse);

    tester.type('X');
    expect(ctl.text, 'X\ncd');
    expect(ctl.textSelection, const TextSelection.collapsed(1));
  });

  testWidgets('Shift+Down extends by grapheme column across lines', (tester) {
    final ctl = TextEditingController(text: 'ab\ncd')..selection = 0;
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

    tester.sendKey(_shiftCode(KeyCode.arrowDown));

    expect(
      ctl.textSelection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
  });

  testWidgets('Ctrl+Z and Ctrl+Y undo and redo multiline edits', (tester) {
    final ctl = TextEditingController();
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

    tester.type('ab');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.type('cd');

    tester.sendKey(_ctrlChar('z'));
    expect(ctl.text, 'ab\n');

    tester.sendKey(_ctrlChar('y'));
    expect(ctl.text, 'ab\ncd');
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

  group('horizontal scrolling', () {
    testWidgets('publishes focused caret geometry after scrolling', (tester) {
      final focusNode = FocusNode(debugLabel: 'area-caret');
      addTearDown(focusNode.dispose);
      final ctl = TextEditingController(text: 'r0\nr1\nr2\nr3\nr4')
        ..selection = 'r0\nr1\nr2\nr3\nr4'.length;
      tester.pumpWidget(
        SizedBox(
          width: 4,
          height: 3,
          child: TextArea(
            controller: ctl,
            focusNode: focusNode,
            autofocus: true,
          ),
        ),
      );

      tester.render(size: const CellSize(4, 3));

      expect(focusNode.caretRect, CellRect.fromLTWH(2, 2, 1, 1));
    });

    testWidgets('keeps the trailing cursor visible in bounded width', (tester) {
      final ctl = TextEditingController(text: 'abcdef');
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

      final buf = tester.render(size: const CellSize(4, 1));

      expect(buf.atColRow(0, 0).grapheme, 'd');
      expect(buf.atColRow(1, 0).grapheme, 'e');
      expect(buf.atColRow(2, 0).grapheme, 'f');
      expect(buf.atColRow(3, 0).grapheme, ' ');
      expect(buf.atColRow(3, 0).style.inverse, isTrue);
    });

    testWidgets('scrolls back when the cursor moves to line start', (tester) {
      final ctl = TextEditingController(text: 'abcdef');
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
      tester.render(size: const CellSize(4, 1));

      tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
      final buf = tester.render(size: const CellSize(4, 1));

      expect(buf.atColRow(0, 0).grapheme, 'a');
      expect(buf.atColRow(0, 0).style.inverse, isTrue);
      expect(buf.atColRow(1, 0).grapheme, 'b');
      expect(buf.atColRow(2, 0).grapheme, 'c');
      expect(buf.atColRow(3, 0).grapheme, 'd');
    });

    testWidgets('does not split a wide grapheme at the scroll boundary', (
      tester,
    ) {
      final ctl = TextEditingController(text: 'ab🙂cd');
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

      final buf = tester.render(size: const CellSize(4, 1));

      expect(buf.atColRow(0, 0).grapheme, 'c');
      expect(buf.atColRow(1, 0).grapheme, 'd');
      expect(buf.atColRow(2, 0).grapheme, ' ');
      expect(buf.atColRow(2, 0).style.inverse, isTrue);
      expect(buf.atColRow(3, 0).grapheme, isNull);
    });

    testWidgets('keeps the active end of a selection visible', (tester) {
      final ctl = TextEditingController(text: 'abcdefgh')
        ..textSelection = const TextSelection(baseOffset: 3, extentOffset: 8);
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

      final buf = tester.render(size: const CellSize(5, 1));

      expect(buf.atColRow(0, 0).grapheme, 'e');
      expect(buf.atColRow(1, 0).grapheme, 'f');
      expect(buf.atColRow(2, 0).grapheme, 'g');
      expect(buf.atColRow(3, 0).grapheme, 'h');
      expect(buf.atColRow(0, 0).style.inverse, isTrue);
      expect(buf.atColRow(3, 0).style.inverse, isTrue);
    });

    testWidgets('resets horizontal scroll when moving to a short line', (
      tester,
    ) {
      final ctl = TextEditingController(text: 'ab\nabcdef');
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
      tester.render(size: const CellSize(4, 2));

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      final buf = tester.render(size: const CellSize(4, 2));

      expect(buf.atColRow(0, 0).grapheme, 'a');
      expect(buf.atColRow(1, 0).grapheme, 'b');
      expect(buf.atColRow(2, 0).grapheme, ' ');
      expect(buf.atColRow(2, 0).style.inverse, isTrue);
      expect(buf.atColRow(0, 1).grapheme, 'a');
      expect(buf.atColRow(1, 1).grapheme, 'b');
    });
  });

  group('bracketed paste', () {
    testWidgets('a multi-line paste inserts verbatim across lines', (tester) {
      final ctl = TextEditingController();
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
      tester.paste('one\ntwo\nthree');
      expect(ctl.text, 'one\ntwo\nthree', reason: 'newlines preserved');
      expect(_lines(tester, rows: 3), ['one', 'two', 'three']);
    });

    testWidgets('paste is one undoable multiline transaction', (tester) {
      final ctl = TextEditingController();
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

      tester.paste('one\ntwo\nthree');
      tester.sendKey(_ctrlChar('z'));
      expect(ctl.text, '');

      tester.sendKey(_ctrlChar('y'));
      expect(ctl.text, 'one\ntwo\nthree');
    });

    testWidgets('large paste is chunked and preserves newlines', (tester) {
      final ctl = TextEditingController();
      tester.pumpWidget(
        TextArea(
          controller: ctl,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 3,
            chunkSize: 3,
          ),
        ),
      );

      tester.paste('ab\ncd\nef');

      expect(ctl.text, 'ab\n');
      var area = tester.semantics().single(role: SemanticRole.textArea);
      expect(area.state.pasteInProgress, isTrue);
      expect(area.state.pasteInsertedLength, 3);
      expect(area.state.pasteTotalLength, 8);

      tester.pump();
      expect(ctl.text, 'ab\ncd\n');

      tester.pump();
      expect(ctl.text, 'ab\ncd\nef');

      tester.pump();
      area = tester.semantics().single(role: SemanticRole.textArea);
      expect(area.state.pasteInProgress, isFalse);

      tester.sendKey(_ctrlChar('z'));
      expect(ctl.text, '');
    });
  });

  group('enabled and readOnly', () {
    testWidgets('readOnly area consumes edits without mutating', (tester) {
      final ctl = TextEditingController(text: 'ab\ncd');
      tester.pumpWidget(
        TextArea(controller: ctl, autofocus: true, readOnly: true),
      );

      tester.type('X');
      tester.paste('YZ');
      tester.sendKey(const KeyEvent(keyCode: KeyCode.backspace));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(ctl.text, 'ab\ncd');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      expect(ctl.selection, ctl.text.length - 1);
    });

    testWidgets('disabled area does not autofocus or edit', (tester) {
      final ctl = TextEditingController();
      tester.pumpWidget(
        TextArea(controller: ctl, autofocus: true, enabled: false),
      );

      tester.type('x');
      tester.paste('y');
      expect(ctl.text, '');

      final area = tester.semantics().single(
        role: SemanticRole.textArea,
        enabled: false,
      );
      expect(area.focused, isFalse);
    });
  });

  group('copy and cut', () {
    testWidgets('Ctrl+C copies selected multiline text', (tester) async {
      final ctl = TextEditingController(text: 'one\ntwo')
        ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 5);
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

      tester.sendKey(_ctrlChar('c'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), 'ne\nt');
      expect(ctl.text, 'one\ntwo');
    });

    testWidgets('Ctrl+X cuts selected multiline text', (tester) async {
      final ctl = TextEditingController(text: 'one\ntwo')
        ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 5);
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

      tester.sendKey(_ctrlChar('x'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), 'ne\nt');
      expect(ctl.text, 'owo');
      expect(ctl.textSelection, const TextSelection.collapsed(1));
    });

    testWidgets('redacted policy preserves newlines without raw content', (
      tester,
    ) async {
      final ctl = TextEditingController(text: 'one\ntwo')
        ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 5);
      tester.pumpWidget(
        TextArea(
          controller: ctl,
          autofocus: true,
          clipboardPolicy: TextClipboardPolicy.redacted,
        ),
      );

      tester.sendKey(_ctrlChar('c'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), '••\n•');
    });

    testWidgets('disabled policy blocks copy and bubbling', (tester) async {
      var ancestorCopies = 0;
      final ctl = TextEditingController(text: 'one')
        ..textSelection = const TextSelection(baseOffset: 0, extentOffset: 3);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.ctrl.c, onEvent: (_) => ancestorCopies += 1),
          ],
          child: TextArea(
            controller: ctl,
            autofocus: true,
            clipboardPolicy: TextClipboardPolicy.disabled,
          ),
        ),
      );

      tester.sendKey(_ctrlChar('c'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), isNull);
      expect(ancestorCopies, 0);
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

  group('semantic setValue (B4)', () {
    testWidgets('replaces the whole body in one call', (tester) async {
      final ctl = TextEditingController(text: 'old');
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
      expect(
        tester.semantics().single(role: SemanticRole.textArea).actions,
        contains(SemanticAction.setValue),
      );
      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        role: SemanticRole.textArea,
        payload: 'first\nsecond',
      );
      expect(ctl.text, 'first\nsecond');
    });

    testWidgets('a readOnly TextArea does not advertise setValue', (tester) {
      final ctl = TextEditingController(text: 'x');
      tester.pumpWidget(TextArea(controller: ctl, readOnly: true));
      expect(
        tester.semantics().single(role: SemanticRole.textArea).actions,
        isNot(contains(SemanticAction.setValue)),
      );
    });

    testWidgets('a caller-provided focusNode keeps its own canRequestFocus '
        '(not clobbered by enabled)', (tester) {
      // Same contract as TextInput: the enabled↔focusable sync is for an
      // OWNED node only; TextArea must not pass a non-null canRequestFocus to
      // its inner Focus and overwrite the caller's node.
      final controller = TextEditingController();
      final node = FocusNode(debugLabel: 'provided', canRequestFocus: false);
      addTearDown(node.dispose);

      tester.pumpWidget(TextArea(controller: controller, focusNode: node));
      tester.render(size: const CellSize(20, 3));
      expect(
        node.canRequestFocus,
        isFalse,
        reason: 'mount must not overwrite the provided flag',
      );

      tester.pumpWidget(
        TextArea(controller: controller, focusNode: node, placeholder: 'x'),
      );
      tester.render(size: const CellSize(20, 3));
      expect(
        node.canRequestFocus,
        isFalse,
        reason: 'rebuild must not re-impose enabled→focusable',
      );
    });
  });

  group('F5: chat keymap + auto-grow', () {
    testWidgets('chat keymap submits on Enter with the current text', (
      tester,
    ) {
      final submitted = <String>[];
      final ctl = TextEditingController(text: 'hello');
      tester.pumpWidget(
        TextArea(
          controller: ctl,
          autofocus: true,
          keymap: TextEditingKeymap.chat,
          onSubmit: submitted.add,
        ),
      );
      tester.render(size: const CellSize(12, 4));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(submitted, ['hello']);
      // Enter submitted — it did not also insert a newline into the draft.
      expect(ctl.text, 'hello');
    });

    testWidgets('chat keymap inserts a newline on Alt+Enter, no submit', (
      tester,
    ) {
      final submitted = <String>[];
      final ctl = TextEditingController(text: 'a');
      tester.pumpWidget(
        TextArea(
          controller: ctl,
          autofocus: true,
          keymap: TextEditingKeymap.chat,
          onSubmit: submitted.add,
        ),
      );
      tester.render(size: const CellSize(12, 4));
      tester.sendKey(
        const KeyEvent(keyCode: KeyCode.enter, modifiers: {KeyModifier.alt}),
      );
      tester.type('b');
      expect(submitted, isEmpty);
      expect(ctl.text, 'a\nb');
    });

    testWidgets('submit with no onSubmit neither submits nor edits', (tester) {
      final ctl = TextEditingController(text: 'x');
      tester.pumpWidget(
        TextArea(
          controller: ctl,
          autofocus: true,
          keymap: TextEditingKeymap.chat,
        ),
      );
      tester.render(size: const CellSize(12, 4));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(ctl.text, 'x');
    });

    testWidgets('auto-grow height tracks content between minLines and '
        'maxLines', (tester) {
      final ctl = TextEditingController();
      tester.pumpWidget(
        Column(
          children: [
            TextArea(controller: ctl, minLines: 1, maxLines: 4),
            const Text('END'),
          ],
        ),
      );

      int endRow() =>
          _lines(tester, cols: 12, rows: 10).indexWhere((l) => l == 'END');

      // Empty draft -> one row tall, so END sits on row 1.
      expect(endRow(), 1);
      // Grows with the content.
      ctl.text = 'a\nb\nc';
      expect(endRow(), 3);
      // Capped at maxLines (4) even with more content.
      ctl.text = 'a\nb\nc\nd\ne\nf';
      expect(endRow(), 4);
    });

    testWidgets('minLines floors the height for a short draft', (tester) {
      final ctl = TextEditingController(text: 'one line');
      tester.pumpWidget(
        Column(
          children: [
            TextArea(controller: ctl, minLines: 3, maxLines: 6),
            const Text('END'),
          ],
        ),
      );
      // One content line, but minLines:3 reserves three rows above END.
      expect(
        _lines(tester, cols: 20, rows: 10).indexWhere((l) => l == 'END'),
        3,
      );
    });

    testWidgets('auto-grow under a parent tighter than maxLines keeps the '
        'cursor line visible', (tester) {
      // maxLines (4) exceeds the 2-row slot the parent gives; the cursor is on
      // the last line, so the capped viewport must scroll to it — the pre-fix
      // scroll math ran against the un-capped height and froze on l0/l1,
      // dropping the caret off-screen.
      final ctl = TextEditingController(text: 'l0\nl1\nl2\nl3\nl4')
        ..selection = 14; // end of the text, on line l4
      tester.pumpWidget(
        Column(
          children: [
            const Text('HEAD'),
            SizedBox(
              height: 2,
              child: TextArea(controller: ctl, minLines: 1, maxLines: 4),
            ),
          ],
        ),
      );
      final lines = _lines(tester, cols: 6, rows: 6);
      expect(lines[0], 'HEAD');
      // The 2-row area shows the tail around the cursor (l3, l4), not l0/l1.
      expect(lines.sublist(1, 3), ['l3', 'l4']);
    });
  });

  group('line split memoization', () {
    // Each assertion opens its own collector window (beginFrame) and reads
    // the delta with takeFrameStats — the same opt-in idiom as
    // RenderLayoutDebugStats, so nothing is counted outside a window and
    // tests cannot flake on each other's order.
    int splitsDuring(void Function() body) {
      TextAreaDebugStats.beginFrame(enabled: true);
      body();
      return TextAreaDebugStats.takeFrameStats().lineSplitCount;
    }

    testWidgets('layout/paint passes reuse one split until the text changes', (
      tester,
    ) {
      final ctl = TextEditingController(text: 'one\ntwo\nthree')
        ..selection = 13; // end of the document
      tester.pumpWidget(TextArea(controller: ctl, autofocus: true));

      expect(
        splitsDuring(() => tester.render(size: const CellSize(10, 4))),
        1,
        reason: 'one frame is one split, shared by layout, caret, and paint',
      );

      // An unchanged frame performs zero new splits.
      expect(
        splitsDuring(() => tester.render(size: const CellSize(10, 4))),
        0,
      );

      // Cursor movement re-lays-out and repaints, but the text is unchanged
      // — still no new split.
      expect(
        splitsDuring(() {
          tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
          tester.render(size: const CellSize(10, 4));
        }),
        0,
      );
      expect(ctl.selection, 7, reason: 'column clamps to the end of "two"');

      // An edit reassigns the text: exactly one new split, and the memoized
      // lines reflect the new document.
      expect(
        splitsDuring(() {
          tester.type('X');
          tester.render(size: const CellSize(10, 4));
        }),
        1,
      );
      expect(ctl.text, 'one\ntwoX\nthree');
      expect(
        splitsDuring(
          () => expect(_lines(tester, rows: 4), ['one', 'twoX', 'three', '']),
        ),
        0,
        reason: 'rendering the edited document again reuses the new split',
      );
    });

    testWidgets('placeholder lines share the memo and rebuild on swap', (
      tester,
    ) {
      final ctl = TextEditingController();
      tester.pumpWidget(
        TextArea(controller: ctl, autofocus: true, placeholder: 'type\nhere'),
      );

      expect(
        splitsDuring(() => tester.render(size: const CellSize(10, 2))),
        1,
      );
      expect(
        splitsDuring(() => expect(_lines(tester, rows: 2), ['type', 'here'])),
        0,
      );

      // Typing swaps the split source to the document; clearing swaps back
      // to the placeholder. Each swap re-splits exactly once.
      expect(
        splitsDuring(() {
          tester.type('x');
          tester.render(size: const CellSize(10, 2));
          expect(_lines(tester, rows: 1).first, 'x');
        }),
        1,
      );
      expect(
        splitsDuring(() {
          tester.sendKey(const KeyEvent(keyCode: KeyCode.backspace));
          tester.render(size: const CellSize(10, 2));
          expect(_lines(tester, rows: 2), ['type', 'here']);
        }),
        1,
      );
    });
  });
}
