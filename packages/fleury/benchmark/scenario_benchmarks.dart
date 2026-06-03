// Scenario benchmarks for app-shaped Fleury workloads.
//
// These sit above the package:benchmark_harness microbenchmarks. The goal is
// repeatable user-visible journeys with JSON output, not isolated hot loops.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';

const _schemaVersion = 1;
const _fleuryVersion = '0.0.0';
const _defaultWarmups = 2;
const _defaultIterations = 20;
const _defaultTextChars = 10000;
const _counterIncrement = CommandId('scenario.counter.increment');
const _layoutIncrement = CommandId('scenario.layout.increment');
const _viewportPaintRows = 2000;
const _viewportPaintScrollOffset = 1000;

Future<void> main(List<String> args) async {
  final options = _ScenarioOptions.parse(args);
  final scenarios = <_ScenarioBenchmark>[
    const _CounterAppScenario(),
    const _TextEditingComposerScenario(),
    const _LayoutDirtinessScenario(),
  ];

  if (options.list) {
    for (final scenario in scenarios) {
      stdout.writeln('${scenario.id}\t${scenario.name}');
    }
    return;
  }

  final selected = scenarios
      .where((scenario) => options.matches(scenario))
      .toList(growable: false);
  if (selected.isEmpty) {
    stderr.writeln('No scenario matched filter "${options.filter}".');
    exitCode = 64;
    return;
  }

  final results = <_ScenarioResult>[];
  for (final scenario in selected) {
    final result = await scenario.run(options.config);
    results.add(result);
    stdout.writeln(result.summaryLine);
  }

  final document = <String, Object?>{
    'schemaVersion': _schemaVersion,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'results': [for (final result in results) result.toJson()],
  };
  final jsonText = const JsonEncoder.withIndent('  ').convert(document);
  if (options.printJson) {
    stdout.writeln(jsonText);
  }
  if (options.savePath != null) {
    final file = File(options.savePath!);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$jsonText\n');
    stdout.writeln('saved ${file.path}');
  }
}

final class _ScenarioOptions {
  const _ScenarioOptions({
    required this.config,
    this.filter,
    this.printJson = false,
    this.list = false,
    this.savePath,
  });

  factory _ScenarioOptions.parse(List<String> args) {
    var filter = '';
    var printJson = false;
    var list = false;
    var savePath = '';
    var warmups = _defaultWarmups;
    var iterations = _defaultIterations;
    var seed = 1;
    var size = const CellSize(80, 24);
    var textChars = _defaultTextChars;

    for (final arg in args) {
      if (arg == '--json') {
        printJson = true;
      } else if (arg == '--list') {
        list = true;
      } else if (arg.startsWith('--filter=')) {
        filter = arg.substring('--filter='.length);
      } else if (arg.startsWith('--save=')) {
        savePath = arg.substring('--save='.length);
      } else if (arg.startsWith('--warmup=')) {
        warmups = _positiveInt(arg, '--warmup=');
      } else if (arg.startsWith('--iterations=')) {
        iterations = _positiveInt(arg, '--iterations=');
      } else if (arg.startsWith('--seed=')) {
        seed = _positiveInt(arg, '--seed=');
      } else if (arg.startsWith('--text-chars=')) {
        textChars = _positiveInt(arg, '--text-chars=');
      } else if (arg.startsWith('--size=')) {
        size = _parseSize(arg.substring('--size='.length));
      } else if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      } else {
        stderr.writeln('Unknown option: $arg');
        _printUsageAndExit(exitCodeValue: 64);
      }
    }

    return _ScenarioOptions(
      config: _ScenarioConfig(
        warmupIterations: warmups,
        measuredIterations: iterations,
        seed: seed,
        terminalSize: size,
        textChars: textChars,
      ),
      filter: filter.isEmpty ? null : filter,
      printJson: printJson,
      list: list,
      savePath: savePath.isEmpty ? null : savePath,
    );
  }

  final _ScenarioConfig config;
  final String? filter;
  final bool printJson;
  final bool list;
  final String? savePath;

  bool matches(_ScenarioBenchmark scenario) {
    final text = filter;
    if (text == null) return true;
    final query = text.toLowerCase();
    return scenario.id.toLowerCase().contains(query) ||
        scenario.name.toLowerCase().contains(query);
  }
}

final class _ScenarioConfig {
  const _ScenarioConfig({
    required this.warmupIterations,
    required this.measuredIterations,
    required this.seed,
    required this.terminalSize,
    required this.textChars,
  });

  final int warmupIterations;
  final int measuredIterations;
  final int seed;
  final CellSize terminalSize;
  final int textChars;
}

abstract interface class _ScenarioBenchmark {
  String get id;
  String get name;
  Future<_ScenarioResult> run(_ScenarioConfig config);
}

final class _TextEditingComposerScenario implements _ScenarioBenchmark {
  const _TextEditingComposerScenario();

  @override
  String get id => 'SB.2';

  @override
  String get name => 'Text Editing Composer Stress';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    final fixture = _TextEditingFixture.generate(config);
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runTextEditingJourney(config, fixture);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_TextEditingJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runTextEditingJourney(config, fixture));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final journey = _Stats.from(samples.map((sample) => sample.totalJourneyUs));
    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final cursorMove = _Stats.from(
      samples.expand((sample) => sample.cursorMoveUs),
    );
    final insertionDeletion = _Stats.from(
      samples.expand((sample) => sample.insertionDeletionUs),
    );
    final selection = _Stats.from(
      samples.expand((sample) => sample.selectionUs),
    );
    final pasteComplete = _Stats.from(
      samples.map((sample) => sample.pasteCompleteUs),
    );
    final undoRedo = _Stats.from(samples.expand((sample) => sample.undoRedoUs));
    final historyNavigation = _Stats.from(
      samples.expand((sample) => sample.historyNavigationUs),
    );
    final completionAccept = _Stats.from(
      samples.map((sample) => sample.completionAcceptUs),
    );
    final secretRender = _Stats.from(
      samples.map((sample) => sample.secretRenderUs),
    );
    final semanticQuery = _Stats.from(
      samples.map((sample) => sample.semanticQueryUs),
    );
    final correct = samples.every((sample) => sample.correct);
    final last = samples.last;

    return _ScenarioResult(
      scenarioId: id,
      scenarioName: name,
      startedAt: startedAt,
      duration: total.elapsed,
      warmupIterations: config.warmupIterations,
      measuredIterations: config.measuredIterations,
      seed: config.seed,
      terminalSize: config.terminalSize,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'cursorMoveUs': cursorMove.toJson(),
        'insertionDeletionUs': insertionDeletion.toJson(),
        'selectionUs': selection.toJson(),
        'pasteCompleteUs': pasteComplete.toJson(),
        'undoRedoUs': undoRedo.toJson(),
        'historyNavigationUs': historyNavigation.toJson(),
        'completionAcceptUs': completionAccept.toJson(),
        'secretRenderUs': secretRender.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'firstFrameAnsiBytes': last.firstFrameAnsiBytes,
        'finalAnsiBytes': last.finalAnsiBytes,
        'semanticNodeCount': last.semanticNodeCount,
        'textCharsRequested': config.textChars,
        'initialEditorChars': fixture.editorText.length,
        'finalEditorChars': last.finalEditorChars,
        'pasteChars': fixture.pasteText.length,
        'pasteFrameCount': last.pasteFrameCount,
        'completionAccepted': last.completionAccepted,
        'historyRestoredDraft': last.historyRestoredDraft,
        'secretSemanticRedacted': last.secretSemanticRedacted,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateCursorMoveP95Us': 16000,
        'candidateInsertionDeletionP95Us': 16000,
        'candidateSelectionP95Us': 16000,
        'candidateSemanticQueryP95Us': 16000,
        'candidatePasteCompleteP95Us': 100000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Run mode is test-style harness execution, not a full terminal process.',
        'Completion popup rendering lives in fleury_widgets; this core scenario measures the shared editing state and TextInput acceptance path.',
      ],
    );
  }
}

