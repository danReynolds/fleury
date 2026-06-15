import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_storybook/storybook.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('cyber theme is the default and paints its dark bg + green accent',
      (tester) {
    tester.pumpWidget(StorybookApp());
    final buffer = tester.render(size: const CellSize(120, 40));
    const green = RgbColor(0x2E, 0xE6, 0xA6);
    const bg = RgbColor(0x0E, 0x0F, 0x13);
    var greenCells = 0;
    var bgCells = 0;
    for (var r = 0; r < buffer.size.rows; r++) {
      for (var c = 0; c < buffer.size.cols; c++) {
        final style = buffer.atColRow(c, r).style;
        if (style.foreground == green || style.background == green) greenCells++;
        if (style.background == bg) bgCells++;
      }
    }
    expect(greenCells, greaterThan(0),
        reason: 'the cool-green accent should render (focus/selection/primary)');
    expect(bgCells, greaterThan(1000),
        reason: 'the dark cyber background should fill the surface');
  });

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
    // Grouped browse mode: a CORE section header, category tag suppressed.
    expect(output, contains('CORE'));
    expect(output, contains('  Column'));
    expect(output, contains('> Container'));
  });

  testWidgets('left arrow returns focus from the details panel to the widgets '
      'list', (tester) {
    // Regression: the details panel used to sit outside the focus-traversal
    // group, so once focus crossed into it (e.g. onto a control), Left/Right
    // had no group to handle them and focus was stranded on the right.
    tester.pumpWidget(
      StorybookApp(initialStoryId: 'core.layout-text.text'),
    );
    tester.render(size: const CellSize(120, 40));

    int? left() => tester.focusManager.focusedNode?.rect?.left;

    // Walk Right into the details panel (its content starts past column ~76).
    var enteredDetails = false;
    for (var i = 0; i < 8 && !enteredDetails; i++) {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      tester.pump();
      tester.render(size: const CellSize(120, 40));
      if ((left() ?? 0) > 76) enteredDetails = true;
    }
    expect(enteredDetails, isTrue,
        reason: 'arrow-right should be able to reach the details panel');

    // Now Left must carry focus back leftward and ultimately into the widgets
    // panel (column < selector width ~34) — not get stuck on a details control.
    var reachedWidgets = false;
    var lastLeft = left() ?? 999;
    for (var i = 0; i < 14 && !reachedWidgets; i++) {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      tester.pump();
      tester.render(size: const CellSize(120, 40));
      final l = left() ?? lastLeft;
      expect(l, lessThanOrEqualTo(lastLeft),
          reason: 'each Left should move focus leftward, never rightward');
      lastLeft = l;
      if (l < 34) reachedWidgets = true;
    }
    expect(reachedWidgets, isTrue,
        reason: 'Left from the details panel should return to the widgets list');
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
    tester.render(size: const CellSize(120, 24));

    // Select the ScrollView widget by search (order-independent).
    tester.type('ScrollView');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump();
    tester.render(size: const CellSize(120, 24));

    var output = tester.renderToString(
      size: const CellSize(120, 24),
      emptyMark: ' ',
    );
    expect(output, contains('> ScrollView  Core'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    tester.pump();
    tester.render(size: const CellSize(120, 24));
    expect(tester.focusManager.focusedNode.toString(), contains('ScrollView'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.pump();

    output = tester.renderToString(
      size: const CellSize(120, 24),
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
    tester.render(size: const CellSize(120, 24));

    // Select the ScrollView widget by search (order-independent).
    tester.type('ScrollView');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump();
    tester.render(size: const CellSize(120, 24));

    var output = tester.renderToString(
      size: const CellSize(120, 24),
      emptyMark: ' ',
    );
    expect(output, contains('> ScrollView  Core'));

    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 42,
        row: 14,
      ),
    );
    tester.pump();
    tester.render(size: const CellSize(120, 24));
    expect(tester.focusManager.focusedNode.toString(), contains('ScrollView'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.pump();

    output = tester.renderToString(
      size: const CellSize(120, 24),
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

  testWidgets('Fit preview drops the redundant inner viewport border', (
    tester,
  ) {
    // Regression: in Fit mode the preview drew a second rounded box inside the
    // pane, whose bottom corner stranded above the footer next to the
    // full-height pane borders. Fit now renders the widget directly under the
    // single pane border; a fixed-size preset still frames its viewport.
    int roundedBoxes(String s) => '╭'.allMatches(s).length;

    // Distinct keys force fresh State on the second pump so initialViewport is
    // re-read (otherwise the State persists and both renders use Fit).
    tester.pumpWidget(
      StorybookApp(
        key: const ValueKey('fit'),
        initialStoryId: 'core.layout-text.text',
      ),
    );
    final fit = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );

    tester.pumpWidget(
      StorybookApp(
        key: const ValueKey('framed'),
        initialStoryId: 'core.layout-text.text',
        initialViewport: StorybookViewportPreset.compact80x24,
      ),
    );
    final framed = tester.renderToString(
      size: const CellSize(120, 40),
      emptyMark: ' ',
    );

    expect(
      roundedBoxes(framed),
      roundedBoxes(fit) + 1,
      reason: 'the fixed-size preset adds exactly one rounded viewport box; '
          'Fit must not draw a nested border of its own',
    );
  });
}
