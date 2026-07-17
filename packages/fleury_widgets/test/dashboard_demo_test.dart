// Smoke test for example/dashboard_demo.dart — the live-data dashboard
// that composes the full viz catalog under one layout. This is the
// "do they actually compose?" check: if any of the widgets, the layout
// flex math, or the theme threading regresses, this test crashes the
// loudest.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../example/dashboard_demo.dart';

void main() {
  group('DashboardApp smoke', () {
    testWidgets('renders one frame at a typical terminal size', (tester) {
      tester.pumpWidget(const DashboardApp());
      // Just rendering without throwing is the assertion. Pick a size
      // similar to a terminal window opened with `tmux split`.
      tester.render(size: const CellSize(80, 24));
    });

    testWidgets('renders at a narrow size without crashing', (tester) {
      tester.pumpWidget(const DashboardApp());
      tester.render(size: const CellSize(50, 20));
    });

    testWidgets('renders at a tiny size without crashing', (tester) {
      // Sanity floor — at 20×10 most panels can't fit their content,
      // but the layout should clip silently, not throw.
      tester.pumpWidget(const DashboardApp());
      tester.render(size: const CellSize(20, 10));
    });

    testWidgets('renders with a custom theme threaded through', (tester) {
      tester.pumpWidget(
        Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(const AnsiColor(5)),
          ),
          child: const DashboardApp(),
        ),
      );
      tester.render(size: const CellSize(80, 24));
    });

    testWidgets('app route supplies the advertised Tab traversal', (tester) {
      tester.pumpFleuryHome(const DashboardApp());
      tester.render(size: const CellSize(80, 24));

      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));

      expect(tester.focusManager.focusedNode?.debugLabel, 'line chart');
    });
  });
}