Future<_TextEditingJourneySample> _runTextEditingJourney(
  _ScenarioConfig config,
  _TextEditingFixture fixture,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final composer = TextEditingController(text: fixture.composerText);
  final editor = TextEditingController(text: fixture.editorText);
  final secret = TextEditingController(text: fixture.secretText);
  final history = TextHistoryController(entries: fixture.historyEntries);
  final completion = TextCompletionController();
  final composerFocus = FocusNode(debugLabel: 'SB.2 composer');
  final editorFocus = FocusNode(debugLabel: 'SB.2 editor');
  final secretFocus = FocusNode(debugLabel: 'SB.2 secret');
  final total = Stopwatch()..start();

  try {
    final mount = Stopwatch()..start();
    tester.pumpWidget(
      _TextEditingScenarioApp(
        composer: composer,
        editor: editor,
        secret: secret,
        history: history,
        completion: completion,
        composerFocus: composerFocus,
        editorFocus: editorFocus,
        secretFocus: secretFocus,
      ),
    );
    mount.stop();

    final firstRender = Stopwatch()..start();
    final initial = tester.render(size: config.terminalSize);
    firstRender.stop();
    final firstFrameBytes = _ansiBytes(initial, config.terminalSize);

    tester.focusManager.requestFocus(composerFocus);
    tester.pump();
    final cursorMoveUs = <int>[
      _visibleActionUs(tester, config, () {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      }),
      _visibleActionUs(tester, config, () {
        tester.sendKey(
          const KeyEvent(
            keyCode: KeyCode.arrowLeft,
            modifiers: {KeyModifier.ctrl},
          ),
        );
      }),
      _visibleActionUs(tester, config, () {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
      }),
      _visibleActionUs(tester, config, () {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      }),
    ];
    final insertionDeletionUs = <int>[
      _visibleActionUs(tester, config, () {
        tester.type(' --verbose');
      }),
      _visibleActionUs(tester, config, () {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.backspace));
      }),
    ];
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
    insertionDeletionUs.add(
      _visibleActionUs(tester, config, () {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.delete));
      }),
    );
    final insertionDeletionWorked =
        composer.text.contains('--verbo') &&
        !composer.text.contains('--verbose');

    tester.focusManager.requestFocus(editorFocus);
    tester.pump();
    final selectionUs = <int>[
      for (var i = 0; i < 4; i++)
        _visibleActionUs(tester, config, () {
          tester.sendKey(
            const KeyEvent(
              keyCode: KeyCode.arrowLeft,
              modifiers: {KeyModifier.shift},
            ),
          );
        }),
      _visibleActionUs(tester, config, () {
        tester.type(fixture.selectionReplacement);
      }),
    ];
    final selectionReplacementInserted = editor.text.contains(
      fixture.selectionReplacement,
    );

    final undoRedoUs = <int>[
      _visibleActionUs(tester, config, () {
        tester.sendKey(
          const KeyEvent(char: 'z', modifiers: {KeyModifier.ctrl}),
        );
      }),
      _visibleActionUs(tester, config, () {
        tester.sendKey(
          const KeyEvent(char: 'y', modifiers: {KeyModifier.ctrl}),
        );
      }),
    ];
    final undoRedoRestored = editor.text.contains(fixture.selectionReplacement);

    final paste = Stopwatch()..start();
    tester.paste(fixture.pasteText);
    tester.render(size: config.terminalSize);
    var pasteFrameCount = 1;
    while (_pasteInProgress(tester, SemanticRole.textArea)) {
      if (pasteFrameCount > fixture.maxPasteFrames) {
        break;
      }
      tester.pump();
      tester.render(size: config.terminalSize);
      pasteFrameCount += 1;
    }
    paste.stop();
    final pasteInserted = editor.text.contains(fixture.pasteMarker);

    tester.focusManager.requestFocus(composerFocus);
    composer.value = TextEditingValue(text: 'git che');
    completion.open(
      range: const TextRange(start: 4, end: 7),
      query: 'che',
      options: const [
        TextCompletionOption(label: 'checkout'),
        TextCompletionOption(label: 'cherry-pick'),
      ],
    );
    tester.pump();
    final completionAcceptUs = _visibleActionUs(tester, config, () {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));
    });
    final completionAccepted = composer.text == 'git checkout';

    composer.value = TextEditingValue(text: fixture.historyDraft);
    tester.pump();
    final historyNavigationUs = <int>[
      _visibleActionUs(tester, config, () {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      }),
      _visibleActionUs(tester, config, () {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      }),
    ];
    final historyRestoredDraft = composer.text == fixture.historyDraft;

    tester.focusManager.requestFocus(secretFocus);
    tester.pump();
    final secretRender = Stopwatch()..start();
    final finalFrame = tester.render(size: config.terminalSize);
    secretRender.stop();
    final finalFrameBytes = _ansiBytes(finalFrame, config.terminalSize);

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final region = tree.single(
      role: SemanticRole.region,
      label: 'Text editing composer stress',
    );
    final composerNode = tree.single(
      role: SemanticRole.textField,
      label: 'Command composer',
    );
    final editorNode = tree.single(
      role: SemanticRole.textArea,
      label: 'Longform editor',
    );
    final secretNode = tree.single(
      role: SemanticRole.textField,
      label: 'Secret token',
    );
    semantics.stop();
    total.stop();

    final secretRedacted =
        secretNode.value == null && secretNode.state.redactedValue == true;
    final composerHasHistory =
        composerNode.state.historyCount == fixture.historyEntries.length;
    final editorHasPasteState =
        editorNode.state.pasteInProgress == false &&
        editorNode.state.pasteInsertedLength == 0;

    return _TextEditingJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      cursorMoveUs: cursorMoveUs,
      insertionDeletionUs: insertionDeletionUs,
      selectionUs: selectionUs,
      pasteCompleteUs: paste.elapsedMicroseconds,
      undoRedoUs: undoRedoUs,
      historyNavigationUs: historyNavigationUs,
      completionAcceptUs: completionAcceptUs,
      secretRenderUs: secretRender.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      firstFrameAnsiBytes: firstFrameBytes,
      finalAnsiBytes: finalFrameBytes,
      semanticNodeCount: tree.nodes.length,
      finalEditorChars: editor.text.length,
      pasteFrameCount: pasteFrameCount,
      completionAccepted: completionAccepted,
      historyRestoredDraft: historyRestoredDraft,
      secretSemanticRedacted: secretRedacted,
      correct:
          region.state['fixture'] == 'SB.2' &&
          insertionDeletionWorked &&
          selectionReplacementInserted &&
          undoRedoRestored &&
          pasteInserted &&
          completionAccepted &&
          historyRestoredDraft &&
          secretRedacted &&
          composerHasHistory &&
          editorHasPasteState,
    );
  } finally {
    tester.dispose();
    composer.dispose();
    editor.dispose();
    secret.dispose();
    history.dispose();
    completion.dispose();
    composerFocus.dispose();
    editorFocus.dispose();
    secretFocus.dispose();
  }
}

