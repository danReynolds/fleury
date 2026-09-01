// IntrinsicWidth / IntrinsicHeight through wrappers that add no geometry.
//
// A single-child render object reported an intrinsic size of 0 unless it
// overrode the query. IntrinsicWidth read that as "wants to be empty" and
// tightened the subtree to zero width — blank — for almost any real child:
// anything under a Focus, a GestureDetector, a RepaintBoundary, a Stack.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// The column where [needle] first lands on row 0 (-1 when absent).
int _findCol(FleuryTester tester, String needle, {int cols = 20}) {
  final buf = tester.render(size: CellSize(cols, 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    sb.write(buf.atColRow(c, 0).grapheme ?? ' ');
  }
  return sb.toString().indexOf(needle);
}

/// The row where [needle] first lands in column 0 (-1 when absent).
int _findRow(FleuryTester tester, String needle, {int rows = 6}) {
  final buf = tester.render(size: CellSize(20, rows));
  for (var r = 0; r < rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < 20; c++) {
      sb.write(buf.atColRow(c, r).grapheme ?? ' ');
    }
    if (sb.toString().startsWith(needle)) return r;
  }
  return -1;
}

Widget _rowWith(Widget child) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    IntrinsicWidth(child: child),
    const Text('|END'),
  ],
);

void main() {
  group('IntrinsicWidth through geometry-free wrappers', () {
    testWidgets('Focus', (tester) {
      tester.pumpWidget(_rowWith(const Focus(child: Text('abc'))));
      expect(_findCol(tester, '|END'), 3);
      expect(_findCol(tester, 'abc'), 0, reason: 'the content is painted');
    });

    testWidgets('GestureDetector around a stretched Column', (tester) {
      tester.pumpWidget(
        _rowWith(
          GestureDetector(
            onTap: () {},
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Text('abcd'), Text('x')],
            ),
          ),
        ),
      );
      expect(_findCol(tester, '|END'), 4);
    });

    testWidgets('RepaintBoundary', (tester) {
      tester.pumpWidget(_rowWith(const RepaintBoundary(child: Text('ab'))));
      expect(_findCol(tester, '|END'), 2);
    });

    testWidgets('Container.framed: the child plus its frame', (tester) {
      tester.pumpWidget(_rowWith(const Container.framed(child: Text('ab'))));
      expect(
        _findCol(tester, '|END'),
        4,
        reason: '2 cells of text + 2 of frame',
      );
    });

    testWidgets('Stack: the widest non-positioned child', (tester) {
      tester.pumpWidget(
        _rowWith(const Stack(children: [Text('abcde'), Text('a')])),
      );
      expect(_findCol(tester, '|END'), 5);
    });
  });

  group('IntrinsicHeight through geometry-free wrappers', () {
    testWidgets('Focus around a Column', (tester) {
      tester.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            IntrinsicHeight(
              child: Focus(child: Column(children: [Text('a'), Text('b')])),
            ),
            Text('END'),
          ],
        ),
      );
      expect(_findRow(tester, 'END'), 2);
    });
  });
}
