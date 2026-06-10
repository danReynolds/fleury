import 'dart:async';

import 'package:fleury/fleury.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runTui(
    _WireCounterApp(
      driver: driver,
      steps: options.steps,
      interval: options.interval,
    ),
    driver: driver,
    frameInterval: const Duration(milliseconds: 16),
  );
}

final class _WireOptions {
  const _WireOptions({
    required this.steps,
    required this.interval,
  });

  factory _WireOptions.parse(List<String> args) {
    var steps = 1;
    var intervalMs = 60;
    for (final arg in args) {
      if (arg.startsWith('--rows=')) {
        positiveInt(arg, '--rows=');
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
      steps: steps,
      interval: Duration(milliseconds: intervalMs),
    );
  }

  final int steps;
  final Duration interval;
}

Never _printUsage() {
  throw ArgumentError(
    'usage: dart run bin/fleury_sb1_wire.dart '
    '[--steps=N] [--interval-ms=N]',
  );
}

final class _WireCounterApp extends StatefulWidget {
  const _WireCounterApp({
    required this.driver,
    required this.steps,
    required this.interval,
  });

  final WireTerminalDriver driver;
  final int steps;
  final Duration interval;

  @override
  State<_WireCounterApp> createState() => _WireCounterAppState();
}

final class _WireCounterAppState extends State<_WireCounterApp> {
  Timer? _timer;
  var _count = 0;
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
    if (_count >= widget.steps) {
      _timer?.cancel();
      _queueExitAfterFrame();
      return;
    }
    setState(() {
      _count++;
    });
    if (_count >= widget.steps) {
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
      child: Text('Count: $_count', softWrap: false),
    );
  }
}