final class _CounterAppScenario implements _ScenarioBenchmark {
  const _CounterAppScenario();

  @override
  String get id => 'SB.1';

  @override
  String get name => 'Time To Counter App';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runCounterJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final total = Stopwatch()..start();
    final samples = <_CounterJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runCounterJourney(config));
    }
    total.stop();

    final commandToFrame = _Stats.from(
      samples.map((sample) => sample.commandToFrameUs),
    );
    final firstFrame = _Stats.from(
      samples.map((sample) => sample.firstFrameUs),
    );
    final startupMount = _Stats.from(
      samples.map((sample) => sample.startupMountUs),
    );
    final semanticQuery = _Stats.from(
      samples.map((sample) => sample.semanticQueryUs),
    );
    final firstFrameLayoutPerformed = _Stats.from(
      samples.map((sample) => sample.firstFrameLayoutStats.performedCount),
    );
    final firstFrameLayoutSkipped = _Stats.from(
      samples.map((sample) => sample.firstFrameLayoutStats.skippedCount),
    );
    final commandFrameLayoutPerformed = _Stats.from(
      samples.map((sample) => sample.commandFrameLayoutStats.performedCount),
    );
    final commandFrameLayoutSkipped = _Stats.from(
      samples.map((sample) => sample.commandFrameLayoutStats.skippedCount),
    );
    final journey = _Stats.from(samples.map((sample) => sample.totalJourneyUs));
    final correct = samples.every((sample) => sample.correct);
    final last = samples.last;

    return _ScenarioResult(
      scenarioId: id,
      scenarioName: name,
      startedAt: startedAt,
      duration: total.elapsed,
      warmupIterations: config.warmupIterations,
      measuredIterations: config.measuredIterations,
      seed: config.seed,
      terminalSize: config.terminalSize,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'startupMountUs': startupMount.toJson(),
        'firstFrameUs': firstFrame.toJson(),
        'commandToFrameUs': commandToFrame.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'firstFrameLayoutPerformed': firstFrameLayoutPerformed.toJson(),
        'firstFrameLayoutSkipped': firstFrameLayoutSkipped.toJson(),
        'commandFrameLayoutPerformed': commandFrameLayoutPerformed.toJson(),
        'commandFrameLayoutSkipped': commandFrameLayoutSkipped.toJson(),
        'lastCommandFrameLayout': _layoutStatsToJson(
          last.commandFrameLayoutStats,
        ),
        'firstFrameAnsiBytes': last.firstFrameAnsiBytes,
        'semanticNodeCount': last.semanticNodeCount,
        'commandCount': last.commandCount,
        'counterValue': last.counterValue,
      },
      thresholds: const <String, Object?>{
        'candidateCommandToFrameP95Us': 16000,
        'candidateFirstFrameP95Us': 33000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until first baselines stabilize.',
        'Run mode is test-style harness execution, not a full terminal process.',
      ],
    );
  }
}

final class _LayoutDirtinessScenario implements _ScenarioBenchmark {
  const _LayoutDirtinessScenario();

  @override
  String get id => 'SB.12';

