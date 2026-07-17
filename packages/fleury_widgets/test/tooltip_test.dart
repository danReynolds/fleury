import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester, {int cols = 20, int rows = 6}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  testWidgets('shows the hint while the wrapped widget is focused', (tester) {
    tester.pumpWidget(
      const Tooltip(
        message: 'Save file',
        child: Focus(autofocus: true, child: Text('Save')),
      ),
    );
    final out = _screen(tester);
    expect(out.contains('Save'), isTrue);
    expect(out.contains('Save file'), isTrue, reason: 'tooltip shown on focus');
    expect(tester.overlay.entries.length, 2);
  });

  testWidgets('hides when focus moves away', (tester) {
    final other = FocusNode(debugLabel: 'other');
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Tooltip(
              message: 'tip',
              child: Focus(autofocus: true, child: Text('A')),
            ),
            Focus(focusNode: other, child: const Text('B')),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(20, 6)); // record rects
    expect(_screen(tester).contains('tip'), isTrue);

    // Move focus down to B; the tooltip disappears.
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    expect(other.hasFocus, isTrue);
    expect(_screen(tester).contains('tip'), isFalse, reason: 'hidden on blur');
    expect(tester.overlay.entries.length, 1);
  });

  testWidgets('Esc hides the tip but keeps focus on the trigger', (tester) {
    final node = FocusNode(debugLabel: 'trigger');
    tester.pumpWidget(
      Tooltip(
        message: 'Save file',
        child: Focus(
          focusNode: node,
          autofocus: true,
          child: const Text('Save'),
        ),
      ),
    );
    tester.render(size: const CellSize(20, 6));
    expect(_screen(tester).contains('Save file'), isTrue);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    expect(node.hasFocus, isTrue, reason: 'Esc must not move focus');
    expect(
      _screen(tester).contains('Save file'),
      isFalse,
      reason: 'tip hidden',
    );
  });

  testWidgets('exposes tooltip region semantics and visible state', (tester) {
    tester.pumpWidget(
      const Tooltip(
        message: 'Save file',
        semanticLabel: 'Save help',
        child: Focus(autofocus: true, child: Text('Save')),
      ),
    );
    tester.render(size: const CellSize(20, 6));

    final region = tester.semantics().single(
      role: SemanticRole.region,
      label: 'Save help',
      value: 'Save file',
    );
    expect(region.hint, 'Save file');
    expect(region.state['tooltipVisible'], isTrue);

    final visible = tester.semantics().single(
      role: SemanticRole.text,
      label: 'Save help',
      value: 'Save file',
    );
    expect(visible.value, 'Save file');
    expect(visible.state['tooltipVisible'], isTrue);
  });

  testWidgets('tooltip region semantics track hidden state', (tester) {
    final other = FocusNode(debugLabel: 'other');
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Tooltip(
              message: 'tip',
              child: Focus(autofocus: true, child: Text('A')),
            ),
            Focus(focusNode: other, child: const Text('B')),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(20, 6));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));

    final region = tester.semantics().single(
      role: SemanticRole.region,
      label: 'Tooltip',
      value: 'tip',
    );
    expect(region.state['tooltipVisible'], isFalse);
    expect(
      tester.semantics().where(role: SemanticRole.text, label: 'Tooltip'),
      isEmpty,
    );
  });
}
