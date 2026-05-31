import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<String> _rows(FleuryTester tester, int cols, int rows) => tester
    .renderToString(size: CellSize(cols, rows), emptyMark: ' ')
    .split('\n');

void main() {
  group('Histogram', () {
    testWidgets('bins values and renders the counts as bars', (tester) {
      // Range (0, 2) in 3 equal bins → edges (0, 0.667, 1.333, 2.0).
      // 0.1, 0.2, 0.3 → bin 0 (3); 1.0 → bin 1 (1); 1.5, 2.0 → bin 2 (2).
      tester.pumpWidget(
        const SizedBox(
          width: 5,
          height: 5,
          child: Histogram(
            values: [0.1, 0.2, 0.3, 1.0, 1.5, 2.0],
            bins: 3,
            range: (0, 2),
            barWidth: 1,
            gap: 1,
            showLabels: false,
            showValues: true,
          ),
        ),
      );
      final out = _rows(tester, 5, 5);
      expect(out[0], '3 1 2');
    });

    testWidgets('autoscales when range is omitted', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 5,
          height: 3,
          child: Histogram(
            values: [0, 1, 2, 3, 4],
            bins: 5,
            range: null,
            barWidth: 1,
            gap: 0,
            showLabels: false,
          ),
        ),
      );
      // One value per bin → all bins count 1 → all bars equal height.
      // Just assert that something rendered (each bar = '█').
      final out = _rows(tester, 5, 3);
      expect(out[0].trim().isNotEmpty, isTrue);
    });

    testWidgets('single value with a single bin does not crash', (tester) {
      // Degenerate: one value, one bin — min == max would make the bin
      // edges collapse. The widget should still render something safely.
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 3,
          child: Histogram(
            values: [5],
            bins: 1,
            barWidth: 1,
            showLabels: false,
          ),
        ),
      );
      tester.render(size: const CellSize(3, 3));
    });

    testWidgets('all-equal values do not crash', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 5,
          height: 3,
          child: Histogram(
            values: [3, 3, 3, 3],
            bins: 4,
            barWidth: 1,
            gap: 0,
            showLabels: false,
          ),
        ),
      );
      tester.render(size: const CellSize(5, 3));
    });

    testWidgets('empty input renders nothing', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 5, height: 5, child: Histogram(values: [])),
      );
      expect(_rows(tester, 5, 5).join().trim(), '');
    });
  });
}
