import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

// The DST regression only manifests in a zone that actually observes the
// autumn fall-back / spring-forward transitions (a 25h / 23h civil day). The
// dev tool pins `TZ=America/New_York` for the fleury_widgets test run (see
// `_run(... workingDirectory: widgets, environment: {'TZ': ...})` in
// tool/fleury_dev.dart), so `dart tool/fleury_dev.dart check` runs these
// locally and in CI. In a fixed-offset zone (e.g. a bare `dart test` under
// UTC) the buggy and fixed date math agree, so the checks would be vacuous;
// skip with a clear reason there instead of asserting nothing.
bool _hasFallBack2026() =>
    DateTime(2026, 11, 2).difference(DateTime(2026, 11, 1)).inHours == 25;
bool _hasSpringForward2026() =>
    DateTime(2026, 3, 9).difference(DateTime(2026, 3, 8)).inHours == 23;

final Object _dstSkip = _hasFallBack2026() && _hasSpringForward2026()
    ? false
    : 'requires a DST timezone (run with TZ=America/New_York)';

void main() {
  group('CalendarHeatmap', () {
    testWidgets(
      'lays out 7 day rows (Sun-first by default) and one column per week',
      (tester) {
        // A 14-day window starting on Monday spans 3 weeks with Sun-first
        // anchoring (the GitHub-canonical layout).
        final start = DateTime(2024, 1, 1); // Monday
        final end = DateTime(2024, 1, 14); // Sunday
        tester.pumpWidget(
          SizedBox(
            width: 12,
            height: 8,
            child: CalendarHeatmap(
              start: start,
              end: end,
              values: const {},
              cellWidth: 1,
            ),
          ),
        );
        // Sun-first: rows are Sun, Mon, Tue, Wed, Thu, Fri, Sat. With one
        // month-label row above the grid, Mon → row 2, Wed → row 4, Fri → 6.
        final buf = tester.render(size: const CellSize(12, 8));
        expect(buf.atColRow(0, 2).grapheme, 'M');
        expect(buf.atColRow(1, 2).grapheme, 'o');
        expect(buf.atColRow(2, 2).grapheme, 'n');
        expect(buf.atColRow(0, 4).grapheme, 'W');
        expect(buf.atColRow(0, 6).grapheme, 'F');
      },
    );

    testWidgets('Mon-first opt-in puts Mon at the top row', (tester) {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 1, 14);
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 8,
          child: CalendarHeatmap(
            start: start,
            end: end,
            values: const {},
            cellWidth: 1,
            weekStartsOn: CalendarWeekStart.monday,
          ),
        ),
      );
      // Mon-first: rows are Mon, Tue, Wed, Thu, Fri, Sat, Sun.
      // Mon → row 1, Wed → row 3, Fri → row 5.
      final buf = tester.render(size: const CellSize(12, 8));
      expect(buf.atColRow(0, 1).grapheme, 'M');
      expect(buf.atColRow(0, 3).grapheme, 'W');
      expect(buf.atColRow(0, 5).grapheme, 'F');
    });

    testWidgets('renders one cell per day at the right (week, dow) position', (
      tester,
    ) {
      // Wed Jan 3 2024, Sun-first → week 0, dow 3 (Sun=0, Wed=3).
      // gridTop = 1 (month row) → row 1 + 3 = 4.
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 1),
            end: DateTime(2024, 1, 14),
            values: {DateTime(2024, 1, 3): 1},
            min: 0,
            max: 1,
            cellWidth: 1,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(12, 8));
      expect(buf.atColRow(4, 4).grapheme, '█');
    });

    testWidgets('values outside [start, end] are ignored', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 6, 1),
            end: DateTime(2024, 6, 14),
            values: {DateTime(2024, 1, 1): 999},
            min: 0,
            max: 1,
            cellWidth: 1,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(12, 8));
      // No data in window → no fills (no `·` either).
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 12; c++) {
          final g = buf.atColRow(c, r).grapheme;
          expect(['·', '░', '▒', '▓', '█'].contains(g), isFalse);
        }
      }
    });

    testWidgets('intensity ladder maps to ·░▒▓█ (5 steps)', (tester) {
      // Mon=row 2 .. Fri=row 6 in Sun-first. Place values so all five
      // ladder steps appear in order.
      tester.pumpWidget(
        SizedBox(
          width: 8,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 1), // Mon
            end: DateTime(2024, 1, 7), // Sun
            values: {
              DateTime(2024, 1, 1): 0, // Mon → ·  (recorded zero)
              DateTime(2024, 1, 2): 0.25, // Tue → ░
              DateTime(2024, 1, 3): 0.5, // Wed → ▒
              DateTime(2024, 1, 4): 0.75, // Thu → ▓
              DateTime(2024, 1, 5): 1.0, // Fri → █
            },
            min: 0,
            max: 1,
            cellWidth: 1,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(8, 8));
      // gridTop=1, Sun=0 → row 1+1=2 for Mon, then +1 each subsequent day.
      expect(buf.atColRow(4, 2).grapheme, '·'); // Mon
      expect(buf.atColRow(4, 3).grapheme, '░'); // Tue
      expect(buf.atColRow(4, 4).grapheme, '▒'); // Wed
      expect(buf.atColRow(4, 5).grapheme, '▓'); // Thu
      expect(buf.atColRow(4, 6).grapheme, '█'); // Fri
    });

    testWidgets('below-min and above-max values clamp to the end buckets', (
      tester,
    ) {
      // Explicit min=1, max=2. Values 0 (below) and 5 (above) should
      // clamp to · and █ rather than disappear.
      tester.pumpWidget(
        SizedBox(
          width: 8,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 1),
            end: DateTime(2024, 1, 7),
            values: {
              DateTime(2024, 1, 1): 0, // below min → ·
              DateTime(2024, 1, 2): 5, // above max → █
            },
            min: 1,
            max: 2,
            cellWidth: 1,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(8, 8));
      expect(
        buf.atColRow(4, 2).grapheme,
        '·',
        reason: 'below-min should clamp to the dim dot, not vanish',
      );
      expect(
        buf.atColRow(4, 3).grapheme,
        '█',
        reason: 'above-max should clamp to the full block',
      );
    });

    testWidgets(
      'month label appears at the week containing the 1st of each month',
      (tester) {
        // GitHub convention: label only months whose 1st day is in the
        // window, anchored to the week containing that 1st. Span Jan 22
        // → Feb 11: Jan 1 is BEFORE start (no Jan label), Feb 1 is in
        // the window (gets a label).
        //
        // Sun-first anchor: Sunday on or before Jan 22 (Mon) → Jan 21.
        // Week 0 = Jan 21–27, Week 1 = Jan 28–Feb 3 (contains Feb 1).
        // No day labels → gridLeft = 0; cellWidth = 2 → 'Feb' at col 2.
        tester.pumpWidget(
          SizedBox(
            width: 20,
            height: 8,
            child: CalendarHeatmap(
              start: DateTime(2024, 1, 22),
              end: DateTime(2024, 2, 11),
              values: const {},
              cellWidth: 2,
              showDayLabels: false,
            ),
          ),
        );
        final buf = tester.render(size: const CellSize(20, 8));
        expect(buf.atColRow(2, 0).grapheme, 'F');
        expect(buf.atColRow(3, 0).grapheme, 'e');
        expect(buf.atColRow(4, 0).grapheme, 'b');
        // No stray previous-month label in earlier cols.
        expect(buf.atColRow(0, 0).grapheme, isNull);
        expect(buf.atColRow(1, 0).grapheme, isNull);
      },
    );

    testWidgets('months whose 1st is before the window are not labeled', (
      tester,
    ) {
      // Start Jan 5 — Jan 1 is before, so no 'Jan' header.
      tester.pumpWidget(
        SizedBox(
          width: 20,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 5),
            end: DateTime(2024, 1, 20),
            values: const {},
            cellWidth: 2,
            showDayLabels: false,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(20, 8));
      for (var c = 0; c < 20; c++) {
        expect(
          buf.atColRow(c, 0).grapheme,
          isNull,
          reason: 'no month label when no 1st falls in the window',
        );
      }
    });

    testWidgets('uses the supplied color for filled cells', (tester) {
      // Mon Jan 1 with Sun-first → row 2.
      tester.pumpWidget(
        SizedBox(
          width: 6,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 1),
            end: DateTime(2024, 1, 7),
            values: {DateTime(2024, 1, 1): 1},
            min: 0,
            max: 1,
            color: const AnsiColor(2),
            cellWidth: 1,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(6, 8));
      expect(buf.atColRow(4, 2).style.foreground, const AnsiColor(2));
    });

    testWidgets('autoscales when min/max are omitted', (tester) {
      // Values 1 and 4. Autoscale → lo=1, hi=4. Mon's value = lo → t=0
      // → `·` (dim dot). Tue's value = hi → t=1 → `█`. Mon-first opt-in
      // so the test rows match the natural reading order.
      tester.pumpWidget(
        SizedBox(
          width: 8,
          height: 8,
          child: CalendarHeatmap(
            start: DateTime(2024, 1, 1),
            end: DateTime(2024, 1, 7),
            values: {
              DateTime(2024, 1, 1): 1, // low end
              DateTime(2024, 1, 2): 4, // high end
            },
            weekStartsOn: CalendarWeekStart.monday,
            cellWidth: 1,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(8, 8));
      expect(buf.atColRow(4, 1).grapheme, '·');
      expect(buf.atColRow(4, 2).grapheme, '█');
    });

    testWidgets(
      'fall-back DST day maps to exactly one cell — no dup, shift, or drop',
      (tester) {
        // America/New_York fall-back is Nov 1 2026 (a 25h civil day). Oct 25
        // (Sun) → Nov 7 (Sat) is exactly two Sun-first weeks. Stepping days
        // with add(Duration(days:)) drifts to 23:00 of the previous date once
        // past the transition, which snapped Nov 1 onto BOTH the Sun and Mon
        // rows and pushed Nov 7 out of every cell slot.
        tester.pumpWidget(
          SizedBox(
            width: 12,
            height: 8,
            child: CalendarHeatmap(
              start: DateTime(2026, 10, 25),
              end: DateTime(2026, 11, 7),
              values: {
                DateTime(2026, 11, 1): 4, // transition day → █
                DateTime(2026, 11, 7): 1, // range end → ░
              },
              min: 0,
              max: 4,
              cellWidth: 1,
            ),
          ),
        );
        final buf = tester.render(size: const CellSize(12, 8));
        int countGlyph(String glyph) {
          var n = 0;
          for (var r = 0; r < 8; r++) {
            for (var c = 0; c < 12; c++) {
              if (buf.atColRow(c, r).grapheme == glyph) n++;
            }
          }
          return n;
        }

        expect(
          countGlyph('█'),
          1,
          reason: 'the fall-back day must render once, not on two rows',
        );
        expect(
          countGlyph('░'),
          1,
          reason: 'the range-end day must not be dropped by the 23:00 drift',
        );
      },
      skip: _dstSkip,
    );

    testWidgets(
      'spring-forward day count is not truncated by the 23h day',
      (tester) {
        // America/New_York spring-forward is Mar 8 2026 (a 23h civil day). A
        // range spanning it must still count every calendar day; the old
        // difference().inDays swallowed the short day and under-reported.
        tester.pumpWidget(
          SizedBox(
            width: 20,
            height: 8,
            child: CalendarHeatmap(
              semanticLabel: 'Activity',
              start: DateTime(2026, 3, 7),
              end: DateTime(2026, 3, 10),
              values: const {},
              cellWidth: 1,
            ),
          ),
        );
        final chart = tester.semantics().single(
          role: SemanticRole.chart,
          label: 'Activity',
        );
        // Mar 7, 8, 9, 10 inclusive = 4 calendar days.
        expect(chart.state.chartPointCount, 4);
      },
      skip: _dstSkip,
    );

    testWidgets('zero-day window renders nothing safely', (tester) {
      final d = DateTime(2024, 1, 1);
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 8,
          child: CalendarHeatmap(
            start: d,
            end: d.subtract(const Duration(days: 1)),
            values: const {},
          ),
        ),
      );
      tester.render(size: const CellSize(10, 8));
    });

    testWidgets('exposes chart semantics and text-first fallback', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 8,
          child: CalendarHeatmap(
            semanticLabel: 'Release activity',
            start: DateTime(2024, 1, 1),
            end: DateTime(2024, 1, 14),
            values: {
              DateTime(2024, 1, 1, 12): 0,
              DateTime(2024, 1, 3): 4,
              DateTime(2024, 2, 1): 99,
            },
            weekStartsOn: CalendarWeekStart.monday,
            cellWidth: 1,
          ),
        ),
      );

      final chart = tester.semantics().single(
        role: SemanticRole.chart,
        label: 'Release activity',
      );
      expect(chart.state.chartType, 'calendarHeatmap');
      expect(chart.state.chartRowCount, 7);
      expect(chart.state.chartColumnCount, 2);
      expect(chart.state.chartPointCount, 14);
      expect(chart.state.chartRecordedPointCount, 2);
      expect(chart.state.chartMinValue, 0);
      expect(chart.state.chartMaxValue, 4);
      expect(chart.state.chartStartDate, '2024-01-01');
      expect(chart.state.chartEndDate, '2024-01-14');
      expect(chart.state.chartWeekStart, 'monday');
      expect(
        tester.render(size: const CellSize(12, 8)).atColRow(4, 1).grapheme,
        '·',
        reason: 'time-of-day keys should bucket into their calendar day',
      );

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.chart,
        label: 'Release activity',
      );
      expect(
        fallback.states,
        contains(
          'chart calendarHeatmap, 7 rows, 2 columns, 14 points, '
          '2 recorded, min 0, max 4, 2024-01-01 to 2024-01-14, '
          'week starts monday',
        ),
      );
    });
  });
}
