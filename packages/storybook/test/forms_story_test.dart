import 'package:fleury/fleury.dart';
import 'package:fleury_storybook/storybook.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('forms showcase completes a realistic validated workflow', (
    tester,
  ) async {
    final story = storybookStories.singleWhere(
      (story) => story.id == 'forms.workflow.form',
    );
    tester.pumpFleuryHome(
      story.builder(
        StoryBuildContext(story: story, values: story.initialControlValues()),
      ),
    );

    String rendered() =>
        tester.renderToString(size: const CellSize(80, 28), emptyMark: ' ');

    expect(rendered(), contains('CREATE SERVICE  ·  1 OF 3'));

    await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
    );
    tester.pump();
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(rendered(), contains('Enter a service name.'));

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.textField,
      label: 'Service name',
      payload: 'fleury',
    );
    await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
    );
    tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    tester.pump();
    expect(rendered(), contains('That service name is already in use.'));

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.textField,
      label: 'Service name',
      payload: 'webhook-worker',
    );
    await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
    );
    tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    tester.pump();
    expect(rendered(), contains('DEPLOYMENT  ·  2 OF 3'));
    expect(rendered(), contains('Production'));
    expect(rendered(), contains('Toronto'));

    await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
    );
    tester.pump();
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(rendered(), contains('REVIEW  ·  3 OF 3'));
    expect(rendered(), contains('webhook-worker'));

    await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
    );
    tester.pump();
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(rendered(), contains('Confirm the production deployment.'));

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.checkbox,
      label: 'I reviewed these settings',
      payload: true,
    );
    await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
    );
    tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 470));
    tester.pump();
    expect(rendered(), contains('SERVICE DEPLOYED'));
    expect(rendered(), contains('webhook-worker is live in Toronto.'));
  });
}
