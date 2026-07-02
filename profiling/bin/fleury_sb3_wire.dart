import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runApp(
    _WireDataTableApp(
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
    var steps = 5;
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
    'usage: dart run bin/fleury_sb3_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireDataTableApp extends StatefulWidget {
  const _WireDataTableApp({
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
  State<_WireDataTableApp> createState() => _WireDataTableAppState();
}

final class _WireDataTableAppState extends State<_WireDataTableApp> {
  late final DataTableController _controller;
  late final FocusNode _focusNode;
  late final _RunFixture _fixture;
  Timer? _timer;
  var _step = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _controller = DataTableController();
    _focusNode = FocusNode(debugLabel: 'SB.3 wire table');
    _fixture = const _RunFixture(seed: 1);
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
      switch (_step % 5) {
        case 0:
          _controller.moveSelection(rowDelta: 1);
        case 1:
          _controller.moveSelection(rowDelta: 20);
        case 2:
          _controller.selectedIndex = widget.rows ~/ 2;
        case 3:
          _controller.selectedIndex = widget.rows - 1;
        case 4:
          _controller.selectedColumnIndex = 1;
      }
      _step++;
    });

    if (_step >= widget.steps) {
      _timer?.cancel();
      _queueExitAfterFrame();
    }
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
    return DataTable(
      rowCount: widget.rows,
      columns: _columns,
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      rowKeyBuilder: _fixture.rowKey,
      sortColumnId: 'status',
      sortDirection: DataTableSortDirection.ascending,
      filterText: 'status:failed',
      cellBuilder: _fixture.cell,
    );
  }
}

const _columns = [
  DataTableColumn(id: 'id', title: 'ID', width: FixedColumnWidth(12)),
  DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(8)),
  DataTableColumn(id: 'title', title: 'Title', width: FlexColumnWidth(3)),
  DataTableColumn(id: 'owner', title: 'Owner', width: FixedColumnWidth(10)),
  DataTableColumn(
    id: 'duration',
    title: 'Duration',
    width: FixedColumnWidth(8),
  ),
  DataTableColumn(
    id: 'progress',
    title: 'Progress',
    width: FixedColumnWidth(8),
  ),
  DataTableColumn(id: 'warnings', title: 'Warn', width: FixedColumnWidth(5)),
  DataTableColumn(id: 'updated', title: 'Updated', width: FixedColumnWidth(10)),
];

final class _RunFixture {
  const _RunFixture({required this.seed});

  final int seed;

  Object rowKey(int row) => 'RUN-${100000 + row}';

  String cell(int row, String columnId) {
    return switch (columnId) {
      'id' => rowKey(row).toString(),
      'status' => _statuses[(row + seed) % _statuses.length],
      'title' => _title(row),
      'owner' => _owners[(row + seed * 3) % _owners.length],
      'duration' => '${(row % 3).toString().padLeft(2, '0')}:'
          '${(row % 60).toString().padLeft(2, '0')}',
      'progress' => '${(row * 7 + seed) % 101}%',
      'warnings' => '${(row + seed) % 6}',
      'updated' => 'T-${(row % 1440).toString().padLeft(4, '0')}',
      _ => '',
    };
  }

  String _title(int row) {
    final shard = (row + seed) % 2048;
    final lane = _lanes[(row ~/ 17 + seed) % _lanes.length];
    return 'Build shard $shard $lane';
  }
}

const _statuses = ['queued', 'running', 'passed', 'failed', 'blocked'];
const _owners = ['agent', 'ops', 'qa', 'infra', 'cli'];
const _lanes = ['core', 'widgets', 'unicode', 'deploy', '日本語'];
