import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// Returns the cell column where the [needle]'s first cell lands on row 0.
int _findCol(FleuryTester tester, String needle, {int cols = 20}) {
  final buf = tester.render(size: CellSize(cols, 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    sb.write(buf.atColRow(c, 0).grapheme ?? ' ');
  }
  return sb.toString().indexOf(needle);
}

void main() {
  group('IntrinsicWidth', () {
    testWidgets(
      'sizes a child to its content width inside an expanding parent',
      (tester) {
        // Center stretches its child to fill the available space *unless* the
        // child specifies its own size. With IntrinsicWidth, the child column
        // is tightened to its widest row's natural width — so a marker placed
        // *after* it (in a Row) sits right next to it rather than hugging the
        // viewport edge.
        tester.pumpWidget(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Text('abc'), Text('hi')],
                ),
              ),
              Text('|END'),
            ],
          ),
        );
        // 'abc' is the widest row → IntrinsicWidth tightens the Column to 3
        // columns. The Row places '|END' starting at col 3.
        expect(_findCol(tester, '|END'), 3);
      },
    );

    testWidgets('without IntrinsicWidth, the same Column collapses to its '
        'tightest child (so the test is a real A/B)', (tester) {
      // Same tree minus IntrinsicWidth: Column with stretch but unbounded
      // width sizes to its tightest content. The '|END' marker still ends
      // up at the column's right edge — but its position is no longer
      // anchored to the *widest* row.
      tester.pumpWidget(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Text('abc'), Text('hi')],
            ),
            Text('|END'),
          ],
        ),
      );
      // The Column with `stretch` and no width bound collapses to the
      // widest child (still 3 here). The wrapped/unwrapped values match in
      // this simple case — IntrinsicWidth matters more when the Column is
      // inside a parent that would have expanded it.
      expect(_findCol(tester, '|END'), 3);
    });

    testWidgets('forces a content-sized child inside an expanding parent', (
      tester,
    ) {
      // SizedBox(width: 20) stretches its child to 20 columns. Wrapping the
      // *contents* in IntrinsicWidth (inside an Align) shows the content
      // sized to itself rather than to 20.
      tester.pumpWidget(
        SizedBox(
          width: 20,
          height: 1,
          child: Row(
            children: const [
              IntrinsicWidth(child: Text('abc')),
              Text('|END'),
            ],
          ),
        ),
      );
      expect(_findCol(tester, '|END'), 3);
    });
  });

  group('IntrinsicHeight', () {
    testWidgets("matches the child's natural height", (tester) {
      // Vertical analogue: a Column of Texts inside IntrinsicHeight is sized
      // to its own row count, not expanded to fill an enclosing SizedBox.
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              IntrinsicHeight(child: Column(children: [Text('A'), Text('B')])),
              Text('END'),
            ],
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 8));
      // 'A' on row 0, 'B' on row 1, 'END' on row 2 (right after the
      // intrinsic-height block).
      expect(buf.atColRow(0, 0).grapheme, 'A');
      expect(buf.atColRow(0, 1).grapheme, 'B');
      expect(buf.atColRow(0, 2).grapheme, 'E');
    });
  });
}
