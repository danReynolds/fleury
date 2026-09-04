import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:fleury_widgets/src/braille.dart';
import 'package:fleury_widgets/src/half_block_buffer.dart';
import 'package:fleury_widgets/src/octant_buffer.dart';
import 'package:fleury_widgets/src/quadrant_buffer.dart';
import 'package:fleury_widgets/src/sextant_buffer.dart';
import 'package:fleury_widgets/src/sub_cell_buffer.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void _expectMeasuredCells(CellBuffer buffer, CellWidthPolicy policy) {
  var leading = 0;
  for (var row = 0; row < buffer.size.rows; row++) {
    for (var col = 0; col < buffer.size.cols; col++) {
      final cell = buffer.atColRow(col, row);
      if (cell.role != CellRole.leading) continue;
      leading++;
      final width = const DefaultWidthResolver().widthOfGrapheme(
        cell.grapheme!,
        policy,
      );
      final hasContinuation =
          col + 1 < buffer.size.cols &&
          buffer.atColRow(col + 1, row).role == CellRole.continuation;
      expect(
        hasContinuation,
        width == 2,
        reason: '${cell.grapheme} at ($col,$row) measures $width',
      );
    }
  }
  expect(leading, greaterThan(0), reason: 'the drawing must remain visible');
}

class _Diagonal implements CanvasPainter {
  const _Diagonal();
  @override
  void paint(CanvasContext context) => context.drawLine(0, 0, 1, 1);
}