  @override
  String get name => 'Layout Dirtiness Cache';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runLayoutDirtinessJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final total = Stopwatch()..start();
    final samples = <_LayoutDirtinessJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runLayoutDirtinessJourney(config));
    }
    total.stop();

    final journey = _Stats.from(samples.map((sample) => sample.totalJourneyUs));
    final firstFrame = _Stats.from(
      samples.map((sample) => sample.firstFrameUs),
    );
    final commandToFrame = _Stats.from(
      samples.map((sample) => sample.commandToFrameUs),
    );
    final idleFrame = _Stats.from(samples.map((sample) => sample.idleFrameUs));
    final paintOnlyFrame = _Stats.from(
      samples.map((sample) => sample.paintOnlyFrameUs),
    );
    final textPaintOnlyFrame = _Stats.from(
      samples.map((sample) => sample.textPaintOnlyFrameUs),
    );
    final childListNoOpFrame = _Stats.from(
      samples.map((sample) => sample.childListNoOpFrameUs),
    );
    final viewportFirstFrame = _Stats.from(
      samples.map((sample) => sample.viewportFirstFrameUs),
    );
    final viewportScrollFrame = _Stats.from(
      samples.map((sample) => sample.viewportScrollFrameUs),
    );
    final viewportFirstPaintedRows = _Stats.from(
      samples.map((sample) => sample.viewportFirstPaintedRows),
    );
    final viewportScrolledPaintedRows = _Stats.from(
      samples.map((sample) => sample.viewportScrolledPaintedRows),
    );
    final updatePerformed = _Stats.from(
      samples.map((sample) => sample.updateLayoutStats.performedCount),
    );
    final updateSkipped = _Stats.from(
      samples.map((sample) => sample.updateLayoutStats.skippedCount),
    );
    final idlePerformed = _Stats.from(
      samples.map((sample) => sample.idleLayoutStats.performedCount),
    );
    final idleSkipped = _Stats.from(
      samples.map((sample) => sample.idleLayoutStats.skippedCount),
    );
    final paintOnlyPerformed = _Stats.from(
      samples.map((sample) => sample.paintOnlyLayoutStats.performedCount),
    );
    final paintOnlySkipped = _Stats.from(
      samples.map((sample) => sample.paintOnlyLayoutStats.skippedCount),
    );
    final textPaintOnlyPerformed = _Stats.from(
      samples.map((sample) => sample.textPaintOnlyLayoutStats.performedCount),
    );
    final textPaintOnlySkipped = _Stats.from(
      samples.map((sample) => sample.textPaintOnlyLayoutStats.skippedCount),
    );
    final childListNoOpPerformed = _Stats.from(
      samples.map((sample) => sample.childListNoOpLayoutStats.performedCount),
    );
    final childListNoOpSkipped = _Stats.from(
      samples.map((sample) => sample.childListNoOpLayoutStats.skippedCount),
    );
    final semanticQuery = _Stats.from(
      samples.map((sample) => sample.semanticQueryUs),
    );
    final correct = samples.every((sample) => sample.correct);
    final last = samples.last;

    return _ScenarioResult(
      scenarioId: id,
      scenarioName: name,
      startedAt: startedAt,
      duration: total.elapsed,
      warmupIterations: config.warmupIterations,
      measuredIterations: config.measuredIterations,
      seed: config.seed,
      terminalSize: config.terminalSize,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'firstFrameUs': firstFrame.toJson(),
        'commandToFrameUs': commandToFrame.toJson(),
        'idleFrameUs': idleFrame.toJson(),
        'paintOnlyFrameUs': paintOnlyFrame.toJson(),
        'textPaintOnlyFrameUs': textPaintOnlyFrame.toJson(),
        'childListNoOpFrameUs': childListNoOpFrame.toJson(),
        'viewportFirstFrameUs': viewportFirstFrame.toJson(),
        'viewportScrollFrameUs': viewportScrollFrame.toJson(),
        'viewportFirstPaintedRows': viewportFirstPaintedRows.toJson(),
        'viewportScrolledPaintedRows': viewportScrolledPaintedRows.toJson(),
        'updateLayoutPerformed': updatePerformed.toJson(),
        'updateLayoutSkipped': updateSkipped.toJson(),
        'idleLayoutPerformed': idlePerformed.toJson(),
        'idleLayoutSkipped': idleSkipped.toJson(),
        'paintOnlyLayoutPerformed': paintOnlyPerformed.toJson(),
        'paintOnlyLayoutSkipped': paintOnlySkipped.toJson(),
        'textPaintOnlyLayoutPerformed': textPaintOnlyPerformed.toJson(),
        'textPaintOnlyLayoutSkipped': textPaintOnlySkipped.toJson(),
        'childListNoOpLayoutPerformed': childListNoOpPerformed.toJson(),
        'childListNoOpLayoutSkipped': childListNoOpSkipped.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'lastFirstFrameLayout': _layoutStatsToJson(last.firstFrameLayoutStats),
        'lastUpdateFrameLayout': _layoutStatsToJson(last.updateLayoutStats),
        'lastIdleFrameLayout': _layoutStatsToJson(last.idleLayoutStats),
        'lastPaintOnlyFrameLayout': _layoutStatsToJson(
          last.paintOnlyLayoutStats,
        ),
        'lastTextPaintOnlyFrameLayout': _layoutStatsToJson(
          last.textPaintOnlyLayoutStats,
        ),
        'lastChildListNoOpFrameLayout': _layoutStatsToJson(
          last.childListNoOpLayoutStats,
        ),
        'staticRows': _LayoutDirtinessScenarioApp.staticRows,
        'viewportRows': last.viewportRows,
        'viewportTotalRows': _viewportPaintRows,
        'viewportScrollOffset': _viewportPaintScrollOffset,
        'lastViewportFirstPaintedRows': last.viewportFirstPaintedRows,
        'lastViewportScrolledPaintedRows': last.viewportScrolledPaintedRows,
        'semanticNodeCount': last.semanticNodeCount,
        'counterValue': last.counterValue,
        'paintAccent': last.paintAccent,
        'textVariant': last.textVariant,
      },
      thresholds: const <String, Object?>{
        'candidateCommandToFrameP95Us': 16000,
        'candidateIdleFrameP95Us': 8000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Measures layout dirtiness through a static pane plus a changing counter pane.',
        'Update frames should skip clean static subtree layouts; idle frames should skip the root layout.',
        'Paint-only style changes should repaint while skipping same-constraint layout.',
        'Same-width single-line text swaps should repaint while skipping same-constraint layout.',
        'Same-identity child-list rebuilds should preserve cached layout.',
        'Viewport paint should visit visible non-selectable rows, not every row in a long ScrollView child.',
      ],
    );
  }
}

Future<_CounterJourneySample> _runCounterJourney(_ScenarioConfig config) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final total = Stopwatch()..start();
  try {
    final mount = Stopwatch()..start();
    tester.pumpWidget(const _CounterScenarioApp());
    mount.stop();

    final firstFrame = Stopwatch()..start();
    final firstFrameSample = _renderMeasured(tester, config);
    final initial = firstFrameSample.buffer;
    firstFrame.stop();
    final bytes = _ansiBytes(initial, config.terminalSize);

    final command = Stopwatch()..start();
    final result = await tester.invokeCommand(_counterIncrement);
    final commandFrameSample = _renderMeasured(tester, config);
    command.stop();

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final counter = tree.single(
      role: SemanticRole.region,
      label: 'Counter app',
    );
    final app = tree.single(role: SemanticRole.app, label: 'Scenario Counter');
    semantics.stop();
    total.stop();

    return _CounterJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      startupMountUs: mount.elapsedMicroseconds,
      firstFrameUs: firstFrame.elapsedMicroseconds,
      commandToFrameUs: command.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      firstFrameLayoutStats: firstFrameSample.layoutStats,
      commandFrameLayoutStats: commandFrameSample.layoutStats,
      firstFrameAnsiBytes: bytes,
      semanticNodeCount: tree.nodes.length,
      commandCount: app.state.commandCount ?? 0,
      counterValue: counter.state['counterValue'] as int? ?? -1,
      correct:
          result.status == CommandInvocationStatus.completed &&
          counter.state['counterValue'] == 1,
    );
  } finally {
    tester.dispose();
  }
}

