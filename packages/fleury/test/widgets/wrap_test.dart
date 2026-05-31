// Wrap: flow layout that reflows children onto new rows.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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
  testWidgets('keeps children on one row when they fit', (tester) {
    tester.pumpWidget(
      const Wrap(spacing: 1, children: [Text('aa'), Text('bb'), Text('cc')]),
    );
    // "aa bb cc" fits in 10 cols.
    expect(_lines(tester, cols: 10, rows: 2), ['aa bb cc', '']);
  });

  testWidgets('wraps to a new row when the line is full', (tester) {
    tester.pumpWidget(
      const Wrap(spacing: 1, children: [Text('aa'), Text('bb'), Text('cc')]),
    );
    // Width 5: "aa bb" = 5 fits; "cc" overflows → next row.
    expect(_lines(tester, cols: 5, rows: 2), ['aa bb', 'cc']);
  });

  testWidgets('runSpacing inserts blank rows between runs', (tester) {
    tester.pumpWidget(
      const Wrap(
        spacing: 1,
        runSpacing: 1,
        children: [Text('aa'), Text('bb'), Text('cc')],
      ),
    );
    // Width 5: row0 "aa bb", a blank run-gap row, then "cc".
    expect(_lines(tester, cols: 5, rows: 3), ['aa bb', '', 'cc']);
  });

  testWidgets('spacing separates children within a row', (tester) {
    tester.pumpWidget(const Wrap(spacing: 2, children: [Text('a'), Text('b')]));
    // 'a' at col 0, 2-col gap, 'b' at col 3.
    final buf = tester.render(size: const CellSize(6, 1));
    expect(buf.atColRow(0, 0).grapheme, 'a');
    expect(buf.atColRow(3, 0).grapheme, 'b');
  });

  testWidgets('unbounded width keeps everything on one row', (tester) {
    // A Row gives its non-flex child an unbounded main axis; the Wrap
    // inside then can't wrap, so all children stay on one line.
    tester.pumpWidget(
      const Row(
        children: [
          Wrap(spacing: 1, children: [Text('aa'), Text('bb'), Text('cc')]),
        ],
      ),
    );
    expect(_lines(tester, cols: 20, rows: 2), ['aa bb cc', '']);
  });

  testWidgets('a child wider than the line gets its own row', (tester) {
    tester.pumpWidget(
      const Wrap(
        spacing: 1,
        children: [Text('aa'), Text('wide', softWrap: false), Text('bb')],
      ),
    );
    // Width 5: "aa" then "wide" (4) doesn't fit after "aa " → row1;
    // "bb" doesn't fit after "wide" → row2.
    expect(_lines(tester, cols: 5, rows: 3), ['aa', 'wide', 'bb']);
  });
}
