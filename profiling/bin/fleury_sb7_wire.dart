import 'dart:async';
import 'dart:math' as math;

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runApp(
    _WireResizeStormApp(
      driver: driver,
      rows: options.rows,
      steps: options.steps,
      fallbackTimeout: options.fallbackTimeout,
    ),
    driver: driver,
    frameInterval: const Duration(milliseconds: 16),
  );
}

final class _WireOptions {
  const _WireOptions({
    required this.rows,
    required this.steps,
    required this.fallbackTimeout,
  });

  factory _WireOptions.parse(List<String> args) {
    var rows = 100000;
    var steps = 8;
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
      fallbackTimeout: Duration(milliseconds: intervalMs * (steps + 6)),
    );
  }

  final int rows;
  final int steps;
  final Duration fallbackTimeout;
}

Never _printUsage() {
  throw ArgumentError(
    'usage: dart run bin/fleury_sb7_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireResizeStormApp extends StatefulWidget {
  const _WireResizeStormApp({
    required this.driver,
    required this.rows,
    required this.steps,
    required this.fallbackTimeout,
  });

  final WireTerminalDriver driver;
  final int rows;
  final int steps;
  final Duration fallbackTimeout;

  @override
  State<_WireResizeStormApp> createState() => _WireResizeStormAppState();
}

final class _WireResizeStormAppState extends State<_WireResizeStormApp> {
  late final DataTableController _tableController;
  late final LogRegionController _logController;
  late final TextEditingController _inputController;
  late final _RunFixture _fixture;
  late final List<LogEntry> _logs;
  StreamSubscription<TuiEvent>? _events;
  Timer? _fallback;
  var _resizeCount = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _tableController = DataTableController();
    _logController = LogRegionController();
    _inputController = TextEditingController(text: 'status:failed');
    _fixture = const _RunFixture(seed: 1);
    _logs = List<LogEntry>.generate(_resizeLogCountFor(widget.rows), _logEntry);
    _events = widget.driver.events.listen((event) {
      if (event is! ResizeEvent) return;
      setState(() {
        _resizeCount++;
        _tableController.selectedIndex = _tableController.selectedIndex + 1;
      });
      if (_resizeCount >= widget.steps) _queueExitAfterFrame();
    });
    _fallback = Timer(widget.fallbackTimeout, _queueExitAfterFrame);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _events?.cancel();
    _tableController.dispose();
    _logController.dispose();
    _inputController.dispose();
    super.dispose();
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
    final size = MediaQuery.of(context).size;
    final tableHeight = math.max(3, size.rows ~/ 2);
    final logHeight = math.max(2, size.rows - tableHeight - 5);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SB.7 resize count=$_resizeCount rows=${widget.rows} '
            'size=${size.cols}x${size.rows}',
            softWrap: false,
          ),
          SizedBox(
            height: 1,
            child: TextInput(
              controller: _inputController,
              placeholder: 'filter',
              autofocus: true,
            ),
          ),
          SizedBox(
            height: tableHeight,
            child: DataTable(
              rowCount: widget.rows,
              columns: _columns,
              controller: _tableController,
              rowKeyBuilder: _fixture.rowKey,
              filterText: _inputController.text,
              cellBuilder: _fixture.cell,
            ),
          ),
          SizedBox(
            height: logHeight,
            child: LogRegion(
              entries: _logs,
              controller: _logController,
              semanticLabel: 'Resize logs',
              copyOptions: const LogRegionCopyOptions(
                clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
              ),
            ),
          ),
        ],
      ),
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
];

final class _RunFixture {
  const _RunFixture({required this.seed});

  final int seed;

  Object rowKey(int row) => 'RUN-${100000 + row}';

  String cell(int row, String columnId) {
    return switch (columnId) {
      'id' => rowKey(row).toString(),
      'status' => _statuses[(row + seed) % _statuses.length],
      'title' => 'Resize shard ${(row + seed) % 2048}',
      'owner' => _owners[(row + seed * 3) % _owners.length],
      'duration' => '${(row % 3).toString().padLeft(2, '0')}:'
          '${(row % 60).toString().padLeft(2, '0')}',
      _ => '',
    };
  }
}

LogEntry _logEntry(int index) {
  final unsafe = index % 17 == 0 ? ' secret-$index payload' : '';
  return LogEntry(
    id: 'log-$index',
    message:
        'resize log $index shard=${index % 31} status=${_statuses[index % 5]}$unsafe',
    severity: index % 11 == 0 ? LogSeverity.warning : LogSeverity.info,
  );
}

int _resizeLogCountFor(int rowCount) {
  final scaled = rowCount ~/ 20;
  if (scaled < 128) return 128;
  if (scaled > 5000) return 5000;
  return scaled;
}

const _statuses = ['queued', 'running', 'passed', 'failed', 'blocked'];
const _owners = ['agent', 'ops', 'qa', 'infra', 'cli'];
