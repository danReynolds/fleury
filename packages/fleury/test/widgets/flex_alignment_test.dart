// A Flex aligns its children within the box its constraints give it, not
// within its content: an Expanded pane, a SizedBox, or a tight minimum can
// make the box larger than the children. And when the children overflow,
// the space-distributing modes have nothing to distribute: their gaps stay
// at zero instead of going negative and painting siblings over each other.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// The rendered rows, trailing empty rows dropped; '·' is an empty cell.
List<String> _rows(FleuryTester tester, CellSize size) {
  final rows = tester.renderToString(size: size, emptyMark: '·').split('\n');
  while (rows.isNotEmpty && rows.last.isEmpty) {
    rows.removeLast();
  }
  return rows;
}

void main() {
  testWidgets('end alignment in an Expanded pane reaches the pane edge', (
    tester,
  ) {
    tester.pumpWidget(
      const Row(
        children: [
          Text('|'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [Text('hi there'), Text('ok')],
            ),
          ),
          Text('|'),
        ],
      ),
    );
    expect(_rows(tester, const CellSize(30, 2)), [
      '|····················hi there|',
      '···························ok',
    ]);
  });

  testWidgets('center alignment in an Expanded pane centers in the pane', (
    tester,
  ) {
    tester.pumpWidget(
      const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Text('Title'), Text('a longer subtitle')],
            ),
          ),
        ],
      ),
    );
    expect(_rows(tester, const CellSize(40, 2)), [
      '·················Title',
      '···········a longer subtitle',
    ]);
  });

  for (final (alignment, row) in [
    (CrossAxisAlignment.center, 1),
    (CrossAxisAlignment.end, 2),
  ]) {
    testWidgets('cross $alignment in a taller SizedBox uses its height', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 3,
          child: Row(
            crossAxisAlignment: alignment,
            children: const [Text('hi')],
          ),
        ),
      );
      final rows = _rows(tester, const CellSize(10, 3));
      expect(rows.indexWhere((r) => r.contains('hi')), row);
    });
  }

  testWidgets('a min-size Row forced wider centers along its main axis', (
    tester,
  ) {
    tester.pumpWidget(
      const SizedBox(
        width: 10,
        height: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text('hi')],
        ),
      ),
    );
    expect(_rows(tester, const CellSize(10, 1)), ['····hi']);
  });

  for (final alignment in [
    MainAxisAlignment.spaceBetween,
    MainAxisAlignment.spaceAround,
    MainAxisAlignment.spaceEvenly,
  ]) {
    testWidgets('$alignment overflow does not overlap siblings', (tester) {
      tester.pumpWidget(
        Row(
          mainAxisAlignment: alignment,
          children: const [Text('LEFT-STATUS'), Text('RIGHT-STATUS')],
        ),
      );
      expect(_rows(tester, const CellSize(16, 1)), ['LEFT-STATUSRIGHT']);
    });
  }
}
