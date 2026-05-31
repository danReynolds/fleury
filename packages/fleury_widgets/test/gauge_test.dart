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
  });
}
