// Selection tests for RichText — confirms the same SelectionArea
// behaviors that work on Text also work on RichText, and that
// mixing the two inside one SelectionArea selects across the
// boundary just like multiple Texts do.

import 'package:fleury/fleury.dart';
import '../../support/harness.dart';
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

void main() {
  group('RichText — selection', () {
    testWidgets('drag selects the plain text across styled spans', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'red ',
                  style: CellStyle(foreground: AnsiColor(1)),
                ),
                TextSpan(
                  text: 'green ',
                  style: CellStyle(foreground: AnsiColor(2)),
                ),
                TextSpan(
                  text: 'blue',
                  style: CellStyle(foreground: AnsiColor(4)),
                ),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Drag spans the boundary between the red and green spans.
      // Cursor at col 9 lands BEFORE the space (col 9 = ' ' after
      // 'green'); selection is [2, 9) → 'd green'.
      tester.sendMouse(_down(2, 0));
      tester.sendMouse(_drag(9, 0));
      tester.sendMouse(_up(9, 0));

      // The captured plain text crosses style boundaries with no
      // ANSI escape codes — that's the contract.
      expect(captured?.plainText, 'd green');
    });

    testWidgets('Ctrl+A selects all spans', (tester) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const RichText(
            text: TextSpan(
              children: [
                TextSpan(text: 'one '),
                TextSpan(text: 'two ', style: CellStyle(bold: true)),
                TextSpan(text: 'three'),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendKey(const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}));
      expect(captured?.plainText, 'one two three');
    });

    testWidgets('double-click selects a word inside a styled span', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const RichText(
            text: TextSpan(
              children: [
                TextSpan(text: 'hello ', style: CellStyle(bold: true)),
                TextSpan(text: 'world', style: CellStyle(italic: true)),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      // Double-click inside 'world' (col 8 is past 'hello ').
      tester.sendMouse(_down(8, 0));
      tester.sendMouse(_up(8, 0));
      tester.sendMouse(_down(8, 0));
      tester.sendMouse(_up(8, 0));

      expect(
        captured?.plainText,
        'world',
        reason: 'word-boundary detection looks at flat text only',
      );
    });

    testWidgets('Shift+Right crosses a style boundary in one keystroke', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'a',
                  style: CellStyle(foreground: AnsiColor(1)),
                ),
                TextSpan(
                  text: 'b',
                  style: CellStyle(foreground: AnsiColor(2)),
                ),
                TextSpan(
                  text: 'c',
                  style: CellStyle(foreground: AnsiColor(3)),
                ),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      // Anchor at 0, select 'a'.
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(1, 0));
      tester.sendMouse(_up(1, 0));
      expect(captured?.plainText, 'a');

      // Shift+Right — should cross the a→b style boundary.
      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowRight,
          modifiers: {KeyModifier.shift},
        ),
      );
      expect(
        captured?.plainText,
        'ab',
        reason: 'Shift+Arrow operates on flat text, ignoring styles',
      );
    });

    testWidgets('allowSelect: false masks RichText from Ctrl+A', (
      tester,
    ) async {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('regular text'),
              RichText(
                allowSelect: false,
                text: TextSpan(text: 'masked rich text'),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));

      tester.sendKey(const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}));
      expect(
        captured?.plainText,
        'regular text',
        reason: 'allowSelect:false hides the RichText from selection',
      );
    });

    testWidgets(
      'selection crosses from a Text into a RichText with a newline',
      (tester) async {
        SelectedContent? captured;
        tester.pumpWidget(
          SelectionArea(
            onSelectionChanged: (sel) => captured = sel,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('plain'),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'styled', style: CellStyle(bold: true)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        tester.render(size: const CellSize(20, 2));

        tester.sendMouse(_down(0, 0));
        tester.sendMouse(_drag(6, 1));
        tester.sendMouse(_up(6, 1));

        expect(
          captured?.plainText,
          'plain\nstyled',
          reason: 'cross-widget selections insert \\n between rows',
        );
      },
    );
  });
}
