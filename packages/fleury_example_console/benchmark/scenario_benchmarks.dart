// Scenario benchmarks for the integrated Fleury proof app.
//
// This runner lives in the example package because SB.10 intentionally
// measures the app-shaped integration surface, not a reusable widget fixture.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';

import '../lib/fleury_example_console.dart';

const _schemaVersion = 1;
const _packageVersion = '0.0.0';
const _defaultWarmups = 1;
const _defaultIterations = 10;

Future<void> main(List<String> args) async {
  final options = _ScenarioOptions.parse(args);
  final scenarios = <_ScenarioBenchmark>[const _ProofAppJourneyScenario()];

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
  if (options.printJson) stdout.writeln(jsonText);
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
    var size = const CellSize(100, 28);

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
    final idFilter = _scenarioIdFilter(query);
    if (idFilter != null) return scenario.id.toLowerCase() == idFilter;
    return scenario.id.toLowerCase().contains(query) ||
        scenario.name.toLowerCase().contains(query);
  }
}

String? _scenarioIdFilter(String query) {
  if (!query.startsWith('sb')) return null;
  final digits = query.substring(2).replaceAll(RegExp('[^0-9]'), '');
  return digits.isEmpty ? null : 'sb.$digits';
}

final class _ScenarioConfig {
  const _ScenarioConfig({
    required this.warmupIterations,
    required this.measuredIterations,
    required this.seed,
    required this.terminalSize,
  });

  final int warmupIterations;
  final int measuredIterations;
  final int seed;
  final CellSize terminalSize;
}

abstract interface class _ScenarioBenchmark {
  String get id;
  String get name;
  Future<_ScenarioResult> run(_ScenarioConfig config);
}

final class _ProofAppJourneyScenario implements _ScenarioBenchmark {
  const _ProofAppJourneyScenario();

  @override
  String get id => 'SB.10';

  @override
  String get name => 'Proof-App Journey';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runProofAppJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_ProofAppJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runProofAppJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final palette = _Stats.from(
      samples.map((sample) => sample.commandPaletteUs),
    );
    final globalSearch = _Stats.from(
      samples.map((sample) => sample.globalSearchUs),
    );
    final indexedLogs = _Stats.from(
      samples.map((sample) => sample.indexedLogsUs),
    );
    final runsFilter = _Stats.from(
      samples.map((sample) => sample.runsFilterUs),
    );
    final runsCopy = _Stats.from(samples.map((sample) => sample.runsCopyUs));
    final transcript = _Stats.from(
      samples.map((sample) => sample.transcriptUs),
    );
    final process = _Stats.from(
      samples.map((sample) => sample.processRunToSuccessUs),
    );
    final diagnostics = _Stats.from(
      samples.map((sample) => sample.diagnosticsUs),
    );
    final debugCapture = _Stats.from(
      samples.map((sample) => sample.debugCaptureUs),
    );
    final semanticQuery = _Stats.from(
      samples.map((sample) => sample.semanticQueryUs),
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
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'commandPaletteUs': palette.toJson(),
        'globalSearchUs': globalSearch.toJson(),
        'indexedLogsUs': indexedLogs.toJson(),
        'runsFilterUs': runsFilter.toJson(),
        'runsCopyUs': runsCopy.toJson(),
        'transcriptUs': transcript.toJson(),
        'processRunToSuccessUs': process.toJson(),
        'diagnosticsUs': diagnostics.toJson(),
        'debugCaptureUs': debugCapture.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'firstFrameAnsiBytes': last.firstFrameAnsiBytes,
        'finalFrameAnsiBytes': last.finalFrameAnsiBytes,
        'semanticNodeCount': last.semanticNodeCount,
        'accessibilityNodeCount': last.accessibilityNodeCount,
        'accessibilityPlainTextBytes': last.accessibilityPlainTextBytes,
        'debugCaptureBytes': last.debugCaptureBytes,
        'commandCount': last.commandCount,
        'statusCount': last.statusCount,
        'finalActiveScreenId': last.finalActiveScreenId,
        'lastCommandId': last.lastCommandId,
        'runsFilteredCount': last.runsFilteredCount,
        'selectedRunKey': last.selectedRunKey,
        'globalSearchResultCount': last.globalSearchResultCount,
        'globalSearchSelectedKey': last.globalSearchSelectedKey,
        'indexedLogRowCount': last.indexedLogRowCount,
        'indexedLogFilterCount': last.indexedLogFilterCount,
        'indexedLogProgressCurrent': last.indexedLogProgressCurrent,
        'indexedLogSelectedKey': last.indexedLogSelectedKey,
        'transcriptRowCount': last.transcriptRowCount,
        'processOutputCount': last.processOutputCount,
        'diagnosticCapabilityRows': last.diagnosticCapabilityRows,
        'unsafeFrameCount': last.unsafeFrameCount,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateCommandPaletteP95Us': 16000,
        'candidateGlobalSearchP95Us': 100000,
        'candidateIndexedLogsP95Us': 100000,
        'candidateRunsFilterP95Us': 16000,
        'candidateRunsCopyP95Us': 16000,
        'candidateTranscriptP95Us': 33000,
        'candidateDiagnosticsP95Us': 16000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Scenario measures the integrated proof app, including app shell, command palette, debounced global search, cooperative indexed logs, DataTable, LogRegion, process task, diagnostics, semantics, accessibility, and debug capture.',
        'The native process step runs the current Dart executable with --version, so process timing includes OS spawn variance.',
      ],
    );
  }
}

