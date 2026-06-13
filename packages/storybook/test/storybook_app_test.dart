import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_storybook/storybook.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('storybook commands navigate stories and variants', (
    tester,
  ) async {
    tester.pumpWidget(StorybookApp());

    var output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('Text'));
    expect(output, contains('Story id: core.layout-text.text'));

    var commandResult = await tester.invokeCommand(
      const CommandId('storybook.story.next'),
    );
    expect(commandResult.completed, isTrue, reason: commandResult.toString());
    tester.pump();
    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('RichText'));
    expect(output, contains('Story id: core.layout-text.rich-text'));

    commandResult = await tester.invokeCommand(
      const CommandId('storybook.story.previous'),
    );
    expect(commandResult.completed, isTrue, reason: commandResult.toString());
    tester.pump();
    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('Text'));
    expect(output, contains('Story id: core.layout-text.text'));

    commandResult = await tester.invokeCommand(
      const CommandId('storybook.variant.next'),
    );
    expect(commandResult.completed, isTrue, reason: commandResult.toString());
    tester.pump();
    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('variant: Plain cells'));
    expect(output, contains('Plain cells: Layout primitives'));

    commandResult = await tester.invokeCommand(
      const CommandId('storybook.variant.next'),
    );
    expect(commandResult.completed, isTrue, reason: commandResult.toString());
    tester.pump();
    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('variant: Long label'));
    expect(output, contains('Long label: Wrapping and clipping'));
  });

  testWidgets('storybook variant navigation includes the default target', (
    tester,
  ) async {
    tester.pumpWidget(
      StorybookApp(initialStoryId: 'controls.boolean-buttons.button'),
    );

    var output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('Button'));
    expect(output, contains('Variant id: default'));
    expect(output, isNot(contains('variant: Disabled')));

    var commandResult = await tester.invokeCommand(
      const CommandId('storybook.variant.next'),
    );
    expect(commandResult.completed, isTrue, reason: commandResult.toString());
    tester.pump();
    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('variant: Disabled'));
    expect(output, contains('Variant id: disabled'));

    commandResult = await tester.invokeCommand(
      const CommandId('storybook.variant.next'),
    );
    expect(commandResult.completed, isTrue, reason: commandResult.toString());
    tester.pump();
    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('Variant id: default'));
    expect(output, isNot(contains('variant: Disabled')));
  });

  testWidgets('initial story, variant, and control values render', (tester) {
    tester.pumpWidget(
      StorybookApp(
        initialStoryId: 'visualization.charts.line-chart',
        initialVariantId: 'dense-interactive',
        initialControlValues: const <String, Object?>{'samples': 12},
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('LineChart'));
    expect(output, contains('variant: Dense interactive'));
    expect(output, contains('Samples'));
    expect(output, contains('12'));
  });

  testWidgets('widget selector activates individual widget rows with Enter', (
    tester,
  ) {
    tester.pumpWidget(StorybookApp());
    tester.render(size: const CellSize(120, 40));

    tester.type('Button');
    tester.pump();

    var output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('Button'));

    tester.render(size: const CellSize(120, 40));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump();
    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );

    expect(output, contains('Button'));
    expect(output, contains('Selected Widget'));
    expect(output, contains('> Button  Input'));
  });

  testWidgets('widget selector arrow keys move the highlighted row', (tester) {
    tester.pumpWidget(StorybookApp());
    tester.render(size: const CellSize(120, 40));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.pump();

    final output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('  Text  Core'));
    expect(output, contains('> RichText  Core'));
  });

  testWidgets('arrow traversal moves from selector into interactive preview', (
    tester,
  ) {
    tester.pumpWidget(StorybookApp());
    tester.render(size: const CellSize(120, 40));

    tester.type('ListView');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump();
    tester.render(size: const CellSize(120, 40));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    tester.pump();
    tester.render(size: const CellSize(120, 40));
    expect(tester.focusManager.focusedNode.toString(), contains('ListView'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.pump();
    tester.render(size: const CellSize(120, 40));

    final output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('ListView'));
    expect(output, isNot(contains('> ListView  Core')));
    expect(output, contains('  ListView  Core'));
    expect(output, contains('> Lazy row 2'));
  });

  testWidgets('arrow traversal enters the ScrollView preview', (tester) {
    tester.pumpWidget(StorybookApp(initialStoryId: 'core.selection-scroll'));
    tester.render(size: const CellSize(120, 40));

    for (var i = 0; i < 9; i += 1) {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.pump();
    }
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump();
    tester.render(size: const CellSize(120, 40));

    for (var i = 0; i < 5; i += 1) {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      tester.pump();
    }
    var output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('> Row  Core'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    tester.pump();
    tester.render(size: const CellSize(120, 40));
    expect(tester.focusManager.focusedNode.toString(), contains('ScrollView'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.pump();

    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, isNot(contains('SelectionArea + ScrollView')));
    expect(output, contains('Selectable paragraph 1'));
  });

  testWidgets('arrow traversal prefers preview before details controls', (
    tester,
  ) {
    tester.pumpWidget(
      StorybookApp(initialStoryId: 'visualization.charts.line-chart'),
    );
    tester.render(size: const CellSize(120, 40));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    tester.pump();
    tester.render(size: const CellSize(120, 40));

    expect(tester.focusManager.focusedNode.toString(), contains('LineChart'));
  });

  testWidgets('chart stories render focused widget previews', (tester) {
    tester.pumpWidget(
      StorybookApp(initialStoryId: 'visualization.charts.bar-chart'),
    );

    final output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );

    expect(output, contains('BarChart'));
    expect(output, contains('CPU'));
    expect(output, contains('Mem'));
    expect(output, contains('IO'));
    expect(output, isNot(contains('CP Me IO')));
  });

  testWidgets('clicking the ScrollView preview focuses it', (tester) {
    tester.pumpWidget(StorybookApp(initialStoryId: 'core.selection-scroll'));
    tester.render(size: const CellSize(120, 40));

    for (var i = 0; i < 9; i += 1) {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.pump();
    }
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump();
    tester.render(size: const CellSize(120, 40));

    for (var i = 0; i < 5; i += 1) {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      tester.pump();
    }
    var output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, contains('> Row  Core'));

    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 42,
        row: 14,
      ),
    );
    tester.pump();
    tester.render(size: const CellSize(120, 40));
    expect(tester.focusManager.focusedNode.toString(), contains('ScrollView'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.pump();

    output = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );
    expect(output, isNot(contains('SelectionArea + ScrollView')));
    expect(output, contains('Selectable paragraph 1'));
  });

  testWidgets('narrow layout keeps the preview pane visible', (tester) {
    tester.pumpWidget(StorybookApp());

    final output = tester.renderToString(
      size: const CellSize(80, 24),
      emptyMark: ' ',
    );

    expect(output, contains('Widgets'));
    expect(output, contains('Preview'));
    expect(output, isNot(contains('│ Details')));
    expect(output, contains('Details hidden in narrow layout'));
  });
}
