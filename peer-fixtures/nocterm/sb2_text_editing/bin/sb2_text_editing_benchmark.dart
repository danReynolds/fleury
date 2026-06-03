import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fleury_peer_nocterm_sb2_text_editing/text_editing_app.dart';
import 'package:nocterm/nocterm.dart';

const _schemaVersion = 1;
const _peerId = 'nocterm';
const _peerName = 'Nocterm';
const _peerVersion = '0.6.0';
const _peerUrl = 'https://pub.dev/packages/nocterm';
const _scenarioId = 'SB.2';
const _defaultWarmups = 2;
const _defaultIterations = 10;
const _defaultTextChars = 10000;
const _defaultSize = Size(80, 24);

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  for (var i = 0; i < options.warmupIterations; i += 1) {
    await _runSample(options);
  }

  final samples = <_Sample>[];
  for (var i = 0; i < options.measuredIterations; i += 1) {
    samples.add(await _runSample(options));
  }

  final packageRoot = _packageRoot();
  final appLines = _sourceLineCount(
    '${packageRoot.path}/lib/text_editing_app.dart',
  );
  final testLines = _sourceLineCount(
    '${packageRoot.path}/test/text_editing_benchmark_test.dart',
  );
  final capturedAt = DateTime.now().toUtc();
  final runId = 'nocterm-sb2-text-editing-${_timestampForId(capturedAt)}';
  final allCorrect = samples.every((sample) => sample.correct);
  final allSelectionUndoCorrect = samples.every(
    (sample) => sample.selectionAndUndoCorrect,
  );
  final allRedacted = samples.every((sample) => sample.redactedCorrect);

  final artifact = <String, Object?>{
    'schemaVersion': _schemaVersion,
    'kind': 'fleuryPeerBenchmarkRun',
    'runId': runId,
    'peerId': _peerId,
    'scenarioId': _scenarioId,
    'capturedAt': capturedAt.toIso8601String(),
    'source': <String, Object?>{
      'name': _peerName,
      'version': _peerVersion,
      'url': _peerUrl,
    },
    'environment': <String, Object?>{
      'machine': Platform.localHostname,
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'runtime': Platform.version,
      'terminalMode': 'nocterm-test-harness',
      'terminalSize': <String, Object?>{
        'columns': options.size.width.toInt(),
        'rows': options.size.height.toInt(),
      },
    },
    'fixture': <String, Object?>{
      'workingDirectory': 'peer-fixtures/nocterm/sb2_text_editing',
      'command': <String>[
        'dart',
        'run',
        'bin/sb2_text_editing_benchmark.dart',
        '--warmup=${options.warmupIterations}',
        '--iterations=${options.measuredIterations}',
        '--text-chars=${options.textChars}',
        '--json',
      ],
      'warmupIterations': options.warmupIterations,
      'measuredIterations': options.measuredIterations,
    },
    'metrics': <String, Object?>{
      'cursorMoveUs': _stats(samples.expand((sample) => sample.cursorMoveUs)),
      'insertionDeletionUs': _stats(
        samples.expand((sample) => sample.insertionDeletionUs),
      ),
      'selectionUs': _stats(samples.expand((sample) => sample.selectionUs)),
      'undoRedoUs': _stats(samples.expand((sample) => sample.undoRedoUs)),
      'historyNavigationUs': _stats(
        samples.expand((sample) => sample.historyNavigationUs),
      ),
      'completionAcceptUs': _stats(
        samples.map((sample) => sample.completionAcceptUs),
      ),
      'pasteCompleteUs': _stats(
        samples.map((sample) => sample.pasteCompleteUs),
      ),
      'semanticOrTestQueryUs': _stats(
        samples.map((sample) => sample.semanticOrTestQueryUs),
      ),
      'rssDeltaBytes': samples
          .map((sample) => sample.rssDeltaBytes)
          .reduce(math.max),
      'lineOfCodeCount': appLines,
      'testLineOfCodeCount': testLines,
      'textCharsRequested': options.textChars,
      'adapterOwnedFeatureCount': 3,
    },
    'correctness': <Object?>[
      <String, Object?>{
        'gate': 'mixed-width text remains valid',
        'pass': allCorrect,
        'evidence':
            'Nocterm TextField retained emoji, CJK, combining text, and paste marker.',
      },
      <String, Object?>{
        'gate': 'selection and undo state are correct',
        'pass': allSelectionUndoCorrect,
        'evidence':
            'Selection is TextField-owned; undo/redo is fixture app-owned.',
      },
      <String, Object?>{
        'gate': 'redacted value stays redacted',
        'pass': allRedacted,
        'evidence':
            'Obscured TextField terminal buffer does not contain the raw secret.',
      },
    ],
    'ergonomics': <String, Object?>{
      'lineOfCodeCount': appLines,
      'testLineOfCodeCount': testLines,
      'appFile': 'lib/text_editing_app.dart',
      'testFile': 'test/text_editing_benchmark_test.dart',
      'peerOwnedTextField': true,
      'appOwnedUndoRedo': true,
      'appOwnedHistory': true,
      'appOwnedCompletion': true,
      'semanticGraphAvailable': false,
    },
    'artifacts': <Object?>[
      <String, Object?>{
        'kind': 'source',
        'path':
            'peer-fixtures/nocterm/sb2_text_editing/lib/text_editing_app.dart',
      },
      <String, Object?>{
        'kind': 'test',
        'path':
            'peer-fixtures/nocterm/sb2_text_editing/test/text_editing_benchmark_test.dart',
      },
    ],
    'notes': <String>[
      'This is a Nocterm test-harness peer fixture, not a real-terminal run.',
      'Nocterm 0.6.0 supplies TextField, multiline, selection, clipboard paste, and obscured text.',
      'Undo/redo, submission history, and completion are app-owned adapters in this fixture because Nocterm 0.6.0 does not expose Fleury-equivalent built-in primitives for those behaviors.',
      'Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.',
    ],
  };

  final jsonText = const JsonEncoder.withIndent('  ').convert(artifact);
  if (options.outputPath != null) {
    final output = File(options.outputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$jsonText\n');
  }

  if (options.printJson) {
    stdout.writeln(jsonText);
  } else {
    final metrics = artifact['metrics']! as Map<String, Object?>;
    final cursorMove = metrics['cursorMoveUs']! as Map<String, Object?>;
    final paste = metrics['pasteCompleteUs']! as Map<String, Object?>;
    final query = metrics['semanticOrTestQueryUs']! as Map<String, Object?>;
    stdout.writeln('Nocterm SB.2 text editing fixture');
    stdout.writeln('Run: $runId');
    stdout.writeln('Iterations: ${options.measuredIterations}');
    stdout.writeln('cursorMoveUs p95: ${cursorMove['p95']}');
    stdout.writeln('pasteCompleteUs p95: ${paste['p95']}');
    stdout.writeln('semanticOrTestQueryUs p95: ${query['p95']}');
    if (options.outputPath != null) {
      stdout.writeln('Saved ${options.outputPath}');
    }
  }
}

