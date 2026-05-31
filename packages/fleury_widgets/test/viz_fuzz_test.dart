// Cross-widget fuzz + undersize pass for the viz catalog.
//
// LineChart had this in its own file from the start; the rest of the
// catalog didn't, which is how the BarChart bounds bug slipped through
// — every focused BarChart test happened to use a container >= the
// natural bar width, so the unguarded writeGrapheme calls never tripped
// the buffer's bounds check.
//
// This file fixes that systematically: each widget gets (a) a fuzz test
// that pumps it at random sizes and configurations and asserts nothing
// throws, and (b) explicit shrunk-container tests that force the widget
// to render at less than its intrinsic size. Both rely on the fact that
// CellBuffer.writeGrapheme throws RangeError on out-of-bounds writes —
// so an unguarded write surfaces as a test failure here.

import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  // ------------------------------------------------------------------
  // BarChart
  // ------------------------------------------------------------------
  group('BarChart fuzz / undersize', () {
    testWidgets('survives a container narrower than the natural bar width', (
      tester,
    ) {
      // 5 bars × 3 wide + 4 gaps × 2 = 23 cells natural. Render in 10.
      tester.pumpWidget(
        const SizedBox(
          width: 10,
          height: 8,
          child: BarChart(
            bars: [
              Bar('a', 1),
              Bar('b', 2),
              Bar('c', 3),
              Bar('d', 4),
              Bar('e', 5),
            ],
            max: 5,
            barWidth: 3,
            gap: 2,
          ),
        ),
      );
      tester.render(size: const CellSize(10, 8));
    });

    testWidgets('stacked bars survive a narrow container', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 10,
          height: 8,
          child: BarChart(
            bars: [
              Bar.stacked('a', [1, 2, 3]),
              Bar.stacked('b', [2, 3, 4]),
              Bar.stacked('c', [3, 4, 5]),
              Bar.stacked('d', [4, 5, 6]),
              Bar.stacked('e', [5, 6, 7]),
            ],
            max: 18,
            barWidth: 3,
            gap: 2,
          ),
        ),
      );
      tester.render(size: const CellSize(10, 8));
    });

    testWidgets('fuzz: random bars / sizes / configs', (tester) {
      final rng = Random(0xBAA);
      for (var iter = 0; iter < 30; iter++) {
        final cols = 4 + rng.nextInt(40);
        final rows = 2 + rng.nextInt(12);
        final n = 1 + rng.nextInt(10);
        final stacked = rng.nextBool();
        final bars = <Bar>[
          for (var i = 0; i < n; i++)
            if (stacked)
              Bar.stacked('b$i', [
                for (var s = 0; s < 1 + rng.nextInt(4); s++) rng.nextInt(20),
              ])
            else
              Bar('b$i', rng.nextInt(20)),
        ];
        tester.pumpWidget(
          SizedBox(
            width: cols,
            height: rows,
            child: BarChart(
              bars: bars,
              barWidth: 1 + rng.nextInt(4),
              gap: rng.nextInt(3),
              showLabels: rng.nextBool(),
              showValues: rng.nextBool(),
              showLegend: stacked && rng.nextBool(),
              segmentLabels: stacked
                  ? ['a', 'b', 'c', 'd'].sublist(0, 1 + rng.nextInt(3))
                  : null,
            ),
          ),
        );
        tester.render(size: CellSize(cols, rows));
      }
    });
  });

  // ------------------------------------------------------------------
  // Heatmap
  // ------------------------------------------------------------------
  group('Heatmap fuzz / undersize', () {
    testWidgets('survives a container smaller than the grid', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 2,
          child: Heatmap(
            values: [
              [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
              [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
              [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
              [9, 9, 9, 9, 9, 9, 9, 9, 9, 9],
            ],
            cellWidth: 2,
            rowLabels: ['row-one', 'row-two', 'row-three', 'row-four'],
            colLabels: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'],
          ),
        ),
      );
      tester.render(size: const CellSize(4, 2));
    });

    testWidgets('fuzz: random grids / sizes', (tester) {
      final rng = Random(0xC0FFEE);
      for (var iter = 0; iter < 30; iter++) {
        final rows = 1 + rng.nextInt(8);
        final cols = 1 + rng.nextInt(12);
        final values = <List<num>>[
          for (var r = 0; r < rows; r++)
            [for (var c = 0; c < cols; c++) rng.nextDouble() * 10],
        ];
        final ww = 2 + rng.nextInt(12);
        final hh = 1 + rng.nextInt(10);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: Heatmap(
              values: values,
              cellWidth: 1 + rng.nextInt(3),
              rowLabels: rng.nextBool()
                  ? [for (var r = 0; r < rows; r++) 'r$r']
                  : null,
              colLabels: rng.nextBool()
                  ? [for (var c = 0; c < cols; c++) 'c$c']
                  : null,
            ),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // CalendarHeatmap
  // ------------------------------------------------------------------
  group('CalendarHeatmap fuzz / undersize', () {
    testWidgets('survives a container narrower than 8 weeks of cells', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 6,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 1),
            end: DateTime(2024, 3, 1),
            values: {
              for (var i = 0; i < 30; i++)
                DateTime(2024, 1, 1).add(Duration(days: i)): i % 5,
            },
            cellWidth: 2,
          ),
        ),
      );
      tester.render(size: const CellSize(6, 8));
    });

    testWidgets('fuzz: random date windows + sparse activity', (tester) {
      final rng = Random(0xCA1);
      final base = DateTime(2024, 1, 1);
      for (var iter = 0; iter < 25; iter++) {
        final dayCount = 1 + rng.nextInt(120);
        final start = base.add(Duration(days: rng.nextInt(60)));
        final end = start.add(Duration(days: dayCount - 1));
        final values = <DateTime, num>{};
        for (var i = 0; i < dayCount; i++) {
          if (rng.nextDouble() > 0.6) {
            values[start.add(Duration(days: i))] = rng.nextInt(8);
          }
        }
        final ww = 4 + rng.nextInt(50);
        final hh = 2 + rng.nextInt(8);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: CalendarHeatmap(
              start: start,
              end: end,
              values: values,
              cellWidth: 1 + rng.nextInt(3),
              weekStartsOn: rng.nextBool()
                  ? CalendarWeekStart.sunday
                  : CalendarWeekStart.monday,
              showDayLabels: rng.nextBool(),
              showMonthLabels: rng.nextBool(),
            ),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // Sparkline
  // ------------------------------------------------------------------
  group('Sparkline fuzz / undersize', () {
    testWidgets('fuzz: random data and sizes', (tester) {
      final rng = Random(0x5BAD);
      for (var iter = 0; iter < 30; iter++) {
        final cols = 1 + rng.nextInt(60);
        final n = rng.nextInt(200);
        final data = [for (var i = 0; i < n; i++) rng.nextDouble() * 100];
        tester.pumpWidget(
          SizedBox(
            width: cols,
            height: 1,
            child: Sparkline(data: data, max: rng.nextBool() ? 100 : null),
          ),
        );
        tester.render(size: CellSize(cols, 1));
      }
    });
  });

  // ------------------------------------------------------------------
  // Histogram
  // ------------------------------------------------------------------
  group('Histogram fuzz / undersize', () {
    testWidgets('fuzz: random data, bins, and sizes', (tester) {
      final rng = Random(0xACED);
      for (var iter = 0; iter < 25; iter++) {
        final n = rng.nextInt(50);
        final values = [for (var i = 0; i < n; i++) rng.nextDouble() * 20];
        final ww = 2 + rng.nextInt(40);
        final hh = 2 + rng.nextInt(12);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: Histogram(
              values: values,
              bins: 1 + rng.nextInt(8),
              barWidth: 1 + rng.nextInt(3),
              gap: rng.nextInt(3),
              showLabels: rng.nextBool(),
              showValues: rng.nextBool(),
            ),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // Gauge
  // ------------------------------------------------------------------
  group('Gauge fuzz / undersize', () {
    testWidgets('fuzz: random values, labels, sizes', (tester) {
      final rng = Random(0xFADE);
      for (var iter = 0; iter < 25; iter++) {
        final ww = 1 + rng.nextInt(40);
        // -1..2 sweeps below 0 and above 1 — both should clamp safely.
        final value = -1 + rng.nextDouble() * 3;
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: 1,
            child: Gauge(
              value: value,
              label: rng.nextBool() ? 'x' * (1 + rng.nextInt(10)) : null,
              showPercentage: rng.nextBool(),
            ),
          ),
        );
        tester.render(size: CellSize(ww, 1));
      }
    });
  });

  // ------------------------------------------------------------------
  // Digits
  // ------------------------------------------------------------------
  group('Digits fuzz / undersize', () {
    testWidgets('survives a container smaller than the glyph block', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 2, height: 2, child: Digits('12:34')),
      );
      tester.render(size: const CellSize(2, 2));
    });
  });
}
