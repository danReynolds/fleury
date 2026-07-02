import 'dart:async';

import 'package:fleury/fleury.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runApp(
    _WireSubprocessApp(
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
    var rows = 400;
    var steps = 10;
    var intervalMs = 35;
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
    'usage: dart run bin/fleury_sb9_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireSubprocessApp extends StatefulWidget {
  const _WireSubprocessApp({
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
  State<_WireSubprocessApp> createState() => _WireSubprocessAppState();
}

final class _WireSubprocessAppState extends State<_WireSubprocessApp> {
  final List<String> _lines = <String>[];
  Timer? _timer;
  var _step = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _lines.addAll(List<String>.generate(16, _lineFor));
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
      for (var i = 0; i < 4; i++) {
        _lines.add(_lineFor(_lines.length));
      }
      while (_lines.length > 24) {
        _lines.removeAt(0);
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
          Text('SB.9 subprocess output step=$_step total=${_lines.length}'),
          const SizedBox(height: 1),
          for (final line in _lines)
            Text(line, softWrap: false, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  static String _lineFor(int index) {
    final unsafe = index % 5 == 0 ? ' \x1b]52;c;secret-$index\x07' : '';
    return 'proc[$index] stdout shard=${index % 17} status=${index % 3} '
        'message="streamed output $index"$unsafe';
  }
}
