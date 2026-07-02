import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_capture.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  final debugCapturePath = Platform.environment['FLEURY_DEBUG_CAPTURE']?.trim();
  final debugRecorder = debugCapturePath == null || debugCapturePath.isEmpty
      ? null
      : (DebugCaptureRecorder(maxFrames: options.steps + 4)..attach());
  try {
    await runApp(
      _WireDashboardApp(
        driver: driver,
        rows: options.rows,
        steps: options.steps,
        interval: options.interval,
      ),
      driver: driver,
      frameInterval: const Duration(milliseconds: 16),
    );
  } finally {
    if (debugRecorder != null) {
      final output = File(debugCapturePath!);
      output.parent.createSync(recursive: true);
      final json = const JsonEncoder.withIndent(
        '  ',
      ).convert(debugRecorder.snapshot().toJson());
      output.writeAsStringSync('$json\n');
      await debugRecorder.dispose();
    }
  }
}

final class _WireOptions {
  const _WireOptions({
    required this.rows,
    required this.steps,
    required this.interval,
  });

  factory _WireOptions.parse(List<String> args) {
    var rows = 100000;
    var steps = 120;
    var intervalMs = 16;
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
    'usage: dart run bin/fleury_sb6_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireDashboardApp extends StatefulWidget {
  const _WireDashboardApp({
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
  State<_WireDashboardApp> createState() => _WireDashboardAppState();
}

final class _WireDashboardAppState extends State<_WireDashboardApp> {
  late List<num> _history;
  Timer? _timer;
  var _tick = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _history = List<num>.generate(48, (index) => 40 + index % 17);
    _timer = Timer.periodic(widget.interval, (_) => _driveStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _driveStep() {
    if (_tick >= widget.steps) {
      _timer?.cancel();
      _queueExitAfterFrame();
      return;
    }
    setState(() {
      _tick++;
      final next = 20 + ((_tick * 13) % 80);
      _history = <num>[..._history.skip(1), next];
    });
    if (_tick >= widget.steps) {
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
    final cpu = ((_tick * 17) % 100) / 100;
    final mem = ((_tick * 29 + 15) % 100) / 100;
    final disk = ((_tick * 7 + 30) % 100) / 100;
    final completed =
        math.min(widget.rows, _tick * math.max(1, widget.rows ~/ 80));
    final progress = widget.rows <= 0 ? 0.0 : completed / widget.rows;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SB.6 dashboard tick=$_tick rows=${widget.rows} active=${_activeJobs()}',
            softWrap: false,
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              SizedBox(width: 36, child: Gauge(value: cpu, label: 'CPU')),
              const SizedBox(width: 2),
              SizedBox(width: 36, child: Gauge(value: mem, label: 'MEM')),
              const SizedBox(width: 2),
              SizedBox(width: 36, child: Gauge(value: disk, label: 'IO')),
            ],
          ),
          const SizedBox(height: 1),
          Text(
              'build queue ${completed.toString().padLeft(6)} / ${widget.rows}'),
          SizedBox(width: 76, child: ProgressBar(value: progress)),
          const SizedBox(height: 1),
          SizedBox(width: 76, child: Sparkline(data: _history, max: 100)),
          const SizedBox(height: 1),
          SizedBox(
            height: 8,
            child: BarChart(
              bars: [
                Bar('api', (_tick * 3) % 100),
                Bar('cli', (_tick * 5 + 10) % 100),
                Bar('ui', (_tick * 7 + 20) % 100),
                Bar('io', (_tick * 11 + 30) % 100),
                Bar('net', (_tick * 13 + 40) % 100),
              ],
              showValues: false,
            ),
          ),
          const SizedBox(height: 1),
          for (final line in _statusLines())
            Text(line, softWrap: false, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  int _activeJobs() => 20 + (_tick * 7) % 900;

  Iterable<String> _statusLines() sync* {
    for (var i = 0; i < 10; i++) {
      final id = (_tick * 10 + i) % math.max(1, widget.rows);
      final status = switch ((id + _tick) % 5) {
        0 => 'queued',
        1 => 'running',
        2 => 'passed',
        3 => 'failed',
        _ => 'blocked',
      };
      yield 'RUN-${id.toString().padLeft(6, '0')} $status shard=${id % 31} '
          'owner=worker-${id % 17} latency=${20 + id % 900}ms';
    }
  }
}
