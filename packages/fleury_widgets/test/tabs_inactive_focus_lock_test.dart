// Lock test (widget-interaction audit §4): a tab must not advertise
// SemanticAction.focus. Its focused flag is `strip.hasFocus && i == active`,
// so an inactive tab can never satisfy a focus request — the advertised
// capability could not succeed, and `.focus()` threw "Focus was refused".
//
// Satisfying it by selecting the tab is worse: that makes a read-only sweep
// destructive, switching the visible panel and firing onChanged for every tab
// an agent reads. A tab is not independently focusable; the strip is.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('a tab does not advertise focus, and select moves the strip', (
    tester,
  ) async {
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

    // Reading every tab must leave the strip where it was.
    for (final label in ['One', 'Two', 'Three']) {
      tester.semantics().single(role: SemanticRole.tab, label: label);
    }
    expect(
      controller.index,
      0,
      reason: 'inspection is read-only — no tab switch, no onChanged',
    );

    await tester.target(role: SemanticRole.tab, label: 'Two').select();

    expect(
      controller.index,
      1,
      reason: 'select is the action that moves the strip',
    );
    final focused = tester.semantics().single(
      role: SemanticRole.tab,
      label: 'Two',
      selected: true,
      focused: true,
    );
    expect(focused.label, 'Two');
  });
}
