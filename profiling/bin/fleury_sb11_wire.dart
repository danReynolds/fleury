import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runApp(
    _WireTreeTableApp(
      driver: driver,
      rows: options.rows,
      steps: options.steps,
      interval: options.interval,
    ),
    driver: driver,
    frameInterval: const Duration(milliseconds: 16),
  );
}

final class _WireOptions {
  const _WireOptions({
    required this.rows,
    required this.steps,
    required this.interval,
  });

  factory _WireOptions.parse(List<String> args) {
    var rows = 100000;
    var steps = 6;
    var intervalMs = 80;

    for (final arg in args) {
      if (arg.startsWith('--rows=')) {
        rows = positiveInt(arg, '--rows=');
      } else if (arg.startsWith('--steps=')) {
        steps = positiveInt(arg, '--steps=');
      } else if (arg.startsWith('--interval-ms=')) {
        intervalMs = positiveInt(arg, '--interval-ms=');
      } else if (arg == '--help' || arg == '-h') {
        _printUsage();
      } else {
        throw ArgumentError('unknown argument: $arg');
      }
    }

    return _WireOptions(
      rows: rows,
      steps: steps,
      interval: Duration(milliseconds: intervalMs),
    );
  }

  final int rows;
  final int steps;
  final Duration interval;
}

