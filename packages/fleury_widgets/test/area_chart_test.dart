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
  });
}