Future<_ProofAppJourneySample> _runProofAppJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final originalClipboard = Clipboard.instance;
  final clipboard = TestClipboard();
  Clipboard.instance = clipboard;
  final total = Stopwatch()..start();
  var unsafeFrameCount = 0;

  try {
    final mount = Stopwatch()..start();
    tester.pumpWidget(const ProofConsoleApp());
    mount.stop();

    final firstRender = Stopwatch()..start();
    final firstFrame = tester.render(size: config.terminalSize);
    firstRender.stop();
    unsafeFrameCount += _unsafeVisibleFrameCount(
      firstFrame,
      config.terminalSize,
    );

    final palette = Stopwatch()..start();
    await _invoke(tester, proofCommandOpenPalette);
    tester.pump(const Duration(milliseconds: 300));
    var frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    final paletteTree = tester.semantics();
    final paletteNode = paletteTree.single(role: SemanticRole.commandPalette);
    tester.type('go diagnostics');
    tester.pump();
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump(const Duration(milliseconds: 300));
    tester.pump();
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    palette.stop();

    final diagnostics = Stopwatch()..start();
    await _invoke(tester, proofCommandCaptureDebug);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    final diagnosticsTree = tester.semantics();
    final diagnosticsNode = diagnosticsTree.single(
      role: SemanticRole.diagnostic,
      label: 'Terminal diagnostics',
    );
    diagnostics.stop();

    final globalSearch = Stopwatch()..start();
    await _invoke(tester, proofCommandGoSearch);
    await _invoke(tester, proofCommandFocusSearch);
    tester.type('API deploy smoke');
    final searchTask = await _waitForTaskStatus(
      tester,
      label: 'Global search',
      status: 'succeeded',
    );
    await _flushAsyncUi(tester);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    final searchTree = tester.semantics();
    final searchPanel = searchTree.single(
      role: SemanticRole.region,
      label: 'Global search',
    );
    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.listItem,
      label: 'API deploy smoke',
    );
    await _flushAsyncUi(tester);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    globalSearch.stop();

    final indexedLogs = Stopwatch()..start();
    await _invoke(tester, proofCommandGoIndex);
    await _invoke(tester, proofCommandBuildLogIndex);
    var indexTask = await _waitForTaskProgress(
      tester,
      label: 'Proof log index',
      current: proofIndexedLogInitialCount,
    );
    await _invoke(tester, proofCommandFocusIndexFilter);
    tester.type('target:payment');
    await _flushAsyncUi(tester);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    var indexedTree = tester.semantics();
    var indexedLog = indexedTree.single(
      role: SemanticRole.log,
      label: 'Indexed proof logs',
    );
    final indexedLogFilterCount = indexedLog.state.collectionRowCount ?? -1;
    final indexedLogSelectedKey =
        indexedLog.state.selectedKey?.toString() ?? '';
    await _invoke(tester, proofCommandAppendIndexedLogBurst);
    indexTask = await _waitForTaskProgress(
      tester,
      label: 'Proof log index',
      current: proofIndexedLogInitialCount + proofIndexedLogAppendCount,
    );
    await _flushAsyncUi(tester);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    indexedTree = tester.semantics();
    indexedLog = indexedTree.single(
      role: SemanticRole.log,
      label: 'Indexed proof logs',
    );
    indexedLogs.stop();

    final startTask = Stopwatch()..start();
    await _invoke(tester, proofCommandStartTask);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    startTask.stop();

    final runsFilter = Stopwatch()..start();
    await _invoke(tester, proofCommandGoRuns);
    await _invoke(tester, proofCommandFocusRunsFilter);
    tester.type('failed');
    tester.pump();
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    final runsTree = tester.semantics();
    final filteredTable = runsTree.single(role: SemanticRole.table);
    runsFilter.stop();

    final runsCopy = Stopwatch()..start();
    await _invoke(tester, proofCommandFocusRunsTable);
    tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await _flushAsyncUi(tester);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    final copiedRun = clipboard.lastWritten ?? '';
    runsCopy.stop();

    final transcript = Stopwatch()..start();
    await _invoke(tester, proofCommandGoTranscript);
    await _invoke(tester, proofCommandFocusComposer);
    tester.type('operator note ${config.seed}');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    await _flushAsyncUi(tester);
    await _invoke(tester, proofCommandAppendLogBurst);
    await _invoke(tester, proofCommandToggleStream);
    final disabledBurst = await _invoke(tester, proofCommandAppendLogBurst);
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    final transcriptTree = tester.semantics();
    final transcriptLog = transcriptTree.single(
      role: SemanticRole.log,
      label: 'Transcript events',
    );
    transcript.stop();

    final process = Stopwatch()..start();
    await _invoke(tester, proofCommandGoProcess);
    await _invoke(tester, proofCommandRunProcess);
    final processTask = await _waitForTaskStatus(
      tester,
      label: 'Dart version',
      status: 'succeeded',
    );
    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    process.stop();

    final debugCapture = Stopwatch()..start();
    await _invoke(tester, proofCommandGoDiagnostics);
    await _invoke(tester, proofCommandCaptureDebug);
    final semanticTree = tester.semantics();
    final app = semanticTree.single(
      role: SemanticRole.app,
      label: 'Fleury Proof Console',
    );
    final capture = DebugCaptureRecorder()
      ..record(const InputDebugEvent(kind: 'command', summary: 'SB.10'))
      ..recordOutputSummary(
        DebugOutputSummary(
          source: 'proof-app-journey',
          lineCount: transcriptLog.state.collectionRowCount ?? 0,
        ),
      );
    final snapshot = capture.snapshot(semanticTree: semanticTree).toJson();
    final debugCaptureBytes = utf8.encode(jsonEncode(snapshot)).length;
    debugCapture.stop();

    final semanticQuery = Stopwatch()..start();
    final accessibility = semanticTree.toAccessibilitySnapshot();
    semanticQuery.stop();

    frame = tester.render(size: config.terminalSize);
    unsafeFrameCount += _unsafeVisibleFrameCount(frame, config.terminalSize);
    total.stop();

    final accessibilityText = accessibility.toPlainText();
    final correct =
        paletteNode.state.collectionRowCount != null &&
        app.state.activeScreenId == 'diagnostics' &&
        app.state.lastCommandId == 'debug.captureSnapshot' &&
        app.state.lastCommandStatus == 'completed' &&
        app.state.commandCount != null &&
        (app.state.commandCount ?? 0) >= 15 &&
        (app.state.statusCount ?? 0) >= 5 &&
        diagnosticsNode.state['capabilityRowCount'] == 5 &&
        diagnosticsNode.state.clipboardPolicy == 'allowed' &&
        searchTask.state.taskStatus == 'succeeded' &&
        searchTask.state.progressLabel == '1 matches' &&
        searchPanel.state.collectionRowCount == 1 &&
        searchPanel.state.selectedKey == 'run.RUN-1002' &&
        indexTask.state.taskStatus == 'succeeded' &&
        indexTask.state.progressCurrent ==
            proofIndexedLogInitialCount + proofIndexedLogAppendCount &&
        indexedLog.state['totalEntryCount'] ==
            proofIndexedLogInitialCount + proofIndexedLogAppendCount &&
        indexedLogFilterCount == 48 &&
        indexedLog.state.collectionRowCount == 49 &&
        indexedLogSelectedKey == 'IDX-1000' &&
        filteredTable.state.collectionRowCount == 1 &&
        filteredTable.state.filterText == 'failed' &&
        filteredTable.state.selectedKey == 'RUN-1002' &&
        copiedRun.contains('RUN-1002') &&
        copiedRun.contains('API deploy smoke') &&
        disabledBurst.status == CommandInvocationStatus.disabled &&
        transcriptLog.state.collectionRowCount != null &&
        (transcriptLog.state.collectionRowCount ?? 0) >= 6 &&
        processTask.state.taskStatus == 'succeeded' &&
        processTask.state.outputCount != null &&
        (processTask.state.outputCount ?? 0) > 0 &&
        debugCaptureBytes > 0 &&
        accessibilityText.contains('Fleury Proof Console') &&
        accessibilityText.contains('Diagnostics') &&
        unsafeFrameCount == 0;

    return _ProofAppJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      commandPaletteUs: palette.elapsedMicroseconds,
      globalSearchUs: globalSearch.elapsedMicroseconds,
      indexedLogsUs: indexedLogs.elapsedMicroseconds,
      diagnosticsUs: diagnostics.elapsedMicroseconds,
      startTaskUs: startTask.elapsedMicroseconds,
      runsFilterUs: runsFilter.elapsedMicroseconds,
      runsCopyUs: runsCopy.elapsedMicroseconds,
      transcriptUs: transcript.elapsedMicroseconds,
      processRunToSuccessUs: process.elapsedMicroseconds,
      debugCaptureUs: debugCapture.elapsedMicroseconds,
      semanticQueryUs: semanticQuery.elapsedMicroseconds,
      firstFrameAnsiBytes: _ansiBytes(firstFrame, config.terminalSize),
      finalFrameAnsiBytes: _ansiBytes(frame, config.terminalSize),
      semanticNodeCount: semanticTree.nodes.length,
      accessibilityNodeCount: accessibility.nodes.length,
      accessibilityPlainTextBytes: utf8.encode(accessibilityText).length,
      debugCaptureBytes: debugCaptureBytes,
      commandCount: app.state.commandCount ?? 0,
      statusCount: app.state.statusCount ?? 0,
      finalActiveScreenId: app.state.activeScreenId ?? '',
      lastCommandId: app.state.lastCommandId ?? '',
      runsFilteredCount: filteredTable.state.collectionRowCount ?? -1,
      selectedRunKey: filteredTable.state.selectedKey?.toString() ?? '',
      globalSearchResultCount: searchPanel.state.collectionRowCount ?? -1,
      globalSearchSelectedKey: searchPanel.state.selectedKey?.toString() ?? '',
      indexedLogRowCount: indexedLog.state['totalEntryCount'] as int? ?? -1,
      indexedLogFilterCount: indexedLog.state.collectionRowCount ?? -1,
      indexedLogProgressCurrent: (indexTask.state.progressCurrent ?? -1)
          .toInt(),
      indexedLogSelectedKey: indexedLogSelectedKey,
      transcriptRowCount: transcriptLog.state.collectionRowCount ?? -1,
      processOutputCount: processTask.state.outputCount ?? -1,
      diagnosticCapabilityRows:
          diagnosticsNode.state['capabilityRowCount'] as int? ?? -1,
      unsafeFrameCount: unsafeFrameCount,
      correct: correct,
    );
  } finally {
    Clipboard.instance = originalClipboard;
    tester.dispose();
  }
}