Never _printUsage() {
  throw ArgumentError(
    'usage: dart run bin/fleury_sb11_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireTreeTableApp extends StatefulWidget {
  const _WireTreeTableApp({
    required this.driver,
    required this.rows,
    required this.steps,
    required this.interval,
  });

  final WireTerminalDriver driver;
  final int rows;
  final int steps;
  final Duration interval;

  @override
  State<_WireTreeTableApp> createState() => _WireTreeTableAppState();
}

final class _WireTreeTableAppState extends State<_WireTreeTableApp> {
  late final TreeTableController _controller;
  late final FocusNode _focusNode;
  late final _TreeFixture _fixture;
  late final List<TreeTableNode<int>> _roots;
  late final TreeTableSearchIndex<int> _searchIndex;
  TreeTableFilterDescriptor? _filter;
  Timer? _timer;
  var _step = 0;
  var _copiedBytes = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _fixture = _TreeFixture(seed: 1, leafCount: widget.rows);
    _roots = _fixture.roots();
    _searchIndex = TreeTableSearchIndex<int>.build(
      roots: _roots,
      columns: _treeColumns,
      cellBuilder: _cell,
    );
    _controller = TreeTableController(
      selectedIndex: 1,
      expandedKeys: {_fixture.groupKey(0)},
    );
    _focusNode = FocusNode(debugLabel: 'SB.11 wire tree table');
    _timer = Timer.periodic(widget.interval, (_) => _driveStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _driveStep() {
    if (_step >= widget.steps) {
      _timer?.cancel();
      _queueExitAfterFrame();
      return;
    }

    setState(() {
      _focusNode.requestFocus();
      switch (_step % 6) {
        case 0:
          _controller.expand(_fixture.groupKey(1));
          _controller.selectedIndex = _fixture.groupSize + 1;
        case 1:
          _moveSelection(20);
        case 2:
          _controller.selectedIndex = _visibleRows().length - 1;
        case 3:
          _filter = TreeTableFilterDescriptor(
            query: _fixture.targetQuery,
            mode: TreeTableFilterMode.exactToken,
          );
          _controller.selectedIndex = 1;
        case 4:
          _copySelectedRow();
        case 5:
          _filter = null;
          _controller.collapseAll();
          _controller.expand(_fixture.groupKey(0));
          _controller.selectedIndex = 1;
      }
      _step++;
    });

    if (_step >= widget.steps) {
      _timer?.cancel();
      _queueExitAfterFrame();
    }
  }

  void _moveSelection(int delta) {
    final rows = _visibleRows();
    if (rows.isEmpty) return;
    final selected = (_controller.selectedIndex ?? 0) + delta;
    _controller.selectedIndex = selected.clamp(0, rows.length - 1);
  }

  void _copySelectedRow() {
    final rows = _visibleRows();
    if (rows.isEmpty) return;
    final selected = (_controller.selectedIndex ?? 0).clamp(0, rows.length - 1);
    final export = exportTreeTableRows<int>(
      rows: rows,
      columns: _treeColumns,
      cellBuilder: _cell,
      options: TreeTableExportOptions(startRow: selected, maxRows: 1),
    );
    _copiedBytes = utf8.encode(export.text).length;
  }

  List<TreeTableRow<int>> _visibleRows() {
    return buildTreeTableRows<int>(
      roots: _roots,
      columns: _treeColumns,
      expandedKeys: _controller.expandedKeys,
      cellBuilder: _cell,
      filter: _filter,
      searchIndex: _searchIndex,
    );
  }

  void _queueExitAfterFrame() {
    if (_exitQueued) return;
    _exitQueued = true;
    TuiBinding.of(context).addPostFrameCallback((_) {
      TuiBinding.of(context).addPostFrameCallback((_) {
        unawaited(widget.driver.closeEvents());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final filterText = _filter?.query ?? 'none';
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SB.11 tree step=$_step rows=${widget.rows} '
            'filter=$filterText copied=$_copiedBytes',
            softWrap: false,
          ),
          const SizedBox(height: 1),
          Expanded(
            child: TreeTable<int>(
              roots: _roots,
              columns: _treeColumns,
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              cellBuilder: _cell,
              searchIndex: _searchIndex,
              filter: _filter,
              label: 'SB.11 tree table',
              maxVisible: 24,
              copyOptions: const TreeTableCopyOptions(
                clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cell(TreeTableNode<int> node, String columnId) {
    return node.cells[columnId] ?? '';
  }
}

const _treeColumns = [
  DataTableColumn(
    id: 'component',
    title: 'Component',
    width: FixedColumnWidth(36),
  ),
  DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(9)),
  DataTableColumn(id: 'owner', title: 'Owner', width: FixedColumnWidth(10)),
  DataTableColumn(
    id: 'duration',
    title: 'Duration',
    width: FixedColumnWidth(8),
  ),
  DataTableColumn(id: 'notes', title: 'Notes', width: FlexColumnWidth(2)),
];

final class _TreeFixture {
  const _TreeFixture({required this.seed, required this.leafCount});

  final int seed;
  final int leafCount;

  int get groupSize => math.max(1, math.min(1000, leafCount));
  int get groupCount => (leafCount + groupSize - 1) ~/ groupSize;

  String groupKey(int group) => 'GROUP-${group.toString().padLeft(3, '0')}';
  String leafKey(int row) => 'TASK-${100000 + row}';
  String get targetQuery => 'zz-target-${100000 + leafCount - 1}';

  List<TreeTableNode<int>> roots() {
    return List<TreeTableNode<int>>.generate(
      groupCount,
      _group,
      growable: false,
    );
  }

  TreeTableNode<int> _group(int group) {
    final start = group * groupSize;
    final count = math.min(groupSize, leafCount - start);
    return TreeTableNode<int>(
      key: groupKey(group),
      label: 'Component group ${group.toString().padLeft(3, '0')}',
      cells: {
        'status': count == groupSize ? 'ready' : 'partial',
        'owner': _owners[(group + seed) % _owners.length],
        'duration': '${(group % 7).toString().padLeft(2, '0')}:00',
        'notes': '$count tasks',
      },
      children: List<TreeTableNode<int>>.generate(
        count,
        (offset) => _leaf(start + offset),
        growable: false,
      ),
    );
  }

  TreeTableNode<int> _leaf(int row) {
    final key = leafKey(row);
    final lane = _lanes[(row ~/ 13 + seed) % _lanes.length];
    final targetSuffix = row == leafCount - 1 ? ' $targetQuery' : '';
    final unsafe = row % 97 == 0 ? ' unsafe secret-$row payload' : '';
    return TreeTableNode<int>(
      key: key,
      label: 'Task $key $lane$targetSuffix$unsafe',
      value: row,
      cells: {
        'status': _statuses[(row + seed) % _statuses.length],
        'owner': _owners[(row + seed * 7) % _owners.length],
        'duration': '${(row % 4).toString().padLeft(2, '0')}:'
            '${(row % 60).toString().padLeft(2, '0')}',
        'notes': 'shard ${(row + seed) % 4096} $lane',
      },
    );
  }
}

const _statuses = ['queued', 'running', 'passed', 'failed', 'blocked'];
const _owners = ['agent', 'ops', 'qa', 'infra', 'cli'];
const _lanes = ['core', 'widgets', 'unicode', 'deploy'];
