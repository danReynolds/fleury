import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<String> _lines(
  FleuryTester tester, {
  required int cols,
  required int rows,
}) {
  final buf = tester.render(size: CellSize(cols, rows));
  return [
    for (var r = 0; r < rows; r++)
      [
        for (var c = 0; c < cols; c++)
          buf.atColRow(c, r).role == CellRole.leading
              ? buf.atColRow(c, r).grapheme!
              : ' ',
      ].join().trimRight(),
  ];
}

List<DataTableColumn> _columns() {
  return const [
    DataTableColumn(id: 'run', title: 'Run', width: FixedColumnWidth(8)),
    DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(8)),
  ];
}

String _cell(int rowIndex, String columnId) {
  return switch (columnId) {
    'run' => 'run-$rowIndex',
    'status' => rowIndex.isEven ? 'ok' : 'failed',
    _ => '',
  };
}

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('DataTableController lifecycle', () {
    testWidgets('dispose is idempotent and keeps final readable state', (
      tester,
    ) {
      final controller = DataTableController();
      tester.pumpWidget(
        DataTable(
          rowCount: 4,
          columns: _columns(),
          controller: controller,
          cellBuilder: _cell,
        ),
      );

      controller.selectCell(2, 1);
      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 2);
      expect(controller.selectedColumnIndex, 1);
      expect(controller.selectionRange.startRow, 2);
      expect(controller.selectionRange.endRow, 2);
      expect(controller.selectionRange.startColumn, 1);
      expect(controller.selectionRange.endColumn, 1);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = DataTableController()..dispose();

      const message = 'DataTableController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.selectedColumnIndex = 1, _stateError(message));
      expect(() => controller.selectCell(1, 1), _stateError(message));
      expect(() => controller.moveSelection(rowDelta: 1), _stateError(message));
    });
  });

  group('semantic id stability (RFC A1/A2)', () {
    DataTable runs({bool keyed = true}) => DataTable(
      label: 'Runs',
      rowCount: 100,
      columns: _columns(),
      rowKeyBuilder: keyed ? (row) => 'RUN-$row' : null,
      cellBuilder: _cell,
    );

    testWidgets('a keyed-row table gives rows a stable, ~-free id that '
        'survives a from-scratch rebuild', (tester) {
      tester.pumpWidget(runs());
      tester.render(size: const CellSize(20, 6));
      final rowId = tester
          .semantics()
          .single(role: SemanticRole.tableRow, label: 'RUN-0')
          .id;
      expect(rowId.value, contains('/table/row/RUN-0'));
      expect(
        rowId.value,
        isNot(contains('/row/~')),
        reason: 'a real row key is stable, not positional',
      );

      // Rebuild from scratch: the row id is identical — derived from the row
      // key, not the (now-different) element instance.
      tester.pumpWidget(const SizedBox());
      tester.pumpWidget(runs());
      tester.render(size: const CellSize(20, 6));
      final rowId2 = tester
          .semantics()
          .single(role: SemanticRole.tableRow, label: 'RUN-0')
          .id;
      expect(rowId2, rowId);
    });

    testWidgets('a row key containing / or ~ is escaped, so it cannot inject a '
        'segment or collide', (tester) {
      tester.pumpWidget(
        DataTable(
          label: 'Runs',
          rowCount: 10,
          columns: _columns(),
          rowKeyBuilder: (row) => 'a/b~$row',
          cellBuilder: _cell,
        ),
      );
      tester.render(size: const CellSize(20, 6));
      final rowId = tester
          .semantics()
          .byRole(SemanticRole.tableRow)
          .firstWhere((n) => n.state['rowIndex'] == 0)
          .id
          .value;
      // The row key 'a/b~0' is folded escaped, so it adds exactly one segment
      // ('row/<key>') and its '/' can't fork the path or alias another row.
      expect(rowId, contains('/table/row/a%2Fb%7E0'));
      expect(rowId, isNot(contains('row/a/b')));
    });

    testWidgets('a table without a rowKeyBuilder marks its index-keyed rows ~',
        (tester) {
      tester.pumpWidget(runs(keyed: false));
      tester.render(size: const CellSize(20, 6));
      final rowId = tester
          .semantics()
          .byRole(SemanticRole.tableRow)
          .firstWhere((n) => n.state['rowIndex'] == 0)
          .id;
      expect(
        rowId.value,
        contains('/table/row/~0'),
        reason: 'an index-based row is positional / version-fragile',
      );
    });
  });

  testWidgets('setValue(index) jumps the window to an off-screen row (R1 reach)',
      (tester) async {
    tester.pumpWidget(
      DataTable(
        label: 'Runs',
        rowCount: 100000,
        columns: _columns(),
        rowKeyBuilder: (row) => 'RUN-$row',
        cellBuilder: _cell,
      ),
    );
    tester.render(size: const CellSize(20, 6));

    final table = tester.semantics().single(role: SemanticRole.table);
    expect(table.actions, contains(SemanticAction.setValue));
    expect(table.state['collectionRowCount'], 100000);
    // Row 5000 is far off-window — absent from the tree, unreachable by id.
    expect(
      tester
          .semantics()
          .byRole(SemanticRole.tableRow)
          .where((n) => n.state['rowIndex'] == 5000),
      isEmpty,
    );

    await tester.invokeSemanticAction(SemanticAction.setValue,
        node: table, payload: 5000);
    tester.render(size: const CellSize(20, 6)); // relayout windows row 5000 in

    expect(
      tester
          .semantics()
          .byRole(SemanticRole.tableRow)
          .where((n) => n.state['rowIndex'] == 5000),
      isNotEmpty,
      reason: 'the window followed the selection to the requested index',
    );

    // Out-of-range index is clamped to the last row, not rejected.
    await tester.invokeSemanticAction(SemanticAction.setValue,
        role: SemanticRole.table, payload: 999999);
    tester.render(size: const CellSize(20, 6));
    expect(
      tester
          .semantics()
          .byRole(SemanticRole.tableRow)
          .where((n) => n.state['rowIndex'] == 99999),
      isNotEmpty,
    );
  });

  testWidgets('setValue routes to the targeted table, not a sibling '
      '(no cross-fire, no per-widget ownership guard)', (tester) async {
    // Two tables in one tree. Before WS-3 the dispatch walk offered a setValue
    // to the first DataTable contributor it reached, so an action aimed at B
    // could be swallowed by A (only a per-widget `_ownsTarget` check, since
    // removed, masked it). The id→element dispatch map must route a setValue to
    // exactly the table whose node id was targeted.
    final controllerA = DataTableController();
    final controllerB = DataTableController();
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);

    tester.pumpWidget(
      Row(
        children: [
          Expanded(
            child: DataTable(
              key: const ValueKey('table-a'),
              label: 'A',
              rowCount: 50,
              columns: _columns(),
              rowKeyBuilder: (row) => 'A-$row',
              cellBuilder: _cell,
              controller: controllerA,
            ),
          ),
          Expanded(
            child: DataTable(
              key: const ValueKey('table-b'),
              label: 'B',
              rowCount: 50,
              columns: _columns(),
              rowKeyBuilder: (row) => 'B-$row',
              cellBuilder: _cell,
              controller: controllerB,
            ),
          ),
        ],
      ),
    );
    tester.render(size: const CellSize(48, 8));

    // setValue on table B (resolved by role+label) → B moves, A is untouched.
    await tester.invokeSemanticAction(SemanticAction.setValue,
        role: SemanticRole.table, label: 'B', payload: 7);
    tester.render(size: const CellSize(48, 8));

    expect(controllerB.selectedIndex, 7, reason: 'B (the target) moved');
    expect(controllerA.selectedIndex, 0, reason: 'A (a sibling) is untouched');
  });

  testWidgets('a sortable header activates to request a sort; state carries '
      'the active direction', (tester) async {
    String? sorted;
    DataTable build({void Function(String)? onSort}) => DataTable(
      label: 'Runs',
      rowCount: 10,
      columns: _columns(),
      rowKeyBuilder: (row) => 'RUN-$row',
      cellBuilder: _cell,
      sortColumnId: 'run',
      sortDirection: DataTableSortDirection.descending,
      onSort: onSort,
    );

    SemanticNode header(FleuryTester t, String columnId) => t
        .semantics()
        .byRole(SemanticRole.tableCell)
        .firstWhere(
          (n) => n.state['header'] == true && n.state['columnId'] == columnId,
        );

    // No onSort ⇒ headers aren't activatable.
    tester.pumpWidget(build());
    tester.render(size: const CellSize(24, 6));
    expect(
      header(tester, 'run').actions,
      isNot(contains(SemanticAction.activate)),
    );

    // With onSort, a header advertises activate; the sorted column carries the
    // active direction so an agent can see/toggle it.
    tester.pumpWidget(build(onSort: (id) => sorted = id));
    tester.render(size: const CellSize(24, 6));
    final runHeader = header(tester, 'run');
    expect(runHeader.actions, contains(SemanticAction.activate));
    expect(runHeader.state['sortDirection'], 'descending');
    expect(header(tester, 'status').state['sortDirection'], isNull);

    await tester.invokeSemanticAction(SemanticAction.activate, node: runHeader);
    expect(sorted, 'run');
    await tester.invokeSemanticAction(
      SemanticAction.activate,
      node: header(tester, 'status'),
    );
    expect(sorted, 'status');
  });

  testWidgets('renders visible rows only and exposes virtualized semantics', (
    tester,
  ) {
    final requestedRows = <int>{};
    tester.pumpWidget(
      DataTable(
        label: 'Runs table',
        rowCount: 100000,
        columns: _columns(),
        rowKeyBuilder: (row) => 'RUN-$row',
        cellBuilder: (row, column) {
          requestedRows.add(row);
          return _cell(row, column);
        },
      ),
    );

    final out = tester.renderToString(
      size: const CellSize(20, 6),
      emptyMark: ' ',
    );

    expect(out, contains('Run'));
    expect(out, contains('run-0'));
    expect(out, contains('run-3'));
    expect(out, isNot(contains('run-4')));
    expect(out, isNot(contains('run-99999')));
    expect(requestedRows, {0, 1, 2, 3});

    final tree = tester.semantics();
    final table = tree.single(role: SemanticRole.table, label: 'Runs table');
    expect(table.state.collectionRowCount, 100000);
    expect(table.state.collectionColumnCount, 2);
    expect(table.state.values['hasHeader'], isTrue);
    expect(table.state.values['virtualized'], isTrue);
    expect(table.state.visibleRangeStart, 0);
    expect(table.state.visibleRangeEnd, 3);
    expect(table.state.selectedKey, 'RUN-0');

    expect(tree.byRole(SemanticRole.tableRow), hasLength(5));
    expect(tree.byRole(SemanticRole.tableCell), hasLength(10));
    expect(
      tree.single(role: SemanticRole.tableCell, label: 'run-3').state['rowKey'],
      'RUN-3',
    );
    expect(tree.byLabel('run-99999'), isEmpty);
  });

  testWidgets('keyboard movement scrolls the window and updates selection', (
    tester,
  ) {
    final controller = DataTableController();
    int? selected;
    tester.pumpWidget(
      DataTable(
        rowCount: 20,
        columns: _columns(),
        controller: controller,
        autofocus: true,
        rowKeyBuilder: (row) => 'RUN-$row',
        cellBuilder: _cell,
        onSelect: (row) => selected = row,
      ),
    );

    var lines = _lines(tester, cols: 20, rows: 5);
    expect(lines[0], 'Run      Status');
    expect(lines[2], 'run-0    ok');
    expect(lines[3], 'run-1    failed');
    expect(lines[4], 'run-2    ok');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.pageDown));
    expect(controller.selectedIndex, 3);
    lines = _lines(tester, cols: 20, rows: 5);
    expect(lines[0], 'Run      Status');
    expect(lines[2], 'run-1    failed');
    expect(lines[3], 'run-2    ok');
    expect(lines[4], 'run-3    failed');

    final table = tester.semantics().single(role: SemanticRole.table);
    expect(table.state.visibleRangeStart, 1);
    expect(table.state.visibleRangeEnd, 3);
    expect(table.state.selectedKey, 'RUN-3');
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.tableRow, selected: true)
          .state['rowKey'],
      'RUN-3',
    );

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(selected, 3);
  });

  testWidgets('mouse click selects a visible DataTable row', (tester) {
    final controller = DataTableController();
    tester.pumpWidget(
      DataTable(
        rowCount: 8,
        columns: _columns(),
        controller: controller,
        rowKeyBuilder: (row) => 'RUN-$row',
        cellBuilder: _cell,
      ),
    );

    tester.render(size: const CellSize(20, 6));
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 1,
        row: 4,
      ),
    );
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 1,
        row: 4,
      ),
    );

    expect(controller.selectedIndex, 2);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.tableRow, selected: true)
          .state['rowKey'],
      'RUN-2',
    );
    expect(tester.semantics().single(role: SemanticRole.table).focused, isTrue);
  });

  testWidgets('wheel scroll moves the DataTable selection', (tester) {
    final controller = DataTableController();
    tester.pumpWidget(
      DataTable(
        rowCount: 8,
        columns: _columns(),
        controller: controller,
        rowKeyBuilder: (row) => 'RUN-$row',
        cellBuilder: _cell,
      ),
    );
    tester.render(size: const CellSize(20, 6));
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.scrollDown,
        button: MouseButton.none,
        col: 1,
        row: 2,
      ),
    );
    expect(controller.selectedIndex, 1, reason: 'scrolled down one row');
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.scrollUp,
        button: MouseButton.none,
        col: 1,
        row: 2,
      ),
    );
    expect(controller.selectedIndex, 0, reason: 'scrolled back up');
  });

  testWidgets('mouse click selects cells and Shift-click extends range', (
    tester,
  ) {
    final controller = DataTableController();
    tester.pumpWidget(
      DataTable(
        rowCount: 8,
        columns: _columns(),
        controller: controller,
        rowKeyBuilder: (row) => 'RUN-$row',
        cellBuilder: _cell,
        selectionMode: DataTableSelectionMode.cell,
      ),
    );

    tester.render(size: const CellSize(20, 6));
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 10,
        row: 3,
        modifiers: {KeyModifier.shift},
      ),
    );
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 10,
        row: 3,
        modifiers: {KeyModifier.shift},
      ),
    );

    expect(controller.selectedIndex, 1);
    expect(controller.selectedColumnIndex, 1);
    final table = tester.semantics().single(role: SemanticRole.table);
    expect(table.state.selectionStartRow, 0);
    expect(table.state.selectionEndRow, 1);
    expect(table.state.selectionStartColumn, 0);
    expect(table.state.selectionEndColumn, 1);
    expect(
      tester.semantics().where(role: SemanticRole.tableCell, selected: true),
      hasLength(4),
    );
  });

  testWidgets('semantic select and activate update DataTable selection', (
    tester,
  ) async {
    final controller = DataTableController();
    int? selected;
    tester.pumpWidget(
      DataTable(
        rowCount: 6,
        columns: _columns(),
        controller: controller,
        rowKeyBuilder: (row) => 'RUN-$row',
        cellBuilder: _cell,
        onSelect: (row) => selected = row,
      ),
    );

    tester.render(size: const CellSize(20, 6));
    final targetRow = tester.semantics().single(
      role: SemanticRole.tableRow,
      label: 'RUN-2',
      action: SemanticAction.select,
    );

    var result = await tester.invokeSemanticAction(
      SemanticAction.select,
      node: targetRow,
    );

    expect(result.completed, isTrue);
    expect(controller.selectedIndex, 2);
    expect(tester.semantics().single(role: SemanticRole.table).focused, isTrue);

    final selectedRow = tester.semantics().single(
      role: SemanticRole.tableRow,
      label: 'RUN-2',
      selected: true,
      action: SemanticAction.activate,
    );
    result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      node: selectedRow,
    );

    expect(result.completed, isTrue);
    expect(selected, 2);
  });

  testWidgets('sort and filter metadata are semantic state', (tester) {
    tester.pumpWidget(
      DataTable(
        rowCount: 4,
        columns: _columns(),
        cellBuilder: _cell,
        sortColumnId: 'status',
        sortDirection: DataTableSortDirection.descending,
        filterText: 'failed',
      ),
    );
    tester.render(size: const CellSize(20, 6));

    final table = tester.semantics().single(role: SemanticRole.table);
    expect(table.state.sortColumn, 'status');
    expect(table.state.sortDirection, 'descending');
    expect(table.state.filterText, 'failed');
  });

  testWidgets('cell text is sanitized and clipped before painting', (tester) {
    tester.pumpWidget(
      DataTable(
        rowCount: 1,
        columns: const [
          DataTableColumn(
            id: 'name',
            title: 'Name',
            width: FixedColumnWidth(6),
          ),
        ],
        cellBuilder: (_, _) => 'abc\x1b[31m\nlong-tail',
      ),
    );

    final out = tester.renderToString(
      size: const CellSize(6, 3),
      emptyMark: ' ',
    );

    expect(out, contains('abc'));
    expect(out, isNot(contains('\x1b')));
    expect(out, isNot(contains('[31m')));
    expect(out, isNot(contains('long-tail')));
  });

  test('exports rows as CSV with quoting and sanitized fields', () {
    final result = exportDataTableRows(
      rowCount: 1,
      columns: const [
        DataTableColumn(id: 'name', title: 'Name'),
        DataTableColumn(id: 'note', title: 'Note'),
      ],
      cellBuilder: (_, column) => switch (column) {
        'name' => 'alpha,beta',
        'note' => 'say "hi"\nnext',
        _ => '',
      },
      options: const DataTableExportOptions(format: DataTableExportFormat.csv),
    );

    expect(result.text, 'Name,Note\n"alpha,beta","say ""hi"" next"');
    expect(result.rowCount, 1);
    expect(result.columnCount, 2);
    expect(result.truncated, isFalse);
  });

  test('exports rectangular row and column ranges', () {
    final result = exportDataTableRows(
      rowCount: 4,
      columns: const [
        DataTableColumn(id: 'a', title: 'A'),
        DataTableColumn(id: 'b', title: 'B'),
        DataTableColumn(id: 'c', title: 'C'),
      ],
      cellBuilder: (row, column) => '$column-$row',
      options: const DataTableExportOptions(
        startRow: 1,
        maxRows: 2,
        startColumn: 1,
        maxColumns: 2,
      ),
    );

    expect(result.text, 'B\tC\nb-1\tc-1\nb-2\tc-2');
    expect(result.rowCount, 2);
    expect(result.columnCount, 2);
    expect(result.startRow, 1);
    expect(result.startColumn, 1);
    expect(result.truncated, isTrue);
  });

  test('buildDataTableRowOrder filters and sorts source rows', () {
    final order = buildDataTableRowOrder(
      rowCount: 5,
      columns: _columns(),
      cellBuilder: (int row, String column) => switch (column) {
        'run' => 'run-$row',
        'status' => row.isOdd ? 'failed' : 'ok',
        _ => '',
      },
      filter: const DataTableFilterDescriptor(
        query: 'failed',
        columnIds: {'status'},
      ),
      sort: const DataTableSortDescriptor(
        columnId: 'run',
        direction: DataTableSortDirection.descending,
      ),
    );

    expect(order, [3, 1]);
  });

  test('buildDataTableRowOrder caches sort keys while sorting', () {
    var sortColumnCalls = 0;
    final order = buildDataTableRowOrder(
      rowCount: 6,
      columns: _columns(),
      cellBuilder: (int row, String column) {
        if (column == 'run') {
          sortColumnCalls += 1;
          return 'run-${6 - row}';
        }
        if (column == 'status') return 'failed';
        return '';
      },
      sort: const DataTableSortDescriptor(columnId: 'run'),
    );

    expect(order, [5, 4, 3, 2, 1, 0]);
    expect(sortColumnCalls, 6);
  });

  group('copy/export', () {
    late Clipboard originalClipboard;
    late TestClipboard clipboard;

    setUp(() {
      originalClipboard = Clipboard.instance;
      clipboard = TestClipboard();
      Clipboard.instance = clipboard;
    });

    tearDown(() {
      Clipboard.instance = originalClipboard;
    });

    testWidgets('Ctrl+C copies the selected row with clipboard semantics', (
      tester,
    ) async {
      final controller = DataTableController(selectedIndex: 1);
      DataTableCopyResult? copied;
      tester.pumpWidget(
        DataTable(
          rowCount: 4,
          columns: _columns(),
          controller: controller,
          autofocus: true,
          rowKeyBuilder: (row) => 'RUN-$row',
          cellBuilder: _cell,
          copyOptions: const DataTableCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(20, 6));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(clipboard.lastWritten, 'Run\tStatus\nrun-1\tfailed');
      expect(copied, isNotNull);
      expect(copied!.rowIndex, 1);
      expect(copied!.rowKey, 'RUN-1');
      expect(copied!.text, 'Run\tStatus\nrun-1\tfailed');
      expect(copied!.report.policy.name, 'inProcessOnly');
      expect(copied!.report.result, ClipboardWriteResult.inProcessOnly);

      final table = tester.semantics().single(
        role: SemanticRole.table,
        action: SemanticAction.copy,
      );
      expect(table.state['copyEnabled'], isTrue);
      expect(table.state['copyFormat'], 'tsv');
      expect(table.state['copyIncludesHeader'], isTrue);
      expect(table.state.clipboardPolicy, 'inProcessOnly');
      expect(table.state.clipboardCapability, 'clipboardWrite');
      expect(table.state.clipboardCapabilityResolution, 'available');

      final selectedRow = tester.semantics().single(
        role: SemanticRole.tableRow,
        selected: true,
        action: SemanticAction.copy,
      );
      expect(selectedRow.state['rowKey'], 'RUN-1');
    });

    testWidgets('semantic copy copies the current DataTable selection', (
      tester,
    ) async {
      final controller = DataTableController(selectedIndex: 1);
      DataTableCopyResult? copied;
      tester.pumpWidget(
        DataTable(
          rowCount: 4,
          columns: _columns(),
          controller: controller,
          rowKeyBuilder: (row) => 'RUN-$row',
          cellBuilder: _cell,
          copyOptions: const DataTableCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(20, 6));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.table,
      );

      expect(result.completed, isTrue);
      expect(clipboard.lastWritten, 'Run\tStatus\nrun-1\tfailed');
      expect(copied?.rowKey, 'RUN-1');
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    testWidgets('cell mode extends a rectangular range and copies it', (
      tester,
    ) async {
      final controller = DataTableController();
      DataTableCopyResult? copied;
      tester.pumpWidget(
        DataTable(
          rowCount: 4,
          columns: _columns(),
          controller: controller,
          autofocus: true,
          rowKeyBuilder: (row) => 'RUN-$row',
          cellBuilder: _cell,
          selectionMode: DataTableSelectionMode.cell,
          copyOptions: const DataTableCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(20, 6));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowDown,
          modifiers: {KeyModifier.shift},
        ),
      );
      tester.render(size: const CellSize(20, 6));

      var tree = tester.semantics();
      final table = tree.single(role: SemanticRole.table);
      expect(table.state.selectionMode, 'cell');
      expect(table.state.selectedColumnIndex, 1);
      expect(table.state.selectedColumnId, 'status');
      expect(table.state.selectionStartRow, 0);
      expect(table.state.selectionEndRow, 1);
      expect(table.state.selectionStartColumn, 1);
      expect(table.state.selectionEndColumn, 1);
      expect(
        tree.where(role: SemanticRole.tableCell, selected: true),
        hasLength(2),
      );

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(clipboard.lastWritten, 'Status\nok\nfailed');
      expect(copied, isNotNull);
      expect(copied!.rowIndex, 1);
      expect(copied!.rowKey, 'RUN-1');
      expect(copied!.selection.startRow, 0);
      expect(copied!.selection.endRow, 1);
      expect(copied!.selection.startColumn, 1);
      expect(copied!.selection.endColumn, 1);
      expect(copied!.export.columnCount, 1);
    });

    testWidgets('copy sanitizes fields and only builds the selected row', (
      tester,
    ) async {
      final requestedRows = <int>{};
      final controller = DataTableController(selectedIndex: 2);
      tester.pumpWidget(
        DataTable(
          rowCount: 5,
          columns: const [DataTableColumn(id: 'name', title: 'Name')],
          controller: controller,
          autofocus: true,
          cellBuilder: (row, _) {
            requestedRows.add(row);
            return 'abc\x1b[31m\nlong\tcell';
          },
        ),
      );
      tester.render(size: const CellSize(20, 5));
      requestedRows.clear();

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(clipboard.lastWritten, 'Name\nabc long cell');
      expect(clipboard.lastWritten, isNot(contains('\x1b')));
      expect(clipboard.lastWritten, isNot(contains('[31m')));
      expect(requestedRows, {2});
    });

    testWidgets('copySelectedRow false lets Ctrl+C bubble without writing', (
      tester,
    ) async {
      tester.pumpWidget(
        DataTable(
          rowCount: 1,
          columns: _columns(),
          autofocus: true,
          copySelectedRow: false,
          cellBuilder: _cell,
        ),
      );

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(clipboard.lastWritten, isNull);
      final table = tester.semantics().single(role: SemanticRole.table);
      expect(table.actions, isNot(contains(SemanticAction.copy)));
      expect(table.state['copyEnabled'], isNull);
    });
  });
}
