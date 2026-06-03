import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

class _DotAt implements CanvasPainter {
  const _DotAt(this.x, this.y);

  final double x;
  final double y;

  @override
  void paint(CanvasContext ctx) {
    ctx.drawDot(x, y);
  }
}

img.Image _solidImage(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return image;
}

RenderLayoutFrameStats _renderStats(FleuryTester tester, CellSize size) {
  RenderLayoutDebugStats.beginFrame(enabled: true);
  tester.render(size: size);
  return RenderLayoutDebugStats.takeFrameStats();
}

void _expectPaintOnlyStats(RenderLayoutFrameStats stats) {
  expect(stats.performedCount, 0);
  expect(stats.skippedCount, greaterThan(0));
}

void main() {
  group('paint-only widget invalidation', () {
    testWidgets('LineChart data updates reuse cached layout', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(30, 8));

      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 1), (1, 0)]),
            ],
          ),
        ),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(30, 8)));
    });

    testWidgets('Heatmap same-shape value updates reuse cached layout', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 2,
          child: Heatmap(
            values: [
              [0, 1],
              [1, 0],
            ],
            cellWidth: 1,
          ),
        ),
      );
      tester.render(size: const CellSize(4, 2));

      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 2,
          child: Heatmap(
            values: [
              [1, 0],
              [0, 1],
            ],
            cellWidth: 1,
          ),
        ),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(4, 2)));
    });

    testWidgets('CalendarHeatmap value updates reuse cached layout', (tester) {
      final start = DateTime.utc(2026, 1, 1);
      final end = DateTime.utc(2026, 1, 14);
      tester.pumpWidget(
        SizedBox(
          width: 16,
          height: 8,
          child: CalendarHeatmap(start: start, end: end, values: {start: 1}),
        ),
      );
      tester.render(size: const CellSize(16, 8));

      tester.pumpWidget(
        SizedBox(
          width: 16,
          height: 8,
          child: CalendarHeatmap(
            start: start,
            end: end,
            values: {start.add(const Duration(days: 1)): 1},
          ),
        ),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(16, 8)));
    });

    testWidgets('Canvas painter updates reuse cached layout', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 2,
          child: Canvas(painter: _DotAt(0, 0)),
        ),
      );
      tester.render(size: const CellSize(4, 2));

      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 2,
          child: Canvas(painter: _DotAt(1, 1)),
        ),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(4, 2)));
    });

    testWidgets('Digits same-width text updates reuse cached layout', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 7, height: 5, child: Digits('12')),
      );
      tester.render(size: const CellSize(7, 5));

      tester.pumpWidget(
        const SizedBox(width: 7, height: 5, child: Digits('34')),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(7, 5)));
    });

    testWidgets('RangeSlider value updates reuse cached layout', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (0, 10),
            min: 0,
            max: 10,
            onChanged: (_) {},
          ),
        ),
      );
      tester.render(size: const CellSize(11, 1));

      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (2, 8),
            min: 0,
            max: 10,
            onChanged: (_) {},
          ),
        ),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(11, 1)));
    });

    testWidgets('Table visible selection updates reuse cached layout', (
      tester,
    ) {
      final controller = TableController(selectedIndex: 0);
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 4,
          child: Table(
            controller: controller,
            headerSeparator: false,
            columnWidths: const [FixedColumnWidth(5), FixedColumnWidth(3)],
            rows: const [
              [Text('Ada'), Text('ok')],
              [Text('Linus'), Text('ok')],
              [Text('Grace'), Text('ok')],
              [Text('Ken'), Text('ok')],
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(12, 4));

      controller.selectedIndex = 1;
      tester.pump();

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(12, 4)));
    });

    testWidgets('DataTable visible selection updates reuse cached layout', (
      tester,
    ) {
      final controller = DataTableController();
      tester.pumpWidget(
        SizedBox(
          width: 20,
          height: 6,
          child: DataTable(
            rowCount: 8,
            columns: const [
              DataTableColumn(
                id: 'name',
                title: 'Name',
                width: FixedColumnWidth(8),
              ),
              DataTableColumn(
                id: 'state',
                title: 'State',
                width: FixedColumnWidth(8),
              ),
            ],
            controller: controller,
            cellBuilder: (row, column) => column == 'name' ? 'run-$row' : 'ok',
          ),
        ),
      );
      tester.render(size: const CellSize(20, 6));

      controller.selectedIndex = 1;
      tester.pump();

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(20, 6)));
    });

    testWidgets('DataTable visible cell updates reuse cached layout', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 20,
          height: 6,
          child: DataTable(
            rowCount: 8,
            columns: const [
              DataTableColumn(
                id: 'name',
                title: 'Name',
                width: FixedColumnWidth(8),
              ),
              DataTableColumn(
                id: 'state',
                title: 'State',
                width: FixedColumnWidth(8),
              ),
            ],
            cellBuilder: (row, column) => column == 'name' ? 'run-$row' : 'ok',
          ),
        ),
      );
      tester.render(size: const CellSize(20, 6));

      tester.pumpWidget(
        SizedBox(
          width: 20,
          height: 6,
          child: DataTable(
            rowCount: 8,
            columns: const [
              DataTableColumn(
                id: 'name',
                title: 'Name',
                width: FixedColumnWidth(8),
              ),
              DataTableColumn(
                id: 'state',
                title: 'State',
                width: FixedColumnWidth(8),
              ),
            ],
            cellBuilder: (row, column) =>
                column == 'name' ? 'RUN-$row' : 'ready',
          ),
        ),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(20, 6)));
    });

    testWidgets('Image fit updates reuse cached layout', (tester) {
      final image = _solidImage(2, 4, 100, 150, 200);
      tester.pumpWidget(
        SizedBox(
          width: 4,
          height: 2,
          child: Image(
            source: ImageSource.decoded(image),
            fit: ImageFit.contain,
          ),
        ),
      );
      tester.render(size: const CellSize(4, 2));

      tester.pumpWidget(
        SizedBox(
          width: 4,
          height: 2,
          child: Image(source: ImageSource.decoded(image), fit: ImageFit.fill),
        ),
      );

      _expectPaintOnlyStats(_renderStats(tester, const CellSize(4, 2)));
    });
  });
}
