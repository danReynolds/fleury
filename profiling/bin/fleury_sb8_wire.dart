import 'dart:async';

import 'package:fleury/fleury.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runTui(
    _WireOverlayApp(
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
    var rows = 500;
    var steps = 12;
    var intervalMs = 40;
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
    'usage: dart run bin/fleury_sb8_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireOverlayApp extends StatefulWidget {
  const _WireOverlayApp({
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
  State<_WireOverlayApp> createState() => _WireOverlayAppState();
}

final class _WireOverlayAppState extends State<_WireOverlayApp> {
  Timer? _timer;
  var _step = 0;
  var _query = '';
  var _paletteOpen = true;
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
      _paletteOpen = _step % 3 != 2;
      _query = switch (_step % 4) {
        0 => 'open',
        1 => 'run',
        2 => 'diag',
        _ => 'copy',
      };
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
          Text(
              'SB.8 overlay churn step=$_step open=$_paletteOpen query=$_query'),
          const SizedBox(height: 1),
          for (var i = 0; i < 9; i++)
            Text(
              'screen row $i focus=${i == _step % 9} command=cmd-${(_step + i) % widget.rows}',
              softWrap: false,
            ),
          if (_paletteOpen) ...[
            const SizedBox(height: 1),
            Text('+${_repeat('-', 54)}+', softWrap: false),
            Text('| Command Palette query=${_query.padRight(26)} |'),
            for (final command in _matches())
              Text('| ${command.padRight(52)} |', softWrap: false),
            Text('+${_repeat('-', 54)}+', softWrap: false),
          ],
        ],
      ),
    );
  }

  Iterable<String> _matches() sync* {
    for (var i = 0; i < 6; i++) {
      final index = (_step * 7 + i) % widget.rows;
      yield 'cmd-${index.toString().padLeft(4, '0')} $_query action-$i';
    }
  }
}

String _repeat(String value, int count) =>
    List<String>.filled(count, value).join();
