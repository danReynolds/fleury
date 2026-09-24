import 'package:fleury/fleury_core.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

String render(FleuryTester tester) =>
    tester.renderToString(size: tester.viewportSize, emptyMark: ' ');

void main() {
  testWidgets('full-screen preview restores shell context after completion', (
    tester,
  ) async {
    tester.viewportSize = const CellSize(84, 29);
    tester.pumpWidget(const InlineSetupPreview(fullScreen: true));
    expect(render(tester), isNot(contains(r'~/projects $ ls')));
    await tester.field('Project name').fill('full_screen_project');
    await tester.button('Review →').press();
    await tester.button('Generate config').press();
    expect(render(tester), contains(r'~/projects $ ls'));
    expect(
      render(tester),
      contains('Configuration ready for full_screen_project'),
    );
    await tester.button('Run again').press();
    expect(render(tester), isNot(contains(r'~/projects $ ls')));
    await tester.button('Cancel').press();
    expect(render(tester), contains('Setup cancelled.'));
    expect(render(tester), contains(r'~/projects $ ls'));
  });

  testWidgets('validates, reviews, goes back, and returns the chosen config', (
    tester,
  ) async {
    final completed = <InlineSetupResult?>[];
    final steps = <InlineSetupStep>[];
    tester.viewportSize = const CellSize(84, 21);
    tester.pumpWidget(
      InlineSetup(onComplete: completed.add, onStepChanged: steps.add),
    );

    await tester.field('Project name').fill('');
    await tester.button('Review →').press();
    expect(render(tester), contains('Give your project a name.'));
    expect(completed, isEmpty);
    await tester.field('Project name').fill('NOT a package');
    await tester.button('Review →').press();
    expect(render(tester), contains('lowercase letters'));

    await tester.field('Project name').fill('orbit_tools');
    await tester.target(role: SemanticRole.radio, label: 'Library').press();
    await tester.checkbox('Include tests').uncheck();
    await tester.button('Review →').press();
    expect(render(tester), contains('lib/orbit_tools.dart'));
    expect(render(tester), isNot(contains('dev_dependencies:')));

    tester.press(KeySequence.escape);
    tester.pump();
    expect(render(tester), contains('orbit_tools'));
    await tester.checkbox('Include tests').check();
    await tester.button('Review →').press();
    expect(render(tester), contains('test/orbit_tools_test.dart'));
    expect(render(tester), contains('dev_dependencies:'));
    await tester.button('Generate config').press();
    await tester.button('Generate config').press();
    expect(completed, hasLength(1));
    expect(completed.single!.name, 'orbit_tools');
    expect(completed.single!.template, ProjectTemplate.library);
    expect(completed.single!.includeTests, isTrue);
    expect(steps, [
      InlineSetupStep.review,
      InlineSetupStep.configure,
      InlineSetupStep.review,
    ]);
  });

  testWidgets('narrow layout keeps completion reachable from the keyboard', (
    tester,
  ) {
    InlineSetupResult? result;
    tester.viewportSize = const CellSize(40, 21);
    tester.pumpWidget(InlineSetup(onComplete: (value) => result = value));
    tester.press(KeySequence.enter);
    tester.pump();
    expect(render(tester), contains('Your project, at a glance.'));
    expect(render(tester), contains('Generate config'));
    tester.press(KeySequence.shift.tab);
    tester.press(KeySequence.end);
    tester.pump();
    expect(render(tester), contains('dev_dependencies:'));
    tester.press(KeySequence.tab);
    tester.press(KeySequence.enter);
    tester.pump();
    expect(result?.name, 'orbit');
  });

  testWidgets('switching pages moves focus from the previous action', (
    tester,
  ) async {
    InlineSetupResult? result;
    tester.viewportSize = const CellSize(84, 21);
    tester.pumpWidget(InlineSetup(onComplete: (value) => result = value));
    await tester.button('Review →').focus();
    await tester.button('Review →').press();
    tester.pump();
    tester.press(KeySequence.escape);
    tester.pump();
    tester.type('_tools');
    expect(render(tester), contains('orbit_tools'));
    await tester.button('Review →').focus();
    await tester.button('Review →').press();
    tester.pump();
    tester.press(KeySequence.enter);
    tester.pump();
    expect(result?.name, 'orbit_tools');
  });

  testWidgets(
    'preview completes, resets, and cancels without losing the shell',
    (tester) async {
      tester.viewportSize = const CellSize(84, 29);
      tester.pumpWidget(const InlineSetupPreview());
      await tester.field('Project name').fill('starlight');
      await tester.button('Review →').press();
      await tester.button('Generate config').press();
      var output = render(tester);
      expect(output, contains('Configuration ready for starlight'));
      expect(output, contains(r'~/projects $ ls'));
      expect(output, contains(r'~/projects $ ▌'));
      expect(output, isNot(contains('Generate config')));
      await tester.button('Run again').press();
      expect(render(tester), contains('orbit'));
      await tester.button('Cancel').press();
      output = render(tester);
      expect(output, contains('Setup cancelled.'));
      expect(output, contains(r'~/projects $ ls'));
    },
  );
}