Future<_LayoutDirtinessJourneySample> _runLayoutDirtinessJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final counterModel = _CounterModel(initialValue: 9);
  final total = Stopwatch()..start();
  try {
    tester.pumpWidget(_LayoutDirtinessScenarioApp(counter: counterModel));

    final firstFrame = Stopwatch()..start();
    final firstFrameSample = _renderMeasured(tester, config);
    firstFrame.stop();

    final command = Stopwatch()..start();
    final result = await tester.invokeCommand(_layoutIncrement);
    final updateFrameSample = _renderMeasured(tester, config);
    command.stop();

    final paintOnly = Stopwatch()..start();
    counterModel.toggleAccent();
    final paintOnlyFrameSample = _renderMeasured(tester, config);
    paintOnly.stop();

    final textPaintOnly = Stopwatch()..start();
    counterModel.toggleTextVariant();
    final textPaintOnlyFrameSample = _renderMeasured(tester, config);
    textPaintOnly.stop();

    final childListNoOp = Stopwatch()..start();
    tester.pumpWidget(_LayoutDirtinessScenarioApp(counter: counterModel));
    final childListNoOpFrameSample = _renderMeasured(tester, config);
    childListNoOp.stop();

    final idle = Stopwatch()..start();
    final idleFrameSample = _renderMeasured(tester, config);
    idle.stop();

    final viewportPaintSample = _runViewportPaintCullingJourney(config);

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final counter = tree.single(
      role: SemanticRole.region,
      label: 'Layout dirtiness counter',
    );
    semantics.stop();
    total.stop();

    final counterValue = counter.state['counterValue'] as int? ?? -1;
    final paintAccent = counter.state['paintAccent'] == true;
    final textVariant = counter.state['textVariant'] == true;
    return _LayoutDirtinessJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      firstFrameUs: firstFrame.elapsedMicroseconds,
      commandToFrameUs: command.elapsedMicroseconds,
      paintOnlyFrameUs: paintOnly.elapsedMicroseconds,
      textPaintOnlyFrameUs: textPaintOnly.elapsedMicroseconds,
      childListNoOpFrameUs: childListNoOp.elapsedMicroseconds,
      viewportFirstFrameUs: viewportPaintSample.firstFrameUs,
      viewportScrollFrameUs: viewportPaintSample.scrollFrameUs,
      idleFrameUs: idle.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      firstFrameLayoutStats: firstFrameSample.layoutStats,
      updateLayoutStats: updateFrameSample.layoutStats,
      paintOnlyLayoutStats: paintOnlyFrameSample.layoutStats,
      textPaintOnlyLayoutStats: textPaintOnlyFrameSample.layoutStats,
      childListNoOpLayoutStats: childListNoOpFrameSample.layoutStats,
      idleLayoutStats: idleFrameSample.layoutStats,
      viewportRows: viewportPaintSample.viewportRows,
      viewportFirstPaintedRows: viewportPaintSample.firstPaintedRows,
      viewportScrolledPaintedRows: viewportPaintSample.scrolledPaintedRows,
      semanticNodeCount: tree.nodes.length,
      counterValue: counterValue,
      paintAccent: paintAccent,
      textVariant: textVariant,
      correct:
          result.status == CommandInvocationStatus.completed &&
          counterValue == 10 &&
          paintAccent &&
          textVariant &&
          firstFrameSample.layoutStats.performedCount > 0 &&
          updateFrameSample.layoutStats.performedCount > 0 &&
          updateFrameSample.layoutStats.skippedCount > 0 &&
          paintOnlyFrameSample.layoutStats.performedCount == 0 &&
          paintOnlyFrameSample.layoutStats.skippedCount > 0 &&
          textPaintOnlyFrameSample.layoutStats.performedCount == 0 &&
          textPaintOnlyFrameSample.layoutStats.skippedCount > 0 &&
          childListNoOpFrameSample.layoutStats.performedCount == 0 &&
          childListNoOpFrameSample.layoutStats.skippedCount > 0 &&
          idleFrameSample.layoutStats.performedCount == 0 &&
          idleFrameSample.layoutStats.skippedCount > 0 &&
          viewportPaintSample.correct,
    );
  } finally {
    tester.dispose();
    counterModel.dispose();
  }
}

_ViewportPaintCullingSample _runViewportPaintCullingJourney(
  _ScenarioConfig config,
) {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final controller = ScrollController();
  final counter = _ViewportPaintCounter();
  try {
    tester.pumpWidget(
      _ViewportPaintCullingApp(controller: controller, counter: counter),
    );

    counter.reset();
    final firstFrame = Stopwatch()..start();
    tester.render(size: config.terminalSize);
    firstFrame.stop();
    final firstPaintedRows = counter.paintCount;
    final firstPaintedIndexes = counter.paintedIndexes.toList(growable: false);

    counter.reset();
    controller.jumpTo(_viewportPaintScrollOffset);
    final scrollFrame = Stopwatch()..start();
    tester.render(size: config.terminalSize);
    scrollFrame.stop();
    final scrolledPaintedRows = counter.paintCount;
    final scrolledPaintedIndexes = counter.paintedIndexes.toList(
      growable: false,
    );

    final viewportRows = config.terminalSize.rows;
    final expectedScrolledFirstIndex = _viewportPaintScrollOffset;
    final expectedScrolledLastIndex =
        _viewportPaintScrollOffset + scrolledPaintedRows - 1;
    final firstStartsAtTop =
        firstPaintedIndexes.isNotEmpty && firstPaintedIndexes.first == 0;
    final scrolledStartsAtOffset =
        scrolledPaintedIndexes.isNotEmpty &&
        scrolledPaintedIndexes.first == expectedScrolledFirstIndex;
    final scrolledEndsInViewport =
        scrolledPaintedIndexes.isNotEmpty &&
        scrolledPaintedIndexes.last == expectedScrolledLastIndex;

    return _ViewportPaintCullingSample(
      firstFrameUs: firstFrame.elapsedMicroseconds,
      scrollFrameUs: scrollFrame.elapsedMicroseconds,
      viewportRows: viewportRows,
      firstPaintedRows: firstPaintedRows,
      scrolledPaintedRows: scrolledPaintedRows,
      correct:
          controller.offset == _viewportPaintScrollOffset &&
          firstPaintedRows <= viewportRows &&
          scrolledPaintedRows <= viewportRows &&
          firstStartsAtTop &&
          scrolledStartsAtOffset &&
          scrolledEndsInViewport,
    );
  } finally {
    tester.dispose();
  }
}

int _ansiBytes(CellBuffer buffer, CellSize size) {
  final sink = _CountingAnsiSink();
  const AnsiRenderer().renderDiff(CellBuffer(size), buffer, sink);
  return sink.bytes;
}

Map<String, Object?> _layoutStatsToJson(RenderLayoutFrameStats stats) {
  return <String, Object?>{
    'performedCount': stats.performedCount,
    'skippedCount': stats.skippedCount,
    'totalCount': stats.totalCount,
    'skippedRatio': stats.skippedRatio,
  };
}

_MeasuredRender _renderMeasured(FleuryTester tester, _ScenarioConfig config) {
  RenderLayoutDebugStats.beginFrame(enabled: true);
  try {
    final buffer = tester.render(size: config.terminalSize);
    final stats = RenderLayoutDebugStats.takeFrameStats();
    return _MeasuredRender(buffer: buffer, layoutStats: stats);
  } catch (_) {
    RenderLayoutDebugStats.takeFrameStats();
    rethrow;
  }
}