Future<_Sample> _runSample(_Options options) async {
  final fixture = Sb2TextEditingFixture.generate(textChars: options.textChars);
  final rssBefore = ProcessInfo.currentRss;
  final tester = await NoctermTester.create(size: options.size);
  try {
    await tester.pumpComponent(Sb2TextEditingApp(fixture: fixture));
    final state = tester.findState<Sb2TextEditingState>();

    state.focusComposer();
    await tester.pump();
    final cursorMoveUs = <int>[
      await _actionUs(() => tester.sendArrowLeft()),
      await _actionUs(
        () => tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.arrowLeft,
            modifiers: ModifierKeys(ctrl: true),
          ),
        ),
      ),
      await _actionUs(() => tester.sendKey(LogicalKey.home)),
      await _actionUs(() => tester.sendKey(LogicalKey.end)),
    ];
    final insertionDeletionUs = <int>[
      await _actionUs(() => tester.enterText(' --verbose')),
      await _actionUs(() => tester.sendBackspace()),
    ];
    await tester.sendArrowLeft();
    insertionDeletionUs.add(await _actionUs(() => tester.sendDelete()));
    final insertionDeletionWorked =
        state.composer.text.contains('--verbo') &&
        !state.composer.text.contains('--verbose');

    state.focusEditor();
    state.moveEditorCursorToEnd();
    await tester.pump();
    final selectionUs = <int>[];
    for (var i = 0; i < 4; i += 1) {
      selectionUs.add(
        await _actionUs(
          () => tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.arrowLeft,
              modifiers: ModifierKeys(shift: true),
            ),
          ),
        ),
      );
    }
    selectionUs.add(
      await _actionUs(() => tester.enterText(fixture.selectionReplacement)),
    );
    final selectionReplacementInserted = state.editor.text.contains(
      fixture.selectionReplacement,
    );

    final undoRedoUs = <int>[
      await _actionUs(
        () => tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.keyZ,
            modifiers: ModifierKeys(ctrl: true),
          ),
        ),
      ),
      await _actionUs(
        () => tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.keyY,
            modifiers: ModifierKeys(ctrl: true),
          ),
        ),
      ),
    ];
    final undoRedoRestored = state.editor.text.contains(
      fixture.selectionReplacement,
    );

    ClipboardManager.copy(fixture.pasteText);
    final pasteCompleteUs = await _actionUs(
      () => tester.sendKeyEvent(
        const KeyboardEvent(
          logicalKey: LogicalKey.keyV,
          modifiers: ModifierKeys(ctrl: true),
        ),
      ),
    );
    final pasteInserted = state.editor.text.contains(fixture.pasteMarker);

    state.focusComposer();
    state.setComposerText('git che');
    await tester.pump();
    final completionAcceptUs = await _actionUs(() => tester.sendTab());
    final completionAccepted =
        state.composer.text == 'git checkout' && state.completionAccepted;

    state.setComposerText(fixture.historyDraft);
    await tester.pump();
    final historyNavigationUs = <int>[
      await _actionUs(() => tester.sendArrowUp()),
      await _actionUs(() => tester.sendArrowDown()),
    ];
    final historyRestoredDraft = state.composer.text == fixture.historyDraft;

    state.focusSecret();
    await tester.pump();
    final query = Stopwatch()..start();
    final visible = tester.terminalState;
    final mixedWidthValid =
        state.editor.text.contains(fixture.pasteMarker) &&
        state.editor.text.contains('\u6F22\u5B57') &&
        state.editor.text.contains('\u{1F642}') &&
        state.editor.text.contains('e\u0301');
    final redactedCorrect =
        !visible.containsText(fixture.secretText) &&
        visible.containsText('••••');
    final labelsVisible =
        visible.containsText('Nocterm SB.2 Text Editing') &&
        visible.containsText('Composer') &&
        visible.containsText('Editor') &&
        visible.containsText('Secret');
    query.stop();

    return _Sample(
      cursorMoveUs: cursorMoveUs,
      insertionDeletionUs: insertionDeletionUs,
      selectionUs: selectionUs,
      undoRedoUs: undoRedoUs,
      historyNavigationUs: historyNavigationUs,
      completionAcceptUs: completionAcceptUs,
      pasteCompleteUs: pasteCompleteUs,
      semanticOrTestQueryUs: query.elapsedMicroseconds,
      rssDeltaBytes: math.max(0, ProcessInfo.currentRss - rssBefore),
      correct:
          insertionDeletionWorked &&
          mixedWidthValid &&
          selectionReplacementInserted &&
          undoRedoRestored &&
          pasteInserted &&
          completionAccepted &&
          historyRestoredDraft &&
          redactedCorrect &&
          labelsVisible,
      selectionAndUndoCorrect: selectionReplacementInserted && undoRedoRestored,
      redactedCorrect: redactedCorrect,
    );
  } finally {
    tester.dispose();
  }
}

