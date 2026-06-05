import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  Timer(
    options.interval * (options.steps + 4) + const Duration(milliseconds: 250),
    () => exit(0),
  );
  await runApp(
    _NoctermLayoutDirtinessApp(
      rows: options.rows,
      steps: options.steps,
      interval: options.interval,
    ),
  );
}

final class _Options {
  const _Options({
    required this.rows,
    required this.steps,
    required this.interval,
  });

  factory _Options.parse(List<String> args) {
    var rows = 2000;
    var steps = 8;
    var intervalMs = 60;
    for (final arg in args) {
      if (arg == '--wire') {
        continue;
      } else if (arg.startsWith('--rows=')) {
        rows = _positive(arg, '--rows=');
      } else if (arg.startsWith('--steps=')) {
        steps = _positive(arg, '--steps=');
      } else if (arg.startsWith('--interval-ms=')) {
        intervalMs = _positive(arg, '--interval-ms=');
      } else if (arg.startsWith('--size=')) {
        continue;
      } else if (arg == '--help' || arg == '-h') {
        throw ArgumentError(
          'usage: dart run bin/sb12_layout_dirtiness_benchmark.dart '
          '--wire [--rows=N] [--steps=N] [--interval-ms=N] [--size=COLSxROWS]',
        );
      } else {
        throw ArgumentError('unknown argument: $arg');
      }
    }
    return _Options(
      rows: rows,
      steps: steps,
      interval: Duration(milliseconds: intervalMs),
    );
  }

  final int rows;
  final int steps;
  final Duration interval;
}

int _positive(String arg, String prefix) {
  final parsed = int.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('$prefix expects a positive integer');
  }
  return parsed;
}

class _NoctermLayoutDirtinessApp extends StatefulComponent {
  const _NoctermLayoutDirtinessApp({
    required this.rows,
    required this.steps,
    required this.interval,
  });

  final int rows;
  final int steps;
  final Duration interval;

  @override
  State<_NoctermLayoutDirtinessApp> createState() =>
      _NoctermLayoutDirtinessAppState();
}

class _NoctermLayoutDirtinessAppState
    extends State<_NoctermLayoutDirtinessApp> {
  Timer? _timer;
  var _step = 0;
  var _counter = 0;
  var _accent = false;
  var _textVariant = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(component.interval, (_) => _driveStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _driveStep() {
    if (_step >= component.steps) {
      _timer?.cancel();
      _finish();
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
    if (_step >= component.steps) {
      _timer?.cancel();
      Timer(component.interval, _finish);
    }
  }

  void _finish() {
    shutdownApp();
    Timer(const Duration(milliseconds: 20), () => exit(0));
  }

  @override
  Component build(BuildContext context) {
    final visible = math.min(26, math.max(1, component.rows));
    final start = math.max(0, component.rows - visible);
    final style = TextStyle(color: _accent ? Colors.cyan : Colors.green);
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SB.12 layout step=$_step counter=$_counter accent=$_accent variant=$_textVariant',
              style: style,
            ),
            const SizedBox(height: 1),
            Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    'hot region counter=${_counter.toString().padLeft(4, '0')}',
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
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            for (var i = 0; i < visible; i++)
              Text(
                'row ${(start + i).toString().padLeft(6, '0')} stable payload '
                'owner=layout shard=${(start + i) % 31} checksum=${(start + i) * 17 % 997}',
              ),
          ],
        ),
      ),
    );
  }
}
