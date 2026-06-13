import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_codec.dart' show RemotePlan;
import 'package:fleury_web/src/remote_client/plan_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('remotePlanToPresentation', () {
    test('full repaint maps to a full dirty-row set', () {
      final plan = RemotePlan(
        size: const CellSize(20, 6),
        fullRepaint: true,
        rows: [
          for (var r = 0; r < 6; r++)
            RowSpanModel(row: r, cols: 20, runs: const []),
        ],
      );
      final presentation = remotePlanToPresentation(plan);
      expect(presentation.size, const CellSize(20, 6));
      expect(presentation.fullRepaint, isTrue);
      expect(presentation.damage.dirtyRows.isFull, isTrue);
      expect(presentation.dirtyRowModels, hasLength(6));
      expect(presentation.damage.source, FrameDamageSource.fullRepaint);
    });

    test('partial update keeps only the carried rows dirty', () {
      final plan = RemotePlan(
        size: const CellSize(20, 10),
        fullRepaint: false,
        rows: [
          RowSpanModel(row: 2, cols: 20, runs: const []),
          RowSpanModel(row: 7, cols: 20, runs: const []),
        ],
      );
      final presentation = remotePlanToPresentation(plan);
      expect(presentation.fullRepaint, isFalse);
      expect(presentation.damage.dirtyRows.isFull, isFalse);
      expect(presentation.damage.dirtyRows.rows, [2, 7]);
      expect(presentation.damage.source, FrameDamageSource.paintDamage);
    });

    test('scroll-up shift carries through', () {
      final plan = RemotePlan(
        size: const CellSize(20, 10),
        fullRepaint: false,
        scrollUpRows: 3,
        rows: const [],
      );
      final presentation = remotePlanToPresentation(plan);
      expect(presentation.scrollUpRows, 3);
    });

    test('row span models pass through unchanged for the surface', () {
      const run = CellSpanRun(
        startCol: 0,
        widthCols: 5,
        text: 'hello',
        style: CellStyle(bold: true),
        kind: CellRunKind.text,
        correction: WidthCorrection.none,
      );
      final plan = RemotePlan(
        size: const CellSize(20, 1),
        fullRepaint: true,
        rows: [RowSpanModel(row: 0, cols: 20, runs: const [run])],
      );
      final presentation = remotePlanToPresentation(plan);
      expect(presentation.dirtyRowModels.single.runs.single.text, 'hello');
      expect(presentation.dirtyRowModels.single.runs.single.style.bold, isTrue);
    });
  });
}
