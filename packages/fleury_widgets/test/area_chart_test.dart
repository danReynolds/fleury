import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('AreaChart', () {
    testWidgets('fills with solid block columns, not braille', (tester) {
      tester.pumpWidget(
        AreaChart(
          series: const [
            AreaSeries(
              [(0, 2), (1, 8), (2, 4), (3, 9), (4, 3)],
              gradient: [
                RgbColor(0, 200, 100),
                RgbColor(240, 190, 40),
                RgbColor(255, 90, 90),
              ],
            ),
          ],
          showAxes: false,
          yRange: (0, 10),
        ),
      );
      final buf = tester.render(size: const CellSize(24, 8));
      var braille = 0;
      var blocks = 0;
      final colors = <Color>{};
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 24; c++) {
          final cell = buf.atColRow(c, r);
          final g = cell.grapheme;
          if (g == null || g.isEmpty) continue;
          final cp = g.runes.first;
          if (cp >= 0x2800 && cp <= 0x28FF) braille++;
          if (cp >= 0x2581 && cp <= 0x2588) {
            blocks++;
            final fg = cell.style.foreground;
            if (fg != null) colors.add(fg);
          }
        }
      }
      expect(braille, 0, reason: 'AreaChart must not use braille');
      expect(blocks, greaterThan(8), reason: 'the region should be filled');
      expect(
        colors.length,
        greaterThan(1),
        reason: 'the gradient should produce more than one color',
      );
    });

    testWidgets('a flat color fills solid in a single color', (tester) {
      tester.pumpWidget(
        AreaChart(
          series: const [
            AreaSeries(
              [(0, 2), (1, 8), (2, 4), (3, 9)],
              color: RgbColor(0, 200, 100),
            ),
          ],
          showAxes: false,
          yRange: (0, 10),
        ),
      );
      final buf = tester.render(size: const CellSize(24, 8));
      final colors = <Color>{};
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 24; c++) {
          final cell = buf.atColRow(c, r);
          final g = cell.grapheme;
          if (g == null || g.isEmpty) continue;
          final cp = g.runes.first;
          if (cp >= 0x2581 && cp <= 0x2588) {
            final fg = cell.style.foreground;
            if (fg != null) colors.add(fg);
          }
        }
      }
      expect(colors, {const RgbColor(0, 200, 100)});
    });

    testWidgets('an empty palette falls back instead of throwing', (tester) {
      // Regression: the empty-list guard was inverted and indexed [0] into the
      // empty list, replacing the whole chart with the framework error box.
      tester.pumpWidget(
        AreaChart(
          series: const [
            AreaSeries([(0, 1), (1, 5), (2, 3)]),
          ],
          palette: const [],
        ),
      );
      final buf = tester.render(size: const CellSize(24, 8));
      expect(
        _glyphCount(buf, 24, 8, 0x2581, 0x2588),
        greaterThan(0),
        reason: 'the chart should still render its fill',
      );
    });

    testWidgets('constant data still renders a visible fill', (tester) {
      // Regression: a degenerate range padded only upward, pinning the series
      // to the baseline where an area fill has zero height and vanished.
      tester.pumpWidget(
        AreaChart(
          series: const [
            AreaSeries([(0, 5), (1, 5), (2, 5), (3, 5)]),
          ],
        ),
      );
      final buf = tester.render(size: const CellSize(30, 8));
      expect(
        _glyphCount(buf, 30, 8, 0x2581, 0x2588),
        greaterThan(0),
        reason: 'a flat series must not autoscale itself invisible',
      );
    });

    testWidgets('an empty gradient keeps the solid-fill contract', (tester) {
      // Regression: `gradient: []` fell through to LineChart's braille area.
      tester.pumpWidget(
        AreaChart(
          series: const [
            AreaSeries([(0, 1), (1, 6), (2, 3)], gradient: []),
          ],
        ),
      );
      final buf = tester.render(size: const CellSize(24, 8));
      expect(
        _glyphCount(buf, 24, 8, 0x2800, 0x28FF),
        0,
        reason: 'AreaChart must not use braille',
      );
      expect(_glyphCount(buf, 24, 8, 0x2581, 0x2588), greaterThan(0));
    });

    testWidgets('a lone point fills its column', (tester) {
      // Regression: sampling only walked segments, so a one-point series had
      // no segment to interpolate and drew nothing at all.
      tester.pumpWidget(
        AreaChart(
          series: const [
            AreaSeries([(2, 6)]),
          ],
        ),
      );
      final buf = tester.render(size: const CellSize(24, 8));
      expect(
        _glyphCount(buf, 24, 8, 0x2581, 0x2588),
        greaterThan(0),
        reason: 'a lone point should still fill its own column',
      );
    });
  });
}

/// Cells whose glyph falls in the inclusive codepoint range [lo], [hi].
int _glyphCount(CellBuffer buf, int cols, int rows, int lo, int hi) {
  var found = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final g = buf.atColRow(c, r).grapheme;
      if (g == null || g.isEmpty) continue;
      final cp = g.runes.first;
      if (cp >= lo && cp <= hi) found++;
    }
  }
  return found;
}
