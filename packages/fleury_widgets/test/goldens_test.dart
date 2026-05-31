// Holistic visual snapshots of each widget's full rendered frame, to
// complement the focused behavior tests. These capture layout/structure
// (grapheme grid) — not cell styles, which the behavior tests assert
// inline. Regenerate with `FLEURY_UPDATE_GOLDENS=1 dart test` and review
// the diff before committing.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('home');
  }
}

void main() {
  group('goldens', () {
    testWidgets('tabs strip + content', (tester) {
      tester.pumpWidget(
        Tabs(
          controller: TabController(initialIndex: 1),
          tabs: const [
            TabItem(label: 'Files', content: Text('file list')),
            TabItem(label: 'Edit', content: Text('the editor')),
            TabItem(label: 'Run', content: Text('output')),
          ],
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(24, 2)),
        matchesGolden('tabs/three_tabs.txt'),
      );
    });

    testWidgets('table with header rule', (tester) {
      tester.pumpWidget(
        Table(
          header: const [Text('Name'), Text('Lang')],
          rows: const [
            [Text('Ada'), Text('Ada')],
            [Text('Linus'), Text('C')],
          ],
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(14, 4)),
        matchesGolden('table/people.txt'),
      );
    });

    testWidgets('tree expanded', (tester) {
      tester.pumpWidget(
        const Tree<String>(
          autofocus: true,
          roots: [
            TreeNode<String>(
              'lib',
              children: [
                TreeNode<String>(
                  'src',
                  children: [TreeNode<String>('main.dart')],
                ),
                TreeNode<String>('widgets.dart'),
              ],
            ),
            TreeNode<String>('README.md'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight)); // expand lib
      tester.sendKey(
        const KeyEvent(keyCode: KeyCode.arrowRight),
      ); // step to src
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight)); // expand src
      expect(
        tester.renderToString(size: const CellSize(18, 6)),
        matchesGolden('tree/expanded.txt'),
      );
    });

    testWidgets('command palette modal', (tester) {
      BuildContext? ctx;
      tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
      Navigator.of(ctx!).present<void>(
        CommandPalette(
          width: 22,
          placeholder: 'Search…',
          commands: [
            Command(label: 'Open File', onInvoke: () {}),
            Command(label: 'Save File', onInvoke: () {}),
            Command(label: 'Close Window', onInvoke: () {}),
          ],
        ),
        alignment: Alignment.topCenter,
      );
      tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.renderToString(size: const CellSize(32, 12)),
        matchesGolden('command_palette/open.txt'),
      );
    });

    // ----- Viz catalog goldens ------------------------------------------

    testWidgets('sparkline / mixed levels', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 16,
          height: 1,
          child: Sparkline(
            data: [0, 1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1],
            max: 8,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(16, 1)),
        matchesGolden('viz/sparkline_mixed.txt'),
      );
    });

    testWidgets('gauge / labeled with percentage', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 24,
          height: 1,
          child: Gauge(value: 0.62, label: 'CPU'),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(24, 1)),
        matchesGolden('viz/gauge_cpu.txt'),
      );
    });

    testWidgets('bar chart / labels and values', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 13,
          height: 7,
          child: BarChart(
            bars: [Bar('apr', 4), Bar('may', 8), Bar('jun', 12), Bar('jul', 6)],
            max: 12,
            barWidth: 2,
            gap: 1,
            showValues: true,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(13, 7)),
        matchesGolden('viz/bar_chart_labeled.txt'),
      );
    });

    testWidgets('histogram / distribution', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 24,
          height: 8,
          child: Histogram(
            values: [1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 5],
            bins: 5,
            showValues: true,
            showLabels: true,
            barWidth: 3,
            gap: 1,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(24, 8)),
        matchesGolden('viz/histogram_distribution.txt'),
      );
    });

    testWidgets('bar chart / stacked with palette', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 14,
          height: 8,
          child: BarChart(
            bars: [
              Bar.stacked('a', [4, 3, 2]),
              Bar.stacked('b', [2, 4, 1]),
              Bar.stacked('c', [1, 2, 5]),
            ],
            max: 9,
            barWidth: 3,
            gap: 1,
            showValues: true,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(14, 8)),
        matchesGolden('viz/bar_chart_stacked.txt'),
      );
    });

    testWidgets('calendar heatmap / monthly activity', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 28,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 1),
            end: DateTime(2024, 2, 25),
            values: {
              DateTime(2024, 1, 3): 4,
              DateTime(2024, 1, 4): 2,
              DateTime(2024, 1, 9): 1,
              DateTime(2024, 1, 12): 3,
              DateTime(2024, 1, 18): 4,
              DateTime(2024, 1, 22): 2,
              DateTime(2024, 2, 5): 3,
              DateTime(2024, 2, 8): 1,
              DateTime(2024, 2, 14): 4,
              DateTime(2024, 2, 20): 2,
            },
            min: 0,
            max: 4,
            cellWidth: 2,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(28, 8)),
        matchesGolden('viz/calendar_heatmap.txt'),
      );
    });

    testWidgets('heatmap / weekly activity', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 28,
          height: 6,
          child: Heatmap(
            values: [
              [0, 1, 3, 2, 0, 0, 1],
              [0, 2, 3, 4, 1, 0, 0],
              [1, 3, 4, 4, 2, 1, 0],
              [2, 4, 4, 3, 1, 0, 0],
              [0, 1, 2, 1, 0, 0, 0],
            ],
            rowLabels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
            colLabels: ['J', 'F', 'M', 'A', 'M', 'J', 'J'],
            cellWidth: 3,
            max: 4,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(28, 6)),
        matchesGolden('viz/heatmap_weekly.txt'),
      );
    });

    testWidgets('digits / clock face', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 17, height: 5, child: Digits('12:34')),
      );
      expect(
        tester.renderToString(size: const CellSize(17, 5)),
        matchesGolden('viz/digits_clock.txt'),
      );
    });

    testWidgets('canvas / diagonal line', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 12,
          height: 4,
          child: Canvas(painter: _DiagonalPainter()),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(12, 4)),
        matchesGolden('viz/canvas_diagonal.txt'),
      );
    });

    testWidgets('line chart / basic with axes', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 10,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (5, 8), (10, 3), (15, 9), (20, 5)]),
            ],
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(40, 10)),
        matchesGolden('viz/line_chart_basic.txt'),
      );
    });

    testWidgets('line chart / scatter', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([
                (0, 1),
                (2, 5),
                (4, 3),
                (6, 8),
                (8, 6),
                (10, 9),
              ], type: LineType.scatter),
            ],
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(30, 8)),
        matchesGolden('viz/line_chart_scatter.txt'),
      );
    });

    testWidgets('line chart / area filled', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([
                (0, 1),
                (2, 6),
                (4, 3),
                (6, 8),
                (8, 4),
                (10, 9),
              ], type: LineType.area),
            ],
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(30, 8)),
        matchesGolden('viz/line_chart_area.txt'),
      );
    });

    testWidgets('line chart / reference lines + threshold color', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 32,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries(
                [(0, 2), (1, 6), (2, 3), (3, 9), (4, 5)],
                label: 'rps',
                color: AnsiColor(2),
                belowColor: AnsiColor(1),
                thresholdY: 5,
              ),
            ],
            references: const [
              ReferenceLine.horizontal(5, color: AnsiColor(3), label: 'SLA'),
            ],
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(32, 8)),
        matchesGolden('viz/line_chart_threshold.txt'),
      );
    });

    testWidgets('line chart / tick formatters (percent + compact)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0.1), (1, 0.4), (2, 0.85)]),
            ],
            xTickFormat: TickFormat.compact,
            yTickFormat: TickFormat.percent,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(40, 8)),
        matchesGolden('viz/line_chart_formatters.txt'),
      );
    });

    testWidgets('line chart / interactive crosshair + tooltip', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 10,
          child: LineChart(
            series: const [
              LineSeries([(0, 1), (1, 4), (2, 2), (3, 6)], label: 'cpu'),
              LineSeries(
                [(0, 3), (1, 2), (2, 5), (3, 3)],
                label: 'mem',
                color: AnsiColor(2),
              ),
            ],
            interactive: true,
            autofocus: true,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(
        tester.renderToString(size: const CellSize(40, 10)),
        matchesGolden('viz/line_chart_crosshair.txt'),
      );
    });

    testWidgets('line chart / grid + legend', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 44,
          height: 10,
          child: LineChart(
            series: const [
              LineSeries([(0, 1), (5, 8), (10, 3), (15, 6)], label: 'cpu'),
              LineSeries(
                [(0, 4), (5, 2), (10, 7), (15, 5)],
                label: 'mem',
                color: AnsiColor(2),
              ),
            ],
            showGrid: true,
            showLegend: true,
          ),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(44, 10)),
        matchesGolden('viz/line_chart_grid_legend.txt'),
      );
    });
  });
}

class _DiagonalPainter implements CanvasPainter {
  const _DiagonalPainter();
  @override
  void paint(CanvasContext ctx) {
    ctx.drawLine(0, 0, 1, 1);
  }
}