void main() {
  testWidgetsOnBothTextPolicies('sparkline retains four independent samples', (
    tester,
    policy,
  ) {
    tester.pumpWidget(const Sparkline(data: [1, 2, 3, 4]));
    final buffer = tester.render(size: const CellSize(4, 1));
    _expectMeasuredCells(buffer, tester.textPolicy.widths);
    expect(
      [for (var col = 0; col < 4; col++) buffer.atColRow(col, 0).grapheme],
      tester.textPolicy.widths.ambiguous == CellWidth.two
          ? [':', '=', '*', '#']
          : ['▂', '▄', '▆', '█'],
    );
  });

  final fixtures = <String, Widget>{
    'progress': const ProgressBar(value: 0.57),
    'gauge': const Gauge(value: 0.57, label: '·界🙂'),
    'bars': const BarChart(
      bars: [Bar('·界🙂', 2), Bar('B', 4)],
      barWidth: 6,
      showValues: true,
    ),
    'line grid references legend': const LineChart(
      series: [
        LineSeries([(0, 1), (1, 3), (2, 2)], label: '·界🙂'),
      ],
      showGrid: true,
      showLegend: true,
      references: [
        ReferenceLine.horizontal(2, label: '·界🙂'),
        ReferenceLine.vertical(1, style: ReferenceStyle.dotted),
      ],
    ),
    'line tooltip': const LineChart(
      series: [
        LineSeries([(0, 1), (1, 3), (2, 2)], label: '·界🙂'),
      ],
      interactive: true,
      autofocus: true,
    ),
    'area': AreaChart(
      series: const [
        AreaSeries([(0, 1), (1, 3), (2, 2)]),
      ],
    ),
    'heatmap': const Heatmap(
      values: [
        [1, 2, 3, 4],
      ],
      min: 0,
      max: 4,
      cellWidth: 6,
      rowLabels: ['·界🙂'],
      colLabels: ['·界🙂', 'B', 'C', 'D'],
    ),
    'calendar': CalendarHeatmap(
      values: {for (var d = 1; d <= 7; d++) DateTime(2026, 9, d): d},
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 7),
      min: 0,
      max: 7,
    ),
    'digits': const Digits('12:34', offGlyph: '·'),
    'digits wide off glyph': const Digits('12', offGlyph: '🙂'),
    'range': RangeSlider(values: (2, 8), min: 0, max: 10, onChanged: (_) {}),
    for (final marker in CanvasMarker.values)
      'canvas ${marker.name}': Canvas(
        painter: const _Diagonal(),
        marker: marker,
      ),
    'scrolling table': Table(
      header: const [Text('·界🙂')],
      rows: List.generate(15, (_) => const [Text('·界🙂')]),
      selectable: true,
    ),
    'data table': DataTable(
      columns: const [DataTableColumn(id: 'a', title: '·界🙂', sortable: true)],
      rowCount: 15,
      cellBuilder: (_, _) => '·界🙂',
      sortColumnId: 'a',
      sortDirection: DataTableSortDirection.ascending,
    ),
  };
  for (final entry in fixtures.entries) {
    testWidgetsOnBothTextPolicies(
      '${entry.key} obeys the surface cell widths',
      (tester, policy) {
        tester.pumpWidget(entry.value);
        final buffer = tester.render(size: const CellSize(48, 10));
        _expectMeasuredCells(buffer, tester.textPolicy.widths);
        if ([
          'gauge',
          'bars',
          'line grid references legend',
          'heatmap',
          'scrolling table',
        ].contains(entry.key)) {
          final text = [
            for (var r = 0; r < 10; r++)
              for (var c = 0; c < 48; c++) buffer.atColRow(c, r).grapheme ?? '',
          ].join();
          expect(
            text,
            contains('·界🙂'),
            reason: 'labels retain whole Unicode graphemes',
          );
        }
      },
    );
  }

  testWidgets('a retained drawing responds to changing surface policy', (
    tester,
  ) {
    const chart = Sparkline(data: [1, 2, 3, 4]);
    for (final policy in [
      TextPresentationPolicy.spec,
      ambiguousWidePolicy,
      TextPresentationPolicy.spec,
    ]) {
      tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const CellSize(4, 1),
            capabilities: SurfaceCapabilities(textPolicy: policy),
          ),
          child: chart,
        ),
      );
      final buffer = tester.render(size: const CellSize(4, 1));
      _expectMeasuredCells(buffer, policy.widths);
      expect(
        buffer.atColRow(3, 0).grapheme,
        policy.widths.ambiguous == CellWidth.two ? '#' : '█',
      );
    }
  });

  testWidgets('chart labels lower emoji according to the surface policy', (
    tester,
  ) {
    const policy = TextPresentationPolicy(lowering: ClusterLowering.split);
    tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: CellSize(30, 1),
          capabilities: SurfaceCapabilities(textPolicy: policy),
        ),
        child: Gauge(value: 0.5, label: '👩‍👧'),
      ),
    );
    final buffer = tester.render(size: const CellSize(30, 1));
    expect(buffer.atColRow(0, 0).grapheme, '👩');
    expect(buffer.atColRow(2, 0).grapheme, '👧');
    _expectMeasuredCells(buffer, policy.widths);
  });

  testWidgets(
    'wide-policy image fallback averages a full cell of pixels',
    (tester) {
      final decoded = img.Image(width: 1, height: 2);
      decoded.setPixelRgb(0, 0, 255, 0, 0);
      decoded.setPixelRgb(0, 1, 0, 0, 255);
      tester.pumpWidget(
        Image(source: ImageSource.decoded(decoded), fit: ImageFit.fill),
      );
      final buffer = tester.render(size: const CellSize(1, 1));
      expect(buffer.atColRow(0, 0).grapheme, ' ');
      expect(
        buffer.atColRow(0, 0).style.background,
        const RgbColor(128, 0, 128),
      );
    },
    textPolicy: ambiguousWidePolicy,
  );

  for (final glyph in ImageGlyph.values) {
    testWidgetsOnBothTextPolicies('image ${glyph.name} obeys surface widths', (
      tester,
      policy,
    ) {
      final decoded = img.Image(width: 4, height: 4);
      img.fill(decoded, color: img.ColorRgb8(100, 150, 200));
      tester.pumpWidget(
        Image(
          source: ImageSource.decoded(decoded),
          glyph: glyph,
          fit: ImageFit.fill,
        ),
      );
      final buffer = tester.render(size: const CellSize(4, 2));
      _expectMeasuredCells(buffer, tester.textPolicy.widths);
      if (tester.textPolicy.widths.ambiguous == CellWidth.two) {
        expect(
          buffer.atColRow(0, 0).style.background,
          const RgbColor(100, 150, 200),
        );
      }
    });
  }

  final buffers = <String, SubCellBuffer Function()>{
    'braille': () => BrailleBuffer(3, 2),
    'half block': () => HalfBlockBuffer(3, 2),
    'quadrant': () => QuadrantBuffer(3, 2),
    'sextant': () => SextantBuffer(3, 2),
    'octant': () => OctantBuffer(3, 2),
  };
  for (final entry in buffers.entries) {
    test('${entry.key} accepts a width policy for standalone painting', () {
      final pixels = entry.value();
      // Exercise mixed masks and a full cell (which often uses a legacy block).
      for (var y = 0; y < pixels.pixelHeight; y++) {
        for (var x = 0; x < pixels.pixelWidth; x++) {
          if (x < 2 || (x + y).isEven) pixels.setPixel(x, y);
        }
      }
      final target = CellBuffer(const CellSize(3, 2));
      pixels.writeTo(
        target,
        CellOffset.zero,
        CellStyle.none,
        policy: CellWidthPolicy.cjk,
      );
      _expectMeasuredCells(target, CellWidthPolicy.cjk);
    });
  }
}
