// A TreeTable's selection is its row's key (TreeTableNode.key is the row's
// identity), not an index. Expanding or collapsing above the cursor, a
// filter, or new roots rebuild the rows; the cursor stays on its node, and
// Enter and copy act on it. When the node leaves the rows, the cursor moves
// to its nearest ancestor that is still there.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _columns = [
  DataTableColumn(id: 'name', title: 'Name', width: FixedColumnWidth(18)),
];

TreeTableNode<String> _node(String key, [List<TreeTableNode<String>>? kids]) =>
    TreeTableNode<String>(
      key: key,
      label: key,
      value: key,
      children: kids ?? const [],
    );

final _roots = [
  _node('app', [_node('search'), _node('logs')]),
  _node('docs'),
  _node('notes'),
  _node('readme'),
];

Widget _table(
  TreeTableController controller, {
  List<TreeTableNode<String>>? roots,
  TreeTableFilterDescriptor? filter,
  void Function(TreeTableRow<String> row)? onSelect,
}) => TreeTable<String>(
  roots: roots ?? _roots,
  columns: _columns,
  controller: controller,
  filter: filter,
  onSelect: onSelect,
  autofocus: true,
);

Object? _selectedKey(FleuryTester tester) {
  tester.render(size: const CellSize(40, 12));
  return tester.semantics().single(role: SemanticRole.tree).state.selectedKey;
}

void main() {
  testWidgets('expanding above the cursor keeps it on its node', (tester) {
    final controller = TreeTableController(initialIndex: 2);
    addTearDown(controller.dispose);
    final selected = <Object>[];
    tester.pumpWidget(
      _table(controller, onSelect: (row) => selected.add(row.key)),
    );
    expect(_selectedKey(tester), 'notes');

    controller.expand('app');
    tester.pump();
    expect(_selectedKey(tester), 'notes');
    expect(controller.currentIndex, 4);

    tester.sendKey(const KeyEvent(KeyCode.enter));
    expect(selected, ['notes']);
  });

  testWidgets('collapsing above the cursor keeps it on its node', (tester) {
    final controller = TreeTableController(
      initialIndex: 4,
      expandedKeys: const {'app'},
    );
    addTearDown(controller.dispose);
    tester.pumpWidget(_table(controller));
    expect(_selectedKey(tester), 'notes');

    controller.collapseAll();
    tester.pump();

    expect(_selectedKey(tester), 'notes');
    expect(controller.currentIndex, 2);
  });

  testWidgets('a filter that keeps the node keeps the cursor on it', (tester) {
    final controller = TreeTableController(initialIndex: 2);
    addTearDown(controller.dispose);
    tester.pumpWidget(_table(controller));
    expect(_selectedKey(tester), 'notes');

    tester.pumpWidget(
      _table(controller, filter: const TreeTableFilterDescriptor(query: 'o')),
    );

    expect(_selectedKey(tester), 'notes');
  });

  testWidgets('new roots keep the cursor on its node', (tester) {
    final controller = TreeTableController(initialIndex: 2);
    addTearDown(controller.dispose);
    tester.pumpWidget(_table(controller));
    expect(_selectedKey(tester), 'notes');

    tester.pumpWidget(_table(controller, roots: [_node('aaa'), ..._roots]));

    expect(_selectedKey(tester), 'notes');
    expect(controller.currentIndex, 3);
  });

  testWidgets('collapsing the node\'s parent moves the cursor to the parent', (
    tester,
  ) {
    final controller = TreeTableController(
      initialIndex: 2,
      expandedKeys: const {'app'},
    );
    addTearDown(controller.dispose);
    tester.pumpWidget(_table(controller));
    expect(_selectedKey(tester), 'logs');

    controller.collapse('app');
    tester.pump();

    expect(_selectedKey(tester), 'app');
    expect(controller.currentIndex, 0);
  });
}
