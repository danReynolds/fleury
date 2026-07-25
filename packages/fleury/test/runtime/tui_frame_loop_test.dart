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

    // A repaint boundary reconstructs a cached subtree by blitting it under
    // withoutDamageTracking: the cells ARE rebuilt, but the presenter is told
    // not to re-scan them. These fixtures stand in for that, because it is the
    // case where "damaged" and "reconstructed" genuinely disagree.
    //
    // Suppressing damage carries an unwritten precondition — the cells written
    // must already match what is on screen there, which is what makes skipping
    // the re-scan safe. A cache HIT means exactly that. Every blit below
    // reproduces content an earlier committed frame put there, so the fixtures
    // stay faithful to what a boundary can actually produce.
    void blit(CellBuffer buffer, int row, String text) =>
        buffer.withoutDamageTracking(
          () => buffer.writeText(CellOffset(0, row), text),
        );

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

    test('content vacated from behind a cached blit is damaged', () {
      // The ghost a paint-damage-only union cannot see. Row 2 is on screen, but
      // the frame that most recently rebuilt it did so with a cache-hit blit,
      // which records no damage. Reading "what did the shown frame paint" finds
      // nothing for row 2, concludes it was never occupied, and leaves the
      // stale text on screen when the row is finally abandoned.
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      final first = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'aaaa');
          buffer.writeText(const CellOffset(0, 2), 'cccc');
        },
      )!;
      loop.commit(first);

      // Cache hit: row 2 is rebuilt with the content already on screen.
      final second = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'aaaa');
          blit(buffer, 2, 'cccc');
        },
      )!;
      loop.commit(second);
      expect(
        second.damage.dirtyRowsFor(size).rows,
        isNot(contains(2)),
        reason: 'a cache hit changes nothing, so it must not dirty the row',
      );

      // The subtree goes away; nothing rebuilds row 2.
      final third = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 0), 'aaaa'),
      )!;

      expect(third.next.atColRow(0, 2).grapheme ?? '', '');
      expect(
        third.damage.dirtyRowsFor(size).rows,
        contains(2),
        reason: 'the abandoned row emptied out and must be repainted',
      );
    });

    test('a row rebuilt by a cached blit is not treated as vacated', () {
      // The mirror failure: counting only DAMAGED writes makes every
      // cache-hit row look abandoned, so a one-row change re-dirties the whole
      // screen — the ListView/Overlay steady state.
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      final first = loop.render(
        size: size,
        paint: (buffer) {
          for (var row = 0; row < 4; row++) {
            buffer.writeText(CellOffset(0, row), 'row$row');
          }
        },
      )!;
      loop.commit(first);

      final second = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 1), 'CHNG');
          for (final row in [0, 2, 3]) {
            blit(buffer, row, 'row$row'); // cache hits: unchanged content
          }
        },
      )!;

      expect(
        second.damage.dirtyRowsFor(size).rows,
        <int>[1],
        reason: 'only the repainted row is dirty; blits rebuilt the rest',
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
        paint: (buffer) => blit(buffer, 3, 'zzzz'),
      )!;

      // Null bounds mean "this frame did not track what it mutated", and
      // presenters answer that with a full diff. Bounding it from coverage
      // would make them trust a claim that omits the untracked write.
      expect(second.damage.diffBounds, isNull);
    });

    test('an uncommitted frame does not become the reference', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      final first = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'aaaa');
          buffer.writeText(const CellOffset(0, 2), 'cccc');
        },
      )!;
      loop.commit(first);

      // Rendered, never presented: the screen still shows `first`.
      loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 0), 'aaaa'),
      );

      final third = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 0), 'aaaa'),
      )!;

      expect(
        third.damage.dirtyRowsFor(size).rows,
        contains(2),
        reason: 'row 2 is still on screen from the committed frame',
      );
    });

    test('a resize drops stale coverage instead of damaging by old geometry', () {
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

      expect(shrunk.damage.fullRepaint, isTrue);
      expect(shrunk.damage.dirtyRowsFor(const CellSize(6, 3)).isFull, isTrue);
    });

    test('the damage oracle holds as content moves, shrinks and grows', () {
      TuiFrameLoop.debugCheckDamageCoverage = true;
      addTearDown(() => TuiFrameLoop.debugCheckDamageCoverage = false);
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());

      void paintRows(List<int> tracked, {List<int> blitted = const []}) {
        final frame = loop.render(
          size: size,
          paint: (buffer) {
            for (final row in tracked) {
              buffer.writeText(CellOffset(0, row), 'xxxx');
            }
            for (final row in blitted) {
              blit(buffer, row, 'xxxx');
            }
          },
        )!;
        loop.commit(frame);
      }

      // Each render asserts damage covers every changed cell, in both the row
      // and rect shapes; an uncovered vacated cell throws instead of ghosting.
      // Blits reproduce rows the previous frame already committed, which is the
      // only thing a cache hit can do.
      paintRows([0, 1, 2, 3]);
      paintRows([0], blitted: [1, 2, 3]); // boundaries cache-hit
      paintRows([0]); // ...then unmount: rows 1-3 abandoned
      paintRows([0, 1, 2, 3]); // grow back
      paintRows([2, 3]); // shrink from the top
      paintRows([2, 3], blitted: []); // steady state
      paintRows([]); // clear entirely
    });
  });
}
