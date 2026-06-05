import 'dart:async';

import 'package:fleury/fleury.dart';

import 'fleury_wire_support.dart';

Future<void> main(List<String> args) async {
  final options = _WireOptions.parse(args);
  final driver = WireTerminalDriver();
  await runTui(
    _WireTextEditingApp(
      driver: driver,
      textChars: options.rows,
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
    var rows = 10000;
    var steps = 8;
    var intervalMs = 60;

    for (final arg in args) {
      if (arg.startsWith('--rows=')) {
        rows = positiveInt(arg, '--rows=');
      } else if (arg.startsWith('--text-chars=')) {
        rows = positiveInt(arg, '--text-chars=');
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
    'usage: dart run bin/fleury_sb2_wire.dart '
    '[--rows=N] [--steps=N] [--interval-ms=N]',
  );
}

final class _WireTextEditingApp extends StatefulWidget {
  const _WireTextEditingApp({
    required this.driver,
    required this.textChars,
    required this.steps,
    required this.interval,
  });

  final WireTerminalDriver driver;
  final int textChars;
  final int steps;
  final Duration interval;

  @override
  State<_WireTextEditingApp> createState() => _WireTextEditingAppState();
}

final class _WireTextEditingAppState extends State<_WireTextEditingApp> {
  late final _TextFixture _fixture;
  late final TextEditingController _composer;
  late final TextEditingController _editor;
  late final TextEditingController _secret;
  late final TextHistoryController _history;
  late final TextCompletionController _completion;
  late final FocusNode _composerFocus;
  late final FocusNode _editorFocus;
  late final FocusNode _secretFocus;
  Timer? _timer;
  var _step = 0;
  var _exitQueued = false;

  @override
  void initState() {
    super.initState();
    _fixture = _TextFixture.generate(widget.textChars);
    _composer = TextEditingController(text: _fixture.composerText);
    _editor = TextEditingController(text: _fixture.editorText);
    _secret = TextEditingController(text: _fixture.secretText);
    _history = TextHistoryController(entries: _fixture.historyEntries);
    _completion = TextCompletionController();
    _composerFocus = FocusNode(debugLabel: 'SB.2 wire composer');
    _editorFocus = FocusNode(debugLabel: 'SB.2 wire editor');
    _secretFocus = FocusNode(debugLabel: 'SB.2 wire secret');
    _timer = Timer.periodic(widget.interval, (_) => _driveStep());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _composer.dispose();
    _editor.dispose();
    _secret.dispose();
    _history.dispose();
    _completion.dispose();
    _composerFocus.dispose();
    _editorFocus.dispose();
    _secretFocus.dispose();
    super.dispose();
  }

  void _driveStep() {
    if (_step >= widget.steps) {
      _timer?.cancel();
      _queueExitAfterFrame();
      return;
    }

    setState(() {
      switch (_step % 8) {
        case 0:
          _composerFocus.requestFocus();
          _composer.value = TextEditingModel.moveWordLeft(_composer.value);
          _composer.value = TextEditingModel.moveLeft(_composer.value);
          _composer.value = TextEditingModel.moveRight(_composer.value);
        case 1:
          _composer
            ..insert('x')
            ..backspace();
        case 2:
          _editorFocus.requestFocus();
          final index = _editor.text.indexOf(_fixture.selectionNeedle);
          if (index >= 0) {
            _editor.textSelection = TextSelection(
              baseOffset: index,
              extentOffset: index + _fixture.selectionNeedle.length,
            );
            _editor.insert(_fixture.selectionReplacement);
          }
        case 3:
          _editor
            ..undo()
            ..redo();
        case 4:
          _editor.paste(_fixture.pasteText);
        case 5:
          _composerFocus.requestFocus();
          _composer.value = TextEditingValue(text: 'git che');
          _completion.open(
            range: const TextRange(start: 4, end: 7),
            query: 'che',
            options: const [
              TextCompletionOption(label: 'checkout'),
              TextCompletionOption(label: 'cherry-pick'),
            ],
          );
          final completed = _completion.accept(
            _composer.value,
            singleLine: true,
          );
          if (completed != null) _composer.value = completed;
        case 6:
          _composer.value = TextEditingValue(text: _fixture.historyDraft);
          final previous = _history.navigatePrevious(_composer.value);
          if (previous != null) _composer.value = previous;
          final next = _history.navigateNext();
          if (next != null) _composer.value = next;
        case 7:
          _secretFocus.requestFocus();
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
    return FleuryApp(
      title: 'SB.2 wire text editing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Composer'),
          TextInput(
            controller: _composer,
            focusNode: _composerFocus,
            historyController: _history,
            completionController: _completion,
            autofocus: true,
            enableBlink: false,
            placeholder: 'Command composer',
            validationError: 'Review required',
            pastePolicy: const TextPastePolicy(
              largePasteThreshold: 512,
              chunkSize: 512,
            ),
            onSubmit: (_) {},
          ),
          const Text('Editor'),
          SizedBox(
            height: 10,
            child: TextArea(
              controller: _editor,
              focusNode: _editorFocus,
              placeholder: 'Longform editor',
              validationError: 'Contains mixed-width fixture text',
              pastePolicy: const TextPastePolicy(
                largePasteThreshold: 512,
                chunkSize: 512,
              ),
            ),
          ),
          const Text('Secret'),
          TextInput(
            controller: _secret,
            focusNode: _secretFocus,
            enableBlink: false,
            placeholder: 'Secret token',
            obscureText: true,
            clipboardPolicy: TextClipboardPolicy.redacted,
          ),
        ],
      ),
    );
  }
}

final class _TextFixture {
  const _TextFixture({
    required this.composerText,
    required this.editorText,
    required this.secretText,
    required this.pasteText,
    required this.selectionNeedle,
    required this.selectionReplacement,
    required this.historyEntries,
    required this.historyDraft,
  });

  factory _TextFixture.generate(int textChars) {
    return _TextFixture(
      composerText: 'deploy service --target staging --verbose',
      editorText: _mixedText(textChars),
      secretText: 'fleury-secret-do-not-leak',
      pasteText: '${_repeat('paste🙂界 café ', 128)}paste-marker-final',
      selectionNeedle: 'segment-alpha',
      selectionReplacement: 'selection-replaced',
      historyEntries: const [
        'status --short',
        'git branch --show-current',
        'git che',
      ],
      historyDraft: 'draft command',
    );
  }

  final String composerText;
  final String editorText;
  final String secretText;
  final String pasteText;
  final String selectionNeedle;
  final String selectionReplacement;
  final List<String> historyEntries;
  final String historyDraft;
}

String _mixedText(int targetChars) {
  final target = targetChars < 256 ? 256 : targetChars;
  final parts = [
    'segment-beta ascii words ',
    'café combining mark ',
    '界面 表格 入力 ',
    'emoji🙂 cursor ',
    'line-wrap sample text\n',
  ];
  final buffer = StringBuffer('segment-alpha ascii words ');
  while (buffer.length < target) {
    for (final part in parts) {
      buffer.write(part);
      if (buffer.length >= target) break;
    }
  }
  return buffer.toString();
}

String _repeat(String text, int count) {
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    buffer.write(text);
  }
  return buffer.toString();
}
