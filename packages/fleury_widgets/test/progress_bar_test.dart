import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _bar(FleuryTester tester, {int cols = 10}) {
  final buf = tester.render(size: CellSize(cols, 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    sb.write(buf.atColRow(c, 0).grapheme ?? ' ');
  }
  return sb.toString();
}

void main() {
  testWidgets('fills proportionally with a track behind', (tester) {
    tester.pumpWidget(const ProgressBar(value: 0.5));
    expect(_bar(tester), '█████░░░░░');
  });

  testWidgets('full and empty extremes', (tester) {
    tester.pumpWidget(const ProgressBar(value: 1));
    expect(_bar(tester), '██████████');
    tester.pumpWidget(const ProgressBar(value: 0));
    expect(_bar(tester), '░░░░░░░░░░');
  });

  testWidgets('renders a partial block for sub-cell precision', (tester) {
    // 0.45 * 10 = 4.5 cells → 4 full + a half block + 5 track.
    tester.pumpWidget(const ProgressBar(value: 0.45));
    expect(_bar(tester), '████▌░░░░░');
  });

  testWidgets('clamps out-of-range values', (tester) {
    tester.pumpWidget(const ProgressBar(value: 1.5));
    expect(_bar(tester), '██████████');
    tester.pumpWidget(const ProgressBar(value: -0.3));
    expect(_bar(tester), '░░░░░░░░░░');
  });

  testWidgets('fills the bounded width it is given', (tester) {
    tester.pumpWidget(const SizedBox(width: 4, child: ProgressBar(value: 0.5)));
    expect(_bar(tester, cols: 4), '██░░'); // 4-wide bar, half filled
  });
}
