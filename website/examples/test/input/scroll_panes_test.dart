import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/scroll_panes.dart';
import 'pointer_test_helpers.dart';

void main() {
  for (final contain in [false, true]) {
    testWidgets('wheel handoff follows the containment checkbox ($contain)', (
      tester,
    ) {
      tester.pumpFleuryHome(const SizedBox(width: 36, child: ScrollPanes()));
      if (contain) {
        pointer(tester, MouseEventKind.down, 2, 0);
        pointer(tester, MouseEventKind.up, 2, 0);
      }
      expect(
        tester.semantics().single(role: SemanticRole.checkbox).checked,
        contain,
      );
      expect(tester.renderToString(), isNot(contains('July')));
      pointer(
        tester,
        MouseEventKind.scrollDown,
        4,
        6,
        button: MouseButton.none,
      );
      expect(tester.renderToString(), contains('6  Final'));
      pointer(
        tester,
        MouseEventKind.scrollDown,
        4,
        6,
        button: MouseButton.none,
      );
      expect(tester.renderToString().contains('July'), !contain);
    });
  }
}
