import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

import '../support/render_fixtures.dart';

void main() {
  // The harness disables the indicator in its constructor, so flip it on
  // inside each test body (after the tester exists).
  tearDown(() => RenderFlex.debugShowOverflow = false);

  testWidgets('a horizontal overflow marks the right edge', (tester) {
    RenderFlex.debugShowOverflow = true;
    // Three 4-wide boxes (12 cells) in an 8-wide viewport → overflow.
    tester.pumpWidget(
      const Row(
        children: [
          SizedBox(width: 4, height: 1, child: Text('aaaa')),
          SizedBox(width: 4, height: 1, child: Text('bbbb')),
          SizedBox(width: 4, height: 1, child: Text('cccc')),
        ],
      ),
    );
    final buf = tester.render(size: const CellSize(8, 1));
    expect(buf.atColRow(7, 0).grapheme, '▓', reason: 'overflow marker at edge');
    expect(buf.atColRow(7, 0).style.foreground, const AnsiColor(1));
  });

  testWidgets('a vertical overflow marks the bottom edge', (tester) {
    RenderFlex.debugShowOverflow = true;
    tester.pumpWidget(
      const Column(
        children: [
          SizedBox(width: 1, height: 2, child: Text('a')),
          SizedBox(width: 1, height: 2, child: Text('b')),
        ],
      ),
    );
    final buf = tester.render(size: const CellSize(2, 3)); // needs 4 rows
    expect(
      buf.atColRow(0, 2).grapheme,
      '▓',
      reason: 'overflow marker at bottom',
    );
  });

  testWidgets('no marker when content fits', (tester) {
    RenderFlex.debugShowOverflow = true;
    tester.pumpWidget(
      const Row(children: [SizedBox(width: 2, height: 1, child: Text('ab'))]),
    );
    final buf = tester.render(size: const CellSize(8, 1));
    for (var c = 0; c < 8; c++) {
      expect(buf.atColRow(c, 0).grapheme, isNot('▓'));
    }
  });

  testWidgets('respects the debug flag being off', (tester) {
    RenderFlex.debugShowOverflow = false;
    tester.pumpWidget(
      const Row(
        children: [SizedBox(width: 10, height: 1, child: Text('xxxxxxxxxx'))],
      ),
    );
    final buf = tester.render(size: const CellSize(4, 1));
    for (var c = 0; c < 4; c++) {
      expect(buf.atColRow(c, 0).grapheme, isNot('▓'));
    }
  });

  testWidgets('clips a trailing image to the Flex box', (tester) {
    tester.pumpWidget(
      const Column(
        children: [
          SizedBox(width: 4, height: 2, child: Text('before')),
          ImageLeaf(),
        ],
      ),
    );

    final buf = tester.render(size: const CellSize(4, 3));
    final p = buf.imagePlacements.single;
    expect([p.col, p.row, p.cols, p.rows], [0, 2, 4, 1]);
    expect([p.boxCols, p.boxRows], [4, 2]);
    expect([p.boxOffsetCol, p.boxOffsetRow], [0, 0]);
    expect(buf.atColRow(0, 2).role, CellRole.overlay);
  });

  testWidgets('end-aligned overflow retains an image leading slice', (tester) {
    tester.pumpWidget(
      const Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ImageLeaf(),
          SizedBox(width: 4, height: 2, child: Text('after')),
        ],
      ),
    );

    final buf = tester.render(size: const CellSize(4, 3));
    final p = buf.imagePlacements.single;
    expect([p.col, p.row, p.cols, p.rows], [0, 0, 4, 1]);
    expect([p.boxCols, p.boxRows], [4, 2]);
    expect([p.boxOffsetCol, p.boxOffsetRow], [0, 1]);
    expect(buf.atColRow(0, 0).role, CellRole.overlay);
  });
}
