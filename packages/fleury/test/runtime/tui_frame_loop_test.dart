import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

void main() {
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

      expect(rows.isFull, isFalse);
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
}
