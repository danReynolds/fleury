import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _columns = [
  DataTableColumn(id: 'name', title: 'Name', width: FixedColumnWidth(18)),
  DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(8)),
  DataTableColumn(id: 'owner', title: 'Owner', width: FixedColumnWidth(8)),
];

const _roots = [
  TreeTableNode<String>(
    key: 'app',
    label: 'App',
    value: 'app',
    cells: {'status': 'running', 'owner': 'platform'},
    children: [
      TreeTableNode<String>(
        key: 'search',
        label: 'Search',
        value: 'search',
        cells: {'status': 'passed', 'owner': 'tooling'},
      ),
      TreeTableNode<String>(
        key: 'logs',
        label: 'Logs',
        value: 'logs',
        cells: {'status': 'warning', 'owner': 'ops'},
      ),
    ],
  ),
  TreeTableNode<String>(
    key: 'docs',
    label: 'Docs',
    value: 'docs',
    cells: {'status': 'queued', 'owner': 'docs'},
  ),
];

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('TreeTableController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = TreeTableController(
        selectedIndex: 1,
        expandedKeys: const {'app'},
      );

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 1);
      expect(controller.expandedKeys, {'app'});
      expect(controller.isExpanded('app'), isTrue);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = TreeTableController(expandedKeys: const {'app'})
        ..dispose();

      const message = 'TreeTableController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.expand('docs'), _stateError(message));
      expect(() => controller.collapse('app'), _stateError(message));
      expect(() => controller.toggle('docs'), _stateError(message));
      expect(() => controller.collapseAll(), _stateError(message));
    });
  });

  testWidgets('renders hierarchical rows with tree and cell semantics', (
    tester,
  ) {
    tester.pumpWidget(
      const TreeTable<String>(
        semanticLabel: 'Work tree',
        roots: _roots,
        columns: _columns,
        autofocus: true,
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(60, 8),
      emptyMark: ' ',
    );
    expect(output, contains('Name'));
    expect(output, contains('▸ App'));
    expect(output, contains('Docs'));
    expect(output, isNot(contains('Search')));

    final tree = tester.semantics().single(role: SemanticRole.tree);
    expect(tree.label, 'Work tree');
    expect(tree.state.collectionRowCount, 2);
    expect(tree.state.collectionColumnCount, 3);
    expect(tree.state.selectedKey, 'app');
    expect(tree.actions, contains(SemanticAction.copy));

    final app = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'App',
    );
    expect(app.selected, isTrue);
    expect(app.actions, contains(SemanticAction.open));
    expect(app.state['rowIndex'], 0);
    expect(app.state['rowKey'], 'app');
    expect(app.state['depth'], 0);
    expect(app.state['isBranch'], isTrue);
    expect(app.state['expanded'], isFalse);

    final status = tester
        .semantics()
        .byRole(SemanticRole.tableCell)
        .singleWhere(
          (node) =>
              node.state['columnId'] == 'status' &&
              node.state['rowKey'] == 'app',
        );
    expect(status.label, 'running');
    expect(status.state['rowKey'], 'app');
    expect(status.state['treeDepth'], 0);
  });

  testWidgets('Enter expands branches and activates leaves', (tester) {
    TreeTableRow<String>? selected;
    tester.pumpWidget(
      TreeTable<String>(
        roots: _roots,
        columns: _columns,
        autofocus: true,
        onSelect: (row) => selected = row,
      ),
    );

    tester.sendKey(const KeyEvent(KeyCode.enter));
    var output = tester.renderToString(size: const CellSize(60, 8));
    expect(output, contains('▾ App'));
    expect(output, contains('Search'));

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(KeyCode.enter));
    expect(selected, isNotNull);
    expect(selected!.key, 'search');
  });

  testWidgets('semantic open and activate drive TreeTable rows', (
    tester,
  ) async {
    final controller = TreeTableController();
    TreeTableRow<String>? selected;
    tester.pumpWidget(
      TreeTable<String>(
        roots: _roots,
        columns: _columns,
        controller: controller,
        onSelect: (row) => selected = row,
      ),
    );

    tester.render(size: const CellSize(60, 8));
    var result = await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.treeItem,
      label: 'App',
    );
    expect(result.completed, isTrue);
    expect(controller.expandedKeys, contains('app'));
    tester.render(size: const CellSize(60, 8));

    result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.treeItem,
      label: 'Search',
    );

    expect(result.completed, isTrue);
    expect(selected?.key, 'search');
  });

  testWidgets('semantic close collapses an expanded TreeTable branch', (
    tester,
  ) async {
    final controller = TreeTableController();
    tester.pumpWidget(
      TreeTable<String>(
        roots: _roots,
        columns: _columns,
        controller: controller,
      ),
    );
    tester.render(size: const CellSize(60, 8));
    await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.treeItem,
      label: 'App',
    );
    expect(controller.expandedKeys, contains('app'));
    tester.render(size: const CellSize(60, 8));

    // Expanded ⇒ the row offers close, not open (the symmetric pair).
    final expanded = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'App',
    );
    expect(expanded.actions, contains(SemanticAction.close));
    expect(expanded.actions, isNot(contains(SemanticAction.open)));

    final result = await tester.invokeSemanticAction(
      SemanticAction.close,
      role: SemanticRole.treeItem,
      label: 'App',
    );
    expect(result.completed, isTrue);
    expect(controller.expandedKeys, isNot(contains('app')));
  });

  testWidgets('filter reveals matching collapsed descendants with ancestors', (
    tester,
  ) {
    tester.pumpWidget(
      const TreeTable<String>(
        roots: _roots,
        columns: _columns,
        filter: TreeTableFilterDescriptor(query: 'logs'),
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(60, 8),
      emptyMark: ' ',
    );
    expect(output, contains('▾ App'));
    expect(output, contains('Logs'));
    expect(output, isNot(contains('Search')));
    expect(output, isNot(contains('Docs')));

    final tree = tester.semantics().single(role: SemanticRole.tree);
    expect(tree.state.collectionRowCount, 2);
    expect(tree.state.filterText, 'logs');

    final logs = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'Logs',
    );
    expect(logs.state['depth'], 1);
    expect(logs.state['rowKey'], 'logs');
  });

  test(
    'TreeTableSearchIndex matches direct filtering without rescanning cells',
    () {
      var cellBuilderCalls = 0;
      String cellBuilder(TreeTableNode<String> node, String columnId) {
        cellBuilderCalls += 1;
        return node.cells[columnId] ?? '';
      }

      final direct = buildTreeTableRows<String>(
        roots: _roots,
        columns: _columns,
        cellBuilder: cellBuilder,
        filter: const TreeTableFilterDescriptor(
          query: 'tooling',
          columnIds: {'owner'},
        ),
      );
      final directKeys = [for (final row in direct) row.key];

      final index = TreeTableSearchIndex<String>.build(
        roots: _roots,
        columns: _columns,
        cellBuilder: cellBuilder,
      );
      expect(index.rowCount, 4);
      expect(cellBuilderCalls, greaterThan(0));

      cellBuilderCalls = 0;
      final indexed = buildTreeTableRows<String>(
        roots: _roots,
        columns: _columns,
        cellBuilder: cellBuilder,
        filter: const TreeTableFilterDescriptor(
          query: 'tooling',
          columnIds: {'owner'},
        ),
        searchIndex: index,
      );

      expect([for (final row in indexed) row.key], directKeys);
      expect(directKeys, ['app', 'search']);
      expect(cellBuilderCalls, 0);

      final statusFiltered = buildTreeTableRows<String>(
        roots: _roots,
        columns: _columns,
        filter: const TreeTableFilterDescriptor(
          query: 'warning',
          columnIds: {'name'},
        ),
        searchIndex: index,
      );
      expect(statusFiltered, isEmpty);
    },
  );

  test('indexed filtering keeps fuzzy mode distinct from exact-token mode', () {
    const roots = [
      TreeTableNode<String>(key: 'alpha', label: 'AlphaBeta'),
      TreeTableNode<String>(key: 'beta', label: 'Beta'),
    ];
    final index = TreeTableSearchIndex<String>.build(
      roots: roots,
      columns: _columns,
    );

    final fuzzy = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(query: 'Beta'),
      searchIndex: index,
    );
    expect([for (final row in fuzzy) row.key], ['alpha', 'beta']);

    final exactToken = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'Beta',
        mode: TreeTableFilterMode.exactToken,
      ),
      searchIndex: index,
    );
    expect([for (final row in exactToken) row.key], ['beta']);
  });

  test('indexed exact-token filtering supports durable symbol tokens', () {
    const roots = [
      TreeTableNode<String>(
        key: 'agent',
        label: 'Agent',
        cells: {'status': 'ready', 'owner': 'team:runtime'},
        metadata: {'target': 'zz-target_42'},
      ),
    ];
    final index = TreeTableSearchIndex<String>.build(
      roots: roots,
      columns: _columns,
    );

    final symbolToken = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'zz-target_42',
        mode: TreeTableFilterMode.exactToken,
      ),
      searchIndex: index,
    );
    expect([for (final row in symbolToken) row.key], ['agent']);

    final colonToken = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'team:runtime',
        mode: TreeTableFilterMode.exactToken,
      ),
      searchIndex: index,
    );
    expect([for (final row in colonToken) row.key], ['agent']);

    final substring = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'target',
        mode: TreeTableFilterMode.exactToken,
      ),
      searchIndex: index,
    );
    expect(substring, isEmpty);
  });

  test('indexed filtering preserves case-sensitive matching semantics', () {
    const roots = [
      TreeTableNode<String>(
        key: 'upper',
        label: 'Build Alpha',
        cells: {'status': 'Ready', 'owner': 'OpsTeam'},
      ),
      TreeTableNode<String>(
        key: 'lower',
        label: 'build alpha',
        cells: {'status': 'ready', 'owner': 'opsteam'},
      ),
    ];
    final index = TreeTableSearchIndex<String>.build(
      roots: roots,
      columns: _columns,
    );

    final indexed = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'OpsTeam',
        caseSensitive: true,
      ),
      searchIndex: index,
    );
    expect([for (final row in indexed) row.key], ['upper']);

    final indexedColumn = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'Ready',
        columnIds: {'status'},
        caseSensitive: true,
      ),
      searchIndex: index,
    );
    expect([for (final row in indexedColumn) row.key], ['upper']);
  });

  test('indexed prefix-token filtering supports durable ID typeahead', () {
    const roots = [
      TreeTableNode<String>(
        key: 'run-1002',
        label: 'Run 1002',
        cells: {'status': 'ready', 'owner': 'ops'},
      ),
      TreeTableNode<String>(
        key: 'prod-run-1003',
        label: 'Production runner',
        cells: {'status': 'ready', 'owner': 'platform'},
      ),
      TreeTableNode<String>(
        key: 'run-1004',
        label: 'Run 1004',
        cells: {'status': 'queued', 'owner': 'ops'},
      ),
    ];
    var cellBuilderCalls = 0;
    String cellBuilder(TreeTableNode<String> node, String columnId) {
      cellBuilderCalls += 1;
      return node.cells[columnId] ?? '';
    }

    final direct = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      cellBuilder: cellBuilder,
      filter: const TreeTableFilterDescriptor(
        query: 'run-10',
        mode: TreeTableFilterMode.prefixToken,
      ),
    );
    expect([for (final row in direct) row.key], ['run-1002', 'run-1004']);

    final index = TreeTableSearchIndex<String>.build(
      roots: roots,
      columns: _columns,
      cellBuilder: cellBuilder,
    );
    expect(index.rowCount, 3);

    cellBuilderCalls = 0;
    final indexed = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      cellBuilder: cellBuilder,
      filter: const TreeTableFilterDescriptor(
        query: 'run-10',
        mode: TreeTableFilterMode.prefixToken,
      ),
      searchIndex: index,
    );

    expect([for (final row in indexed) row.key], ['run-1002', 'run-1004']);
    expect(cellBuilderCalls, 0);

    final exact = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'run-10',
        mode: TreeTableFilterMode.exactToken,
      ),
      searchIndex: index,
    );
    expect(exact, isEmpty);
  });

  test('TreeTableSearchIndex can build cooperatively', () async {
    const roots = [
      TreeTableNode<String>(
        key: 'app',
        label: 'App',
        cells: {'status': 'ready', 'owner': 'platform'},
        children: [
          TreeTableNode<String>(
            key: 'agent',
            label: 'Agent Runner',
            cells: {'status': 'running', 'owner': 'team:runtime'},
            metadata: {'target': 'zz-target_42'},
          ),
          TreeTableNode<String>(
            key: 'logs',
            label: 'Logs',
            cells: {'status': 'warning', 'owner': 'ops'},
          ),
        ],
      ),
    ];
    final controller = TaskController<TreeTableSearchIndex<String>>(
      id: 'tree-index',
    );

    final result = await controller.start(
      (context) => TreeTableSearchIndex.buildCooperatively<String>(
        roots: roots,
        columns: _columns,
        context: context,
        yieldPolicy: const TaskYieldPolicy(
          itemBudget: 1,
          elapsedBudget: Duration(days: 1),
        ),
        progressLabel: 'index tree',
      ),
    );

    expect(result.succeeded, isTrue);
    final index = result.value!;
    expect(index.rowCount, 3);
    expect(controller.progress?.label, 'index tree complete');
    expect(
      controller.events.where((event) => event.kind == TaskEventKind.progress),
      hasLength(greaterThanOrEqualTo(3)),
    );

    final filtered = buildTreeTableRows<String>(
      roots: roots,
      columns: _columns,
      filter: const TreeTableFilterDescriptor(
        query: 'zz-target_42',
        mode: TreeTableFilterMode.exactToken,
      ),
      searchIndex: index,
    );
    expect([for (final row in filtered) row.key], ['app', 'agent']);

    controller.dispose();
  });

  group('copy/export', () {
    testWidgets('Ctrl+C copies the selected visible tree row', (tester) async {
      final controller = TreeTableController(
        selectedIndex: 1,
        expandedKeys: const {'app'},
      );
      TreeTableCopyResult<String>? copied;
      tester.pumpWidget(
        TreeTable<String>(
          roots: _roots,
          columns: _columns,
          controller: controller,
          autofocus: true,
          copyOptions: const TreeTableCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(60, 8));
      tester.sendKey(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        tester.clipboard.readInProcess(),
        'Name\tStatus\tOwner\n  Search\tpassed\ttooling',
      );
      expect(copied, isNotNull);
      expect(copied!.rowIndex, 1);
      expect(copied!.rowKey, 'search');
      expect(copied!.row.key, 'search');
      expect(copied!.report.policy.name, 'inProcessOnly');
    });

    testWidgets('semantic copy copies the selected visible tree row', (
      tester,
    ) async {
      final controller = TreeTableController(
        selectedIndex: 1,
        expandedKeys: const {'app'},
      );
      TreeTableCopyResult<String>? copied;
      tester.pumpWidget(
        TreeTable<String>(
          roots: _roots,
          columns: _columns,
          controller: controller,
          copyOptions: const TreeTableCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(60, 8));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.treeItem,
        label: 'Search',
      );

      expect(result.completed, isTrue);
      expect(
        tester.clipboard.readInProcess(),
        'Name\tStatus\tOwner\n  Search\tpassed\ttooling',
      );
      expect(copied?.rowKey, 'search');
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    test('exportTreeTableRows supports CSV escaping and no indentation', () {
      final rows = buildTreeTableRows<String>(
        roots: const [
          TreeTableNode<String>(
            key: 'root',
            label: 'Root, Node',
            cells: {'status': 'ok'},
          ),
        ],
        columns: _columns,
      );
      final result = exportTreeTableRows<String>(
        rows: rows,
        columns: _columns,
        options: const TreeTableExportOptions(
          format: DataTableExportFormat.csv,
          includeTreeIndent: false,
        ),
      );

      expect(result.text, 'Name,Status,Owner\n"Root, Node",ok,');
      expect(result.rowCount, 1);
      expect(result.columnCount, 3);
      expect(result.truncated, isFalse);
    });
  });

  group('flattened row-model cache', () {
    // Rebuild cost is observed through cellBuilder: with an active filter and
    // no search index, buildTreeTableRows invokes cellBuilder once (for the
    // non-tree column) per visited node, so a full re-flatten adds at least
    // [nodeCount] invocations. Cell paint also calls cellBuilder, but only
    // for the mounted window (maxVisible rows), which stays far below
    // [nodeCount].
    const nodeCount = 200;
    const maxVisible = 4;
    const cacheColumns = [
      DataTableColumn(id: 'name', title: 'Name', width: FixedColumnWidth(18)),
      DataTableColumn(
        id: 'status',
        title: 'Status',
        width: FixedColumnWidth(12),
      ),
    ];
    final cacheRoots = List<TreeTableNode<String>>.unmodifiable([
      const TreeTableNode<String>(
        key: 'row-0',
        label: 'row-0',
        cells: {'status': 'status-0'},
        children: [
          TreeTableNode<String>(
            key: 'row-0-child',
            label: 'row-0-child',
            cells: {'status': 'status-child'},
          ),
        ],
      ),
      for (var i = 1; i < nodeCount; i++)
        TreeTableNode<String>(
          key: 'row-$i',
          label: 'row-$i',
          cells: {'status': 'status-$i'},
        ),
    ]);

    testWidgets('selection moves reuse the cached model; expansion and '
        'identity changes re-flatten', (tester) {
      var cellBuilderCalls = 0;
      String cellBuilder(TreeTableNode<String> node, String columnId) {
        cellBuilderCalls += 1;
        return node.cells[columnId] ?? '';
      }

      final controller = TreeTableController();
      addTearDown(controller.dispose);
      // Matches every node, so each flatten visits (and cell-builds) all of
      // them. Deliberately non-const: identity is the cache key.
      final stableFilter = TreeTableFilterDescriptor(query: 'row');
      TreeTable<String> buildTable({
        List<TreeTableNode<String>>? roots,
        TreeTableFilterDescriptor? filter,
      }) => TreeTable<String>(
        roots: roots ?? cacheRoots,
        columns: cacheColumns,
        controller: controller,
        autofocus: true,
        maxVisible: maxVisible,
        cellBuilder: cellBuilder,
        filter: filter ?? stableFilter,
      );

      tester.pumpWidget(buildTable());
      tester.render(size: const CellSize(60, 10));
      expect(
        cellBuilderCalls,
        greaterThanOrEqualTo(nodeCount),
        reason: 'the first build must flatten the full model',
      );

      // Arrow-key selection move: no re-flatten, only the mounted window
      // rebuilds.
      cellBuilderCalls = 0;
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.render(size: const CellSize(60, 10));
      expect(controller.selectedIndex, 1);
      expect(
        cellBuilderCalls,
        lessThan(nodeCount),
        reason: 'a selection move must not re-flatten the row model',
      );

      // Re-pumping a new widget instance whose inputs are identical reuses
      // the cache.
      cellBuilderCalls = 0;
      tester.pumpWidget(buildTable());
      tester.render(size: const CellSize(60, 10));
      expect(
        cellBuilderCalls,
        lessThan(nodeCount),
        reason: 'identical inputs must not re-flatten on rebuild',
      );

      // Expansion state is structural: toggling re-flattens.
      cellBuilderCalls = 0;
      controller.expand('row-0');
      tester.pump();
      tester.render(size: const CellSize(60, 10));
      expect(
        cellBuilderCalls,
        greaterThanOrEqualTo(nodeCount),
        reason: 'an expansion change must rebuild the row model',
      );
      cellBuilderCalls = 0;
      controller.collapse('row-0');
      tester.pump();
      tester.render(size: const CellSize(60, 10));
      expect(
        cellBuilderCalls,
        greaterThanOrEqualTo(nodeCount),
        reason: 'a collapse must rebuild the row model',
      );

      // A fresh roots list (same contents, new identity) re-flattens.
      cellBuilderCalls = 0;
      tester.pumpWidget(buildTable(roots: List.of(cacheRoots)));
      tester.render(size: const CellSize(60, 10));
      expect(
        cellBuilderCalls,
        greaterThanOrEqualTo(nodeCount),
        reason: 'a new roots identity must rebuild the row model',
      );

      // A fresh filter instance (equal by value, new identity) re-flattens.
      cellBuilderCalls = 0;
      tester.pumpWidget(
        buildTable(filter: TreeTableFilterDescriptor(query: 'row')),
      );
      tester.render(size: const CellSize(60, 10));
      expect(
        cellBuilderCalls,
        greaterThanOrEqualTo(nodeCount),
        reason: 'a new filter identity must rebuild the row model',
      );
    });

    testWidgets('a new searchIndex instance invalidates the cached model', (
      tester,
    ) {
      // The second index covers only the first two nodes; a stale cached
      // model would keep every row visible.
      final controller = TreeTableController();
      addTearDown(controller.dispose);
      final filter = TreeTableFilterDescriptor(query: 'row');
      final fullIndex = TreeTableSearchIndex<String>.build(
        roots: cacheRoots,
        columns: cacheColumns,
      );
      final subsetIndex = TreeTableSearchIndex<String>.build(
        roots: cacheRoots.sublist(0, 2),
        columns: cacheColumns,
      );
      TreeTable<String> buildTable(TreeTableSearchIndex<String> index) =>
          TreeTable<String>(
            roots: cacheRoots,
            columns: cacheColumns,
            controller: controller,
            maxVisible: maxVisible,
            filter: filter,
            searchIndex: index,
          );

      tester.pumpWidget(buildTable(fullIndex));
      tester.render(size: const CellSize(60, 10));
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.tree)
            .state
            .collectionRowCount,
        nodeCount + 1,
      );

      tester.pumpWidget(buildTable(subsetIndex));
      tester.render(size: const CellSize(60, 10));
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.tree)
            .state
            .collectionRowCount,
        3,
        reason: 'the swapped-in index must be consulted, not the stale cache',
      );
    });

    testWidgets('post-expansion cached model matches a from-scratch flatten', (
      tester,
    ) {
      final controller = TreeTableController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        TreeTable<String>(
          roots: _roots,
          columns: _columns,
          controller: controller,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(60, 8));

      controller.expand('app');
      tester.pump();
      tester.render(size: const CellSize(60, 8));

      List<Object?> visibleRowKeys() {
        final items = tester.semantics().byRole(SemanticRole.treeItem).toList()
          ..sort(
            (a, b) =>
                (a.state['rowIndex']! as int) - (b.state['rowIndex']! as int),
          );
        return [for (final item in items) item.state['rowKey']];
      }

      final expected = buildTreeTableRows<String>(
        roots: _roots,
        columns: _columns,
        expandedKeys: controller.expandedKeys,
      );
      expect(visibleRowKeys(), [for (final row in expected) row.key]);
      expect(visibleRowKeys(), ['app', 'search', 'logs', 'docs']);

      controller.collapse('app');
      tester.pump();
      tester.render(size: const CellSize(60, 8));
      expect(visibleRowKeys(), ['app', 'docs']);
    });

    testWidgets('selection clamps against the cached model after collapse', (
      tester,
    ) {
      final controller = TreeTableController(
        selectedIndex: 3,
        expandedKeys: const {'app'},
      );
      addTearDown(controller.dispose);
      tester.pumpWidget(
        TreeTable<String>(
          roots: _roots,
          columns: _columns,
          controller: controller,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(60, 8));
      expect(
        tester.semantics().single(role: SemanticRole.tree).state.selectedKey,
        'docs',
      );

      controller.collapseAll();
      tester.pump();
      tester.render(size: const CellSize(60, 8));

      final tree = tester.semantics().single(role: SemanticRole.tree);
      expect(tree.state.collectionRowCount, 2);
      expect(tree.state['selectedIndex'], 1);
      expect(tree.state.selectedKey, 'docs');
    });
  });

  testWidgets(
    'sanitizes unsafe labels and cells for display/search/semantics',
    (tester) {
      const unsafeRows = [
        TreeTableNode<String>(
          key: 'unsafe',
          label: 'bad\x1b]52;c;secret\x07\nnode',
          cells: {'status': 'ok\tvalue'},
        ),
      ];

      expect(
        buildTreeTableRows<String>(
          roots: unsafeRows,
          columns: _columns,
          filter: const TreeTableFilterDescriptor(query: 'secret'),
        ),
        isEmpty,
      );
      final unsafeIndex = TreeTableSearchIndex<String>.build(
        roots: unsafeRows,
        columns: _columns,
      );
      expect(
        buildTreeTableRows<String>(
          roots: unsafeRows,
          columns: _columns,
          filter: const TreeTableFilterDescriptor(query: 'secret'),
          searchIndex: unsafeIndex,
        ),
        isEmpty,
      );

      tester.pumpWidget(
        const TreeTable<String>(roots: unsafeRows, columns: _columns),
      );
      final output = tester.renderToString(
        size: const CellSize(60, 6),
        emptyMark: ' ',
      );

      expect(output, contains('bad'));
      expect(output, contains('node'));
      expect(output, contains('ok value'));
      expect(output, contains(replacementCharacter));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final row = tester.semantics().single(role: SemanticRole.treeItem);
      expect(row.label, contains(replacementCharacter));
      expect(row.state.outputSanitized, isTrue);

      final status = tester
          .semantics()
          .byRole(SemanticRole.tableCell)
          .singleWhere((node) => node.state['columnId'] == 'status');
      expect(status.label, 'ok value');
      expect(status.state.outputSanitized, isTrue);
    },
  );
}
