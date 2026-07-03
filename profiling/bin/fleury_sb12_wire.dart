import 'dart:async';
import 'dart:math' as math;

import 'package:fleury/fleury.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runApp(
    _WireLayoutDirtinessApp(
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
    var rows = 2000;
    var steps = 8;
    var intervalMs = 60;
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
    'usage: dart run bin/fleury_sb12_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireLayoutDirtinessApp extends StatefulWidget {
  const _WireLayoutDirtinessApp({
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
  State<_WireLayoutDirtinessApp> createState() =>
      _WireLayoutDirtinessAppState();
}

final class _WireLayoutDirtinessAppState
    extends State<_WireLayoutDirtinessApp> {
  Timer? _timer;
  var _step = 0;
  var _counter = 0;
  var _accent = false;
  var _textVariant = false;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
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
      switch (_step % 4) {
        case 0:
          _counter++;
        case 1:
          _accent = !_accent;
        case 2:
          _textVariant = !_textVariant;
        case 3:
          _counter = _counter;
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
    final visible = math.min(26, math.max(1, widget.rows));
    final start = math.max(0, widget.rows - visible);
    final style = _accent
        ? const CellStyle(foreground: Colors.cyan)
        : const CellStyle(foreground: Colors.green);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SB.12 layout step=$_step counter=$_counter accent=$_accent variant=$_textVariant',
            style: style,
            softWrap: false,
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  'hot region counter=${_counter.toString().padLeft(4, '0')}',
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 38,
                child: Text(
                  _textVariant
                      ? 'paint-only text variant=B'
                      : 'paint-only text variant=A',
                  style: style,
                  softWrap: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          for (var i = 0; i < visible; i++)
            Text(
              'row ${(start + i).toString().padLeft(6, '0')} stable payload '
              'owner=layout shard=${(start + i) % 31} checksum=${(start + i) * 17 % 997}',
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