int _visibleActionUs(
  FleuryTester tester,
  _ScenarioConfig config,
  void Function() action,
) {
  final stopwatch = Stopwatch()..start();
  action();
  tester.render(size: config.terminalSize);
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

bool _pasteInProgress(FleuryTester tester, SemanticRole role) {
  final node = tester.semantics().single(role: role);
  return node.state.pasteInProgress == true;
}

final class _TextEditingFixture {
  const _TextEditingFixture({
    required this.composerText,
    required this.editorText,
    required this.secretText,
    required this.pasteText,
    required this.pasteMarker,
    required this.selectionReplacement,
    required this.historyEntries,
    required this.historyDraft,
    required this.maxPasteFrames,
  });

  factory _TextEditingFixture.generate(_ScenarioConfig config) {
    final editorText = _mixedText(
      targetChars: config.textChars,
      seed: config.seed,
      linePrefix: 'editor',
    );
    final pasteTarget = (config.textChars ~/ 2).clamp(1024, 8192);
    const pasteMarker = 'SB2_PASTE_MARKER';
    final pasteText =
        '$pasteMarker\n'
        '${_mixedText(targetChars: pasteTarget, seed: config.seed + 17, linePrefix: 'paste')}';
    return _TextEditingFixture(
      composerText: 'deploy service-${config.seed} --target staging',
      editorText: editorText,
      secretText: 'fleury-secret-${config.seed}-do-not-leak',
      pasteText: pasteText,
      pasteMarker: pasteMarker,
      selectionReplacement: '[edited]',
      historyEntries: const [
        'status --json',
        'logs --tail',
        'deploy --dry-run',
      ],
      historyDraft: 'draft command',
      maxPasteFrames: (pasteText.length ~/ 256) + 20,
    );
  }

  final String composerText;
  final String editorText;
  final String secretText;
  final String pasteText;
  final String pasteMarker;
  final String selectionReplacement;
  final List<String> historyEntries;
  final String historyDraft;
  final int maxPasteFrames;
}

String _mixedText({
  required int targetChars,
  required int seed,
  required String linePrefix,
}) {
  const emoji = '\u{1F642}';
  const cjk = '\u6F22\u5B57';
  const combining = 'e\u0301';
  const longToken =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final buffer = StringBuffer();
  var i = 0;
  while (buffer.length < targetChars) {
    final lane = (i + seed) % 5;
    buffer
      ..write(linePrefix)
      ..write('-')
      ..write(i)
      ..write(' ');
    switch (lane) {
      case 0:
        buffer.writeln('alpha beta gamma $combining $emoji');
      case 1:
        buffer.writeln('paths /tmp/fleury/$seed/$i $cjk');
      case 2:
        buffer.writeln('long-line $longToken$longToken$longToken');
      case 3:
        buffer.writeln('command --flag=$i --label=$combining');
      default:
        buffer.writeln('wide $cjk $emoji $combining');
    }
    i += 1;
  }
  return buffer.toString();
}

final class _TextEditingJourneySample {
  const _TextEditingJourneySample({
    required this.totalJourneyUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.cursorMoveUs,
    required this.insertionDeletionUs,
    required this.selectionUs,
    required this.pasteCompleteUs,
    required this.undoRedoUs,
    required this.historyNavigationUs,
    required this.completionAcceptUs,
    required this.secretRenderUs,
    required this.semanticQueryUs,
    required this.firstFrameAnsiBytes,
    required this.finalAnsiBytes,
    required this.semanticNodeCount,
    required this.finalEditorChars,
    required this.pasteFrameCount,
    required this.completionAccepted,
    required this.historyRestoredDraft,
    required this.secretSemanticRedacted,
    required this.correct,
  });

  final int totalJourneyUs;
  final int mountUs;
  final int firstRenderUs;
  final List<int> cursorMoveUs;
  final List<int> insertionDeletionUs;
  final List<int> selectionUs;
  final int pasteCompleteUs;
  final List<int> undoRedoUs;
  final List<int> historyNavigationUs;
  final int completionAcceptUs;
  final int secretRenderUs;
  final int semanticQueryUs;
  final int firstFrameAnsiBytes;
  final int finalAnsiBytes;
  final int semanticNodeCount;
  final int finalEditorChars;
  final int pasteFrameCount;
  final bool completionAccepted;
  final bool historyRestoredDraft;
  final bool secretSemanticRedacted;
  final bool correct;
}

final class _MeasuredRender {
  const _MeasuredRender({required this.buffer, required this.layoutStats});

  final CellBuffer buffer;
  final RenderLayoutFrameStats layoutStats;
}

final class _CounterJourneySample {
  const _CounterJourneySample({
    required this.totalJourneyUs,
    required this.startupMountUs,
    required this.firstFrameUs,
    required this.commandToFrameUs,
    required this.semanticQueryUs,
    required this.firstFrameLayoutStats,
    required this.commandFrameLayoutStats,
    required this.firstFrameAnsiBytes,
    required this.semanticNodeCount,
    required this.commandCount,
    required this.counterValue,
    required this.correct,
  });

  final int totalJourneyUs;
  final int startupMountUs;
  final int firstFrameUs;
  final int commandToFrameUs;
  final int semanticQueryUs;
  final RenderLayoutFrameStats firstFrameLayoutStats;
  final RenderLayoutFrameStats commandFrameLayoutStats;
  final int firstFrameAnsiBytes;
  final int semanticNodeCount;
  final int commandCount;
  final int counterValue;
  final bool correct;
}

final class _LayoutDirtinessJourneySample {
  const _LayoutDirtinessJourneySample({
    required this.totalJourneyUs,
    required this.firstFrameUs,
    required this.commandToFrameUs,
    required this.paintOnlyFrameUs,
    required this.textPaintOnlyFrameUs,
    required this.childListNoOpFrameUs,
    required this.viewportFirstFrameUs,
    required this.viewportScrollFrameUs,
    required this.idleFrameUs,
    required this.semanticQueryUs,
    required this.firstFrameLayoutStats,
    required this.updateLayoutStats,
    required this.paintOnlyLayoutStats,
    required this.textPaintOnlyLayoutStats,
    required this.childListNoOpLayoutStats,
    required this.idleLayoutStats,
    required this.viewportRows,
    required this.viewportFirstPaintedRows,
    required this.viewportScrolledPaintedRows,
    required this.semanticNodeCount,
    required this.counterValue,
    required this.paintAccent,
    required this.textVariant,
    required this.correct,
  });

  final int totalJourneyUs;
  final int firstFrameUs;
  final int commandToFrameUs;
  final int paintOnlyFrameUs;
  final int textPaintOnlyFrameUs;
  final int childListNoOpFrameUs;
  final int viewportFirstFrameUs;
  final int viewportScrollFrameUs;
  final int idleFrameUs;
  final int semanticQueryUs;
  final RenderLayoutFrameStats firstFrameLayoutStats;
  final RenderLayoutFrameStats updateLayoutStats;
  final RenderLayoutFrameStats paintOnlyLayoutStats;
  final RenderLayoutFrameStats textPaintOnlyLayoutStats;
  final RenderLayoutFrameStats childListNoOpLayoutStats;
  final RenderLayoutFrameStats idleLayoutStats;
  final int viewportRows;
  final int viewportFirstPaintedRows;
  final int viewportScrolledPaintedRows;
  final int semanticNodeCount;
  final int counterValue;
  final bool paintAccent;
  final bool textVariant;
  final bool correct;
}

final class _ViewportPaintCullingSample {
  const _ViewportPaintCullingSample({
    required this.firstFrameUs,
    required this.scrollFrameUs,
    required this.viewportRows,
    required this.firstPaintedRows,
    required this.scrolledPaintedRows,
    required this.correct,
  });

  final int firstFrameUs;
  final int scrollFrameUs;
  final int viewportRows;
  final int firstPaintedRows;
  final int scrolledPaintedRows;
  final bool correct;
}

final class _ScenarioResult {
  const _ScenarioResult({
    required this.scenarioId,
    required this.scenarioName,
    required this.startedAt,
    required this.duration,
    required this.warmupIterations,
    required this.measuredIterations,
    required this.seed,
    required this.terminalSize,
    required this.metrics,
    required this.thresholds,
    required this.pass,
    required this.notes,
  });

  final String scenarioId;
  final String scenarioName;
  final DateTime startedAt;
  final Duration duration;
  final int warmupIterations;
  final int measuredIterations;
  final int seed;
  final CellSize terminalSize;
  final Map<String, Object?> metrics;
  final Map<String, Object?> thresholds;
  final bool pass;
  final List<String> notes;

  String get summaryLine {
    final primary = switch (scenarioId) {
      'SB.2' => metrics['cursorMoveUs'],
      _ => metrics['commandToFrameUs'],
    };
    final p95 = primary is Map<String, Object?> ? primary['p95'] : null;
    final status = pass ? 'pass' : 'fail';
    final label = switch (scenarioId) {
      'SB.2' => 'cursor_move_p95_us',
      _ => 'command_to_frame_p95_us',
    };
    return '$scenarioId $scenarioName: $status, $label=$p95';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _schemaVersion,
    'scenarioId': scenarioId,
    'scenarioName': scenarioName,
    'fleuryVersion': _fleuryVersion,
    'gitSha': Platform.environment['GIT_SHA'] ?? 'unknown',
    'dartVersion': Platform.version,
    'runMode': 'test',
    'os': Platform.operatingSystem,
    'cpu': Platform.numberOfProcessors,
    'terminalProfile': const <String, Object?>{
      'colorMode': 'truecolor',
      'imageProtocol': 'halfBlock',
      'tmuxPassthrough': false,
    },
    'terminalSize': <String, Object?>{
      'columns': terminalSize.cols,
      'rows': terminalSize.rows,
    },
    'seed': seed,
    'warmupIterations': warmupIterations,
    'measuredIterations': measuredIterations,
    'startedAt': startedAt.toIso8601String(),
    'durationMs': duration.inMicroseconds / 1000,
    'metrics': metrics,
    'thresholds': thresholds,
    'pass': pass,
    'notes': notes,
  };
}

final class _Stats {
  const _Stats({
    required this.min,
    required this.median,
    required this.p95,
    required this.p99,
    required this.max,
    required this.samples,
  });

  factory _Stats.from(Iterable<int> rawSamples) {
    final sorted = rawSamples.toList(growable: false)..sort();
    if (sorted.isEmpty) {
      return const _Stats(
        min: 0,
        median: 0,
        p95: 0,
        p99: 0,
        max: 0,
        samples: 0,
      );
    }
    return _Stats(
      min: sorted.first,
      median: _percentile(sorted, 0.50),
      p95: _percentile(sorted, 0.95),
      p99: _percentile(sorted, 0.99),
      max: sorted.last,
      samples: sorted.length,
    );
  }

  final int min;
  final int median;
  final int p95;
  final int p99;
  final int max;
  final int samples;

  Map<String, Object?> toJson() => <String, Object?>{
    'min': min,
    'median': median,
    'p95': p95,
    'p99': p99,
    'max': max,
    'samples': samples,
  };
}

int _percentile(List<int> sorted, double p) {
  if (sorted.length == 1) return sorted.single;
  final rank = (sorted.length - 1) * p;
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sorted[lower];
  final lowerValue = sorted[lower];
  final upperValue = sorted[upper];
  final fraction = rank - lower;
  return (lowerValue + (upperValue - lowerValue) * fraction).round();
}

final class _CountingAnsiSink implements AnsiSink {
  int bytes = 0;

  @override
  void write(String data) {
    bytes += utf8.encode(data).length;
  }

  @override
  Future<void> flush() async {}
}

class _CounterScenarioApp extends StatefulWidget {
  const _CounterScenarioApp();

  @override
  State<_CounterScenarioApp> createState() => _CounterScenarioAppState();
}

class _CounterScenarioAppState extends State<_CounterScenarioApp> {
  final _counter = _CounterModel();

  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FleuryApp(
      title: 'Scenario Counter',
      commands: [
        AppCommand(
          id: _counterIncrement,
          title: 'Increment Counter',
          semanticAction: SemanticAction.increment,
          run: (_) {
            _counter.increment();
          },
        ),
      ],
      child: _CounterScenarioBody(counter: _counter),
    );
  }
}

