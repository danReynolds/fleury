import 'package:fleury/fleury.dart';
import 'package:fleury_storybook/src/storybook_runner.dart';
import 'package:fleury_storybook/storybook.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  final stateStories = storybookStories
      .where((story) => story.category == 'State')
      .toList();
  final targets = storybookTargets(stories: stateStories);

  for (final target in targets) {
    testWidgets('${target.id} updates through its displayed controls', (
      tester,
    ) async {
      final actions = <String>[];
      final payloads = <Map<String, Object?>>[];
      tester.pumpFleuryHome(
        target.story.builder(
          StoryBuildContext(
            story: target.story,
            variant: target.variant,
            values: target.values,
            selectedWidgetName: target.story.widgets.single,
            recordAction: (name, [data = const <String, Object?>{}]) {
              actions.add(name);
              payloads.add(data);
            },
          ),
        ),
      );

      String rendered() =>
          tester.renderToString(size: const CellSize(40, 12), emptyMark: ' ');
      final contextReader = target.values['reader'] == 1;

      if (target.story.id.startsWith('state.tree.')) {
        expect(
          rendered(),
          contains(contextReader ? 'context.scope<Project>()' : 'ScopeBuilder'),
        );
        expect(rendered(), contains('Project: Atlas'));
        expect(rendered(), contains('Open tasks: 3'));

        await tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Switch project',
        );
        tester.pump();

        expect(rendered(), contains('Project: Beacon'));
        expect(rendered(), contains('Open tasks: 7'));
        expect(actions, ['project.changed']);
        expect(payloads.single, {'project': 'Beacon', 'openTasks': 7});

        await tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Switch project',
        );
        tester.pump();
        expect(rendered(), contains('Project: Atlas'));
        expect(rendered(), contains('Open tasks: 3'));
      } else {
        final valueNotifier = target.story.id == 'state.value.value-notifier';
        expect(
          rendered(),
          contains(
            contextReader
                ? 'context.listen(${valueNotifier ? 'count' : 'cart'})'
                : 'NotifierBuilder',
          ),
        );
        expect(rendered(), contains('Items: 0'));

        for (var items = 1; items <= 2; items++) {
          await tester.invokeSemanticAction(
            SemanticAction.activate,
            role: SemanticRole.button,
            label: 'Add item',
          );
          tester.pump();
          expect(rendered(), contains('Items: $items'));
          expect(payloads.last, {'items': items});
        }
        expect(
          actions,
          List.filled(2, valueNotifier ? 'count.changed' : 'cart.add-item'),
        );
      }
    });
  }
}
