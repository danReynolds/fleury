// Lock test: Autocomplete's suggestion overlay uses bare BoundsAnchor, not
// AnchoredFloat. Select/Menu got a full-slot AbsorbPointer barrier in audit
// A3/6.f; Autocomplete was left out. Clicks on the surround — including on a
// partially-covered button — must not activate widgets underneath.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets(
    'open Autocomplete dropdown blocks clicks on widgets underneath',
    (tester) {
      var presses = 0;
      tester.pumpWidget(
        Column(
          children: [
            const SizedBox(
              height: 1,
              child: Autocomplete(
                options: ['apple', 'apricot', 'banana'],
                autofocus: true,
              ),
            ),
            Button(label: 'DELETE ALL', onPressed: () => presses++),
          ],
        ),
      );

      tester.type('ap');
      expect(tester.overlay.entries.length, 2, reason: 'dropdown open');

      final buf = tester.render(size: const CellSize(40, 12));
      // With the dropdown overlapping the button row, only the trailing
      // "L ]" of "[DELETE ALL]" remains visible beside the frame.
      var clickCol = -1;
      var clickRow = -1;
      for (var r = 0; r < buf.size.rows && clickCol < 0; r++) {
        for (var c = 0; c < buf.size.cols - 1; c++) {
          if (buf.atColRow(c, r).grapheme == 'L' &&
              buf.atColRow(c + 1, r).grapheme == ' ') {
            // Prefer the remnant that sits next to a frame glyph.
            if (c > 0 &&
                (buf.atColRow(c - 1, r).grapheme == '\u256e' ||
                    buf.atColRow(c - 1, r).grapheme == '─' ||
                    buf.atColRow(c - 1, r).grapheme == '╮')) {
              clickCol = c;
              clickRow = r;
              break;
            }
          }
        }
      }
      // Fallback: any visible 'L' followed by " ]" pattern from the button.
      if (clickCol < 0) {
        for (var r = 0; r < buf.size.rows && clickCol < 0; r++) {
          for (var c = 0; c < buf.size.cols - 2; c++) {
            if (buf.atColRow(c, r).grapheme == 'L' &&
                buf.atColRow(c + 2, r).grapheme == ']') {
              clickCol = c;
              clickRow = r;
              break;
            }
          }
        }
      }
      expect(clickCol, isNonNegative, reason: 'button remnant must be visible');

      // Control: without an open dropdown, the same click fires the button.
      // (We assert the open-dropdown case must NOT.)
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: clickCol,
          row: clickRow,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: clickCol,
          row: clickRow,
        ),
      );

      expect(
        presses,
        0,
        reason:
            'click on a button remnant beside an open Autocomplete dropdown '
            'must not activate it — Autocomplete needs the same AbsorbPointer '
            'slot barrier AnchoredFloat gives Select/Menu',
      );
    },
  );

  testWidgets(
    'control: button under Autocomplete fires when dropdown is closed',
    (tester) {
      var presses = 0;
      tester.pumpWidget(
        Column(
          children: [
            const SizedBox(
              height: 1,
              child: Autocomplete(
                options: ['apple', 'apricot', 'banana'],
                autofocus: true,
              ),
            ),
            Button(label: 'DELETE ALL', onPressed: () => presses++),
          ],
        ),
      );

      final buf = tester.render(size: const CellSize(40, 12));
      var col = -1;
      var row = -1;
      for (var r = 0; r < buf.size.rows && col < 0; r++) {
        for (var c = 0; c < buf.size.cols - 5; c++) {
          if (buf.atColRow(c, r).grapheme == 'D' &&
              buf.atColRow(c + 1, r).grapheme == 'E') {
            col = c;
            row = r;
            break;
          }
        }
      }
      expect(col, isNonNegative);
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: col,
          row: row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: col,
          row: row,
        ),
      );
      expect(presses, 1, reason: 'sanity: button works with dropdown closed');
    },
  );
}
