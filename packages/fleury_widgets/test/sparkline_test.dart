import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _row(FleuryTester tester, int cols) => tester
    .renderToString(size: CellSize(cols, 1), emptyMark: ' ')
    .replaceAll(RegExp(r'\n+$'), '');

void main() {
  group('Sparkline', () {
    testWidgets('maps known data to the expected block levels', (tester) {
      // With max=4 and min=0 the eighth-block index = ceil(t*8) for t>0.
      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 1,
          child: Sparkline(data: const [0, 1, 2, 3, 4], max: 4),
        ),
      );
      // 0 → empty, 0.25 → ▂, 0.5 → ▄, 0.75 → ▆, 1.0 → █.
      expect(_row(tester, 5), ' ▂▄▆█');
    });

    testWidgets('uses ASCII ramp under ASCII glyph tier', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 1,
          child: Sparkline(data: const [0, 1, 2, 3, 4], max: 4),
        ),
      );
      expect(_row(tester, 5), ' :=*#');
    }, glyphTier: GlyphTier.ascii);

    testWidgets('keeps the newest value on the right when data is wider than '
        'the available cells', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 3,
          height: 1,
          child: Sparkline(data: const [0, 0, 0, 0, 4], max: 4),
        ),
      );
      // Only the last 3 points fit: [0, 0, 4] → '  █'.
      expect(_row(tester, 3), '  █');
    });

    testWidgets('left-pads when the data is shorter than the width', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 6,
          height: 1,
          child: Sparkline(data: const [4, 4], max: 4),
        ),
      );
      expect(_row(tester, 6), '    ██');
    });

    testWidgets('renders nothing when the data is empty', (tester) {
      tester.pumpWidget(
        SizedBox(width: 5, height: 1, child: Sparkline(data: const [])),
      );
      expect(_row(tester, 5).trim(), '');
    });

    testWidgets('renders non-finite data points as gaps instead of throwing', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 1,
          child: Sparkline(
            data: const [4, double.nan, 2, double.infinity, 4],
            max: 4,
          ),
        ),
      );
      expect(_row(tester, 5), '█ ▄ █');
    });

    testWidgets('non-finite values do not poison the autoscaled max', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 3,
          height: 1,
          child: Sparkline(data: const [double.nan, 2, 4]),
        ),
      );
      // Autoscale ignores the NaN: max = 4 → gap, ▄, █.
      expect(_row(tester, 3), ' ▄█');
    });

    testWidgets('showValue formats a non-finite latest value without '
        'throwing', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 1,
          child: Sparkline(
            data: const [1, 2, double.infinity],
            max: 4,
            showValue: true,
          ),
        ),
      );
      expect(_row(tester, 12), contains('Infinity'));
    });

    testWidgets('same-length data updates repaint without relayout', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 1,
          child: Sparkline(data: const [0, 0, 0, 0, 0], max: 4),
        ),
      );
      tester.render(size: const CellSize(5, 1));

      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 1,
          child: Sparkline(data: const [0, 1, 2, 3, 4], max: 4),
        ),
      );
      RenderLayoutDebugStats.beginFrame(enabled: true);
      final row = _row(tester, 5);
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(row, ' ▂▄▆█');
      expect(stats.performedCount, 0);
      expect(stats.skippedCount, greaterThan(0));
    });

    testWidgets('exposes chart semantics and fallback state', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 1,
          child: Sparkline(
            data: const [1, 3, 5],
            max: 10,
            semanticLabel: 'CPU trend',
          ),
        ),
      );

      final chart = tester.semantics().single(
        role: SemanticRole.chart,
        label: 'CPU trend',
        value: '5',
      );
      expect(chart.state.chartType, 'sparkline');
      expect(chart.state.chartPointCount, 3);
      expect(chart.state.chartMinValue, 0);
      expect(chart.state.chartMaxValue, 10);
      expect(chart.state.chartLatestValue, 5);

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.chart,
        label: 'CPU trend',
      );
      expect(
        fallback.states,
        contains('chart sparkline, 3 points, min 0, max 10, latest 5'),
      );
    });

  testWidgets('semantic state omits non-finite values', (tester) {
    tester.pumpWidget(
      const Sparkline(
        data: [1, 2, double.nan],
        semanticLabel: 'q',
        min: double.nan,
      ),
    );
    final chart = tester.semantics().single(
      role: SemanticRole.chart,
      label: 'q',
    );
    // serve jsonEncodes semantic state; JSON has no NaN/Infinity, so a
    // non-finite latest sample or bound must be absent, not shipped raw.
    expect(chart.state.chartLatestValue, isNull);
    expect(chart.state.chartMinValue, isNull);
    expect(chart.state.chartMaxValue, 2);
  });
  });
}