Future<CommandInvocationResult> _invoke(
  FleuryTester tester,
  CommandId command,
) async {
  final result = await tester.invokeCommand(command);
  await _flushAsyncUi(tester);
  return result;
}

Future<void> _flushAsyncUi(FleuryTester tester) async {
  tester.pump();
  await Future<void>.delayed(Duration.zero);
  tester.pump();
}

Future<SemanticNode> _waitForTaskStatus(
  FleuryTester tester, {
  required String label,
  required String status,
}) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    tester.pump();
    final matches = tester.semantics().where(
      role: SemanticRole.task,
      label: label,
    );
    for (final node in matches) {
      if (node.state.taskStatus == status) return node;
    }
  }
  throw StateError('Timed out waiting for task `$label` to reach `$status`.');
}

Future<SemanticNode> _waitForTaskProgress(
  FleuryTester tester, {
  required String label,
  required num current,
}) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    tester.pump();
    final matches = tester.semantics().where(
      role: SemanticRole.task,
      label: label,
    );
    for (final node in matches) {
      if (node.state.progressCurrent == current) return node;
    }
  }
  final states = tester
      .semantics()
      .where(role: SemanticRole.task, label: label)
      .map((node) => node.state.values)
      .toList();
  throw StateError(
    'Timed out waiting for task `$label` to report progress `$current`: '
    '$states',
  );
}