Future<int> _actionUs(Future<void> Function() action) async {
  final stopwatch = Stopwatch()..start();
  await action();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

Map<String, Object?> _stats(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    throw StateError('Cannot summarize empty metric samples.');
  }
  return <String, Object?>{
    'min': sorted.first,
    'median': _percentile(sorted, 0.50),
    'p95': _percentile(sorted, 0.95),
    'p99': _percentile(sorted, 0.99),
    'max': sorted.last,
    'samples': sorted.length,
  };
}

int _percentile(List<int> sorted, double percentile) {
  final index = ((sorted.length * percentile).ceil() - 1).clamp(
    0,
    sorted.length - 1,
  );
  return sorted[index];
}

Directory _packageRoot() {
  final script = File(Platform.script.toFilePath()).absolute;
  return script.parent.parent;
}

int _sourceLineCount(String path) {
  var lines = 0;
  for (final line in File(path).readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
    lines += 1;
  }
  return lines;
}

String _timestampForId(DateTime value) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}T'
      '${two(value.hour)}-${two(value.minute)}-${two(value.second)}Z';
}

final class _Sample {
  const _Sample({
    required this.cursorMoveUs,
    required this.insertionDeletionUs,
    required this.selectionUs,
    required this.undoRedoUs,
    required this.historyNavigationUs,
    required this.completionAcceptUs,
    required this.pasteCompleteUs,
    required this.semanticOrTestQueryUs,
    required this.rssDeltaBytes,
    required this.correct,
    required this.selectionAndUndoCorrect,
    required this.redactedCorrect,
  });

