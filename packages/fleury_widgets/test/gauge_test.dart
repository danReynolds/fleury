import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _row(FleuryTester tester, int cols) => tester
    .renderToString(size: CellSize(cols, 1), emptyMark: ' ')
    .replaceAll(RegExp(r'\n+$'), '');

void main() {
  group('Gauge', () {
    testWidgets('fills exactly half the track at value=0.5', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 6,
          height: 1,
          child: Gauge(value: 0.5, showPercentage: false),
        ),
      );
      // 6 cells, half filled → 3 blocks + 3 track.
      expect(_row(tester, 6), '███░░░');
    });

    testWidgets('renders sub-cell precision with the eighth glyphs', (tester) {
      // 4 cells, value 0.625 → 2.5 cells filled → 2 full + ▌ + 1 track.
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 1,
          child: Gauge(value: 0.625, showPercentage: false),
        ),
      );
      expect(_row(tester, 4), '██▌░');
    });

    testWidgets('appends a percentage when enabled', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 10, height: 1, child: Gauge(value: 0.5)),
      );
      // 10 - ' 50%'(4) = 6-cell track, half filled.
      expect(_row(tester, 10), '███░░░ 50%');
    });

    testWidgets('lays out label + track + percentage to exactly the width', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 15,
          height: 1,
          child: Gauge(value: 0.0, label: 'CPU'),
        ),
      );
      // prefix 'CPU  '(5) + track(7) + suffix ' 0%'(3) = 15.
      expect(_row(tester, 15), 'CPU  ░░░░░░░ 0%');
    });

    testWidgets('clamps value < 0 and value > 1', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 5,
          height: 1,
          child: Gauge(value: 2.0, showPercentage: false),
        ),
      );
      expect(_row(tester, 5), '█████');
      tester.pumpWidget(
        const SizedBox(
          width: 5,
          height: 1,
          child: Gauge(value: -0.5, showPercentage: false),
        ),
      );
      expect(_row(tester, 5), '░░░░░');
    });

    testWidgets('value updates repaint without relayout', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 8,
          height: 1,
          child: Gauge(value: 0.25, showPercentage: false),
        ),
      );
      tester.render(size: const CellSize(8, 1));

      tester.pumpWidget(
        const SizedBox(
          width: 8,
          height: 1,
          child: Gauge(value: 0.75, showPercentage: false),
        ),
      );
      RenderLayoutDebugStats.beginFrame(enabled: true);
      final row = tester
          .renderToString(size: const CellSize(8, 1), emptyMark: ' ')
          .trimRight();
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(row, '██████░░');
      expect(stats.performedCount, 0);
      expect(stats.skippedCount, greaterThan(0));
    });

    testWidgets('exposes chart semantics and text-first fallback', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 12,
          height: 1,
          child: Gauge(value: 0.42, label: 'CPU', semanticLabel: 'CPU gauge'),
        ),
      );

      final chart = tester.semantics().single(
        role: SemanticRole.chart,
        label: 'CPU gauge',
        value: '42%',
      );
      expect(chart.state.chartType, 'gauge');
      expect(chart.state.chartLatestValue, 0.42);
      expect(chart.state.progressCurrent, 42);
      expect(chart.state.progressTotal, 100);

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.chart,
        label: 'CPU gauge',
      );
      expect(fallback.states, contains('progress CPU 42 of 100'));
      expect(
        fallback.states,
        contains('chart gauge, min 0, max 1, latest 0.42'),
      );
    });
  });
}