class _TextEditingScenarioApp extends StatelessWidget {
  const _TextEditingScenarioApp({
    required this.composer,
    required this.editor,
    required this.secret,
    required this.history,
    required this.completion,
    required this.composerFocus,
    required this.editorFocus,
    required this.secretFocus,
  });

  static const _pastePolicy = TextPastePolicy(
    largePasteThreshold: 512,
    chunkSize: 512,
  );

  final TextEditingController composer;
  final TextEditingController editor;
  final TextEditingController secret;
  final TextHistoryController history;
  final TextCompletionController completion;
  final FocusNode composerFocus;
  final FocusNode editorFocus;
  final FocusNode secretFocus;

  @override
  Widget build(BuildContext context) {
    return FleuryApp(
      title: 'Scenario Text Editing',
      child: Semantics(
        role: SemanticRole.region,
        label: 'Text editing composer stress',
        state: const SemanticState({'fixture': 'SB.2'}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Composer'),
            TextInput(
              controller: composer,
              focusNode: composerFocus,
              historyController: history,
              completionController: completion,
              autofocus: true,
              enableBlink: false,
              placeholder: 'Command composer',
              validationError: 'Review required',
              pastePolicy: _pastePolicy,
              onSubmit: (_) {},
            ),
            const Text('Editor'),
            SizedBox(
              height: 10,
              child: TextArea(
                controller: editor,
                focusNode: editorFocus,
                placeholder: 'Longform editor',
                validationError: 'Contains mixed-width fixture text',
                pastePolicy: _pastePolicy,
              ),
            ),
            const Text('Secret'),
            TextInput(
              controller: secret,
              focusNode: secretFocus,
              enableBlink: false,
              placeholder: 'Secret token',
              obscureText: true,
              clipboardPolicy: TextClipboardPolicy.redacted,
            ),
          ],
        ),
      ),
    );
  }
}

final class _CounterModel extends ChangeNotifier {
  _CounterModel({int initialValue = 0}) : _value = initialValue;

  int _value;
  var _accent = false;
  var _textVariant = false;

  int get value => _value;
  bool get accent => _accent;
  bool get textVariant => _textVariant;

