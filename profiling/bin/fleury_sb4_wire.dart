import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/terminal_sequences.dart'
    show buildTerminalEnterSequences, buildTerminalExitSequences;
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = _WireTerminalDriver();
  await runApp(
    _WireLogRegionApp(
      driver: driver,
      rowCount: options.rows,
      appendCount: options.append,
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
    required this.append,
    required this.steps,
    required this.interval,
  });

  factory _WireOptions.parse(List<String> args) {
    var rows = 200;
    var append = 50;
    var steps = 10;
    var intervalMs = 16;

    for (final arg in args) {
      if (arg.startsWith('--rows=')) {
        rows = _positiveInt(arg, '--rows=');
      } else if (arg.startsWith('--append=')) {
        append = _positiveInt(arg, '--append=');
      } else if (arg.startsWith('--steps=')) {
        steps = _positiveInt(arg, '--steps=');
      } else if (arg.startsWith('--interval-ms=')) {
        intervalMs = _positiveInt(arg, '--interval-ms=');
      } else if (arg == '--help' || arg == '-h') {
        _printUsage();
      } else {
        throw ArgumentError('unknown argument: $arg');
      }
    }

    return _WireOptions(
      rows: rows,
      append: append,
      steps: steps,
      interval: Duration(milliseconds: intervalMs),
    );
  }

  final int rows;
  final int append;
  final int steps;
  final Duration interval;
}

int _positiveInt(String arg, String prefix) {
  final parsed = int.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('$prefix expects a positive integer');
  }
  return parsed;
}

Never _printUsage() {
  throw ArgumentError(
    'usage: dart run bin/fleury_sb4_wire.dart '
    '[--rows=N] [--append=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireTerminalDriver implements TerminalDriver {
  @override
  RemoteSurfaceSink? get surfaceSink => null; // byte presentation only

  _WireTerminalDriver() : _stdout = stdout;

  final Stdout _stdout;
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  var _active = false;
  TerminalMode? _mode;

  Future<void> closeEvents() async {
    if (!_events.isClosed) await _events.close();
  }

  @override
  TerminalCapabilities get capabilities =>
      detectTerminalCapabilitiesFromEnvironment(Platform.environment);

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => _stdout.hasTerminal;

  @override
  CellSize get size {
    try {
      return CellSize(_stdout.terminalColumns, _stdout.terminalLines);
    } on StdoutException {
      return CellSize(
        _envInt('COLUMNS') ?? 120,
        _envInt('LINES') ?? 32,
      );
    }
  }

  @override
  Future<void> enter(TerminalMode mode) async {
    if (_active) return;
    _mode = mode;
    _active = true;
    final enter = buildTerminalEnterSequences(mode);
    if (enter.isNotEmpty) _stdout.write(enter);
  }

  @override
  Future<void> restore() async {
    if (!_active) return;
    final exit = buildTerminalExitSequences(_mode ?? TerminalMode.interactive);
    if (exit.isNotEmpty) _stdout.write(exit);
    try {
      await _stdout.flush();
    } catch (_) {}
    _active = false;
    _mode = null;
  }

  @override
  void write(String data) => _stdout.write(data);
}

int? _envInt(String name) => int.tryParse(Platform.environment[name] ?? '');

final class _WireLogRegionApp extends StatefulWidget {
  const _WireLogRegionApp({
    required this.driver,
    required this.rowCount,
    required this.appendCount,
    required this.steps,
    required this.interval,
  });

  final _WireTerminalDriver driver;
  final int rowCount;
  final int appendCount;
  final int steps;
  final Duration interval;

  @override
  State<_WireLogRegionApp> createState() => _WireLogRegionAppState();
}

final class _WireLogRegionAppState extends State<_WireLogRegionApp> {
  late final List<LogEntry> _entries;
  late final LogRegionController _controller;
  Timer? _timer;
  var _appended = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _entries = List<LogEntry>.generate(widget.rowCount, _logEntry);
    _controller = LogRegionController();
    _timer = Timer.periodic(widget.interval, (_) => _appendStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _appendStep() {
    if (_appended >= widget.appendCount) {
      _timer?.cancel();
      _queueExitAfterFrame();
      return;
    }

    final remaining = widget.appendCount - _appended;
    final remainingSteps =
        widget.steps - (_appended * widget.steps ~/ widget.appendCount);
    var batch = remainingSteps <= 1 ? remaining : remaining ~/ remainingSteps;
    if (batch <= 0) batch = 1;

    setState(() {
      final start = _entries.length;
      for (var i = 0; i < batch; i++) {
        _entries.add(_logEntry(start + i));
      }
      _appended += batch;
    });

    if (_appended >= widget.appendCount) {
      _timer?.cancel();
      _queueExitAfterFrame();
    }
  }

  void _queueExitAfterFrame() {
    if (_exitQueued) return;
    _exitQueued = true;
    TuiBinding.of(context).addPostFrameCallback((_) {
      unawaited(widget.driver.closeEvents());
    });
  }

  @override
  Widget build(BuildContext context) {
    return LogRegion(
      entries: _entries,
      controller: _controller,
      autofocus: true,
      showPrefix: false,
      copySelection: false,
      label: 'SB.4 wire logs',
    );
  }
}

LogEntry _logEntry(int sourceIndex) {
  return LogEntry(
    id: _logKey(sourceIndex),
    severity: switch (sourceIndex) {
      final i when i % 17 == 0 => LogSeverity.error,
      final i when i % 7 == 0 => LogSeverity.warning,
      _ => LogSeverity.info,
    },
    message: _logText(sourceIndex),
  );
}

String _logText(int sourceIndex) {
  final severity = switch (sourceIndex) {
    final i when i % 17 == 0 => 'ERROR',
    final i when i % 7 == 0 => 'WARN',
    _ => 'INFO',
  };
  return '${_logKey(sourceIndex)} $severity worker-${sourceIndex % 23} '
      'request=$sourceIndex duration=${20 + sourceIndex % 900}ms';
}

String _logKey(int sourceIndex) =>
    'LOG-${(100000 + sourceIndex).toString().padLeft(6, '0')}';
