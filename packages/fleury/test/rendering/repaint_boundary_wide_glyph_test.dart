// A cached RepaintBoundary blit over wide glyphs keeps the wide-cell
// invariant — through the real widget layer, on the default path.
//
// Every ListView item is wrapped in a RepaintBoundary by default, and an
// overlay entry (a menu, a dropdown, a palette) floats over the app. When
// such a boundary's cache is blitted over a row a sibling already painted,
// a CJK or emoji pair straddling the blit edge used to be severed: an
// orphaned leading modelled as one column that the terminal drew as two, so
// everything after it on the row landed one cell to the right — and stayed
// there, because the shown buffer believed the frame was correct.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Fails on any continuation cell that has no leading directly before it.
void _expectWideInvariant(dynamic frame, CellSize size) {
  for (var row = 0; row < size.rows; row++) {
    for (var col = 0; col < size.cols; col++) {
      final cell = frame.atColRow(col, row);
      if (cell.role != CellRole.continuation) continue;
      expect(
        col > 0 && frame.atColRow(col - 1, row).role == CellRole.leading,
        isTrue,
        reason: 'orphaned continuation at ($col, $row)',
      );
    }
  }
}

void main() {
  testWidgets('a ListView blitted over CJK text does not sever a pair', (
    tester,
  ) {
    const size = CellSize(12, 2);
    tester.pumpWidget(
      Stack(
        children: [
          const Text('漢字漢字漢字\n漢字漢字漢字'),
          Positioned(
            left: 1,
            top: 0,
            child: SizedBox(
              width: 4,
              height: 2,
              child: ListView(children: const [Text('ab'), Text('cd')]),
            ),
          ),
        ],
      ),
    );
    // Frame 1 fills the boundary caches; from frame 2 on, the items are
    // blitted from cache over the Text the Stack painted first.
    tester.render(size: size);
    final frame = tester.render(size: size);

    _expectWideInvariant(frame, size);
    expect(
      frame.atColRow(0, 0),
      const Cell.empty(),
      reason: '漢 at col 0 lost its continuation to the blit and must go',
    );
    expect(frame.atColRow(1, 0).grapheme, 'a');
    expect(frame.atColRow(2, 0).grapheme, 'b');
    // The boundary blits its TIGHT non-empty box — "ab" is two columns, so
    // the blit lands on cols 1..2. Col 2 was 字's leading (pair 2-3): its
    // continuation at col 3 is orphaned and must go. The pair at 4-5 is
    // untouched and stays whole.
    expect(frame.atColRow(3, 0), const Cell.empty(), reason: 'orphaned 字 tail');
    expect(frame.atColRow(4, 0).grapheme, '漢');
    expect(frame.atColRow(5, 0).role, CellRole.continuation);
  });
}
