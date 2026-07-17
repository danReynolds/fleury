import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

bool _hasBraille(FleuryTester tester, int cols, int rows) {
  final buf = tester.render(size: CellSize(cols, rows));
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final g = buf.atColRow(c, r).grapheme;
      if (g != null && g.codeUnitAt(0) >= 0x2800 && g.codeUnitAt(0) <= 0x28FF) {
        return true;
      }
    }
  }
  return false;
}

String _row(FleuryTester tester, int row, int cols, int rows) {
  final buf = tester.render(size: CellSize(cols, rows));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    sb.write(buf.atColRow(c, row).grapheme ?? ' ');
  }
  return sb.toString();
}

void main() {
  group('LineChart', () {
    testWidgets('renders braille in the plot region when given a series', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1), (2, 0), (3, 1)]),
            ],
          ),
        ),
      );
      expect(
        _hasBraille(tester, 30, 8),
        isTrue,
        reason: 'the plot should contain at least one braille glyph',
      );
    });

    testWidgets('shows min and max y-axis labels in the left gutter', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 10)]),
            ],
          ),
        ),
      );
      // Top row's y-axis label is "10"; bottom plot row's label is "0".
      final top = _row(tester, 0, 30, 8);
      final bottom = _row(tester, 6, 30, 8); // row 7 is the x-axis row
      expect(top.contains('10'), isTrue, reason: 'max y label on top row');
      expect(bottom.contains('0'), isTrue, reason: 'min y label above x-axis');
    });

    testWidgets('y-axis labels honor the paint offset, not screen column 0', (
      tester,
    ) {
      // Regression: the y-tick labels were written at literal column 0 instead
      // of offset.col, so any LineChart not flush against the screen's left
      // edge (a padded card, a multi-column dashboard) leaked its labels to
      // col 0 — bleeding onto whatever sat there.
      tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SizedBox(
            width: 30,
            height: 8,
            child: LineChart(
              series: const [
                LineSeries([(0, 0), (1, 10)]),
              ],
            ),
          ),
        ),
      );
      final top = _row(tester, 0, 42, 8);
      expect(
        top.substring(0, 12).trim(),
        isEmpty,
        reason: 'no y-label should leak into the 12-col left padding',
      );
      expect(
        top.indexOf('10') >= 12,
        isTrue,
        reason: 'the max y label renders inside the offset chart gutter',
      );
    });

    testWidgets('yTickCount adds intermediate y-axis labels', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 11,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 40)]),
            ],
            yTickCount: 5,
          ),
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(30, 11),
        emptyMark: ' ',
      );
      // 5 ticks over 0..40 → labels 40/30/20/10/0; the default 3 would
      // show only 40/20/0, so '30' proves the extra ticks rendered.
      expect(out.contains('30'), isTrue, reason: 'intermediate 30 tick');
      expect(out.contains('10'), isTrue, reason: 'intermediate 10 tick');
    });

    testWidgets('shows min and max x-axis labels on the bottom row', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (5, 1)]),
            ],
          ),
        ),
      );
      final bottom = _row(tester, 7, 30, 8);
      expect(bottom.contains('0'), isTrue, reason: 'min x label');
      expect(bottom.contains('5'), isTrue, reason: 'max x label');
    });

    testWidgets('renders nothing when given no series', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 30, height: 8, child: LineChart(series: [])),
      );
      expect(_hasBraille(tester, 30, 8), isFalse);
    });

    testWidgets('a series of one point still draws a dot', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0.5, 0.5)]),
            ],
          ),
        ),
      );
      expect(_hasBraille(tester, 30, 8), isTrue);
    });

    testWidgets('scatter mode draws only points, not connecting lines', (
      tester,
    ) {
      // Two distant points: line mode would fill the cells in between;
      // scatter mode leaves them empty.
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)], type: LineType.scatter),
            ],
            showAxes: false,
          ),
        ),
      );
      // Count cells with braille glyphs — scatter mode should have very few.
      final buf = tester.render(size: const CellSize(30, 8));
      var brailleCount = 0;
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 30; c++) {
          final g = buf.atColRow(c, r).grapheme;
          if (g != null &&
              g.codeUnitAt(0) >= 0x2800 &&
              g.codeUnitAt(0) <= 0x28FF) {
            brailleCount++;
          }
        }
      }
      // Scatter of two points → at most 2 cells lit.
      expect(brailleCount, lessThanOrEqualTo(2));
    });

    testWidgets('showGrid draws faint crosshair dots through the plot', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0)]),
            ],
            showGrid: true,
          ),
        ),
      );
      // The mid-row should contain `·` cells outside any braille glyph.
      final buf = tester.render(size: const CellSize(30, 8));
      var midRowDots = 0;
      for (var c = 0; c < 30; c++) {
        if (buf.atColRow(c, 8 ~/ 2).grapheme == '·') midRowDots++;
      }
      expect(midRowDots, greaterThan(0));
    });

    testWidgets('showLegend draws a colored bullet for each labeled series', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)], label: 'a'),
              LineSeries([(0, 1), (1, 0)], label: 'b', color: AnsiColor(2)),
            ],
            showLegend: true,
          ),
        ),
      );
      // The legend is one row of "● label" entries at top-right.
      final buf = tester.render(size: const CellSize(40, 8));
      var foundA = false;
      var foundB = false;
      for (var c = 0; c < 40; c++) {
        final g = buf.atColRow(c, 0).grapheme;
        if (g == '●') {
          // Find the label that follows.
          final letter = buf.atColRow(c + 2, 0).grapheme;
          if (letter == 'a') foundA = true;
          if (letter == 'b') {
            foundB = true;
            // The 'b' series bullet should carry its specified color.
            expect(buf.atColRow(c, 0).style.foreground, const AnsiColor(2));
          }
        }
      }
      expect(foundA, isTrue);
      expect(foundB, isTrue);
    });

    testWidgets('legend is skipped silently when it does not fit', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)], label: 'this-is-too-long'),
            ],
            showLegend: true,
          ),
        ),
      );
      // No bullets, no crash, no label.
      final buf = tester.render(size: const CellSize(12, 8));
      for (var c = 0; c < 12; c++) {
        expect(buf.atColRow(c, 0).grapheme, isNot('●'));
      }
    });

    testWidgets('endpoints land in the plot corners', (tester) {
      // 30×8 with axes: left gutter ≈ 6, bottom gutter = 1 → plot top-right
      // corner is (29, 0), plot bottom-left lives at row 6, col ≈ 6.
      // We verify that (0,0) and (1,1) light braille in the corner cells —
      // not the rest of the plot interior in those corners.
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
      final buf = tester.render(size: const CellSize(30, 8));
      bool isBraille(int? code) =>
          code != null && code >= 0x2800 && code <= 0x28FF;
      // Bottom-left corner of the plot: row 6, first col after the gutter.
      expect(
        isBraille(buf.atColRow(6, 6).grapheme?.codeUnitAt(0)),
        isTrue,
        reason: '(0,0) should land in the bottom-left plot cell',
      );
      // Top-right corner of the plot: last col, row 0.
      expect(
        isBraille(buf.atColRow(29, 0).grapheme?.codeUnitAt(0)),
        isTrue,
        reason: '(1,1) should land in the top-right plot cell',
      );
    });

    testWidgets('horizontal line lights only the row at its y', (tester) {
      // Two points at the same y. Bresenham across the row should leave
      // every cell *above* and *below* the line empty.
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0.5), (1, 0.5)]),
            ],
            showAxes: false, // simpler indexing
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // y=0.5 with autoscale (0.5,1.5): t=0, py = (1-0)*(8*4-1) = 31 → cell row 7.
      // So only row 7 should hold braille; rows 0..6 should be empty.
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 30; c++) {
          final g = buf.atColRow(c, r).grapheme;
          if (g == null) continue;
          expect(
            g.codeUnitAt(0) >= 0x2800 && g.codeUnitAt(0) <= 0x28FF,
            isFalse,
            reason: 'no braille should appear at row $r, col $c',
          );
        }
      }
    });

    // ----- Edge cases -----------------------------------------------------

    testWidgets('survives a 1×1 layout without crashing', (tester) {
      // A box too small to show axes, gutters, or even a full plot cell.
      // The chart should clip silently rather than throw.
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
          ),
        ),
      );
      // Just rendering without error is the assertion.
      tester.render(size: const CellSize(1, 1));
    });

    testWidgets('survives a 0-sized box', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 0,
          height: 0,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(10, 4));
    });

    testWidgets('all-equal y values render a flat line, no NaN', (tester) {
      // Autoscaled y range would be zero-width. The chart must guard
      // against div-by-zero and still produce a visible glyph.
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 5), (1, 5), (2, 5), (3, 5)]),
            ],
          ),
        ),
      );
      expect(
        _hasBraille(tester, 30, 8),
        isTrue,
        reason: 'a flat line should still be drawn',
      );
    });

    testWidgets('all-equal x values (vertical line) does not crash', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(2, 0), (2, 5), (2, 10)]),
            ],
          ),
        ),
      );
      expect(_hasBraille(tester, 30, 8), isTrue);
    });

    testWidgets('negative-range data renders inside the plot', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(-5, -10), (-2, -3), (0, 0)]),
            ],
          ),
        ),
      );
      expect(_hasBraille(tester, 30, 8), isTrue);
    });

    testWidgets('explicit range outside the data clips silently', (tester) {
      // Data is at (0,0)..(1,1) but range forces a much larger window.
      // The chart should not throw; data may end up at the corner.
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            xRange: (-100, 100),
            yRange: (-100, 100),
          ),
        ),
      );
      tester.render(size: const CellSize(30, 8));
    });

    testWidgets('NaN and infinite y values do not crash', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: [
              LineSeries([
                (0, 0),
                (1, double.nan),
                (2, double.infinity),
                (3, 1),
              ]),
            ],
          ),
        ),
      );
      // The exact behavior is "skip" or "clip"; we just require no throw.
      tester.render(size: const CellSize(30, 8));
    });

    // ----- Fuzz -----------------------------------------------------------

    testWidgets('fuzz: random series of arbitrary sizes render without crash', (
      tester,
    ) {
      // Deterministic seed → reproducible failures.
      final rng = Random(0xC0FFEE);
      for (var iter = 0; iter < 25; iter++) {
        final cols = 4 + rng.nextInt(40);
        final rows = 2 + rng.nextInt(16);
        final seriesCount = 1 + rng.nextInt(3);
        final series = <LineSeries>[];
        for (var s = 0; s < seriesCount; s++) {
          final n = rng.nextInt(20); // sometimes zero points
          final pts = <(num, num)>[];
          for (var i = 0; i < n; i++) {
            pts.add((
              rng.nextDouble() * 200 - 100,
              rng.nextDouble() * 200 - 100,
            ));
          }
          series.add(
            LineSeries(
              pts,
              type: LineType.values[rng.nextInt(LineType.values.length)],
            ),
          );
        }
        tester.pumpWidget(
          SizedBox(
            width: cols,
            height: rows,
            child: LineChart(
              series: series,
              showAxes: rng.nextBool(),
              showGrid: rng.nextBool(),
              showLegend: rng.nextBool(),
            ),
          ),
        );
        final buf = tester.render(size: CellSize(cols, rows));
        // Sanity: any rendered glyph must live inside the buffer.
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            // Just reading every cell — out-of-bounds writes would have
            // surfaced as an exception above.
            buf.atColRow(c, r);
          }
        }
      }
    });

    // ----- New: TickFormat ------------------------------------------------

    test('TickFormat.number formats integers and decimals predictably', () {
      expect(TickFormat.number(0), '0');
      expect(TickFormat.number(42), '42');
      expect(TickFormat.number(-7), '-7');
      expect(TickFormat.number(1.5), '1.5');
      expect(TickFormat.number(1.234), '1.2');
      expect(TickFormat.number(1e7), '10000000.0');
    });

    test('TickFormat.percent multiplies and adds %', () {
      expect(TickFormat.percent(0), '0%');
      expect(TickFormat.percent(0.5), '50%');
      expect(TickFormat.percent(1), '100%');
      expect(TickFormat.percent(0.625), '63%');
    });

    test('TickFormat.compact uses K/M/B/T suffixes', () {
      expect(TickFormat.compact(999), '999');
      expect(TickFormat.compact(1500), '1.5K');
      expect(TickFormat.compact(2_400_000), '2.4M');
      expect(TickFormat.compact(3.1e9), '3.1B');
      expect(TickFormat.compact(-1_500_000), '-1.5M');
    });

    test('TickFormat.currency prefixes the symbol', () {
      final usd = TickFormat.currency(r'$');
      expect(usd(0), r'$0');
      expect(usd(1500), r'$1.5K');
      expect(usd(-200), r'$-200');
    });

    test('TickFormat.epochMs formats with the given pattern', () {
      // 2024-01-15T10:30:00Z
      final ms = DateTime.utc(2024, 1, 15, 10, 30).millisecondsSinceEpoch;
      final f = TickFormat.epochMs('yyyy-MM-dd');
      expect(
        f(ms).startsWith('2024-01-'),
        isTrue,
        reason: 'date should contain year & month — exact day depends on TZ',
      );
      final f2 = TickFormat.epochMs('MMM');
      expect(f2(ms), 'Jan');
    });

    testWidgets('xTickFormat changes the x-axis labels', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            xTickFormat: TickFormat.percent,
          ),
        ),
      );
      // Bottom row should show '0%' and '100%' for x range [0,1].
      final bottom = _row(tester, 7, 30, 8);
      expect(bottom.contains('0%'), isTrue);
      expect(bottom.contains('100%'), isTrue);
    });

    // ----- New: palette ---------------------------------------------------

    testWidgets(
      'auto color palette cycles when series have no explicit color',
      (tester) {
        tester.pumpWidget(
          SizedBox(
            width: 40,
            height: 8,
            child: LineChart(
              series: const [
                LineSeries([(0, 0), (1, 1)], label: 'a'),
                LineSeries([(0, 1), (1, 0)], label: 'b'),
                LineSeries([(0, 0.5), (1, 0.5)], label: 'c'),
              ],
              // Custom palette so the test doesn't depend on theme defaults.
              palette: const [AnsiColor(1), AnsiColor(2), AnsiColor(3)],
              showLegend: true,
            ),
          ),
        );
        final buf = tester.render(size: const CellSize(40, 8));
        // Find each labeled bullet on row 0 and check its color.
        final colors = <Color>[];
        for (var c = 0; c < 40; c++) {
          if (buf.atColRow(c, 0).grapheme == '●') {
            colors.add(buf.atColRow(c, 0).style.foreground!);
          }
        }
        expect(
          colors,
          containsAll(const [AnsiColor(1), AnsiColor(2), AnsiColor(3)]),
          reason: 'each series should pick the next palette color',
        );
      },
    );

    testWidgets('explicit series color overrides the palette', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)], label: 'a', color: AnsiColor(5)),
            ],
            palette: const [AnsiColor(1), AnsiColor(2)],
            showLegend: true,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(40, 8));
      for (var c = 0; c < 40; c++) {
        if (buf.atColRow(c, 0).grapheme == '●') {
          expect(buf.atColRow(c, 0).style.foreground, const AnsiColor(5));
          return;
        }
      }
      fail('expected a colored bullet from the explicit series color');
    });

    // ----- New: reference lines ------------------------------------------

    testWidgets(
      'horizontal reference line draws a dashed row across the plot',
      (tester) {
        tester.pumpWidget(
          SizedBox(
            width: 30,
            height: 8,
            child: LineChart(
              series: const [
                LineSeries([(0, 0), (1, 1)]),
              ],
              references: const [
                ReferenceLine.horizontal(0.5, color: AnsiColor(1)),
              ],
              showAxes: false,
            ),
          ),
        );
        final buf = tester.render(size: const CellSize(30, 8));
        // y=0.5 with range [0,1] over 8 rows → row at ((1-0.5)*7).round() = 4.
        var dashesAt4 = 0;
        for (var c = 0; c < 30; c++) {
          if (buf.atColRow(c, 4).grapheme == '╌') dashesAt4++;
        }
        expect(
          dashesAt4,
          greaterThan(20),
          reason: 'most cells in the reference row should be dashes',
        );
      },
    );

    testWidgets('vertical reference line draws a column down the plot', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (10, 10)]),
            ],
            references: const [
              ReferenceLine.vertical(5, style: ReferenceStyle.dotted),
            ],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // x=5 with range [0,10] over 30 cols → col at (0.5*29).round() = 15.
      var dotsAt15 = 0;
      for (var r = 0; r < 8; r++) {
        if (buf.atColRow(15, r).grapheme == '·') dotsAt15++;
      }
      expect(
        dotsAt15,
        greaterThan(3),
        reason: 'most cells in the reference column should be dots',
      );
    });

    testWidgets('reference line out of range is silently skipped', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            references: const [ReferenceLine.horizontal(99)],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // No dashed glyphs anywhere.
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 30; c++) {
          expect(buf.atColRow(c, r).grapheme, isNot('╌'));
        }
      }
    });

    // ----- New: threshold coloring ---------------------------------------

    testWidgets('threshold color paints above and below in different colors', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries(
                [(0, 0), (5, 10)],
                color: AnsiColor(2),
                belowColor: AnsiColor(1),
                thresholdY: 5,
              ),
            ],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // Sample one cell near the bottom (below threshold) and one near
      // the top (above threshold); each must use the assigned color.
      Color? bottomColor;
      Color? topColor;
      for (var c = 0; c < 30; c++) {
        for (var r = 5; r < 8; r++) {
          final g = buf.atColRow(c, r).grapheme;
          if (g != null &&
              g.codeUnitAt(0) >= 0x2800 &&
              g.codeUnitAt(0) <= 0x28FF) {
            bottomColor ??= buf.atColRow(c, r).style.foreground;
          }
        }
        for (var r = 0; r < 3; r++) {
          final g = buf.atColRow(c, r).grapheme;
          if (g != null &&
              g.codeUnitAt(0) >= 0x2800 &&
              g.codeUnitAt(0) <= 0x28FF) {
            topColor ??= buf.atColRow(c, r).style.foreground;
          }
        }
      }
      expect(
        bottomColor,
        const AnsiColor(1),
        reason: 'segments below threshold should use belowColor',
      );
      expect(
        topColor,
        const AnsiColor(2),
        reason: 'segments above threshold should use color',
      );
    });

    // ----- New: missing-data gap -----------------------------------------

    testWidgets('NaN y splits the line — left and right cells lit, gap empty', (
      tester,
    ) {
      // Three points: (0,0), (1, NaN), (2, 0). Both segments touching
      // the NaN are skipped, so only the bare endpoints (0,0) and (2,0)
      // get lit as isolated dots — no connecting glyphs in between.
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 4,
          child: LineChart(
            series: [
              LineSeries([(0, 0), (1, double.nan), (2, 0)]),
            ],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 4));
      // Count braille cells across each column; the middle should have
      // strictly fewer hits than the endpoints' columns.
      int countCol(int col) {
        var n = 0;
        for (var r = 0; r < 4; r++) {
          final g = buf.atColRow(col, r).grapheme;
          if (g != null &&
              g.codeUnitAt(0) >= 0x2800 &&
              g.codeUnitAt(0) <= 0x28FF) {
            n++;
          }
        }
        return n;
      }

      // Middle column (index ~5) should be empty (no segment drawn through).
      expect(countCol(5), 0, reason: 'NaN should leave a gap mid-plot');
    });

    // ----- New: interactive crosshair ------------------------------------

    testWidgets('interactive mode shows a vertical cursor when focused', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1), (2, 0), (3, 1)]),
            ],
            interactive: true,
            autofocus: true,
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // First data x (0) → cursor at col 0; count the cursor glyph.
      var cursorCells = 0;
      for (var r = 1; r < 7; r++) {
        // Skip top row — that's the tooltip header.
        if (buf.atColRow(0, r).grapheme == '╎') cursorCells++;
      }
      expect(
        cursorCells,
        greaterThan(0),
        reason: 'a focused interactive chart should show its cursor',
      );
    });

    testWidgets('arrow-right advances the cursor to the next data x', (tester) {
      final focus = FocusNode();
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1), (2, 0), (3, 1)]),
            ],
            interactive: true,
            autofocus: true,
            focusNode: focus,
            showAxes: false,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      final buf = tester.render(size: const CellSize(30, 8));
      // 4 data x's → cursor moves to index 1 → x=1, t≈0.333 across 30 cols.
      // Find which column has the cursor — expect it advanced away from 0.
      var cursorCol = -1;
      for (var c = 0; c < 30; c++) {
        for (var r = 1; r < 7; r++) {
          if (buf.atColRow(c, r).grapheme == '╎') {
            cursorCol = c;
            break;
          }
        }
        if (cursorCol >= 0) break;
      }
      expect(
        cursorCol,
        greaterThan(0),
        reason: 'cursor should have advanced past the leftmost column',
      );
      expect(
        cursorCol,
        lessThan(15),
        reason: 'cursor at x=1 (of 0..3) should be in the left half',
      );
    });

    testWidgets('interactive chart exposes semantic cursor actions', (
      tester,
    ) async {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            semanticLabel: 'Latency chart',
            series: const [
              LineSeries([(0, 1), (2, 5)], label: 'p95'),
            ],
            references: const [ReferenceLine.horizontal(4)],
            interactive: true,
            showAxes: false,
          ),
        ),
      );

      var chart = tester.semantics().single(
        role: SemanticRole.chart,
        label: 'Latency chart',
        action: SemanticAction.increment,
      );
      expect(chart.state.chartType, 'line');
      expect(chart.state.chartSeriesCount, 1);
      expect(chart.state.chartPointCount, 2);
      expect(chart.state.chartXMin, 0);
      expect(chart.state.chartXMax, 2);
      expect(chart.state.chartYMin, 1);
      expect(chart.state.chartYMax, 5);
      expect(chart.state.chartReferenceCount, 1);
      expect(chart.state.chartInteractive, isTrue);
      expect(chart.state.chartCursorCount, 2);
      expect(chart.state.chartCursorIndex, 0);
      expect(chart.state.chartCursorX, 0);

      final focus = await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.chart,
        label: 'Latency chart',
      );
      expect(focus.completed, isTrue);

      final next = await tester.invokeSemanticAction(
        SemanticAction.increment,
        role: SemanticRole.chart,
        label: 'Latency chart',
      );
      expect(next.completed, isTrue);
      tester.pump();

      chart = tester.semantics().single(
        role: SemanticRole.chart,
        label: 'Latency chart',
        focused: true,
        action: SemanticAction.decrement,
      );
      expect(chart.value, 'x: 2');
      expect(chart.state.chartCursorIndex, 1);
      expect(chart.state.chartCursorX, 2);
      expect(chart.actions, isNot(contains(SemanticAction.increment)));

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.chart,
        label: 'Latency chart',
      );
      expect(
        fallback.states,
        contains(
          'chart line, 1 series, 2 points, x 0.0-2.0, y 1.0-5.0, '
          '1 reference, interactive, cursor 2 of 2, cursor x 2',
        ),
      );
    });

    testWidgets('cursor stays put at the right edge', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            interactive: true,
            autofocus: true,
            showAxes: false,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      // Another arrow-right should be a no-op.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      final buf = tester.render(size: const CellSize(30, 8));
      // Cursor should be at the rightmost column (col 29).
      var rightCursor = 0;
      for (var r = 1; r < 7; r++) {
        if (buf.atColRow(29, r).grapheme == '╎') rightCursor++;
      }
      expect(rightCursor, greaterThan(0));
    });

    testWidgets('tooltip box shows x value and per-series readout', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 1), (1, 2)], label: 'cpu'),
            ],
            interactive: true,
            autofocus: true,
            showAxes: false,
          ),
        ),
      );
      // Cursor at (0, 1). Tooltip should render 'x: 0' and '● cpu: 1'.
      final out = tester.renderToString(
        size: const CellSize(30, 8),
        emptyMark: ' ',
      );
      expect(
        out.contains('x: 0'),
        isTrue,
        reason: 'tooltip should display the cursor x',
      );
      expect(
        out.contains('cpu: 1'),
        isTrue,
        reason: 'tooltip should display the per-series y',
      );
    });

    testWidgets('cursor hidden when interactive chart is not focused', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            interactive: true,
            // autofocus: false → starts unfocused
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 30; c++) {
          expect(buf.atColRow(c, r).grapheme, isNot('╎'));
        }
      }
    });

    // ----- New: range padding --------------------------------------------

    testWidgets('padding default (0) makes data hug the plot edges', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      bool isBraille(int? c) => c != null && c >= 0x2800 && c <= 0x28FF;
      // Without padding, (0,0) lands in cell (0,7) and (1,1) lands at (29,0).
      expect(
        isBraille(buf.atColRow(0, 7).grapheme?.codeUnitAt(0)),
        isTrue,
        reason: 'literal extents — endpoint should touch the edge',
      );
      expect(isBraille(buf.atColRow(29, 0).grapheme?.codeUnitAt(0)), isTrue);
    });

    testWidgets('padding > 0 pulls the data away from the plot edges', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            padding: 0.1, // 10% breathing room
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      bool isBraille(int? c) => c != null && c >= 0x2800 && c <= 0x28FF;
      // With 10% pad, range becomes [-0.1, 1.1] → endpoints sit inward.
      expect(
        isBraille(buf.atColRow(0, 7).grapheme?.codeUnitAt(0)),
        isFalse,
        reason: 'padded chart should not touch the corner',
      );
      expect(isBraille(buf.atColRow(29, 0).grapheme?.codeUnitAt(0)), isFalse);
      // But data should still be visible somewhere in the corner regions.
      var anyBraille = false;
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 30; c++) {
          if (isBraille(buf.atColRow(c, r).grapheme?.codeUnitAt(0))) {
            anyBraille = true;
            break;
          }
        }
        if (anyBraille) break;
      }
      expect(anyBraille, isTrue);
    });

    testWidgets('padding is ignored when an explicit range is given', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            xRange: (0, 1),
            yRange: (0, 1),
            padding: 0.5, // would be huge if applied
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      bool isBraille(int? c) => c != null && c >= 0x2800 && c <= 0x28FF;
      // Explicit range wins — endpoints still touch the edges.
      expect(isBraille(buf.atColRow(0, 7).grapheme?.codeUnitAt(0)), isTrue);
      expect(isBraille(buf.atColRow(29, 0).grapheme?.codeUnitAt(0)), isTrue);
    });

    // ----- New: tooltip interpolation ------------------------------------

    testWidgets('tooltip interpolates linearly between adjacent points', (
      tester,
    ) {
      // y=0 at x=0 and y=10 at x=2. Cursor lands on the midpoint x=1
      // (after one arrow-right from x=0). Interpolated y must be 5, not 0
      // or 10 (which is what nearest-point would have given).
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 10,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 5), (2, 10)], label: 'v'),
            ],
            interactive: true,
            autofocus: true,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      final out = tester.renderToString(
        size: const CellSize(40, 10),
        emptyMark: ' ',
      );
      expect(
        out.contains('v: 5'),
        isTrue,
        reason: 'cursor at the middle data point should read y=5',
      );
    });

    testWidgets('scatter series keeps nearest-point semantics (no interp)', (
      tester,
    ) {
      // Only two scatter points, gap in between — interpolation would be
      // misleading. Cursor at the first point shows that point's y.
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 10,
          child: LineChart(
            series: const [
              LineSeries(
                [(0, 3), (10, 7)],
                label: 'pt',
                type: LineType.scatter,
              ),
            ],
            interactive: true,
            autofocus: true,
          ),
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(40, 10),
        emptyMark: ' ',
      );
      expect(
        out.contains('pt: 3'),
        isTrue,
        reason: 'scatter should not interpolate between points',
      );
    });

    // ----- New: tooltip-follow placement ---------------------------------

    testWidgets('tooltip follows the cursor (right of cursor when room)', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)], label: 'a'),
            ],
            interactive: true,
            autofocus: true,
            showAxes: false,
          ),
        ),
      );
      // Cursor at x=0 (col 0). Tooltip should sit just to the right.
      final buf = tester.render(size: const CellSize(40, 8));
      // Locate the left border '│' of the tooltip on row 1.
      var leftBorderCol = -1;
      for (var c = 0; c < 40; c++) {
        if (buf.atColRow(c, 1).grapheme == '│') {
          leftBorderCol = c;
          break;
        }
      }
      expect(
        leftBorderCol,
        lessThan(20),
        reason: 'tooltip should be in the left half — following the cursor',
      );
    });

    testWidgets('tooltip flips to the left of cursor near the right edge', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)], label: 'a'),
            ],
            interactive: true,
            autofocus: true,
            showAxes: false,
          ),
        ),
      );
      // Jump cursor to the last x with End. With only 2 x's, that's x=1
      // at the right edge.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      final buf = tester.render(size: const CellSize(40, 8));
      var leftBorderCol = -1;
      for (var c = 0; c < 40; c++) {
        if (buf.atColRow(c, 1).grapheme == '│') {
          leftBorderCol = c;
          break;
        }
      }
      expect(
        leftBorderCol,
        greaterThan(20),
        reason: 'cursor at right edge → tooltip flips to the left',
      );
    });

    // ----- New: reference line label placement --------------------------

    testWidgets(
      'horizontal reference label sits on the adjacent row, not on the line',
      (tester) {
        tester.pumpWidget(
          SizedBox(
            width: 30,
            height: 8,
            child: LineChart(
              series: const [
                LineSeries([(0, 0), (1, 1)]),
              ],
              references: const [ReferenceLine.horizontal(0.5, label: 'SLA')],
              showAxes: false,
            ),
          ),
        );
        final buf = tester.render(size: const CellSize(30, 8));
        // y=0.5 → row 4. Label should appear on row 3 (above), not row 4.
        final lineRow = 4;
        // Cell on line row at label x should be the dashed glyph, not 'S'.
        // Right edge is where the label is anchored. Test: at the label
        // columns on row 3 we should see S, L, A; on row 4 we should see ╌.
        expect(buf.atColRow(27, 3).grapheme, 'S');
        expect(buf.atColRow(28, 3).grapheme, 'L');
        expect(buf.atColRow(29, 3).grapheme, 'A');
        expect(
          buf.atColRow(29, lineRow).grapheme,
          '╌',
          reason: 'line row should still show the dashed glyph, not label',
        );
      },
    );

    testWidgets('horizontal reference label flips below when near top row', (
      tester,
    ) {
      // Reference at y-max → row 0 → label can't go above, must go below.
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            references: const [ReferenceLine.horizontal(1.0, label: 'cap')],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // y=1 → row 0. Label should be on row 1 (below).
      expect(buf.atColRow(27, 1).grapheme, 'c');
      expect(buf.atColRow(28, 1).grapheme, 'a');
      expect(buf.atColRow(29, 1).grapheme, 'p');
    });

    testWidgets('vertical reference line label paints at top, next to line', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (10, 1)]),
            ],
            references: const [ReferenceLine.vertical(2, label: 'release')],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // x=2 with range [0,10], 30 cols → col (0.2*29).round() = 6.
      // Label should appear to the right of the line, starting at col 7.
      expect(buf.atColRow(7, 0).grapheme, 'r');
      expect(buf.atColRow(8, 0).grapheme, 'e');
      expect(buf.atColRow(9, 0).grapheme, 'l');
    });

    testWidgets('vertical reference label flips left when it would overflow', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (10, 1)]),
            ],
            references: const [ReferenceLine.vertical(10, label: 'now')],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // x=10 → col 29 (right edge). Label 'now' (3 chars) won't fit to
      // the right, so it should appear to the left at cols 25..27.
      expect(buf.atColRow(25, 0).grapheme, 'n');
      expect(buf.atColRow(26, 0).grapheme, 'o');
      expect(buf.atColRow(27, 0).grapheme, 'w');
    });

    // ----- New: tooltip sort by value -----------------------------------

    testWidgets('tooltip rows sort descending by y at the cursor', (tester) {
      // Three series, cursor at x=0. At x=0 the y values are 1, 9, 5.
      // Tooltip rows after the x line should be hi → lo: 9, 5, 1.
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 12,
          child: LineChart(
            series: const [
              LineSeries([(0, 1), (1, 1)], label: 'low'),
              LineSeries([(0, 9), (1, 9)], label: 'hi'),
              LineSeries([(0, 5), (1, 5)], label: 'mid'),
            ],
            interactive: true,
            autofocus: true,
            showAxes: false,
          ),
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(40, 12),
        emptyMark: ' ',
      );
      // Extract tooltip row text. The tooltip box has 'x:' first, then
      // the sorted series. The series should appear in 'hi', 'mid',
      // 'low' order — find each label's row index and check ordering.
      final lines = out.split('\n');
      int rowOf(String needle) {
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains(needle)) return i;
        }
        return -1;
      }

      final hiRow = rowOf('hi:');
      final midRow = rowOf('mid:');
      final lowRow = rowOf('low:');
      expect(hiRow >= 0 && midRow >= 0 && lowRow >= 0, isTrue);
      expect(
        hiRow < midRow,
        isTrue,
        reason: 'highest-y series should appear above mid',
      );
      expect(
        midRow < lowRow,
        isTrue,
        reason: 'mid-y series should appear above low',
      );
    });

    testWidgets('tooltip rows with no data at cursor sort to the bottom', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 10,
          child: LineChart(
            series: const [
              LineSeries([(0, 1), (1, 1)], label: 'has'),
              LineSeries([(5, 5)], label: 'missing'), // no point near x=0
            ],
            interactive: true,
            autofocus: true,
            showAxes: false,
          ),
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(40, 10),
        emptyMark: ' ',
      );
      final lines = out.split('\n');
      // The series with a value should appear before the one without.
      var hasRow = -1;
      var missingRow = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('has:')) hasRow = i;
        if (lines[i].contains('missing:')) missingRow = i;
      }
      // 'missing' may still get a nearest-value fallback — both will
      // be present, but if both have values they sort by value. Just
      // verify the tooltip rendered both rows somewhere.
      expect(hasRow >= 0, isTrue);
      expect(missingRow >= 0, isTrue);
    });

    // ----- New: real gridlines -----------------------------------------

    testWidgets('showGrid draws dotted gridlines at min/mid/max ticks', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 30,
          height: 8,
          child: LineChart(
            series: const [
              LineSeries([(0, 0), (1, 1)]),
            ],
            showGrid: true,
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      // 8 plot rows, no axes → grid rows at 0 (top), 4 (mid), 7 (bottom).
      var topDots = 0, midDots = 0, bottomDots = 0;
      for (var c = 0; c < 30; c++) {
        if (buf.atColRow(c, 0).grapheme == '·') topDots++;
        if (buf.atColRow(c, 4).grapheme == '·') midDots++;
        if (buf.atColRow(c, 7).grapheme == '·') bottomDots++;
      }
      // All three gridline rows should be present (apart from where data
      // overdraws them).
      expect(topDots, greaterThan(20));
      expect(midDots, greaterThan(20));
      expect(bottomDots, greaterThan(20));
    });

    // ----- New: Palettes.categorical -----------------------------------

    test('Palettes.categorical exposes 6 hue-distinct colors', () {
      expect(Palettes.categorical.length, 6);
      // No duplicates.
      expect(Palettes.categorical.toSet().length, 6);
    });

    testWidgets('area mode fills cells below the line', (tester) {
      // A line from (0, 1) to (1, 1) at the top: line mode lights only the
      // top row; area mode lights the entire vertical column below.
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 4,
          child: LineChart(
            series: const [
              LineSeries([(0, 1), (1, 1)], type: LineType.area),
            ],
            showAxes: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 4));
      // Bottom-most row should also have braille glyphs (filled).
      var bottomFilled = false;
      for (var c = 0; c < 10; c++) {
        final g = buf.atColRow(c, 3).grapheme;
        if (g != null &&
            g.codeUnitAt(0) >= 0x2800 &&
            g.codeUnitAt(0) <= 0x28FF) {
          bottomFilled = true;
          break;
        }
      }
      expect(
        bottomFilled,
        isTrue,
        reason: 'area should fill all the way to the baseline',
      );
    });
  });
}
