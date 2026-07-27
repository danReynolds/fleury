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
      expect(frame.damage.dirtyBounds!.top, 1);
      expect(frame.damage.dirtyBounds!.bottom, 12);
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
      // Exactly the two cells 'hi' occupies — deriving does not inherit the
      // one-column padding paint's write rect carries for wide-glyph eviction.
      expect(frame.damage.dirtyBounds, CellRect.fromLTWH(1, 0, 2, 1));
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
      // Only the one cell that actually differs.
      expect(second.damage.dirtyBounds, CellRect.fromLTWH(1, 0, 1, 1));
      expect(second.damage.diffBounds, CellRect.fromLTWH(1, 0, 1, 1));
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
      expect(second.damage.fullRepaint, isFalse);
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
            buffer.writeText(
              CellOffset(0, row),
              row == 1 ? 'CHNG' : 'row$row',
            );
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

      expect(shrunk.damage.fullRepaint, isTrue);
      expect(shrunk.damage.dirtyRowsFor(const CellSize(6, 3)).isFull, isTrue);
    });

    test('damage stays exact as content moves, shrinks and grows', () {
      final loop = TuiFrameLoop(renderDamage: RenderDamageTracker());
      paint(loop, [0, 1, 2, 3]);

      expect(paint(loop, [0], blitted: [1, 2, 3]).damage
          .dirtyRowsFor(size).rows, isEmpty, reason: 'all cache hits');
      expect(paint(loop, [0]).damage.dirtyRowsFor(size).rows,
          containsAll(<int>[1, 2, 3]), reason: 'boundaries unmounted');
      expect(paint(loop, [0, 1, 2, 3]).damage.dirtyRowsFor(size).rows,
          containsAll(<int>[1, 2, 3]), reason: 'grown back');
      expect(paint(loop, []).damage.dirtyRowsFor(size).rows,
          containsAll(<int>[0, 1, 2, 3]), reason: 'cleared entirely');
    });
  });
}
