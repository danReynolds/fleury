import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/terminal_sequences.dart'
    show buildTerminalEnterSequences, buildTerminalExitSequences;
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = _WireTerminalDriver();
  await runTui(
    _WireMarkdownApp(
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
    var rows = 200;
    var steps = 16;
    var intervalMs = 50;

    for (final arg in args) {
      if (arg.startsWith('--rows=')) {
        rows = _positiveInt(arg, '--rows=');
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
      steps: steps,
      interval: Duration(milliseconds: intervalMs),
    );
  }

  final int rows;
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
    'usage: dart run bin/fleury_sb5_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireTerminalDriver implements TerminalDriver {
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
      return CellSize(_envInt('COLUMNS') ?? 120, _envInt('LINES') ?? 32);
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

final class _WireMarkdownApp extends StatefulWidget {
  const _WireMarkdownApp({
    required this.driver,
    required this.rows,
    required this.steps,
    required this.interval,
  });

  final _WireTerminalDriver driver;
  final int rows;
  final int steps;
  final Duration interval;

  @override
  State<_WireMarkdownApp> createState() => _WireMarkdownAppState();
}

final class _WireMarkdownAppState extends State<_WireMarkdownApp> {
  late final MarkdownViewController _controller;
  late final int _chunkCount;
  late final _MarkdownFixture _fixture;
  final StringBuffer _source = StringBuffer();
  var _document = parseMarkdownDocument('');
  Timer? _timer;
  var _emitted = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _controller = MarkdownViewController();
    _chunkCount = _markdownChunkCountFor(widget.rows);
    _fixture = const _MarkdownFixture(seed: 1);
    _timer = Timer.periodic(widget.interval, (_) => _appendStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _appendStep() {
    if (_emitted >= _chunkCount) {
      _timer?.cancel();
      _selectTailAndExit();
      return;
    }

    final remaining = _chunkCount - _emitted;
    final remainingSteps =
        widget.steps - (_emitted * widget.steps ~/ _chunkCount);
    var batch = remainingSteps <= 1 ? remaining : remaining ~/ remainingSteps;
    if (batch <= 0) batch = 1;

    setState(() {
      for (var i = 0; i < batch && _emitted < _chunkCount; i++) {
        _source.write(_fixture.chunk(_emitted));
        _emitted++;
      }
      _document = parseMarkdownDocument(_source.toString());
    });

    if (_emitted >= _chunkCount) {
      _timer?.cancel();
      _selectTailAndExit();
    }
  }

  void _selectTailAndExit() {
    if (_exitQueued) return;
    _exitQueued = true;
    setState(() {
      final selected =
          _document.blocks.isEmpty ? 0 : _document.blocks.length - 1;
      _controller.selectedIndex = selected;
      _controller.jumpToIndex(selected);
    });
    TuiBinding.of(context).addPostFrameCallback((_) {
      TuiBinding.of(context).addPostFrameCallback((_) {
        unawaited(widget.driver.closeEvents());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownView.document(
      document: _document,
      controller: _controller,
      autofocus: true,
      label: 'Scenario markdown',
      copyOptions: const MarkdownViewCopyOptions(
        clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
      ),
    );
  }
}

final class _MarkdownFixture {
  const _MarkdownFixture({required this.seed});

  final int seed;

  String chunk(int index) {
    final id = index + seed;
    final section = index ~/ 12;
    return switch (index % 12) {
      0 => '## Stream batch $section\n',
      1 => 'Paragraph $id starts with **bold** text, ',
      2 =>
        '[docs-$id](https://fleury.dev/docs/$id), `inline-code`, and 日本語 width.\n',
      3 => '- checklist item $id keeps semantic list state\n',
      4 => '| field | value |\n| --- | --- |\n| chunk | $id |\n',
      5 =>
        '```dart\nfinal chunk$id = "safe";\nfinal hidden$id = "\x1b]52;c;secret-$id\x07";\n',
      6 => 'print(chunk$id);\n```\n',
      7 => '> quoted output $id \x1b]52;c;secret-$id\x07 stays inert\n',
      8 => '1. ordered item $id with [mail](mailto:ops$id@example.com)\n',
      9 => '\n',
      10 => '${_longMarkdownParagraph(id)}\n',
      _ => '[unsafe-$id](javascript:alert($id)) visible fallback only\n',
    };
  }
}

String _longMarkdownParagraph(int id) {
  final buffer = StringBuffer('Long paragraph $id');
  for (var i = 0; i < 24; i++) {
    buffer.write(' word${(id + i) % 17}');
  }
  buffer.write(' with ~~strike~~ and _emphasis_.');
  return buffer.toString();
}

int _markdownChunkCountFor(int rowCount) {
  final scaled = rowCount ~/ 100;
  if (scaled < 64) return 64;
  if (scaled > 1024) return 1024;
  return scaled;
}
