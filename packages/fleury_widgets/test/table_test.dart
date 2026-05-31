import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<String> _lines(
  FleuryTester tester, {
  required int cols,
  required int rows,
}) {
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
  testWidgets('intrinsic columns align across rows', (tester) {
    tester.pumpWidget(
      Table(
        rows: const [
          [Text('a'), Text('one')],
          [Text('bb'), Text('two')],
        ],
      ),
    );
    // col0 width = max('a','bb') = 2, spacing 1 → col1 starts at x=3.
    final lines = _lines(tester, cols: 6, rows: 2);
    expect(lines[0], 'a  one'); // 'a' at 0, 'one' at 3
    expect(lines[1], 'bb two'); // 'bb' at 0-1, 'two' at 3
  });

  testWidgets('header renders with a rule beneath it', (tester) {
    tester.pumpWidget(
      Table(
        header: const [Text('Name'), Text('Age')],
        rows: const [
          [Text('Al'), Text('30')],
        ],
      ),
    );
    // col0 = max('Name','Al') = 4, col1 = max('Age','30') = 3, width = 8.
    final lines = _lines(tester, cols: 8, rows: 3);
    expect(lines[0], 'Name Age'); // header row
    expect(lines[1], '────────'); // 8-wide rule
    expect(lines[2], 'Al   30'); // body, columns aligned (Age/30 at x=5)
  });

  testWidgets('fixed + flex columns size against the available width', (
    tester,
  ) {
    tester.pumpWidget(
      Table(
        columnWidths: const [FixedColumnWidth(2), FlexColumnWidth()],
        headerSeparator: false,
        rows: const [
          [Text('x'), Text('y')],
        ],
      ),
    );
    // Render 8 wide: col0 fixed 2, gap 1, flex col1 fills remaining (5),
    // starting at x = 3.
    final buf = tester.render(size: const CellSize(8, 1));
    expect(buf.atColRow(0, 0).grapheme, 'x');
    expect(buf.atColRow(3, 0).grapheme, 'y');
  });

  testWidgets('two flex columns split proportionally', (tester) {
    tester.pumpWidget(
      Table(
        columnWidths: const [FlexColumnWidth(1), FlexColumnWidth(2)],
        headerSeparator: false,
        rows: const [
          [Text('A'), Text('B')],
        ],
      ),
    );
    // Render 9 wide: gap 1 → 8 to split 1:2 → col0=3 (gets the leftover),
    // col1=5. col1 starts at x = 3 + 1 = 4.
    final buf = tester.render(size: const CellSize(9, 1));
    expect(buf.atColRow(0, 0).grapheme, 'A');
    expect(buf.atColRow(4, 0).grapheme, 'B');
  });

  testWidgets('a short row is padded to the column count', (tester) {
    tester.pumpWidget(
      Table(
        header: const [Text('X'), Text('Y')],
        headerSeparator: false,
        rows: const [
          [Text('only')], // one cell in a two-column table
        ],
      ),
    );
    // Should not throw; the missing cell is empty.
    final lines = _lines(tester, cols: 8, rows: 2);
    expect(lines[1], 'only');
  });

  group('edges & constraints', () {
    testWidgets('an empty table renders nothing', (tester) {
      tester.pumpWidget(Table(rows: const []));
      expect(_lines(tester, cols: 6, rows: 1), ['']);
    });

    testWidgets('a long row is trimmed to the column count', (tester) {
      tester.pumpWidget(
        Table(
          header: const [Text('X'), Text('Y')],
          headerSeparator: false,
          rows: const [
            [Text('a'), Text('b'), Text('c')], // 3 cells, 2 columns
          ],
        ),
      );
      final lines = _lines(tester, cols: 8, rows: 2);
      expect(lines[1].contains('c'), isFalse, reason: 'third cell dropped');
    });

    testWidgets('a wrapping cell grows its row; columns stay aligned', (
      tester,
    ) {
      tester.pumpWidget(
        Table(
          columnWidths: const [FixedColumnWidth(3), IntrinsicColumnWidth()],
          rows: const [
            [Text('abcdef'), Text('x')], // col0 width 3 → wraps to 2 rows
          ],
        ),
      );
      final lines = _lines(tester, cols: 6, rows: 2);
      expect(lines[0], 'abc x', reason: "'x' aligned at col 4");
      expect(lines[1], 'def');
    });

    testWidgets('header without a separator omits the rule', (tester) {
      tester.pumpWidget(
        Table(
          header: const [Text('Name'), Text('Age')],
          headerSeparator: false,
          rows: const [
            [Text('Al'), Text('30')],
          ],
        ),
      );
      final lines = _lines(tester, cols: 8, rows: 2);
      expect(lines[0], 'Name Age');
      expect(lines[1], 'Al   30', reason: 'body directly under the header');
    });

    testWidgets('changing column widths re-lays out on rebuild', (tester) {
      tester.pumpWidget(
        Table(
          columnWidths: const [FixedColumnWidth(2), IntrinsicColumnWidth()],
          headerSeparator: false,
          rows: const [
            [Text('x'), Text('y')],
          ],
        ),
      );
      expect(
        tester.render(size: const CellSize(10, 1)).atColRow(3, 0).grapheme,
        'y',
      );

      tester.pumpWidget(
        Table(
          columnWidths: const [FixedColumnWidth(5), IntrinsicColumnWidth()],
          headerSeparator: false,
          rows: const [
            [Text('x'), Text('y')],
          ],
        ),
      );
      expect(
        tester.render(size: const CellSize(10, 1)).atColRow(6, 0).grapheme,
        'y',
        reason: "col1 shifted to x=6 after the width change",
      );
    });

    testWidgets('an intrinsic column wider than the slot shrinks to fit', (
      tester,
    ) {
      tester.pumpWidget(
        Table(
          headerSeparator: false,
          rows: const [
            [Text('verylongcell')],
          ],
        ),
      );
      // Slot only 4 wide: the column clamps to 4 and the cell wraps
      // within it (rather than painting out of bounds).
      expect(_lines(tester, cols: 4, rows: 3), ['very', 'long', 'cell']);
    });
  });

  group('selectable & scrollable', () {
    Table people({TableController? controller, void Function(int)? onSelect}) =>
        Table(
          selectable: true,
          autofocus: true,
          controller: controller,
          onSelect: onSelect,
          headerSeparator: false,
          header: const [Text('Name'), Text('Age')],
          rows: const [
            [Text('Al'), Text('30')],
            [Text('Bo'), Text('40')],
            [Text('Cy'), Text('50')],
          ],
        );

    testWidgets('the selected row is highlighted; the rest are not', (tester) {
      final buf = (tester..pumpWidget(people())).render(
        size: const CellSize(8, 5),
      );
      // Header row 0, body rows at 1..3. Row 0 (body) selected by default.
      expect(buf.atColRow(0, 0).style.inverse, isFalse, reason: 'header');
      expect(buf.atColRow(0, 1).grapheme, 'A');
      expect(buf.atColRow(0, 1).style.inverse, isTrue, reason: 'selected body');
      expect(buf.atColRow(0, 2).style.inverse, isFalse, reason: 'next row');
    });

    testWidgets('the highlight fills the gap between columns too', (tester) {
      final buf = (tester..pumpWidget(people())).render(
        size: const CellSize(8, 5),
      );
      // 'Al' occupies cols 0-1, gap at col 2, 'Age'/age column after.
      expect(
        buf.atColRow(2, 1).style.inverse,
        isTrue,
        reason: 'inter-column gap is part of the selected bar',
      );
    });

    testWidgets('Down/Up move the highlight', (tester) {
      tester.pumpWidget(people());
      tester.render(size: const CellSize(8, 5));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      var buf = tester.render(size: const CellSize(8, 5));
      expect(
        buf.atColRow(0, 1).style.inverse,
        isFalse,
        reason: 'row 0 blurred',
      );
      expect(
        buf.atColRow(0, 2).style.inverse,
        isTrue,
        reason: 'row 1 selected',
      );

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      buf = tester.render(size: const CellSize(8, 5));
      expect(buf.atColRow(0, 1).style.inverse, isTrue, reason: 'back to row 0');
    });

    testWidgets('Enter fires onSelect with the body-row index', (tester) {
      int? picked;
      tester.pumpWidget(people(onSelect: (i) => picked = i));
      tester.render(size: const CellSize(8, 5));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(picked, 1);
    });

    testWidgets('a controller drives selection programmatically', (tester) {
      final c = TableController();
      tester.pumpWidget(people(controller: c));
      tester.render(size: const CellSize(8, 5));
      c.selectedIndex = 2;
      final buf = tester.render(size: const CellSize(8, 5));
      expect(
        buf.atColRow(0, 3).style.inverse,
        isTrue,
        reason: 'row 2 selected',
      );
    });

    Table longTable() => Table(
      selectable: true,
      autofocus: true,
      headerSeparator: false,
      header: const [Text('H')],
      rows: [
        for (var i = 0; i < 10; i++) [Text('r$i')],
      ],
    );

    testWidgets('a tall body scrolls under a pinned header', (tester) {
      tester.pumpWidget(longTable());
      // Viewport 3 rows: header pinned (row 0) + 2 body rows visible.
      expect(_lines(tester, cols: 4, rows: 3), ['H', 'r0', 'r1']);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      // End jumps to r9; window slides so r9 is the bottom row, header stays.
      expect(_lines(tester, cols: 4, rows: 3), ['H', 'r8', 'r9']);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
      expect(_lines(tester, cols: 4, rows: 3), ['H', 'r0', 'r1']);
    });

    testWidgets('scrolling keeps the moving selection visible', (tester) {
      tester.pumpWidget(longTable());
      tester.render(size: const CellSize(4, 3));
      // Step down past the bottom of the window; it should follow.
      for (var i = 0; i < 3; i++) {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      }
      // Selection is now r3; window shows r2,r3 (r3 at the bottom).
      expect(_lines(tester, cols: 4, rows: 3), ['H', 'r2', 'r3']);
    });
  });
}
