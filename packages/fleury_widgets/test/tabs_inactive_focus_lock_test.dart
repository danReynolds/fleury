// Lock test (widget-interaction audit §4): an inactive tab advertises
// SemanticAction.focus, but the handler only requests focus on the strip
// without selecting that tab. The tab's focused flag is
// `strip.hasFocus && i == active`, so tester.target(...).focus() throws
// "Focus was refused" for every inactive tab — an advertised capability that
// cannot succeed.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets(
    'focusing an inactive tab selects it so the advertised focus succeeds',
    (tester) async {
      final controller = TabController();
      addTearDown(controller.dispose);

      tester.pumpWidget(
        Tabs(
          controller: controller,
          autofocus: true,
          tabs: const [
            TabItem(label: 'One', content: Text('pane-one')),
            TabItem(label: 'Two', content: Text('pane-two')),
            TabItem(label: 'Three', content: Text('pane-three')),
          ],
        ),
      );
      tester.render(size: const CellSize(40, 4));
      expect(controller.index, 0);

      // Inactive tab Two advertises focus; the call must succeed and select it.
      await tester.target(role: SemanticRole.tab, label: 'Two').focus();

      expect(
        controller.index,
        1,
        reason:
            'SemanticAction.focus on an inactive tab must select that tab '
            '(same helper as arrows / Alt+N); focusing the strip alone leaves '
            'focused=false on the addressed node',
      );
      final focused = tester.semantics().single(
        role: SemanticRole.tab,
        label: 'Two',
        selected: true,
        focused: true,
      );
      expect(focused.label, 'Two');
    },
  );
}
