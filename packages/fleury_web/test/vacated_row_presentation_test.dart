// The presentation half of the vacated-cell contract: rows that shrinking
// content left behind must reach the surface as dirty row models.
//
// When content shrinks or moves, the cells it vacates are not "mutated by
// paint" — the untracked buffer clear is what empties them — so they fall
// outside paintDamageBounds/paintDamageRows. The DOM surface regenerates only
// the rows a plan marks dirty, so a vacated row that never makes the plan keeps
// its stale spans: the ghost the LineChart demo showed at its left edge as the
// curve advanced.
//
// TuiFrameLoop closes this by unioning the shown frame's painted set into the
// new frame's damage. This asserts the completion survives all the way through
// the planner into dirtyRowModels.

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/frame_presentation.dart';
import 'package:test/test.dart';

void main() {
  const planner = FramePresentationPlanner();

  test('vacated rows are flagged dirty when painted content shrinks', () {
    final damage = RenderDamageTracker();
    final loop = TuiFrameLoop(renderDamage: damage);
    const size = CellSize(6, 4);

    // Frame 1: content occupies all four rows.
    final first = loop.render(
      size: size,
      paint: (buffer) {
        buffer.writeText(const CellOffset(0, 0), 'aaaa');
        buffer.writeText(const CellOffset(0, 1), 'bbbb');
        buffer.writeText(const CellOffset(0, 2), 'cccc');
        buffer.writeText(const CellOffset(0, 3), 'dddd');
      },
    )!;
    loop.commit(first);

    // Frame 2: content shrinks to rows 0-1 (a partial repaint — nothing is
    // painted into rows 2-3, so the fresh buffer leaves them empty).
    final second = loop.render(
      size: size,
      paint: (buffer) {
        buffer.writeText(const CellOffset(0, 0), 'aaaa');
        buffer.writeText(const CellOffset(0, 1), 'bbbb');
      },
    )!;

    // The model buffer IS clean — rows 2-3 emptied out.
    expect(second.next.atColRow(0, 2).grapheme?.trim() ?? '', '');
    expect(second.next.atColRow(0, 3).grapheme?.trim() ?? '', '');

    final plan = planner.build(reason: 'shrink', frame: second);
    final dirty = plan.dirtyRowModels.map((row) => row.row).toSet();

    // Rows 2-3 went from 'cccc'/'dddd' to empty. A retained surface rebuilds
    // only dirty rows, so unless they are flagged dirty their stale spans ghost.
    expect(
      dirty.containsAll({2, 3}),
      isTrue,
      reason:
          'vacated rows 2-3 must be flagged dirty; got dirty rows $dirty — '
          'the stale content ghosts on a retained surface otherwise',
    );
  });
}
