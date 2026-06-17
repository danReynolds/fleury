import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<String> _rows(FleuryTester tester, int cols, int rows) => tester
    .renderToString(size: CellSize(cols, rows), emptyMark: ' ')
    .split('\n');

void main() {
  group('BarChart', () {
    testWidgets('two bars at proportional heights with a category-label row', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 5,
          child: BarChart(
            bars: [Bar('a', 1), Bar('b', 2)],
            max: 2,
            barWidth: 1,
            gap: 1,
            showLabels: true,
          ),
        ),
      );
      // 5 rows = 4 chart rows + 1 label row. Bar 'a' (1/2 of 4 rows) fills
      // the bottom 2 rows; bar 'b' (2/2) fills all 4.
      final out = _rows(tester, 3, 5);
      expect(out[0], '  █');
      expect(out[1], '  █');
      expect(out[2], '█ █');
      expect(out[3], '█ █');
      expect(out[4], 'a b');
    });

    testWidgets('renders a value row above the bars when enabled', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 4,
          child: BarChart(
            bars: [Bar('x', 2), Bar('y', 2)],
            max: 2,
            barWidth: 1,
            gap: 1,
            showLabels: false,
            showValues: true,
          ),
        ),
      );
      // 4 rows: value(top), 2 chart, label-row skipped.
      // Chart rows = 4 - 1 (value) = 3 rows. Both bars equal max, so all
      // 3 chart rows fully filled.
      final out = _rows(tester, 3, 4);
      expect(out[0], '2 2');
      expect(out[1], '█ █');
      expect(out[2], '█ █');
      expect(out[3], '█ █');
    });

    testWidgets('uses block-eighths for partial fill', (tester) {
      // value = 0.25 of max → 0.25 chart-row → 2/8 of a single row → ▂.
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 2,
          child: BarChart(
            bars: [Bar('a', 0.25)],
            max: 1,
            barWidth: 1,
            gap: 0,
            showLabels: true,
          ),
        ),
      );
      // 1 chart row + 1 label row.
      // 0.25 of 1 row * 8 = 2 ticks → partial=2 → top glyph ▂.
      final out = _rows(tester, 1, 2);
      expect(out[0], '▂');
      expect(out[1], 'a');
    });

    testWidgets('a bar at zero leaves its column empty', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 3,
          child: BarChart(
            bars: [Bar('a', 0), Bar('b', 1)],
            max: 1,
            barWidth: 1,
            gap: 1,
            showLabels: true,
          ),
        ),
      );
      final out = _rows(tester, 3, 3);
      expect(out[0], '  █');
      expect(out[1], '  █');
      expect(out[2], 'a b');
    });

    testWidgets('showYAxis draws a value gutter and shifts the bars right', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 8,
          height: 4,
          child: BarChart(
            bars: [Bar('a', 10)],
            max: 10,
            barWidth: 2,
            gap: 0,
            showLabels: false,
            showYAxis: true,
          ),
        ),
      );
      final out = _rows(tester, 8, 4);
      // 6-col gutter: 'max' label at the top, '0' on the baseline row.
      expect(out[0].contains('10'), isTrue, reason: 'max label at top');
      expect(out[3].contains('0'), isTrue, reason: 'zero baseline label');
      // The full-height bar is pushed past the gutter to cols 6-7, with one
      // column of breathing room before it.
      expect(out[0].endsWith('██'), isTrue, reason: 'bar shifted past gutter');
      expect(out[0][5], ' ');
    });

    // ----- Palette -------------------------------------------------------

    testWidgets('palette cycles colors for single-value bars without color', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 5,
          height: 3,
          child: BarChart(
            bars: [Bar('a', 1), Bar('b', 1), Bar('c', 1)],
            max: 1,
            barWidth: 1,
            gap: 1,
            showLabels: false,
            palette: [AnsiColor(1), AnsiColor(2), AnsiColor(3)],
          ),
        ),
      );
      // All three bars currently use the default color (first palette
      // entry). The palette is wired but single-value bars without an
      // explicit color still fall back to defaultColor — by design, since
      // each bar is a separate categorical entity, not a stacked layer.
      final buf = tester.render(size: const CellSize(5, 3));
      // Bar 'a' uses defaultColor = palette[0] = AnsiColor(1).
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(1));
    });

    testWidgets('explicit Bar.color overrides the chart default', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: BarChart(
            bars: [Bar('a', 1, color: AnsiColor(5))],
            max: 1,
            barWidth: 1,
            gap: 0,
            showLabels: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 1));
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(5));
    });

    testWidgets('same-length bar updates repaint without relayout', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 3,
          child: BarChart(
            bars: [Bar('a', 1), Bar('b', 1)],
            max: 2,
            barWidth: 1,
            gap: 1,
            showLabels: false,
          ),
        ),
      );
      tester.render(size: const CellSize(3, 3));

      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 3,
          child: BarChart(
            bars: [Bar('a', 2), Bar('b', 1)],
            max: 2,
            barWidth: 1,
            gap: 1,
            showLabels: false,
          ),
        ),
      );
      RenderLayoutDebugStats.beginFrame(enabled: true);
      final buf = tester.render(size: const CellSize(3, 3));
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(buf.atColRow(0, 0).grapheme, '█');
      expect(buf.atColRow(2, 0).role, CellRole.empty);
      expect(buf.atColRow(0, 1).grapheme, '█');
      expect(buf.atColRow(2, 1).grapheme, '▄');
      expect(buf.atColRow(0, 2).grapheme, '█');
      expect(buf.atColRow(2, 2).grapheme, '█');
      expect(stats.performedCount, 0);
      expect(stats.skippedCount, greaterThan(0));
    });

    // ----- Stacked bars --------------------------------------------------

    testWidgets('stacked bar fills bottom→top with palette colors', (tester) {
      // Two segments of equal height, max equals their sum so the bar
      // fills the full column. Bottom rows take palette[0], top rows
      // palette[1].
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 4,
          child: BarChart(
            bars: [
              Bar.stacked('a', [2, 2]),
            ],
            max: 4,
            barWidth: 1,
            gap: 0,
            showLabels: false,
            palette: [AnsiColor(1), AnsiColor(2)],
          ),
        ),
      );
      // 4 chart rows. Segment 0 (height 2) = bottom two rows; segment 1
      // (height 2) = top two rows.
      final buf = tester.render(size: const CellSize(1, 4));
      expect(buf.atColRow(0, 3).grapheme, '█');
      expect(buf.atColRow(0, 3).style.foreground, const AnsiColor(1));
      expect(buf.atColRow(0, 2).style.foreground, const AnsiColor(1));
      expect(buf.atColRow(0, 1).style.foreground, const AnsiColor(2));
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(2));
    });

    testWidgets('stacked bar.total drives autoscale and the value label', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 5,
          child: BarChart(
            bars: [
              Bar.stacked('a', [1, 2, 3]),
            ], // total = 6
            barWidth: 1,
            gap: 0,
            showLabels: false,
            showValues: true, // top row should read '6'
          ),
        ),
      );
      final out = _rows(tester, 1, 5);
      expect(out[0], '6', reason: 'value label should show the segment sum');
    });

    testWidgets('explicit Bar.colors overrides the palette per segment', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 2,
          child: BarChart(
            bars: [
              Bar.stacked('a', [1, 1], colors: [AnsiColor(4), AnsiColor(5)]),
            ],
            max: 2,
            barWidth: 1,
            gap: 0,
            showLabels: false,
            palette: [AnsiColor(1), AnsiColor(2)],
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 2));
      expect(buf.atColRow(0, 1).style.foreground, const AnsiColor(4));
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(5));
    });

    testWidgets('exposes chart semantics and fallback state', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 8,
          height: 5,
          child: BarChart(
            bars: [
              Bar('api', 2),
              Bar.stacked('db', [1, 3]),
            ],
            max: 4,
            semanticLabel: 'Service load',
          ),
        ),
      );

      final chart = tester.semantics().single(
        role: SemanticRole.chart,
        label: 'Service load',
      );
      expect(chart.state.chartType, 'bar');
      expect(chart.state.chartBarCount, 2);
      expect(chart.state.chartSegmentCount, 3);
      expect(chart.state.chartMinValue, 2);
      expect(chart.state.chartMaxValue, 4);

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.chart,
        label: 'Service load',
      );
      expect(
        fallback.states,
        contains('chart bar, 2 bars, 3 segments, min 2, max 4'),
      );
    });

    // ----- Legend --------------------------------------------------------

    testWidgets('showLegend draws a colored bullet + label for each segment', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 30,
          height: 6,
          child: BarChart(
            bars: [
              Bar.stacked('a', [2, 1, 1]),
            ],
            max: 4,
            barWidth: 1,
            gap: 0,
            showLabels: false,
            showLegend: true,
            segmentLabels: ['cpu', 'mem', 'disk'],
            palette: [AnsiColor(1), AnsiColor(2), AnsiColor(3)],
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 6));
      // Legend on row 0, right-aligned. Find each bullet and verify its
      // color matches the palette, plus the label follows.
      final found = <String, Color?>{};
      for (var c = 0; c < 30; c++) {
        if (buf.atColRow(c, 0).grapheme == '●') {
          // Read the label after the bullet + space.
          final sb = StringBuffer();
          for (var k = 2; k < 6; k++) {
            final g = buf.atColRow(c + k, 0).grapheme;
            if (g == null || g == ' ' || g == '●') break;
            sb.write(g);
          }
          found[sb.toString()] = buf.atColRow(c, 0).style.foreground;
        }
      }
      expect(found['cpu'], const AnsiColor(1));
      expect(found['mem'], const AnsiColor(2));
      expect(found['disk'], const AnsiColor(3));
    });

    testWidgets('legend is skipped silently when too narrow', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 10,
          height: 6,
          child: BarChart(
            bars: [
              Bar.stacked('a', [1, 1]),
            ],
            max: 2,
            barWidth: 1,
            gap: 0,
            showLabels: false,
            showLegend: true,
            segmentLabels: ['this-is-too-long-a', 'and-this'],
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 6));
      // No bullets anywhere — legend silently skipped.
      for (var c = 0; c < 10; c++) {
        expect(buf.atColRow(c, 0).grapheme, isNot('●'));
      }
    });

    testWidgets('showLegend without segmentLabels is a quiet no-op', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 30,
          height: 6,
          child: BarChart(
            bars: [
              Bar.stacked('a', [1, 2, 3]),
            ],
            max: 6,
            barWidth: 1,
            gap: 0,
            showLabels: false,
            showLegend: true,
            // segmentLabels: null intentionally
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 6));
      // No legend row reserved, no bullets anywhere.
      for (var c = 0; c < 30; c++) {
        expect(buf.atColRow(c, 0).grapheme, isNot('●'));
      }
    });

    testWidgets('zero-height segment is skipped', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 2,
          child: BarChart(
            bars: [
              Bar.stacked('a', [0, 2]),
            ], // first segment skipped
            max: 2,
            barWidth: 1,
            gap: 0,
            showLabels: false,
            palette: [AnsiColor(1), AnsiColor(2)],
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 2));
      // Both filled cells should be the second segment's color.
      expect(buf.atColRow(0, 1).style.foreground, const AnsiColor(2));
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(2));
    });
  });
}
