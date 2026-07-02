import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/remote_client/plan_adapter.dart';
import 'package:test/test.dart';

String _rowText(CellBuffer b, int row) {
  final sb = StringBuffer();
  for (var c = 0; c < b.size.cols; c++) {
    sb.write(b.atColRow(c, row).grapheme ?? ' ');
  }
  return sb.toString().trimRight();
}

void main() {
  group('applyRemotePlan (client mirror)', () {
    test('applies a server-built plan and reports the touched rows', () {
      final prev = CellBuffer(const CellSize(20, 6));
      final next = CellBuffer(const CellSize(20, 6));
      next.writeText(const CellOffset(0, 2), 'second row');
      next.writeText(const CellOffset(0, 4), 'fifth-ish');
      final plan = buildRemotePlan(prev, next, fullRepaint: false);

      final mirror = CellBuffer(const CellSize(20, 6));
      final presentation = applyRemotePlan(plan, mirror);

      expect(presentation.fullRepaint, isFalse);
      expect(presentation.damage.dirtyRows.rows, [2, 4]);
      // The mirror now holds the content; dirty rows have span models.
      expect(_rowText(mirror, 2), 'second row');
      expect(_rowText(mirror, 4), 'fifth-ish');
      expect(presentation.dirtyRowModels, hasLength(2));
      final rowText = presentation.dirtyRowModels.first.runs
          .map((r) => r.text)
          .join();
      expect(rowText.trimRight(), 'second row');
    });

    test('full repaint marks every row dirty', () {
      final prev = CellBuffer(const CellSize(10, 4));
      final next = CellBuffer(const CellSize(10, 4));
      next.writeText(const CellOffset(0, 0), 'hi');
      final plan = buildRemotePlan(prev, next, fullRepaint: true);
      final mirror = CellBuffer(const CellSize(10, 4));
      final presentation = applyRemotePlan(plan, mirror);
      expect(presentation.damage.dirtyRows.isFull, isTrue);
      expect(presentation.dirtyRowModels, hasLength(4));
    });

    test('scroll-up plan scrolls the mirror and carries the shift', () {
      const size = CellSize(60, 8);
      const words = [
        'connect',
        'GET /api',
        'cache miss',
        'retry',
        'flush',
        'commit',
        'timeout',
        'parse',
        'spawn',
        'gc pause',
        'drain',
      ];
      String line(int n) =>
          '${n.toString().padLeft(5)} ${(n * 31) % 9999} '
          '${words[(n * 7) % words.length]} shard=${n % 64} '
          'lat=${(n * 13) % 900}ms';
      final prev = CellBuffer(size);
      for (var r = 0; r < 8; r++) {
        prev.writeText(CellOffset(0, r), line(r));
      }
      final next = CellBuffer(size);
      for (var r = 0; r < 8; r++) {
        next.writeText(CellOffset(0, r), line(r + 1));
      }
      final plan = buildRemotePlan(prev, next, fullRepaint: false);
      expect(plan.scrollUpRows, 1, reason: 'a real scroll was detected');

      // Mirror seeded with prev; adapter scrolls it and applies residual.
      final mirror = CellBuffer(size);
      for (var r = 0; r < 8; r++) {
        mirror.writeText(CellOffset(0, r), line(r));
      }
      final presentation = applyRemotePlan(plan, mirror);
      expect(
        presentation.scrollUpRows,
        1,
        reason: 'the surface gets the DOM scroll hint',
      );
      // The mirror reproduces next exactly.
      for (var r = 0; r < 8; r++) {
        expect(_rowText(mirror, r), _rowText(next, r), reason: 'row $r');
      }
    });

    test('mirror tracks a multi-frame sequence exactly', () {
      final mirror = CellBuffer(const CellSize(20, 3));
      var prev = CellBuffer(const CellSize(20, 3));
      late CellBuffer last;
      for (final text in ['frame one here', 'second', 'a third frame x']) {
        final next = CellBuffer(const CellSize(20, 3));
        // Each frame fully repaints row 1 (20 cols) so there's no remainder.
        next.writeText(const CellOffset(0, 1), text.padRight(20));
        final plan = buildRemotePlan(prev, next, fullRepaint: false);
        applyRemotePlan(plan, mirror);
        prev = next;
        last = next;
      }
      // The mirror reproduces the last frame's content row-for-row.
      for (var r = 0; r < 3; r++) {
        expect(_rowText(mirror, r), _rowText(last, r), reason: 'row $r');
      }
    });
  });
}
