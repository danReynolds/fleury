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
      expect(frame.damage.paintDamageBounds!.top, 1);
      expect(frame.damage.paintDamageBounds!.bottom, 12);
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
      expect(frame.damage.fullRepaint, isTrue);
      expect(frame.damage.requiresFullDiff, isFalse);
      expect(frame.damage.paintDamageBounds, CellRect.fromLTWH(0, 0, 4, 1));
      expect(frame.damage.diffBounds, isNull);
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
      expect(second.damage.fullRepaint, isFalse);
      expect(second.damage.paintDamageBounds, CellRect.fromLTWH(0, 0, 3, 1));
      expect(second.damage.diffBounds, CellRect.fromLTWH(0, 0, 3, 1));
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
      expect(second.damage.fullRepaint, isTrue);
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
      expect(second.damage.fullRepaint, isTrue);
      expect(second.damage.diffBounds, isNull);

      loop.commit(second);
      final third = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(1, 0), 'c'),
      )!;

      expect(third.damage.fullRepaint, isFalse);
      expect(third.damage.diffBounds, CellRect.fromLTWH(0, 0, 3, 1));
    });

    test('conservative layout damage disables bounded diffs for the frame', () {
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

      expect(second.damage.fullRepaint, isFalse);
      expect(second.damage.requiresFullDiff, isTrue);
      expect(second.damage.paintDamageBounds, CellRect.fromLTWH(0, 0, 3, 1));
      expect(second.damage.diffBounds, isNull);
      expect(second.damage.dirtyRowsFor(size).isFull, isTrue);
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

  group('vacated cell damage', () {
    const size = CellSize(6, 4);

    test('rows that shrinking content vacated are damaged', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
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

      // Content shrinks to the top two rows. Nothing repaints rows 2-3, so the
      // untracked buffer clear is what empties them — and that is precisely the
      // change paint damage cannot see on its own.
      final second = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'aaaa');
          buffer.writeText(const CellOffset(0, 1), 'bbbb');
        },
      )!;

      expect(
        second.damage.dirtyRowsFor(size).rows,
        containsAll(<int>[2, 3]),
        reason: 'a retained presenter leaves rows 2-3 stale otherwise',
      );
    });

    test('unchanged content does not widen damage past what it painted', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      final first = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 1), 'hello'),
      )!;
      loop.commit(first);

      final second = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 1), 'hullo'),
      )!;

      // Nothing was vacated, so the union must add nothing: steady-state
      // repainting stays exactly as narrow as it was.
      expect(second.damage.dirtyRowsFor(size).rows, <int>[1]);
    });

    test('a frame that tracked nothing keeps its damage unbounded', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      final first = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 0), 'aaaa'),
      )!;
      loop.commit(first);

      final second = loop.render(
        size: size,
        paint: (buffer) => buffer.withoutDamageTracking(
          () => buffer.writeText(const CellOffset(0, 3), 'zzzz'),
        ),
      )!;

      // Null bounds mean "this frame did not track what it mutated", and
      // presenters answer that with a full diff. Completing it from the shown
      // frame's painted set would bound a claim they then trust, dropping the
      // untracked write on row 3.
      expect(second.damage.diffBounds, isNull);
    });

    test('the damage oracle holds as content moves, shrinks and grows', () {
      TuiFrameLoop.debugCheckDamageCoverage = true;
      addTearDown(() => TuiFrameLoop.debugCheckDamageCoverage = false);
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());

      void paintRows(List<int> rows) {
        final frame = loop.render(
          size: size,
          paint: (buffer) {
            for (final row in rows) {
              buffer.writeText(CellOffset(0, row), 'xxxx');
            }
          },
        )!;
        loop.commit(frame);
      }

      // Each render asserts damage covers every changed cell; an uncovered
      // vacated row throws instead of silently ghosting.
      paintRows([0, 1, 2, 3]);
      paintRows([2, 3]); // shrink
      paintRows([0]); // move up
      paintRows([0, 1, 2, 3]); // grow back
      paintRows([]); // clear entirely
    });
  });
}
