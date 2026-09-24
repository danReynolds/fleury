// A repaint boundary, and a ListView viewport clipping an item at its edge,
// composite their buffer over what is already painted: a cell their child
// did not paint shows what lies beneath, exactly as painting the child
// directly would. A raw copy wrote those empty cells over the parent's
// background, punching holes in every filled panel that held ragged text —
// and ListView wraps every item in a boundary.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

const _fill = RgbColor(0, 0, 200);

/// Every cell of [buffer], row by row.
List<List<Cell>> _cells(CellBuffer buffer) => [
  for (var row = 0; row < buffer.size.rows; row++)
    [
      for (var col = 0; col < buffer.size.cols; col++)
        buffer.atColRow(col, row),
    ],
];

/// 'B' where a cell carries the container background, '.' where it doesn't.
List<String> _backgroundMap(CellBuffer buffer) => [
  for (var row = 0; row < buffer.size.rows; row++)
    [
      for (var col = 0; col < buffer.size.cols; col++)
        buffer.atColRow(col, row).style.background == _fill ? 'B' : '.',
    ].join(),
];

/// The rendered text, row by row, without the fill's trailing spaces.
List<String> _text(FleuryTester tester, CellSize size) => [
  for (final line in tester.renderToString(size: size).trimRight().split('\n'))
    line.trimRight(),
];

Widget _filled(CellSize size, Widget child) => Container(
  color: _fill,
  child: SizedBox(width: size.cols, height: size.rows, child: child),
);

void main() {
  for (final (name, child) in [
    ('ragged text', const Text('ab\nabcdef') as Widget),
    (
      'a Row with a Spacer',
      const Row(children: [Text('a'), Spacer(), Text('b')]),
    ),
  ]) {
    testWidgets('a RepaintBoundary around $name paints like $name', (tester) {
      const size = CellSize(10, 2);
      tester.pumpWidget(_filled(size, child));
      final direct = _cells(tester.render(size: size));

      tester.pumpWidget(_filled(size, RepaintBoundary(child: child)));
      expect(_cells(tester.render(size: size)), direct);
      expect(
        _cells(tester.render(size: size)),
        direct,
        reason: 'the cache hit composites the same way',
      );
    });
  }

  testWidgets('ragged ListView items keep the panel background', (tester) {
    const size = CellSize(8, 4);
    tester.pumpWidget(
      _filled(
        size,
        ListView(
          selectable: false,
          children: const [Text('ab\nabcdef'), Text('xy\nxyz')],
        ),
      ),
    );
    final buffer = tester.render(size: size);
    expect(_backgroundMap(buffer), [
      for (var row = 0; row < size.rows; row++) 'B' * size.cols,
    ]);
    expect(_text(tester, size), ['ab', 'abcdef', 'xy', 'xyz']);
  });

  testWidgets('an item straddling the viewport edge keeps the background', (
    tester,
  ) {
    // Clipping an item at the edge paints the viewport through a scratch
    // buffer; its composite must not blank the panel under it.
    const size = CellSize(10, 3);
    tester.pumpWidget(
      _filled(
        size,
        ListView(
          children: const [Text('a1\na2'), Text('b1\nb2'), Text('c1\nc2')],
        ),
      ),
    );
    expect(_backgroundMap(tester.render(size: size)), [
      for (var row = 0; row < size.rows; row++) 'B' * size.cols,
    ]);
    expect(_text(tester, size), ['a1', 'a2', 'b1']);
  });
}
