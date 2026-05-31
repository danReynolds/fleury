import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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
  });
}