  final List<int> cursorMoveUs;
  final List<int> insertionDeletionUs;
  final List<int> selectionUs;
  final List<int> undoRedoUs;
  final List<int> historyNavigationUs;
  final int completionAcceptUs;
  final int pasteCompleteUs;
  final int semanticOrTestQueryUs;
  final int rssDeltaBytes;
  final bool correct;
  final bool selectionAndUndoCorrect;
  final bool redactedCorrect;
}

final class _Options {
  const _Options({
    required this.warmupIterations,
    required this.measuredIterations,
    required this.textChars,
    required this.size,
    required this.printJson,
    required this.outputPath,
  });

  final int warmupIterations;
  final int measuredIterations;
  final int textChars;
  final Size size;
  final bool printJson;
  final String? outputPath;

  static _Options parse(List<String> args) {
    var warmups = _defaultWarmups;
    var iterations = _defaultIterations;
    var textChars = _defaultTextChars;
    var size = _defaultSize;
    var printJson = false;
    String? outputPath;

    for (final arg in args) {
      if (arg == '--json') {
        printJson = true;
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg.startsWith('--warmup=')) {
        warmups = _positiveInt(arg, '--warmup=');
      } else if (arg.startsWith('--iterations=')) {
        iterations = _positiveInt(arg, '--iterations=');
      } else if (arg.startsWith('--text-chars=')) {
        textChars = _positiveInt(arg, '--text-chars=');
      } else if (arg.startsWith('--size=')) {
        size = _parseSize(arg.substring('--size='.length));
      } else if (arg == '--help' || arg == '-h') {
        _printUsage();
        exit(0);
      } else {
        stderr.writeln('Unknown option: $arg');
        _printUsage();
        exit(64);
      }
    }

    return _Options(
      warmupIterations: warmups,
      measuredIterations: iterations,
      textChars: textChars,
      size: size,
      printJson: printJson,
      outputPath: outputPath,
    );
  }
}

int _positiveInt(String arg, String prefix) {
  final raw = arg.substring(prefix.length);
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    stderr.writeln('$prefix expects a positive integer, got "$raw".');
    exit(64);
  }
  return value;
}

Size _parseSize(String raw) {
  final parts = raw.toLowerCase().split('x');
  if (parts.length != 2) {
    stderr.writeln('--size expects COLSxROWS, got "$raw".');
    exit(64);
  }
  final columns = int.tryParse(parts[0]);
  final rows = int.tryParse(parts[1]);
  if (columns == null || rows == null || columns <= 0 || rows <= 0) {
    stderr.writeln('--size expects positive COLSxROWS, got "$raw".');
    exit(64);
  }
  return Size(columns.toDouble(), rows.toDouble());
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run bin/sb2_text_editing_benchmark.dart '
    '[--warmup=N] [--iterations=N] [--text-chars=N] '
    '[--size=COLSxROWS] [--output=path] [--json]',
  );
}
