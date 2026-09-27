// The tree's own semantic node reports the cursor — currentIndex,
// selectedKey, the visible range — as arrow keys, typeahead and clicks move
// it. It used to report them only when something else rebuilt the tree.
import 'dart:collection';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Roots that count how often the tree reads a root by index, which it does
/// once per root each time it flattens itself into rows.
final class _CountingRoots extends ListBase<TreeNode<String>> {
  _CountingRoots(this._roots);

  final List<TreeNode<String>> _roots;
  var reads = 0;

  @override
  int get length => _roots.length;
  @override
  set length(int value) => throw UnsupportedError('fixed');
  @override
  TreeNode<String> operator [](int index) {
    reads++;
    return _roots[index];
  }

  @override
  void operator []=(int index, TreeNode<String> value) =>
      throw UnsupportedError('fixed');
}

_CountingRoots _roots() => _CountingRoots([
  const TreeNode('alpha'),
  const TreeNode('beta', children: [TreeNode('b1'), TreeNode('b2')]),
  const TreeNode('gamma'),
  const TreeNode('delta'),
]);

Map<String, Object?> _treeState(FleuryTester tester) =>
    tester.semantics().single(role: SemanticRole.tree).state.values;

void main() {
  testWidgets('the tree node follows arrow keys and typeahead', (tester) {
    tester.pumpWidget(Tree<String>(autofocus: true, roots: _roots()));
    tester.render(size: const CellSize(40, 10));

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.pump();
    expect(_treeState(tester)['currentIndex'], 2);
    expect(_treeState(tester)['selectedKey'], '2');

    tester.type('d');
    tester.pump();
    expect(_treeState(tester)['currentIndex'], 3);
    expect(_treeState(tester)['selectedKey'], '3');
  });

  testWidgets('the tree node reports its visible range after one frame', (
    tester,
  ) async {
    tester.pumpWidget(Tree<String>(autofocus: true, roots: _roots()));
    tester.render(size: const CellSize(40, 10));
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    expect(_treeState(tester)['visibleRangeStart'], 0);
    expect(_treeState(tester)['visibleRangeEnd'], 3);
  });

  testWidgets('moving the cursor does not re-flatten the tree', (tester) {
    final roots = _roots();
    tester.pumpWidget(Tree<String>(autofocus: true, roots: roots));
    tester.render(size: const CellSize(40, 10));

    roots.reads = 0;
    for (var i = 0; i < 3; i++) {
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.pump();
    }
    expect(roots.reads, 0);

    tester.sendKey(const KeyEvent(KeyCode.arrowUp));
    tester.sendKey(const KeyEvent(KeyCode.arrowUp));
    tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // expand beta
    tester.pump();
    expect(roots.reads, greaterThan(0), reason: 'expanding changes the rows');
    expect(_treeState(tester)['collectionRowCount'], 6);
  });

  testWidgets('new roots from the parent replace the rows', (tester) {
    final roots = ValueNotifier<List<TreeNode<String>>>(const [
      TreeNode('alpha'),
      TreeNode('beta'),
    ]);
    tester.pumpWidget(
      NotifierBuilder(
        notifier: roots,
        builder: (_, roots) =>
            Tree<String>(autofocus: true, roots: roots.value),
      ),
    );
    tester.render(size: const CellSize(40, 10));

    roots.value = const [TreeNode('gamma')];
    tester.pump();

    final screen = tester.renderToString(size: const CellSize(40, 10));
    expect(screen, contains('gamma'));
    expect(screen, isNot(contains('alpha')));
    expect(_treeState(tester)['collectionRowCount'], 1);
  });
}