int _unsafeVisibleFrameCount(CellBuffer buffer, CellSize size) {
  final visible = _visibleText(buffer, size);
  return visible.contains('secret') || visible.contains('\x1b') ? 1 : 0;
}

String _visibleText(CellBuffer buffer, CellSize size) {
  final lines = <String>[];
  for (var row = 0; row < size.rows; row++) {
    final line = StringBuffer();
    for (var col = 0; col < size.cols; col++) {
      final cell = buffer.atColRow(col, row);
      line.write(cell.role == CellRole.leading ? cell.grapheme ?? ' ' : ' ');
    }
    lines.add(line.toString());
  }
  return lines.join('\n');
}

int _ansiBytes(CellBuffer buffer, CellSize size) {
  final sink = _CountingAnsiSink();
  const AnsiRenderer().renderDiff(CellBuffer(size), buffer, sink);
  return sink.bytes;
}

final class _ProofAppJourneySample {
  const _ProofAppJourneySample({
    required this.totalJourneyUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.commandPaletteUs,
    required this.globalSearchUs,
    required this.indexedLogsUs,
    required this.diagnosticsUs,
    required this.startTaskUs,
    required this.runsFilterUs,
    required this.runsCopyUs,
    required this.transcriptUs,
    required this.processRunToSuccessUs,
    required this.debugCaptureUs,
    required this.semanticQueryUs,
    required this.firstFrameAnsiBytes,
    required this.finalFrameAnsiBytes,
    required this.semanticNodeCount,
    required this.accessibilityNodeCount,
    required this.accessibilityPlainTextBytes,
    required this.debugCaptureBytes,
    required this.commandCount,
    required this.statusCount,
    required this.finalActiveScreenId,
    required this.lastCommandId,
    required this.runsFilteredCount,
    required this.selectedRunKey,
    required this.globalSearchResultCount,
    required this.globalSearchSelectedKey,
    required this.indexedLogRowCount,
    required this.indexedLogFilterCount,
    required this.indexedLogProgressCurrent,
    required this.indexedLogSelectedKey,
    required this.transcriptRowCount,
    required this.processOutputCount,
    required this.diagnosticCapabilityRows,
    required this.unsafeFrameCount,
    required this.correct,
  });

