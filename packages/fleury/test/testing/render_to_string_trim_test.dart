// renderToString trims each row's trailing empty CELLS. It used to strip
// trailing copies of the mark from the finished string instead: an empty
// mark spun forever (a synchronous loop no test timeout can stop), a mark
// of several code units threw RangeError against a short row, and a real
// glyph equal to the mark was trimmed as if it were empty.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('an empty mark renders and trims', (tester) {
    tester.pumpWidget(const Text('Count: 0'));
    expect(
      tester.renderToString(size: const CellSize(20, 2), emptyMark: ''),
      'Count: 0\n\n',
    );
  });

  testWidgets('a mark of several code units renders between content', (tester) {
    tester.pumpWidget(
      const Row(children: [Text('a'), SizedBox(width: 2), Text('b')]),
    );
    expect(
      tester.renderToString(size: const CellSize(6, 1), emptyMark: '..'),
      'a....b\n',
    );
    tester.pumpWidget(const Text('x'));
    expect(
      tester.renderToString(size: const CellSize(6, 1), emptyMark: '🟦'),
      'x\n',
    );
  });

  testWidgets('a glyph equal to the mark is content, not trimmed', (tester) {
    tester.pumpWidget(const Text('a·'));
    expect(tester.renderToString(size: const CellSize(6, 1)), 'a·\n');
  });
}
