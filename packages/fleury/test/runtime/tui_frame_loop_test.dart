import 'dart:typed_data';
import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

void main() {
  group('scattered damage', () {
    test('disjoint painted rows stay disjoint in dirty rows', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      const size = CellSize(10, 12);
      final first = loop.render(size: size, paint: (_) {})!;
      loop.commit(first);

      final frame = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 1), 'aaa');
          buffer.writeText(const CellOffset(0, 6), 'bbb');
          buffer.writeText(const CellOffset(0, 11), 'ccc');
        },
      )!;

      final rows = frame.damage.dirtyRowsFor(size);
      expect(rows.isFull, isFalse);
      expect(rows.rows, [1, 6, 11]);
      // The union rect still spans the gap for rect consumers.
      expect(frame.damage.diffBounds!.top, 1);
      expect(frame.damage.diffBounds!.bottom, 12);
    });
  });

  group('needsRender', () {
    test('cold pool and size changes need a render; warm pool does not', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      const size = CellSize(4, 2);
      expect(loop.needsRender(size), isTrue);

      final frame = loop.render(size: size, paint: (_) {})!;
      loop.commit(frame);
      expect(loop.needsRender(size), isFalse);
      expect(loop.needsRender(const CellSize(5, 2)), isTrue);

      loop.markFullRepaint();
      expect(loop.needsRender(size), isTrue);
    });

    test('render consumes the visual-change signal', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      const size = CellSize(4, 2);
      damage.recordVisualChange();
      expect(damage.hasVisualChange, isTrue);

      final frame = loop.render(size: size, paint: (_) {})!;
      loop.commit(frame);
      expect(damage.hasVisualChange, isFalse);
    });
  });

  const size = CellSize(5, 2);

  group('TuiFrameLoop', () {
    test('first frame allocates buffers and requires a full repaint', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);

      final frame = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'hi'),
      );

      expect(frame, isNotNull);
      expect(frame!.previous.size, size);
      expect(frame.next.size, size);
      expect(frame.previous.atColRow(1, 0), const Cell.empty());
      expect(frame.next.atColRow(1, 0).grapheme, 'h');
      // A full repaint carries no bounds: there is nothing to restrict a diff
      // to, and no second "what it would have been" reading to disagree with.
      expect(frame.damage, isA<FrameFullRepaint>());
      expect(frame.damage.diffBounds, isNull);
      // The no-padding property still needs pinning somewhere: deriving does
      // not inherit the one-column padding paint's write rect carries for
      // wide-glyph eviction. Assert it on the diff itself, which a full repaint
      // no longer exposes.
      expect(
        frame.next.diffAgainst(frame.previous).bounds,
        CellRect.fromLTWH(1, 0, 2, 1),
      );
      final rows = frame.damage.dirtyRowsFor(size);
      expect(rows.isFull, isTrue);
      expect(rows.dirtyRowCount, 2);
      expect(rows.rows, [0, 1]);
    });

    test('commit makes the rendered buffer the next previous frame', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'a'),
      )!;

      loop.commit(first);
      final second = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'b'),
      )!;

      expect(second.previous.atColRow(1, 0).grapheme, 'a');
      expect(second.next.atColRow(1, 0).grapheme, 'b');
      // Only the one cell that actually differs.
      expect(
        second.damage,
        isA<FrameChanged>().having(
          (d) => d.bounds,
          'bounds',
          CellRect.fromLTWH(1, 0, 1, 1),
        ),
      );
      final rows = second.damage.dirtyRowsFor(size);
      expect(rows.isFull, isFalse);
      expect(rows.ranges.single.startRow, 0);
      expect(rows.ranges.single.endRow, 1);
      expect(rows.rows, [0]);
    });

    test('resetBuffers forces the next frame to be presented as full', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'a'),
      )!;
      loop.commit(first);

      loop.resetBuffers();
      final second = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'b'),
      )!;

      expect(second.previous.atColRow(1, 0), const Cell.empty());
      expect(second.damage, isA<FrameFullRepaint>());
      expect(second.damage.diffBounds, isNull);
    });

    test('markFullRepaint preserves buffers but disables one bounded diff', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'a'),
      )!;
      loop.commit(first);

      loop.markFullRepaint();
      final second = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'b'),
      )!;

      expect(second.previous.atColRow(1, 0).grapheme, 'a');
      expect(second.damage, isA<FrameFullRepaint>());
      expect(second.damage.diffBounds, isNull);

      loop.commit(second);
      final third = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'c'),
      )!;

      expect(third.damage, isNot(isA<FrameFullRepaint>()));
      expect(third.damage.diffBounds, CellRect.fromLTWH(1, 0, 1, 1));
    });

    test('layout damage no longer forces a conservative full diff', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'a'),
      )!;
      loop.commit(first);

      final second = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(1, 0), 'b');
          damage.recordLayoutOrConservativePaint();
        },
      )!;

      // Damage is derived by comparing the buffers, so a layout change is just
      // another reason cells differ — the comparison sees it either way. The
      // conservative "diff everything" fallback this used to trigger existed
      // only because reported damage could not be trusted after a relayout.
      expect(second.damage, isNot(isA<FrameFullRepaint>()));
      expect(second.damage.dirtyRowsFor(size).isFull, isFalse);
      expect(second.damage.dirtyRowsFor(size).rows, [0]);
      expect(second.damage.diffBounds, CellRect.fromLTWH(1, 0, 1, 1));
    });

    test('empty sizes do not invoke paint', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      var painted = false;

      final frame = loop.render(
        size: CellSize.zero,
        paint: (_) => painted = true,
      );

      expect(frame, isNull);
      expect(painted, isFalse);
    });

    test('dirty row ranges clip to the viewport', () {
      final rows = TuiDirtyRows.range(-5, 10, rowCount: 3);

      // Clipped to every row: full damage, reported as such.
      expect(rows.isFull, isTrue);
      expect(rows.ranges.single.startRow, 0);
      expect(rows.ranges.single.endRow, 3);
      expect(rows.dirtyRowCount, 3);
      expect(rows.rows, [0, 1, 2]);

      expect(TuiDirtyRows.range(4, 6, rowCount: 3).isEmpty, isTrue);
      expect(TuiDirtyRows.full(0).isEmpty, isTrue);
    });

    test('dirty rows collapse arbitrary row indexes into ranges', () {
      final rows = TuiDirtyRows.fromRows([4, 1, 2, 2, 6], rowCount: 8);

      expect(rows.isFull, isFalse);
      expect(rows.ranges, hasLength(3));
      expect(rows.ranges[0].startRow, 1);
      expect(rows.ranges[0].endRow, 3);
      expect(rows.ranges[1].startRow, 4);
      expect(rows.ranges[1].endRow, 5);
      expect(rows.ranges[2].startRow, 6);
      expect(rows.ranges[2].endRow, 7);
      expect(rows.rows, [1, 2, 4, 6]);
      expect(rows.dirtyRowCount, 4);
    });
  });

  group('derived damage', () {
    const size = CellSize(6, 4);

    // A repaint boundary rebuilds a cached subtree by blitting it under
    // withoutDamageTracking: the cells are reconstructed, but nothing is
    // recorded as damage. Deriving makes that distinction irrelevant — the
    // comparison sees the resulting content either way.
    void blit(CellBuffer buffer, int row, String text) =>
        buffer.withoutDamageTracking(
          () => buffer.writeText(CellOffset(0, row), text),
        );

    TuiRenderedFrame paint(
      TuiFrameLoop loop,
      List<int> tracked, {
      List<int> blitted = const [],
      bool commit = true,
    }) {
      final frame = loop.render(
        size: size,
        paint: (buffer) {
          for (final row in tracked) {
            buffer.writeText(CellOffset(0, row), 'row$row');
          }
          for (final row in blitted) {
            blit(buffer, row, 'row$row');
          }
        },
      )!;
      if (commit) loop.commit(frame);
      return frame;
    }

    test('rows that shrinking content vacated are damaged', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 1, 2, 3]);
      final shrunk = paint(loop, [0, 1], commit: false);

      expect(
        shrunk.damage.dirtyRowsFor(size).rows,
        containsAll(<int>[2, 3]),
        reason: 'a retained presenter leaves rows 2-3 stale otherwise',
      );
    });

    test('content vacated from behind a cached blit is damaged', () {
      // The ghost that reported damage cannot see: the frame that most recently
      // rebuilt row 2 did so with a cache-hit blit, which records nothing. Any
      // scheme reading "what did paint report" concludes row 2 was never
      // occupied and leaves the stale text on screen.
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 2]);
      final cached = paint(loop, [0], blitted: [2]);
      expect(
        cached.damage.dirtyRowsFor(size).rows,
        isEmpty,
        reason: 'a cache hit reproduces what is on screen: nothing changed',
      );

      final abandoned = paint(loop, [0], commit: false);
      expect(abandoned.next.atColRow(0, 2).grapheme ?? '', '');
      expect(
        abandoned.damage.dirtyRowsFor(size).rows,
        contains(2),
        reason: 'the abandoned row emptied out and must be repainted',
      );
    });

    test('repainting identical content reports nothing dirty', () {
      // The payoff over reported damage, which marks every row a widget
      // repainted regardless of whether the output actually differs.
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 1, 2, 3]);
      final same = paint(loop, [0, 1, 2, 3], commit: false);

      expect(same.damage.dirtyRowsFor(size).rows, isEmpty);
      expect(same.damage.diffBounds, isNull);
    });

    test('only the row whose content differs is dirty', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 1, 2, 3]);
      final changed = loop.render(
        size: size,
        paint: (buffer) {
          for (var row = 0; row < 4; row++) {
            buffer.writeText(CellOffset(0, row), row == 1 ? 'CHNG' : 'row$row');
          }
        },
      )!;

      expect(changed.damage.dirtyRowsFor(size).rows, <int>[1]);
    });

    test('an uncommitted frame does not become the reference', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 2]);
      paint(loop, [0], commit: false); // rendered, never presented
      final third = paint(loop, [0], commit: false);

      expect(
        third.damage.dirtyRowsFor(size).rows,
        contains(2),
        reason: 'row 2 is still on screen from the committed frame',
      );
    });

    test('a resize presents as a full repaint', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      final first = loop.render(
        size: const CellSize(6, 8),
        paint: (buffer) {
          for (var row = 0; row < 8; row++) {
            buffer.writeText(CellOffset(0, row), 'xxxx');
          }
        },
      )!;
      loop.commit(first);

      final shrunk = loop.render(
        size: const CellSize(6, 3),
        paint: (buffer) => buffer.writeText(const CellOffset(0, 0), 'xxxx'),
      )!;

      expect(shrunk.damage, isA<FrameFullRepaint>());
      expect(shrunk.damage.dirtyRowsFor(const CellSize(6, 3)).isFull, isTrue);
    });

    test('a beneficial scroll is published, not left to be inferred', () {
      // Regression: scroll detection used to trigger on "damage is unbounded",
      // which every relayout published. Exact damage is never unbounded, so the
      // terminal's ESC[S path and the surface's row shift both went unreachable
      // — with no gate or test to notice.
      const wide = CellSize(20, 10);
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      // Distinct repeated-letter rows: shifting dirties ~all cells, well past
      // the detection gate. ('entry N' -> 'entry N+1' dirties ~1 cell/row —
      // below a row's worth of change, which the gate correctly deems not
      // worth a detector run: scrolling could save at most those few cells.)
      String rowText(int row) => String.fromCharCode(0x41 + row) * 12;
      final first = loop.render(
        size: wide,
        paint: (buffer) {
          for (var row = 0; row < 10; row++) {
            buffer.writeText(CellOffset(0, row), rowText(row));
          }
        },
      )!;
      loop.commit(first);

      final scrolled = loop.render(
        size: wide,
        paint: (buffer) {
          for (var row = 0; row < 10; row++) {
            buffer.writeText(CellOffset(0, row), rowText(row + 1));
          }
        },
      )!;

      expect(
        scrolled.damage,
        isA<FrameScrolled>().having((d) => d.scrollUpRows, 'scrollUpRows', 1),
      );

      // And the gate half: a change too small for scrolling to ever pay
      // (digit-only, ~1 cell/row) must not run detection at all.
      loop.commit(scrolled);
      final tiny = loop.render(
        size: wide,
        paint: (buffer) {
          for (var row = 0; row < 10; row++) {
            buffer.writeText(CellOffset(0, row), rowText(row + 1));
          }
          buffer.writeText(const CellOffset(0, 0), 'x');
        },
      )!;
      expect(tiny.damage, isNot(isA<FrameScrolled>()));
    });

    test('a scroll is still found when a row happens to be unchanged', () {
      // The old trigger also required dirtyRows.isFull; one static row (a
      // header, or an entering row that repeats the last) was enough to lose
      // the shift and rebuild every row instead.
      const wide = CellSize(20, 10);
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      const planner = FramePresentationPlanner();
      String rowText(int row) => String.fromCharCode(0x41 + row) * 12;
      final first = loop.render(
        size: wide,
        paint: (buffer) {
          for (var row = 0; row < 10; row++) {
            buffer.writeText(CellOffset(0, row), rowText(row));
          }
        },
      )!;
      loop.commit(first);

      final scrolled = loop.render(
        size: wide,
        paint: (buffer) {
          for (var row = 0; row < 10; row++) {
            buffer.writeText(
              CellOffset(0, row),
              rowText(row == 9 ? 9 : row + 1),
            );
          }
        },
      )!;

      expect(
        scrolled.damage.dirtyRowsFor(wide).isFull,
        isFalse,
        reason: 'precondition: one row is byte-identical',
      );
      expect(
        scrolled.damage,
        isA<FrameScrolled>().having((d) => d.scrollUpRows, 'scrollUpRows', 1),
      );
      final plan = planner.build(reason: 'scroll', frame: scrolled);
      expect(plan.scrollUpRows, 1);
      expect(
        plan.dirtyRowModels,
        hasLength(1),
        reason: 'shift what is already there; rebuild only the residue',
      );
    });

    test('an identical repaint is reported as empty, not as unknown', () {
      // Distinct variants, so "nothing changed" can no longer be mistaken for
      // "repaint everything" the way a shared null bounds once allowed.
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 1, 2, 3]);
      final same = paint(loop, [0, 1, 2, 3], commit: false);

      expect(same.damage, isA<FrameUnchanged>());
      expect(same.damage.diffBounds, isNull);
    });

    test('incomparable frames are distinguishable from unchanged ones', () {
      // Both carry no rows and null bounds; only the sentinel tells a caller
      // that nothing is KNOWN rather than that nothing CHANGED.
      final small = CellBuffer(const CellSize(4, 2));
      final large = CellBuffer(const CellSize(8, 4));

      final incomparable = large.diffAgainst(small);
      expect(incomparable.isComparable, isFalse);
      expect(incomparable.isUnchanged, isFalse);

      final unchanged = large.diffAgainst(CellBuffer(const CellSize(8, 4)));
      expect(unchanged.isComparable, isTrue);
      expect(unchanged.isUnchanged, isTrue);

      // A placement-only change has zero differing CELLS but is a change:
      // isUnchanged keyed on dirtyCells would freeze in-place image animation
      // for any consumer that skips work on it.
      final withImage = CellBuffer(const CellSize(8, 4))
        ..writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3]),
          width: 2,
          height: 1,
        );
      final swapped = CellBuffer(const CellSize(8, 4))
        ..writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([9, 9, 9]),
          width: 2,
          height: 1,
        );
      final placementOnly = swapped.diffAgainst(withImage);
      expect(placementOnly.dirtyCells, 0, reason: 'cells are byte-identical');
      expect(placementOnly.isUnchanged, isFalse);
    });

    group('inline images', () {
      // Cells under a placement are payload-free Cell.overlay, so the grid
      // cannot express any of this and the placement list has to be compared.
      const box = CellSize(20, 6);

      TuiRenderedFrame place(
        TuiFrameLoop loop,
        List<int> bytes, {
        int row = 0,
        bool commit = true,
      }) {
        final frame = loop.render(
          size: box,
          paint: (buffer) => buffer.writeImage(
            CellOffset(0, row),
            Uint8List.fromList(bytes),
            width: 4,
            height: 2,
          ),
        )!;
        if (commit) loop.commit(frame);
        return frame;
      }

      test('swapping the image in place is damage', () {
        final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
        place(loop, [1, 2, 3]);
        final swapped = place(loop, [9, 9, 9], commit: false);

        expect(
          swapped.damage.dirtyRowsFor(box).rows,
          containsAll(<int>[0, 1]),
          reason: 'same rect, different bytes — the cells are identical',
        );
      });

      test('re-placing the same image is not damage', () {
        final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
        place(loop, [1, 2, 3]);
        final again = place(loop, [1, 2, 3], commit: false);

        expect(again.damage, isA<FrameUnchanged>());
      });

      test('moving a placement damages both the old and new rows', () {
        final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
        place(loop, [1, 2, 3]);
        final moved = place(loop, [1, 2, 3], row: 3, commit: false);

        expect(
          moved.damage.dirtyRowsFor(box).rows,
          containsAll(<int>[0, 1, 3, 4]),
          reason: 'the vacated rows need clearing as much as the new ones',
        );
      });
    });

    test('damage stays exact as content moves, shrinks and grows', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 1, 2, 3]);

      expect(
        paint(loop, [0], blitted: [1, 2, 3]).damage.dirtyRowsFor(size).rows,
        isEmpty,
        reason: 'all cache hits',
      );
      expect(
        paint(loop, [0]).damage.dirtyRowsFor(size).rows,
        containsAll(<int>[1, 2, 3]),
        reason: 'boundaries unmounted',
      );
      expect(
        paint(loop, [0, 1, 2, 3]).damage.dirtyRowsFor(size).rows,
        containsAll(<int>[1, 2, 3]),
        reason: 'grown back',
      );
      expect(
        paint(loop, []).damage.dirtyRowsFor(size).rows,
        containsAll(<int>[0, 1, 2, 3]),
        reason: 'cleared entirely',
      );
    });
  });
}