  final int totalJourneyUs;
  final int mountUs;
  final int firstRenderUs;
  final int commandPaletteUs;
  final int globalSearchUs;
  final int indexedLogsUs;
  final int diagnosticsUs;
  final int startTaskUs;
  final int runsFilterUs;
  final int runsCopyUs;
  final int transcriptUs;
  final int processRunToSuccessUs;
  final int debugCaptureUs;
  final int semanticQueryUs;
  final int firstFrameAnsiBytes;
  final int finalFrameAnsiBytes;
  final int semanticNodeCount;
  final int accessibilityNodeCount;
  final int accessibilityPlainTextBytes;
  final int debugCaptureBytes;
  final int commandCount;
  final int statusCount;
  final String finalActiveScreenId;
  final String lastCommandId;
  final int runsFilteredCount;
  final String selectedRunKey;
  final int globalSearchResultCount;
  final String globalSearchSelectedKey;
  final int indexedLogRowCount;
  final int indexedLogFilterCount;
  final int indexedLogProgressCurrent;
  final String indexedLogSelectedKey;
  final int transcriptRowCount;
  final int processOutputCount;
  final int diagnosticCapabilityRows;
  final int unsafeFrameCount;
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
    final primary = metrics['journeyUs'];
    final p95 = primary is Map<String, Object?> ? primary['p95'] : null;
    final status = pass ? 'pass' : 'fail';
    return '$scenarioId $scenarioName: $status, journey_p95_us=$p95';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _schemaVersion,
    'scenarioId': scenarioId,
    'scenarioName': scenarioName,
    'packageVersion': _packageVersion,
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
    stderr.writeln('--size expects COLUMNSxROWS, for example 100x28.');
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
  stdout.writeln('  --size=COLSxROWS       Terminal size. Default 100x28.');
  exit(exitCodeValue);
}
