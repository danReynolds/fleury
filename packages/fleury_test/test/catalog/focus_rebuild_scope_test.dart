// A focus move rebuilds the controls whose focus changed, not every
// focusable control in the tree. The library's controls listen to their own
// focus node rather than depending on the whole FocusManager.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

const _options = [
  SelectOption(value: 'red', label: 'red'),
  SelectOption(value: 'teal', label: 'teal'),
];

Iterable<TextCompletionOption> _provider(TextCompletionRequest request) =>
    const [TextCompletionOption(label: 'checkout')];

List<Widget> _controls(int i) => [
  Select<String>(
    autofocus: i == 0,
    value: 'red',
    options: _options,
    onChanged: (_) {},
  ),
  MultiSelect<String>(
    values: const {'red'},
    options: _options,
    onChanged: (_) {},
  ),
  Stepper(value: i, onChanged: (_) {}),
  ColorPicker(value: const AnsiColor(1), onChanged: (_) {}),
  DatePicker(value: DateTime(2024, 3, 15), onChanged: (_) {}),
  const Autocomplete(options: ['apple']),
  CompletionTextInput(provider: _provider),
];

void main() {
  testWidgets('a focus move rebuilds only the controls it concerns', (tester) {
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              for (final control in _controls(i))
                SizedBox(height: 1, width: 30, child: control),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(40, 40));
    tester.owner.flushBuild();

    final rebuilt = <int>[];
    for (var move = 0; move < 7; move++) {
      tester.focusManager.focusNext();
      rebuilt.add(tester.owner.flushBuild().rebuiltElementCount);
    }

    for (final count in rebuilt) {
      expect(count, lessThan(12), reason: 'rebuilt per move: $rebuilt');
    }
  });

  group('a panel with a query and a list', () {
    // Its semantic node reports whether either of its own nodes holds focus;
    // a focus move between two other nodes concerns it not at all.
    int rebuiltByUnrelatedMoves(FleuryTester tester, Widget? panel) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      tester.pumpWidget(
        Column(
          children: [
            Focus(focusNode: a, autofocus: true, child: const Text('A')),
            Focus(focusNode: b, child: const Text('B')),
            if (panel != null) SizedBox(height: 12, child: panel),
          ],
        ),
      );
      tester.render(size: const CellSize(60, 20));
      tester.owner.flushBuild();
      var rebuilt = 0;
      for (var i = 0; i < 10; i++) {
        (i.isEven ? b : a).requestFocus();
        rebuilt += tester.owner.flushBuild().rebuiltElementCount;
      }
      return rebuilt;
    }

    final panels = <String, Widget Function()>{
      'SearchPanel': () => SearchPanel(
        results: [for (var i = 0; i < 20; i++) SearchResult(title: 'r$i')],
      ),
      'ConversationNavigator': () =>
          const ConversationNavigator(conversations: []),
      'FileMentionPicker': () => const FileMentionPicker(entries: []),
    };
    for (final MapEntry(key: name, value: panel) in panels.entries) {
      testWidgets('$name does not rebuild for a focus move elsewhere', (
        tester,
      ) {
        final without = rebuiltByUnrelatedMoves(tester, null);
        final withPanel = rebuiltByUnrelatedMoves(tester, panel());

        expect(withPanel, without);
      });
    }

    testWidgets('its semantic node still follows its own focus', (tester) {
      final query = FocusNode(debugLabel: 'query');
      final other = FocusNode(debugLabel: 'other');
      addTearDown(query.dispose);
      addTearDown(other.dispose);
      tester.pumpWidget(
        Column(
          children: [
            Focus(focusNode: other, autofocus: true, child: const Text('X')),
            SizedBox(
              height: 12,
              child: SearchPanel(
                queryFocusNode: query,
                results: const [SearchResult(title: 'r')],
              ),
            ),
          ],
        ),
      );
      bool panelFocused() => tester
          .semantics()
          .single(role: SemanticRole.region, label: 'Search')
          .focused;
      expect(panelFocused(), isFalse);

      query.requestFocus();
      tester.pump();
      expect(panelFocused(), isTrue);

      other.requestFocus();
      tester.pump();
      expect(panelFocused(), isFalse);
    });
  });

  testWidgets('scrolling a Tree rebuilds none of its rows', (tester) {
    final roots = [for (var i = 0; i < 300; i++) _CountingNode('node $i')];
    tester.pumpWidget(
      SizedBox(height: 8, child: Tree<int>(roots: roots, autofocus: true)),
    );
    tester.pump();
    tester.pump();

    // A wheel step renders its frame; the tree's semantic node then follows
    // the new visible range alone, with no second frame of row builds.
    var followUpReads = 0;
    for (var i = 0; i < 20; i++) {
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.scrollDown,
          button: MouseButton.none,
          col: 2,
          row: 2,
        ),
      );
      tester.pump();
      _CountingNode.reads = 0;
      tester.pump();
      followUpReads += _CountingNode.reads;
    }

    expect(followUpReads, 0);
    final tree = tester.semantics().single(role: SemanticRole.tree);
    expect(tree.state['visibleRangeStart'], greaterThan(0));
  });
}

/// Counts the reads of its label: a row reads it when it builds.
final class _CountingNode extends TreeNode<int> {
  _CountingNode(this._label) : super('');

  static var reads = 0;
  final String _label;

  @override
  String get label {
    reads++;
    return _label;
  }
}