  String get stableText => _textVariant ? 'bravo' : 'alpha';

  void increment() {
    _value += 1;
    notifyListeners();
  }

  void toggleAccent() {
    _accent = !_accent;
    notifyListeners();
  }

  void toggleTextVariant() {
    _textVariant = !_textVariant;
    notifyListeners();
  }
}

final class _CounterScenarioBody extends StatelessWidget {
  const _CounterScenarioBody({required this.counter});

  final _CounterModel counter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      animation: counter,
      builder: (context, _) {
        final count = counter.value;
        return Semantics(
          role: SemanticRole.region,
          label: 'Counter app',
          value: count,
          actions: const {SemanticAction.increment},
          state: SemanticState({'counterValue': count}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('Count: $count'), const Text('[+] Increment')],
          ),
        );
      },
    );
  }
}

class _LayoutDirtinessScenarioApp extends StatefulWidget {
  const _LayoutDirtinessScenarioApp({this.counter});

  static const staticRows = 32;

  final _CounterModel? counter;

  @override
  State<_LayoutDirtinessScenarioApp> createState() =>
      _LayoutDirtinessScenarioAppState();
}

class _LayoutDirtinessScenarioAppState
    extends State<_LayoutDirtinessScenarioApp> {
  late final _CounterModel _counter;
  late final bool _ownsCounter;

  @override
  void initState() {
    super.initState();
    final counter = widget.counter;
    _ownsCounter = counter == null;
    _counter = counter ?? _CounterModel();
  }

  @override
  void dispose() {
    if (_ownsCounter) {
      _counter.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FleuryApp(
      title: 'Scenario Layout Dirtiness',
      commands: [
        AppCommand(
          id: _layoutIncrement,
          title: 'Increment Layout Counter',
          semanticAction: SemanticAction.increment,
          run: (_) {
            _counter.increment();
          },
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 42, child: _StaticLayoutPane()),
          SizedBox(width: 30, child: _LayoutCounterPane(counter: _counter)),
        ],
      ),
    );
  }
}

class _StaticLayoutPane extends StatelessWidget {
  const _StaticLayoutPane();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.region,
      label: 'Static layout pane',
      state: const SemanticState({
        'fixture': 'SB.12',
        'staticRows': _LayoutDirtinessScenarioApp.staticRows,
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _LayoutDirtinessScenarioApp.staticRows; i++)
            Text('static row ${i.toString().padLeft(2, '0')} unchanged'),
        ],
      ),
    );
  }
}

class _LayoutCounterPane extends StatelessWidget {
  const _LayoutCounterPane({required this.counter});

  final _CounterModel counter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      animation: counter,
      builder: (context, _) {
        final count = counter.value;
        final accent = counter.accent;
        return Semantics(
          role: SemanticRole.region,
          label: 'Layout dirtiness counter',
          value: count,
          actions: const {SemanticAction.increment},
          state: SemanticState({
            'fixture': 'SB.12',
            'counterValue': count,
            'paintAccent': accent,
            'textVariant': counter.textVariant,
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Layout count: $count',
                style: accent ? const CellStyle(bold: true) : CellStyle.empty,
              ),
              Text('Stable text: ${counter.stableText}'),
              const Text('Only this pane changes.'),
            ],
          ),
        );
      },
    );
  }
}

final class _ViewportPaintCounter {
  final paintedIndexes = <int>[];

  int get paintCount => paintedIndexes.length;

  void reset() {
    paintedIndexes.clear();
  }

  void record(int index) {
    paintedIndexes.add(index);
  }
}

class _ViewportPaintCullingApp extends StatelessWidget {
  const _ViewportPaintCullingApp({
    required this.controller,
    required this.counter,
  });

  final ScrollController controller;
  final _ViewportPaintCounter counter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.region,
      label: 'Viewport paint culling',
      state: const SemanticState({
        'fixture': 'SB.12',
        'totalRows': _viewportPaintRows,
        'scrollOffset': _viewportPaintScrollOffset,
      }),
      child: ScrollView(
        controller: controller,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _viewportPaintRows; i++)
              _ViewportPaintRow(index: i, counter: counter),
          ],
        ),
      ),
    );
  }
}

class _ViewportPaintRow extends LeafRenderObjectWidget {
  const _ViewportPaintRow({required this.index, required this.counter});

  final int index;
  final _ViewportPaintCounter counter;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderViewportPaintRow(index: index, counter: counter);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderViewportPaintRow renderObject,
  ) {
    renderObject
      ..index = index
      ..counter = counter;
  }
}

class _RenderViewportPaintRow extends RenderObject {
  _RenderViewportPaintRow({
    required int index,
    required _ViewportPaintCounter counter,
  }) : _index = index,
       _counter = counter;

  int _index;
  int get index => _index;
  set index(int value) {
    if (_index == value) return;
    _index = value;
    markNeedsPaintOnly();
  }

  _ViewportPaintCounter _counter;
  _ViewportPaintCounter get counter => _counter;
  set counter(_ViewportPaintCounter value) {
    if (identical(_counter, value)) return;
    _counter = value;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    return constraints.constrain(const CellSize(24, 1));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _counter.record(_index);
    buffer.writeText(offset, 'viewport row $_index');
  }
}

int _positiveInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix expects a positive integer.');
    _printUsageAndExit(exitCodeValue: 64);
  }
  return value;
}

CellSize _parseSize(String text) {
  final parts = text.toLowerCase().split('x');
  if (parts.length != 2) {
    stderr.writeln('--size expects COLUMNSxROWS, for example 120x40.');
    _printUsageAndExit(exitCodeValue: 64);
  }
  final cols = int.tryParse(parts[0]);
  final rows = int.tryParse(parts[1]);
  if (cols == null || rows == null || cols <= 0 || rows <= 0) {
    stderr.writeln('--size expects positive integer dimensions.');
    _printUsageAndExit(exitCodeValue: 64);
  }
  return CellSize(cols, rows);
}

Never _printUsageAndExit({int exitCodeValue = 0}) {
  stdout.writeln(
    'Usage: dart run benchmark/scenario_benchmarks.dart [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --list                 List scenarios.');
  stdout.writeln('  --filter=TEXT          Run scenarios matching id/name.');
  stdout.writeln('  --json                 Print JSON result document.');
  stdout.writeln('  --save=PATH            Save JSON result document.');
  stdout.writeln(
    '  --warmup=N             Warmup iterations. Default $_defaultWarmups.',
  );
  stdout.writeln(
    '  --iterations=N         Measured iterations. Default $_defaultIterations.',
  );
  stdout.writeln('  --seed=N               Fixture seed. Default 1.');
  stdout.writeln('  --size=COLSxROWS       Terminal size. Default 80x24.');
  stdout.writeln(
    '  --text-chars=N         SB.2 text fixture chars. Default $_defaultTextChars.',
  );
  exit(exitCodeValue);
}
