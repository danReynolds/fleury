// One-shot snapshot of the dashboard at a fixed terminal size — prints
// the rendered grapheme grid to stdout. Lets you eyeball the layout
// without running the live demo. Useful in CI / on a headless box.
//
// Run from packages/fleury_widgets:
//   dart run example/dashboard_snapshot.dart

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';

import 'dashboard_demo.dart';

void main() {
  // Use FleuryTester to render a single frame at a known size — no PTY,
  // no timer, no live updates. The DashboardApp's initState seeds its
  // CPU/mem windows so the chart is fully populated on the first frame.
  final tester = FleuryTester();
  tester.pumpWidget(const DashboardApp());
  final out = tester.renderToString(
    size: const CellSize(80, 24),
    emptyMark: ' ',
  );
  print(out);
  tester.dispose();
}
