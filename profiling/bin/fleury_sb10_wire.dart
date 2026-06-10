import 'dart:async';

import 'package:fleury/fleury.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runTui(
    _WireDemoApp(
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
    var rows = 1000;
    var steps = 10;
    var intervalMs = 50;
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
    'usage: dart run bin/fleury_sb10_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireDemoApp extends StatefulWidget {
  const _WireDemoApp({
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
  State<_WireDemoApp> createState() => _WireDemoAppState();
}

final class _WireDemoAppState extends State<_WireDemoApp> {
  final List<String> _events = <String>[];
  Timer? _timer;
  var _step = 0;
  var _screen = 'home';
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _events.add('boot demo app');
    _timer = Timer.periodic(widget.interval, (_) => _driveStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _driveStep() {
    if (_step >= widget.steps) {
      _timer?.cancel();
      _queueExitAfterFrame();
      return;
    }
    setState(() {
      _screen = switch (_step % 5) {
        0 => 'home',
        1 => 'search',
        2 => 'task',
        3 => 'logs',
        _ => 'diagnostics',
      };
      _events.add('step=$_step screen=$_screen rows=${widget.rows}');
      while (_events.length > 12) {
        _events.removeAt(0);
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
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SB.10 demo app screen=$_screen step=$_step'),
          const SizedBox(height: 1),
          Row(
            children: [
              SizedBox(width: 22, child: Text('nav: home search task')),
              const SizedBox(width: 2),
              SizedBox(width: 28, child: Text('command: ${_commandName()}')),
              const SizedBox(width: 2),
              SizedBox(width: 24, child: Text('status: ${_status()}')),
            ],
          ),
          const SizedBox(height: 1),
          Text(
              'results visible=${(_step * 17) % widget.rows} selected=${_step % 9}'),
          const SizedBox(height: 1),
          for (final event in _events)
            Text(event, softWrap: false, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _commandName() => switch (_screen) {
        'home' => 'open-palette',
        'search' => 'rank-results',
        'task' => 'run-process',
        'logs' => 'copy-log',
        _ => 'diagnose',
      };

  String _status() => switch (_step % 4) {
        0 => 'idle',
        1 => 'running',
        2 => 'complete',
        _ => 'warning',
      };
}
