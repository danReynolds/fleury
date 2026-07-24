// The boundary half of the vacated-cell contract.
//
// A RepaintBoundary clears vacated cells by its own route: it blits the whole
// bounding box out of a freshly repainted cache (covering cells vacated INSIDE
// the box) and re-damages its previous extent when that box shrinks (covering
// cells vacated outside it). That is complementary to the frame loop's damage
// union, which cannot see content sitting behind a cached boundary — a boundary
// that was a cache-hit last frame recorded no paint damage to union against.
// Both mechanisms are load-bearing; this pins the boundary's half.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _Dots extends LeafRenderObjectWidget {
  const _Dots(this.cells);
  final List<(int, int)> cells;
  @override
  RenderObject createRenderObject(BuildContext context) => _DotsRender(cells);
  @override
  void updateRenderObject(BuildContext context, covariant _DotsRender ro) {
    ro.cells = cells;
  }
}

class _DotsRender extends RenderObject {
  _DotsRender(this._cells);
  List<(int, int)> _cells;
  set cells(List<(int, int)> v) {
    _cells = v;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(8, 8));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    for (final (col, row) in _cells) {
      buffer.writeGrapheme(CellOffset(offset.col + col, offset.row + row), '#');
    }
  }
}

void main() {
  testWidgets('boundary clears a cell vacated within its bounding box', (
    tester,
  ) {
    const size = CellSize(8, 8);
    // Frame 1: three diagonal cells → bounding box (0,0)..(4,4).
    tester.pumpWidget(
      const RepaintBoundary(child: _Dots(<(int, int)>[(0, 0), (2, 2), (4, 4)])),
    );
    final f1 = tester.render(size: size);
    expect(f1.atColRow(2, 2).grapheme, '#', reason: 'frame 1 lights the middle');

    // Frame 2: drop the middle cell; the corners keep the same bounding box.
    tester.pumpWidget(
      const RepaintBoundary(child: _Dots(<(int, int)>[(0, 0), (4, 4)])),
    );
    final f2 = tester.render(size: size);
    expect(f2.atColRow(0, 0).grapheme, '#');
    expect(f2.atColRow(4, 4).grapheme, '#');
    expect(
      f2.atColRow(2, 2).grapheme,
      isNot('#'),
      reason: 'the vacated middle cell must clear, not ghost',
    );
  });
}
