// Scenario benchmarks for app-shaped fleury_widgets workloads.
//
// This runner lives in fleury_widgets because core fleury cannot depend on the
// higher-level widget package without creating the wrong dependency direction.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

const _schemaVersion = 1;
const _fleuryWidgetsVersion = '0.0.0';
const _defaultWarmups = 2;
const _defaultIterations = 20;
const _defaultRows = 100000;
const _indexYieldPolicy = TaskYieldPolicy(itemBudget: 8192);

Future<void> main(List<String> args) async {
  final options = _ScenarioOptions.parse(args);
  final scenarios = <_ScenarioBenchmark>[
    const _DataTable100kScenario(),
    const _LogRegionTailingScenario(),
    const _StreamingMarkdownScenario(),
    const _DashboardUpdateScenario(),
    const _OverlayCommandPaletteScenario(),
    const _ResizeStormScenario(),
    const _SubprocessOutputScenario(),
    const _TreeTableHierarchyScenario(),
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
    var size = const CellSize(120, 32);
    var rows = _defaultRows;
    var resizeEvents = 500;

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
      } else if (arg.startsWith('--rows=')) {
        rows = _positiveInt(arg, '--rows=');
      } else if (arg.startsWith('--resize-events=')) {
        resizeEvents = _positiveInt(arg, '--resize-events=');
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
        rowCount: rows,
        resizeEvents: resizeEvents,
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
    required this.rowCount,
    required this.resizeEvents,
  });

  final int warmupIterations;
  final int measuredIterations;
  final int seed;
  final CellSize terminalSize;
  final int rowCount;
  final int resizeEvents;
}

abstract interface class _ScenarioBenchmark {
  String get id;
  String get name;
  Future<_ScenarioResult> run(_ScenarioConfig config);
}

final class _DataTable100kScenario implements _ScenarioBenchmark {
  const _DataTable100kScenario();

  @override
  String get id => 'SB.3';

  @override
  String get name => 'DataTable 100k Rows';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runDataTableJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_DataTableJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runDataTableJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final arrowMove = _Stats.from(samples.map((sample) => sample.arrowMoveUs));
    final pageMove = _Stats.from(samples.map((sample) => sample.pageMoveUs));
    final jumpToEnd = _Stats.from(samples.map((sample) => sample.jumpToEndUs));
    final copySelectedRow = _Stats.from(
      samples.map((sample) => sample.copySelectedRowUs),
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'arrowMoveUs': arrowMove.toJson(),
        'pageMoveUs': pageMove.toJson(),
        'jumpToEndUs': jumpToEnd.toJson(),
        'copySelectedRowUs': copySelectedRow.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'initialAnsiBytes': last.initialAnsiBytes,
        'finalAnsiBytes': last.finalAnsiBytes,
        'semanticNodeCount': last.semanticNodeCount,
        'visibleRangeStart': last.visibleRangeStart,
        'visibleRangeEnd': last.visibleRangeEnd,
        'selectedKey': last.selectedKey,
        'cellBuilderCalls': last.cellBuilderCalls,
        'uniqueRowsRequested': last.uniqueRowsRequested,
        'maxRequestedRow': last.maxRequestedRow,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateArrowMoveP95Us': 16000,
        'candidatePageMoveP95Us': 16000,
        'candidateCopySelectedRowP95Us': 16000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Run mode is FleuryTester harness execution, not a full terminal process.',
        'Sort/filter helper behavior is covered by widget tests; this scenario keeps the virtualization hot path isolated.',
      ],
    );
  }
}

Future<_DataTableJourneySample> _runDataTableJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final originalClipboard = Clipboard.instance;
  final clipboard = TestClipboard();
  Clipboard.instance = clipboard;
  final requestedRows = <int>{};
  var cellBuilderCalls = 0;
  final total = Stopwatch()..start();
  try {
    final fixture = _RunFixture(seed: config.seed);
    final controller = DataTableController();

    final mount = Stopwatch()..start();
    tester.pumpWidget(
      DataTable(
        rowCount: config.rowCount,
        columns: _columns,
        controller: controller,
        autofocus: true,
        rowKeyBuilder: fixture.rowKey,
        sortColumnId: 'status',
        sortDirection: DataTableSortDirection.ascending,
        filterText: 'status:failed',
        cellBuilder: (row, columnId) {
          cellBuilderCalls += 1;
          requestedRows.add(row);
          return fixture.cell(row, columnId);
        },
      ),
    );
    mount.stop();

    final firstRender = Stopwatch()..start();
    final initial = tester.render(size: config.terminalSize);
    firstRender.stop();

    final arrow = Stopwatch()..start();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.render(size: config.terminalSize);
    arrow.stop();

    final page = Stopwatch()..start();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.pageDown));
    tester.render(size: config.terminalSize);
    page.stop();

    final jump = Stopwatch()..start();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
    final finalFrame = tester.render(size: config.terminalSize);
    jump.stop();

    final copy = Stopwatch()..start();
    tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await Future<void>.delayed(Duration.zero);
    copy.stop();

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final table = tree.single(role: SemanticRole.table);
    semantics.stop();
    total.stop();

    final selectedKey = table.state.selectedKey;
    final expectedKey = fixture.rowKey(config.rowCount - 1);
    final visibleStart = table.state.visibleRangeStart ?? -1;
    final visibleEnd = table.state.visibleRangeEnd ?? -1;
    final maxExpectedUniqueRows = (config.terminalSize.rows * 4).clamp(8, 512);
    final copiedText = clipboard.lastWritten ?? '';
    final correct =
        table.state.collectionRowCount == config.rowCount &&
        table.state.collectionColumnCount == _columns.length &&
        table.state.values['virtualized'] == true &&
        table.actions.contains(SemanticAction.copy) &&
        table.state.sortColumn == 'status' &&
        table.state.sortDirection == 'ascending' &&
        table.state.filterText == 'status:failed' &&
        selectedKey == expectedKey &&
        visibleStart <= config.rowCount - 1 &&
        visibleEnd == config.rowCount - 1 &&
        copiedText.startsWith('ID\tStatus\tTitle') &&
        copiedText.contains(expectedKey.toString()) &&
        requestedRows.length <= maxExpectedUniqueRows;

    return _DataTableJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      arrowMoveUs: arrow.elapsedMicroseconds,
      pageMoveUs: page.elapsedMicroseconds,
      jumpToEndUs: jump.elapsedMicroseconds,
      copySelectedRowUs: copy.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      initialAnsiBytes: _ansiBytes(initial, config.terminalSize),
      finalAnsiBytes: _ansiBytes(finalFrame, config.terminalSize),
      semanticNodeCount: tree.nodes.length,
      visibleRangeStart: visibleStart,
      visibleRangeEnd: visibleEnd,
      selectedKey: selectedKey?.toString() ?? '',
      cellBuilderCalls: cellBuilderCalls,
      uniqueRowsRequested: requestedRows.length,
      maxRequestedRow: requestedRows.isEmpty ? -1 : requestedRows.reduce(_max),
      correct: correct,
    );
  } finally {
    Clipboard.instance = originalClipboard;
    tester.dispose();
  }
}

const _columns = [
  DataTableColumn(id: 'id', title: 'ID', width: FixedColumnWidth(12)),
  DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(8)),
  DataTableColumn(id: 'title', title: 'Title', width: FlexColumnWidth(3)),
  DataTableColumn(id: 'owner', title: 'Owner', width: FixedColumnWidth(10)),
  DataTableColumn(
    id: 'duration',
    title: 'Duration',
    width: FixedColumnWidth(8),
  ),
  DataTableColumn(
    id: 'progress',
    title: 'Progress',
    width: FixedColumnWidth(8),
  ),
  DataTableColumn(id: 'warnings', title: 'Warn', width: FixedColumnWidth(5)),
  DataTableColumn(id: 'updated', title: 'Updated', width: FixedColumnWidth(10)),
];

final class _RunFixture {
  const _RunFixture({required this.seed});

  final int seed;

  Object rowKey(int row) => 'RUN-${100000 + row}';

  String cell(int row, String columnId) {
    return switch (columnId) {
      'id' => rowKey(row).toString(),
      'status' => _statuses[(row + seed) % _statuses.length],
      'title' => _title(row),
      'owner' => _owners[(row + seed * 3) % _owners.length],
      'duration' =>
        '${(row % 3).toString().padLeft(2, '0')}:'
            '${(row % 60).toString().padLeft(2, '0')}',
      'progress' => '${(row * 7 + seed) % 101}%',
      'warnings' => '${(row + seed) % 6}',
      'updated' => 'T-${(row % 1440).toString().padLeft(4, '0')}',
      _ => '',
    };
  }

  String _title(int row) {
    final shard = (row + seed) % 2048;
    final lane = _lanes[(row ~/ 17 + seed) % _lanes.length];
    return 'Build shard $shard $lane';
  }
}

const _statuses = ['queued', 'running', 'passed', 'failed', 'blocked'];
const _owners = ['agent', 'ops', 'qa', 'infra', 'cli'];
const _lanes = ['core', 'widgets', 'unicode', 'deploy', '日本語'];

int _ansiBytes(CellBuffer buffer, CellSize size) {
  final sink = _CountingAnsiSink();
  const AnsiRenderer().renderDiff(CellBuffer(size), buffer, sink);
  return sink.bytes;
}

_MeasuredRender _renderMeasured(FleuryTester tester, CellSize size) {
  RenderLayoutDebugStats.beginFrame(enabled: true);
  try {
    final buffer = tester.render(size: size);
    final stats = RenderLayoutDebugStats.takeFrameStats();
    return _MeasuredRender(buffer: buffer, layoutStats: stats);
  } catch (_) {
    RenderLayoutDebugStats.takeFrameStats();
    rethrow;
  }
}

Map<String, Object?> _layoutStatsToJson(RenderLayoutFrameStats stats) {
  return <String, Object?>{
    'performedCount': stats.performedCount,
    'skippedCount': stats.skippedCount,
    'totalCount': stats.totalCount,
    'skippedRatio': stats.skippedRatio,
  };
}

int _max(int a, int b) => a > b ? a : b;

final class _MeasuredRender {
  const _MeasuredRender({required this.buffer, required this.layoutStats});

  final CellBuffer buffer;
  final RenderLayoutFrameStats layoutStats;
}

final class _DataTableJourneySample {
  const _DataTableJourneySample({
    required this.totalJourneyUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.arrowMoveUs,
    required this.pageMoveUs,
    required this.jumpToEndUs,
    required this.copySelectedRowUs,
    required this.semanticQueryUs,
    required this.initialAnsiBytes,
    required this.finalAnsiBytes,
    required this.semanticNodeCount,
    required this.visibleRangeStart,
    required this.visibleRangeEnd,
    required this.selectedKey,
    required this.cellBuilderCalls,
    required this.uniqueRowsRequested,
    required this.maxRequestedRow,
    required this.correct,
  });

  final int totalJourneyUs;
  final int mountUs;
  final int firstRenderUs;
  final int arrowMoveUs;
  final int pageMoveUs;
  final int jumpToEndUs;
  final int copySelectedRowUs;
  final int semanticQueryUs;
  final int initialAnsiBytes;
  final int finalAnsiBytes;
  final int semanticNodeCount;
  final int visibleRangeStart;
  final int visibleRangeEnd;
  final String selectedKey;
  final int cellBuilderCalls;
  final int uniqueRowsRequested;
  final int maxRequestedRow;
  final bool correct;
}

final class _LogRegionTailingScenario implements _ScenarioBenchmark {
  const _LogRegionTailingScenario();

  @override
  String get id => 'SB.4';

  @override
  String get name => 'LogRegion Tailing And Scrollback';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runLogRegionJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_LogRegionJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runLogRegionJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final fixtureBuild = _Stats.from(
      samples.map((sample) => sample.fixtureBuildUs),
    );
    final searchIndexBuild = _Stats.from(
      samples.map((sample) => sample.searchIndexBuildUs),
    );
    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final appendBurst = _Stats.from(
      samples.map((sample) => sample.appendBurstUs),
    );
    final scrollbackJump = _Stats.from(
      samples.map((sample) => sample.scrollbackJumpUs),
    );
    final scrollToTail = _Stats.from(
      samples.map((sample) => sample.scrollToTailUs),
    );
    final copySelectedEntry = _Stats.from(
      samples.map((sample) => sample.copySelectedEntryUs),
    );
    final filterQuery = _Stats.from(
      samples.map((sample) => sample.filterQueryUs),
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'fixtureBuildUs': fixtureBuild.toJson(),
        'searchIndexBuildUs': searchIndexBuild.toJson(),
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'appendBurstUs': appendBurst.toJson(),
        'scrollbackJumpUs': scrollbackJump.toJson(),
        'scrollToTailUs': scrollToTail.toJson(),
        'copySelectedEntryUs': copySelectedEntry.toJson(),
        'filterQueryUs': filterQuery.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'initialAnsiBytes': last.initialAnsiBytes,
        'appendAnsiBytes': last.appendAnsiBytes,
        'finalAnsiBytes': last.finalAnsiBytes,
        'filteredAnsiBytes': last.filteredAnsiBytes,
        'semanticNodeCount': last.semanticNodeCount,
        'visibleRangeStart': last.visibleRangeStart,
        'visibleRangeEnd': last.visibleRangeEnd,
        'scrollbackVisibleRangeStart': last.scrollbackVisibleRangeStart,
        'filterMatchCount': last.filterMatchCount,
        'filterVisibleRangeStart': last.filterVisibleRangeStart,
        'filterVisibleRangeEnd': last.filterVisibleRangeEnd,
        'selectedKey': last.selectedKey,
        'entryCountAfterAppend': last.entryCountAfterAppend,
        'appendCount': last.appendCount,
        'sanitizingFixtureRows': last.sanitizingFixtureRows,
        'copiedByteCount': last.copiedByteCount,
        'searchIndexTaskEventCount': last.searchIndexTaskEventCount,
        'searchIndexProgressCurrent': last.searchIndexProgressCurrent,
        'appendIndexTaskEventCount': last.appendIndexTaskEventCount,
        'appendIndexProgressCurrent': last.appendIndexProgressCurrent,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateAppendBurstP95Us': 33000,
        'candidateScrollbackJumpP95Us': 16000,
        'candidateCopySelectedEntryP95Us': 16000,
        'candidateFilterQueryP95Us': 80000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'This is a LogRegion widget scenario, not a full subprocess stream.',
        'Fixture includes ANSI/OSC/newline payloads to verify sanitized visible and copied output.',
        'Search-index build and append refresh run cooperatively through TaskController.',
      ],
    );
  }
}

Future<_LogRegionJourneySample> _runLogRegionJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final originalClipboard = Clipboard.instance;
  final clipboard = TestClipboard();
  Clipboard.instance = clipboard;
  final total = Stopwatch()..start();
  try {
    final fixture = _LogFixture(seed: config.seed);
    final fixtureBuild = Stopwatch()..start();
    final entries = List<LogEntry>.generate(
      config.rowCount,
      fixture.entry,
      growable: true,
    );
    fixtureBuild.stop();

    final searchIndexTask = TaskController<LogRegionSearchIndex>(
      id: 'sb4-log-index',
      label: 'SB.4 log index',
    );
    final searchIndexBuild = Stopwatch()..start();
    final searchIndexResult = await searchIndexTask.start(
      (context) => LogRegionSearchIndex.buildCooperatively(
        entries,
        context: context,
        yieldPolicy: _indexYieldPolicy,
        progressLabel: 'index logs',
      ),
    );
    searchIndexBuild.stop();
    final searchIndex = searchIndexResult.value;
    if (searchIndex == null) {
      throw StateError('SB.4 log index build did not produce an index.');
    }

    final controller = LogRegionController();
    final mount = Stopwatch()..start();
    tester.pumpWidget(
      _LogRegionHarness(
        entries: entries,
        controller: controller,
        searchIndex: searchIndex,
      ),
    );
    mount.stop();

    final firstRender = Stopwatch()..start();
    final initial = tester.render(size: config.terminalSize);
    firstRender.stop();

    final appendCount = _appendCountFor(config.rowCount);
    final append = Stopwatch()..start();
    final appendStart = entries.length;
    for (var i = 0; i < appendCount; i++) {
      entries.add(
        fixture.entry(appendStart + i, forceUnsafe: i == appendCount - 1),
      );
    }
    final appendIndexTask = TaskController<LogRegionSearchIndex>(
      id: 'sb4-log-index-refresh',
      label: 'SB.4 log index refresh',
    );
    final appendIndexResult = await appendIndexTask.start((context) async {
      await searchIndex.refreshCooperatively(
        context: context,
        yieldPolicy: _indexYieldPolicy,
        progressLabel: 'refresh logs',
      );
      return searchIndex;
    });
    tester.pumpWidget(
      _LogRegionHarness(
        entries: entries,
        controller: controller,
        searchIndex: searchIndex,
      ),
    );
    final appended = tester.render(size: config.terminalSize);
    append.stop();

    final scrollbackTarget = config.rowCount ~/ 2;
    final scrollback = Stopwatch()..start();
    controller.jumpToIndex(scrollbackTarget);
    tester.pump();
    tester.render(size: config.terminalSize);
    scrollback.stop();
    final scrollbackVisibleStart = controller.visibleRange?.first ?? -1;

    final tail = Stopwatch()..start();
    controller.scrollToBottom();
    tester.pump();
    final finalFrame = tester.render(size: config.terminalSize);
    tail.stop();

    final copy = Stopwatch()..start();
    tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await Future<void>.delayed(Duration.zero);
    copy.stop();

    final filterController = LogRegionController();
    final filterQuery = fixture.filterQueryFor(appendStart);
    final filter = Stopwatch()..start();
    tester.pumpWidget(
      _LogRegionHarness(
        entries: entries,
        controller: filterController,
        searchIndex: searchIndex,
        filter: LogRegionFilterDescriptor(query: filterQuery),
      ),
    );
    final filteredFrame = tester.render(size: config.terminalSize);
    filter.stop();
    final filterVisibleRange = filterController.visibleRange;

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final log = tree.single(role: SemanticRole.log);
    final selected = tree.single(
      role: SemanticRole.listItem,
      selected: true,
      action: SemanticAction.copy,
    );
    semantics.stop();
    total.stop();

    final expectedLastKey = fixture.key(entries.length - 1);
    final copiedText = clipboard.lastWritten ?? '';
    final finalVisibleRange = controller.visibleRange;
    final visibleStart = finalVisibleRange?.first ?? -1;
    final visibleEnd = finalVisibleRange?.last ?? -1;
    final filterVisibleStart = filterVisibleRange?.first ?? -1;
    final filterVisibleEnd = filterVisibleRange?.last ?? -1;
    final initialText = _visibleText(initial, config.terminalSize);
    final appendedText = _visibleText(appended, config.terminalSize);
    final finalText = _visibleText(finalFrame, config.terminalSize);
    final filteredText = _visibleText(filteredFrame, config.terminalSize);
    final correct =
        log.state.collectionRowCount == appendCount &&
        log.state.filterText == filterQuery &&
        log.actions.contains(SemanticAction.copy) &&
        log.state['filterActive'] == true &&
        controller.selectedIndex == entries.length - 1 &&
        visibleEnd == entries.length - 1 &&
        visibleStart <= visibleEnd &&
        scrollbackVisibleStart <= scrollbackTarget &&
        scrollbackVisibleStart >= 0 &&
        selected.state['rowKey'] == expectedLastKey &&
        copiedText.contains(expectedLastKey) &&
        !copiedText.contains('secret') &&
        !copiedText.contains('\x1b') &&
        initialText.contains(fixture.key(config.rowCount - 1)) &&
        appendedText.contains(expectedLastKey) &&
        finalText.contains(expectedLastKey) &&
        filteredText.contains(expectedLastKey);
    final indexBuildSucceeded =
        searchIndexTask.status == TaskStatus.succeeded &&
        searchIndexTask.progress?.current == config.rowCount;
    final appendIndexSucceeded =
        appendIndexTask.status == TaskStatus.succeeded &&
        appendIndexResult.succeeded &&
        appendIndexTask.progress?.current == entries.length;

    final sample = _LogRegionJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      fixtureBuildUs: fixtureBuild.elapsedMicroseconds,
      searchIndexBuildUs: searchIndexBuild.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      appendBurstUs: append.elapsedMicroseconds,
      scrollbackJumpUs: scrollback.elapsedMicroseconds,
      scrollToTailUs: tail.elapsedMicroseconds,
      copySelectedEntryUs: copy.elapsedMicroseconds,
      filterQueryUs: filter.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      initialAnsiBytes: _ansiBytes(initial, config.terminalSize),
      appendAnsiBytes: _ansiBytes(appended, config.terminalSize),
      finalAnsiBytes: _ansiBytes(finalFrame, config.terminalSize),
      filteredAnsiBytes: _ansiBytes(filteredFrame, config.terminalSize),
      semanticNodeCount: tree.nodes.length,
      visibleRangeStart: visibleStart,
      visibleRangeEnd: visibleEnd,
      scrollbackVisibleRangeStart: scrollbackVisibleStart,
      filterMatchCount: log.state.collectionRowCount ?? -1,
      filterVisibleRangeStart: filterVisibleStart,
      filterVisibleRangeEnd: filterVisibleEnd,
      selectedKey: expectedLastKey,
      entryCountAfterAppend: entries.length,
      appendCount: appendCount,
      sanitizingFixtureRows: fixture.sanitizingRowCount(entries.length),
      copiedByteCount: utf8.encode(copiedText).length,
      searchIndexTaskEventCount: searchIndexTask.events.length,
      searchIndexProgressCurrent: (searchIndexTask.progress?.current ?? -1)
          .toInt(),
      appendIndexTaskEventCount: appendIndexTask.events.length,
      appendIndexProgressCurrent: (appendIndexTask.progress?.current ?? -1)
          .toInt(),
      correct: correct && indexBuildSucceeded && appendIndexSucceeded,
    );
    searchIndexTask.dispose();
    appendIndexTask.dispose();
    return sample;
  } finally {
    Clipboard.instance = originalClipboard;
    tester.dispose();
  }
}

final class _LogRegionHarness extends StatelessWidget {
  const _LogRegionHarness({
    required this.entries,
    required this.controller,
    required this.searchIndex,
    this.filter,
  });

  final List<LogEntry> entries;
  final LogRegionController controller;
  final LogRegionSearchIndex searchIndex;
  final LogRegionFilterDescriptor? filter;

  @override
  Widget build(BuildContext context) {
    return LogRegion(
      entries: entries,
      controller: controller,
      filter: filter,
      searchIndex: searchIndex,
      autofocus: true,
      label: 'Scenario logs',
      copyOptions: const LogRegionCopyOptions(
        clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
      ),
    );
  }
}

final class _LogFixture {
  const _LogFixture({required this.seed});

  final int seed;

  String key(int row) => 'LOG-${100000 + row}';

  String filterQueryFor(int row) {
    final keyText = key(row);
    final dash = keyText.indexOf('-');
    var prefixEnd = dash < 0 ? keyText.length : dash + 4;
    if (prefixEnd < 0) prefixEnd = 0;
    if (prefixEnd > keyText.length) prefixEnd = keyText.length;
    return keyText.substring(0, prefixEnd);
  }

  LogEntry entry(int row, {bool forceUnsafe = false}) {
    final severity = _logSeverities[(row + seed) % _logSeverities.length];
    final source = _logSources[(row ~/ 7 + seed) % _logSources.length];
    final unsafe = forceUnsafe || _isSanitizingRow(row);
    final id = key(row);
    final suffix = unsafe
        ? ' unsafe\x1b]52;c;secret-$row\x07 payload\ncontinued'
        : ' ${_logMessages[(row + seed * 5) % _logMessages.length]}';
    return LogEntry(
      id: id,
      severity: severity,
      source: source,
      message: '$id event=$row$suffix',
      metadata: {'fixtureRow': row, 'unsafeFixture': unsafe},
    );
  }

  int sanitizingRowCount(int entryCount) {
    var count = 0;
    for (var row = 0; row < entryCount; row++) {
      if (_isSanitizingRow(row)) count += 1;
    }
    return count;
  }

  bool _isSanitizingRow(int row) => row % 97 == 0 || row % 389 == 0;
}

const _logSeverities = [
  LogSeverity.trace,
  LogSeverity.debug,
  LogSeverity.info,
  LogSeverity.warning,
  LogSeverity.error,
  LogSeverity.success,
];
const _logSources = ['worker', 'stdout', 'stderr', 'agent', 'build', 'deploy'];
const _logMessages = [
  'indexed workspace shard',
  'received incremental update',
  'rendered semantic snapshot',
  'processed queue item',
  'validated capability fallback',
  'wrote bounded transcript row',
  'kept 日本語 width stable',
];

int _appendCountFor(int rowCount) {
  final scaled = rowCount ~/ 100;
  if (scaled < 128) return 128;
  if (scaled > 1024) return 1024;
  return scaled;
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

final class _LogRegionJourneySample {
  const _LogRegionJourneySample({
    required this.totalJourneyUs,
    required this.fixtureBuildUs,
    required this.searchIndexBuildUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.appendBurstUs,
    required this.scrollbackJumpUs,
    required this.scrollToTailUs,
    required this.copySelectedEntryUs,
    required this.filterQueryUs,
    required this.semanticQueryUs,
    required this.initialAnsiBytes,
    required this.appendAnsiBytes,
    required this.finalAnsiBytes,
    required this.filteredAnsiBytes,
    required this.semanticNodeCount,
    required this.visibleRangeStart,
    required this.visibleRangeEnd,
    required this.scrollbackVisibleRangeStart,
    required this.filterMatchCount,
    required this.filterVisibleRangeStart,
    required this.filterVisibleRangeEnd,
    required this.selectedKey,
    required this.entryCountAfterAppend,
    required this.appendCount,
    required this.sanitizingFixtureRows,
    required this.copiedByteCount,
    required this.searchIndexTaskEventCount,
    required this.searchIndexProgressCurrent,
    required this.appendIndexTaskEventCount,
    required this.appendIndexProgressCurrent,
    required this.correct,
  });

  final int totalJourneyUs;
  final int fixtureBuildUs;
  final int searchIndexBuildUs;
  final int mountUs;
  final int firstRenderUs;
  final int appendBurstUs;
  final int scrollbackJumpUs;
  final int scrollToTailUs;
  final int copySelectedEntryUs;
  final int filterQueryUs;
  final int semanticQueryUs;
  final int initialAnsiBytes;
  final int appendAnsiBytes;
  final int finalAnsiBytes;
  final int filteredAnsiBytes;
  final int semanticNodeCount;
  final int visibleRangeStart;
  final int visibleRangeEnd;
  final int scrollbackVisibleRangeStart;
  final int filterMatchCount;
  final int filterVisibleRangeStart;
  final int filterVisibleRangeEnd;
  final String selectedKey;
  final int entryCountAfterAppend;
  final int appendCount;
  final int sanitizingFixtureRows;
  final int copiedByteCount;
  final int searchIndexTaskEventCount;
  final int searchIndexProgressCurrent;
  final int appendIndexTaskEventCount;
  final int appendIndexProgressCurrent;
  final bool correct;
}

final class _StreamingMarkdownScenario implements _ScenarioBenchmark {
  const _StreamingMarkdownScenario();

  @override
  String get id => 'SB.5';

  @override
  String get name => 'Streaming Markdown';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runStreamingMarkdownJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_StreamingMarkdownJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runStreamingMarkdownJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final parseChunk = _Stats.from(
      samples.expand((sample) => sample.chunkParseUs),
    );
    final frameChunk = _Stats.from(
      samples.expand((sample) => sample.chunkFrameUs),
    );
    final updateChunk = _Stats.from(
      samples.expand((sample) => sample.chunkUpdateUs),
    );
    final finalRender = _Stats.from(
      samples.map((sample) => sample.finalRenderUs),
    );
    final copySelectedBlock = _Stats.from(
      samples.map((sample) => sample.copySelectedBlockUs),
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'chunkParseUs': parseChunk.toJson(),
        'chunkFrameUs': frameChunk.toJson(),
        'chunkUpdateUs': updateChunk.toJson(),
        'finalRenderUs': finalRender.toJson(),
        'copySelectedBlockUs': copySelectedBlock.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'chunkCount': last.chunkCount,
        'sourceByteCount': last.sourceByteCount,
        'blockCount': last.blockCount,
        'headingCount': last.headingCount,
        'listItemCount': last.listItemCount,
        'linkCount': last.linkCount,
        'unsafeLinkCount': last.unsafeLinkCount,
        'codeBlockCount': last.codeBlockCount,
        'codeLineCount': last.codeLineCount,
        'semanticNodeCount': last.semanticNodeCount,
        'visibleRangeStart': last.visibleRangeStart,
        'visibleRangeEnd': last.visibleRangeEnd,
        'selectedBlockIndex': last.selectedBlockIndex,
        'selectedBlockKind': last.selectedBlockKind,
        'initialAnsiBytes': last.initialAnsiBytes,
        'maxChunkAnsiBytes': last.maxChunkAnsiBytes,
        'finalAnsiBytes': last.finalAnsiBytes,
        'unsafeFrameCount': last.unsafeFrameCount,
        'sanitizedBlockCount': last.sanitizedBlockCount,
        'truncatedBlockCount': last.truncatedBlockCount,
        'copiedByteCount': last.copiedByteCount,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateChunkUpdateP95Us': 33000,
        'candidateChunkFrameP95Us': 16000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Scenario appends markdown chunks and measures parse/update/frame cost separately.',
        'The first implementation intentionally measures full-document parse-on-append before committing to an incremental parser.',
        'Fixture includes unsafe OSC/link payloads to verify sanitized visible, copied, and semantic output.',
      ],
    );
  }
}

Future<_StreamingMarkdownJourneySample> _runStreamingMarkdownJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final originalClipboard = Clipboard.instance;
  final clipboard = TestClipboard();
  Clipboard.instance = clipboard;
  final chunkCount = _markdownChunkCountFor(config.rowCount);
  final fixture = _MarkdownFixture(seed: config.seed);
  final buffer = StringBuffer();
  final chunkParseUs = <int>[];
  final chunkFrameUs = <int>[];
  final chunkUpdateUs = <int>[];
  var maxChunkAnsiBytes = 0;
  var unsafeFrameCount = 0;
  var document = parseMarkdownDocument('');
  final controller = MarkdownViewController();
  final total = Stopwatch()..start();
  try {
    final mount = Stopwatch()..start();
    tester.pumpWidget(
      _MarkdownViewHarness(document: document, controller: controller),
    );
    mount.stop();

    final firstRender = Stopwatch()..start();
    final initial = tester.render(size: config.terminalSize);
    firstRender.stop();

    for (var i = 0; i < chunkCount; i++) {
      buffer.write(fixture.chunk(i));
      final update = Stopwatch()..start();
      final parse = Stopwatch()..start();
      document = parseMarkdownDocument(buffer.toString());
      parse.stop();

      final frameWatch = Stopwatch()..start();
      tester.pumpWidget(
        _MarkdownViewHarness(document: document, controller: controller),
      );
      final frame = tester.render(size: config.terminalSize);
      frameWatch.stop();
      update.stop();

      chunkParseUs.add(parse.elapsedMicroseconds);
      chunkFrameUs.add(frameWatch.elapsedMicroseconds);
      chunkUpdateUs.add(update.elapsedMicroseconds);

      final ansiBytes = _ansiBytes(frame, config.terminalSize);
      if (ansiBytes > maxChunkAnsiBytes) maxChunkAnsiBytes = ansiBytes;
      final visible = _visibleText(frame, config.terminalSize);
      if (_containsUnsafeTerminalPayload(visible)) unsafeFrameCount += 1;
    }

    final selectedIndex = document.blocks.isEmpty
        ? 0
        : document.blocks.length - 1;
    controller.selectedIndex = selectedIndex;
    controller.jumpToIndex(selectedIndex);
    tester.pump();
    final finalRender = Stopwatch()..start();
    final finalFrame = tester.render(size: config.terminalSize);
    finalRender.stop();

    final copy = Stopwatch()..start();
    tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await Future<void>.delayed(Duration.zero);
    copy.stop();

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final markdown = tree.single(
      role: SemanticRole.markdown,
      action: SemanticAction.copy,
    );
    final selected = tree.single(
      role: SemanticRole.markdownBlock,
      selected: true,
      action: SemanticAction.copy,
    );
    final links = tree.byRole(SemanticRole.link).toList(growable: false);
    semantics.stop();
    total.stop();

    final copiedText = clipboard.lastWritten ?? '';
    final finalVisible = _visibleText(finalFrame, config.terminalSize);
    final sanitizedBlockCount = document.blocks
        .where((block) => block.outputSanitized)
        .length;
    final truncatedBlockCount = document.blocks
        .where((block) => block.outputTruncated)
        .length;
    final unsafeLinkCount = links
        .where((link) => link.state['safeLinkScheme'] == false)
        .length;
    final visibleRange = controller.visibleRange;
    final visibleStart = visibleRange?.first ?? -1;
    final visibleEnd = visibleRange?.last ?? -1;
    final copiedSafe = !_containsUnsafeTerminalPayload(copiedText);
    final finalVisibleSafe = !_containsUnsafeTerminalPayload(finalVisible);
    final correct =
        markdown.state.collectionRowCount == document.blockCount &&
        markdown.state['blockCount'] == document.blockCount &&
        markdown.state['headingCount'] == document.headingCount &&
        markdown.state['listItemCount'] == document.listItemCount &&
        markdown.state['linkCount'] == document.linkCount &&
        markdown.state['codeBlockCount'] == document.codeBlockCount &&
        markdown.state['codeLineCount'] == document.codeLineCount &&
        markdown.state['selectedKey'] == selectedIndex &&
        selected.state['rowKey'] == selectedIndex &&
        document.headingCount > 0 &&
        document.listItemCount > 0 &&
        document.linkCount > 0 &&
        document.codeBlockCount > 0 &&
        sanitizedBlockCount > 0 &&
        unsafeLinkCount > 0 &&
        visibleStart >= 0 &&
        visibleEnd >= visibleStart &&
        unsafeFrameCount == 0 &&
        copiedSafe &&
        finalVisibleSafe;

    return _StreamingMarkdownJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      chunkParseUs: List<int>.unmodifiable(chunkParseUs),
      chunkFrameUs: List<int>.unmodifiable(chunkFrameUs),
      chunkUpdateUs: List<int>.unmodifiable(chunkUpdateUs),
      finalRenderUs: finalRender.elapsedMicroseconds,
      copySelectedBlockUs: copy.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      initialAnsiBytes: _ansiBytes(initial, config.terminalSize),
      maxChunkAnsiBytes: maxChunkAnsiBytes,
      finalAnsiBytes: _ansiBytes(finalFrame, config.terminalSize),
      chunkCount: chunkCount,
      sourceByteCount: utf8.encode(document.source).length,
      blockCount: document.blockCount,
      headingCount: document.headingCount,
      listItemCount: document.listItemCount,
      linkCount: document.linkCount,
      unsafeLinkCount: unsafeLinkCount,
      codeBlockCount: document.codeBlockCount,
      codeLineCount: document.codeLineCount,
      semanticNodeCount: tree.nodes.length,
      visibleRangeStart: visibleStart,
      visibleRangeEnd: visibleEnd,
      selectedBlockIndex: selectedIndex,
      selectedBlockKind: selected.state['markdownBlockKind'].toString(),
      unsafeFrameCount: unsafeFrameCount,
      sanitizedBlockCount: sanitizedBlockCount,
      truncatedBlockCount: truncatedBlockCount,
      copiedByteCount: utf8.encode(copiedText).length,
      correct: correct,
    );
  } finally {
    Clipboard.instance = originalClipboard;
    tester.dispose();
  }
}

final class _MarkdownViewHarness extends StatelessWidget {
  const _MarkdownViewHarness({
    required this.document,
    required this.controller,
  });

  final MarkdownDocument document;
  final MarkdownViewController controller;

  @override
  Widget build(BuildContext context) {
    return MarkdownView.document(
      document: document,
      controller: controller,
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

bool _containsUnsafeTerminalPayload(String text) {
  return text.contains('\x1b') || text.contains('secret');
}

final class _StreamingMarkdownJourneySample {
  const _StreamingMarkdownJourneySample({
    required this.totalJourneyUs,
    required this.chunkParseUs,
    required this.chunkFrameUs,
    required this.chunkUpdateUs,
    required this.finalRenderUs,
    required this.copySelectedBlockUs,
    required this.semanticQueryUs,
    required this.initialAnsiBytes,
    required this.maxChunkAnsiBytes,
    required this.finalAnsiBytes,
    required this.chunkCount,
    required this.sourceByteCount,
    required this.blockCount,
    required this.headingCount,
    required this.listItemCount,
    required this.linkCount,
    required this.unsafeLinkCount,
    required this.codeBlockCount,
    required this.codeLineCount,
    required this.semanticNodeCount,
    required this.visibleRangeStart,
    required this.visibleRangeEnd,
    required this.selectedBlockIndex,
    required this.selectedBlockKind,
    required this.unsafeFrameCount,
    required this.sanitizedBlockCount,
    required this.truncatedBlockCount,
    required this.copiedByteCount,
    required this.correct,
  });

  final int totalJourneyUs;
  final List<int> chunkParseUs;
  final List<int> chunkFrameUs;
  final List<int> chunkUpdateUs;
  final int finalRenderUs;
  final int copySelectedBlockUs;
  final int semanticQueryUs;
  final int initialAnsiBytes;
  final int maxChunkAnsiBytes;
  final int finalAnsiBytes;
  final int chunkCount;
  final int sourceByteCount;
  final int blockCount;
  final int headingCount;
  final int listItemCount;
  final int linkCount;
  final int unsafeLinkCount;
  final int codeBlockCount;
  final int codeLineCount;
  final int semanticNodeCount;
  final int visibleRangeStart;
  final int visibleRangeEnd;
  final int selectedBlockIndex;
  final String selectedBlockKind;
  final int unsafeFrameCount;
  final int sanitizedBlockCount;
  final int truncatedBlockCount;
  final int copiedByteCount;
  final bool correct;
}

final class _DashboardUpdateScenario implements _ScenarioBenchmark {
  const _DashboardUpdateScenario();

  @override
  String get id => 'SB.6';

  @override
  String get name => 'Dashboard Update Pressure';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runDashboardUpdateJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_DashboardUpdateJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runDashboardUpdateJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final pump = _Stats.from(samples.expand((sample) => sample.updatePumpUs));
    final frame = _Stats.from(samples.expand((sample) => sample.updateFrameUs));
    final update = _Stats.from(
      samples.expand((sample) => sample.updateTotalUs),
    );
    final updateLayoutPerformed = _Stats.from(
      samples.expand((sample) => sample.updateLayoutPerformed),
    );
    final updateLayoutSkipped = _Stats.from(
      samples.expand((sample) => sample.updateLayoutSkipped),
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'updatePumpUs': pump.toJson(),
        'updateFrameUs': frame.toJson(),
        'updateTotalUs': update.toJson(),
        'updateLayoutPerformed': updateLayoutPerformed.toJson(),
        'updateLayoutSkipped': updateLayoutSkipped.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'lastFirstFrameLayout': _layoutStatsToJson(last.firstFrameLayoutStats),
        'lastUpdateFrameLayout': _layoutStatsToJson(last.lastUpdateLayoutStats),
        'dashboardTickCount': last.dashboardTickCount,
        'surfaceCount': last.surfaceCount,
        'progressSurfaceCount': last.progressSurfaceCount,
        'gaugeSurfaceCount': last.gaugeSurfaceCount,
        'sparklineSurfaceCount': last.sparklineSurfaceCount,
        'chartSurfaceCount': last.chartSurfaceCount,
        'semanticNodeCount': last.semanticNodeCount,
        'progressSemanticCount': last.progressSemanticCount,
        'firstFrameAnsiBytes': last.firstFrameAnsiBytes,
        'maxUpdateAnsiBytes': last.maxUpdateAnsiBytes,
        'finalAnsiBytes': last.finalAnsiBytes,
        'unsafeFrameCount': last.unsafeFrameCount,
        'finalTick': last.finalTick,
        'finalProgressLabel': last.finalProgressLabel,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateUpdateTotalP95Us': 16000,
        'candidateUpdateFrameP95Us': 16000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Scenario repeatedly updates a compact dashboard with progress bars, gauges, sparklines, charts, counters, and status rows.',
        'Run mode is FleuryTester harness execution, not a wall-clock scheduler or terminal process.',
      ],
    );
  }
}

Future<_DashboardUpdateJourneySample> _runDashboardUpdateJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final fixture = _DashboardFixture(seed: config.seed);
  final tickCount = _dashboardTickCountFor(config.rowCount);
  final updatePumpUs = <int>[];
  final updateFrameUs = <int>[];
  final updateTotalUs = <int>[];
  final updateLayoutPerformed = <int>[];
  final updateLayoutSkipped = <int>[];
  final total = Stopwatch()..start();
  var maxUpdateAnsiBytes = 0;
  var unsafeFrameCount = 0;
  try {
    final mount = Stopwatch()..start();
    tester.pumpWidget(_DashboardHarness(fixture: fixture, tick: 0));
    mount.stop();

    final firstRender = Stopwatch()..start();
    final firstFrameSample = _renderMeasured(tester, config.terminalSize);
    final firstFrame = firstFrameSample.buffer;
    firstRender.stop();
    var lastUpdateLayoutStats = RenderLayoutFrameStats.empty;

    for (var tick = 1; tick <= tickCount; tick++) {
      final update = Stopwatch()..start();
      final pump = Stopwatch()..start();
      tester.pumpWidget(_DashboardHarness(fixture: fixture, tick: tick));
      pump.stop();

      final frame = Stopwatch()..start();
      final frameSample = _renderMeasured(tester, config.terminalSize);
      final buffer = frameSample.buffer;
      frame.stop();
      update.stop();

      lastUpdateLayoutStats = frameSample.layoutStats;
      updatePumpUs.add(pump.elapsedMicroseconds);
      updateFrameUs.add(frame.elapsedMicroseconds);
      updateTotalUs.add(update.elapsedMicroseconds);
      updateLayoutPerformed.add(frameSample.layoutStats.performedCount);
      updateLayoutSkipped.add(frameSample.layoutStats.skippedCount);

      final ansiBytes = _ansiBytes(buffer, config.terminalSize);
      if (ansiBytes > maxUpdateAnsiBytes) maxUpdateAnsiBytes = ansiBytes;
      final visible = _visibleText(buffer, config.terminalSize);
      if (_containsUnsafeTerminalPayload(visible)) unsafeFrameCount += 1;
    }

    final finalFrame = tester.render(size: config.terminalSize);
    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final progressNodes = tree.byRole(SemanticRole.progress).toList();
    semantics.stop();
    total.stop();

    final firstProgress = progressNodes.isEmpty ? null : progressNodes.first;
    final expectedLabel = fixture.semanticProgressLabel(tickCount, 0);
    final correct =
        progressNodes.length == _DashboardFixture.progressSurfaceCount &&
        firstProgress?.state.progressLabel == expectedLabel &&
        _ansiBytes(finalFrame, config.terminalSize) > 0 &&
        maxUpdateAnsiBytes > 0 &&
        _DashboardFixture.surfaceCount >= 20 &&
        unsafeFrameCount == 0 &&
        firstFrameSample.layoutStats.performedCount > 0 &&
        updateLayoutSkipped.any((count) => count > 0) &&
        updatePumpUs.length == tickCount &&
        updateFrameUs.length == tickCount &&
        updateTotalUs.length == tickCount &&
        updateLayoutPerformed.length == tickCount &&
        updateLayoutSkipped.length == tickCount;

    return _DashboardUpdateJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      updatePumpUs: List<int>.unmodifiable(updatePumpUs),
      updateFrameUs: List<int>.unmodifiable(updateFrameUs),
      updateTotalUs: List<int>.unmodifiable(updateTotalUs),
      updateLayoutPerformed: List<int>.unmodifiable(updateLayoutPerformed),
      updateLayoutSkipped: List<int>.unmodifiable(updateLayoutSkipped),
      semanticQueryUs: semantics.elapsedMicroseconds,
      firstFrameLayoutStats: firstFrameSample.layoutStats,
      lastUpdateLayoutStats: lastUpdateLayoutStats,
      firstFrameAnsiBytes: _ansiBytes(firstFrame, config.terminalSize),
      maxUpdateAnsiBytes: maxUpdateAnsiBytes,
      finalAnsiBytes: _ansiBytes(finalFrame, config.terminalSize),
      dashboardTickCount: tickCount,
      surfaceCount: _DashboardFixture.surfaceCount,
      progressSurfaceCount: _DashboardFixture.progressSurfaceCount,
      gaugeSurfaceCount: _DashboardFixture.gaugeSurfaceCount,
      sparklineSurfaceCount: _DashboardFixture.sparklineSurfaceCount,
      chartSurfaceCount: _DashboardFixture.chartSurfaceCount,
      semanticNodeCount: tree.nodes.length,
      progressSemanticCount: progressNodes.length,
      unsafeFrameCount: unsafeFrameCount,
      finalTick: tickCount,
      finalProgressLabel: firstProgress?.state.progressLabel ?? '',
      correct: correct,
    );
  } finally {
    tester.dispose();
  }
}

final class _DashboardHarness extends StatelessWidget {
  const _DashboardHarness({required this.fixture, required this.tick});

  final _DashboardFixture fixture;
  final int tick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Dashboard pressure tick $tick'),
        for (
          var index = 0;
          index < _DashboardFixture.progressSurfaceCount;
          index++
        )
          _DashboardServiceRow(fixture: fixture, tick: tick, index: index),
        for (
          var index = 0;
          index < _DashboardFixture.gaugeSurfaceCount;
          index++
        )
          Gauge(
            value: fixture.value(tick, index + 10),
            label: 'Gauge ${_two(index)}',
          ),
        for (
          var index = 0;
          index < _DashboardFixture.sparklineSurfaceCount;
          index++
        )
          Row(
            children: [
              SizedBox(width: 10, child: Text('trend-${_two(index)}')),
              Expanded(
                child: Sparkline(data: fixture.series(tick, index), max: 100),
              ),
            ],
          ),
        Expanded(
          child: BarChart(
            bars: fixture.bars(tick),
            max: 100,
            barWidth: 2,
            gap: 1,
            showValues: false,
          ),
        ),
        Text('surfaces ${_DashboardFixture.surfaceCount} tick $tick'),
      ],
    );
  }
}

final class _DashboardServiceRow extends StatelessWidget {
  const _DashboardServiceRow({
    required this.fixture,
    required this.tick,
    required this.index,
  });

  final _DashboardFixture fixture;
  final int tick;
  final int index;

  @override
  Widget build(BuildContext context) {
    final value = fixture.value(tick, index);
    return Row(
      children: [
        SizedBox(width: 8, child: Text('svc-${_two(index)}')),
        Expanded(child: ProgressBar(value: value)),
        SizedBox(width: 5, child: Text(fixture.progressLabel(tick, index))),
        SizedBox(width: 12, child: Text(fixture.status(tick, index))),
      ],
    );
  }
}

final class _DashboardFixture {
  const _DashboardFixture({required this.seed});

  static const progressSurfaceCount = 8;
  static const gaugeSurfaceCount = 6;
  static const sparklineSurfaceCount = 6;
  static const chartSurfaceCount = 1;
  static const counterSurfaceCount = 2;
  static const surfaceCount =
      progressSurfaceCount +
      gaugeSurfaceCount +
      sparklineSurfaceCount +
      chartSurfaceCount +
      counterSurfaceCount;

  final int seed;

  double value(int tick, int index) {
    final raw = (tick * (index + 3) + seed * 17 + index * 11) % 101;
    return raw / 100.0;
  }

  String progressLabel(int tick, int index) {
    return '${(value(tick, index) * 100).round().toString().padLeft(3)}%';
  }

  String semanticProgressLabel(int tick, int index) {
    return '${(value(tick, index) * 100).round()}%';
  }

  String status(int tick, int index) {
    const states = ['ok', 'warn', 'sync', 'busy'];
    return states[(tick + seed + index) % states.length];
  }

  List<num> series(int tick, int index) {
    return List<num>.generate(32, (sample) {
      final point = tick - 31 + sample;
      final raw = (point * (index + 5) + seed * 13 + sample * 7) % 101;
      return raw < 0 ? raw + 101 : raw;
    }, growable: false);
  }

  List<Bar> bars(int tick) {
    return List<Bar>.generate(12, (index) {
      return Bar('b${index % 10}', (value(tick, index + 20) * 100).round());
    }, growable: false);
  }
}

int _dashboardTickCountFor(int rowCount) {
  final scaled = rowCount ~/ 250;
  if (scaled < 120) return 120;
  if (scaled > 600) return 600;
  return scaled;
}

String _two(int value) => value.toString().padLeft(2, '0');

final class _DashboardUpdateJourneySample {
  const _DashboardUpdateJourneySample({
    required this.totalJourneyUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.updatePumpUs,
    required this.updateFrameUs,
    required this.updateTotalUs,
    required this.updateLayoutPerformed,
    required this.updateLayoutSkipped,
    required this.semanticQueryUs,
    required this.firstFrameLayoutStats,
    required this.lastUpdateLayoutStats,
    required this.firstFrameAnsiBytes,
    required this.maxUpdateAnsiBytes,
    required this.finalAnsiBytes,
    required this.dashboardTickCount,
    required this.surfaceCount,
    required this.progressSurfaceCount,
    required this.gaugeSurfaceCount,
    required this.sparklineSurfaceCount,
    required this.chartSurfaceCount,
    required this.semanticNodeCount,
    required this.progressSemanticCount,
    required this.unsafeFrameCount,
    required this.finalTick,
    required this.finalProgressLabel,
    required this.correct,
  });

  final int totalJourneyUs;
  final int mountUs;
  final int firstRenderUs;
  final List<int> updatePumpUs;
  final List<int> updateFrameUs;
  final List<int> updateTotalUs;
  final List<int> updateLayoutPerformed;
  final List<int> updateLayoutSkipped;
  final int semanticQueryUs;
  final RenderLayoutFrameStats firstFrameLayoutStats;
  final RenderLayoutFrameStats lastUpdateLayoutStats;
  final int firstFrameAnsiBytes;
  final int maxUpdateAnsiBytes;
  final int finalAnsiBytes;
  final int dashboardTickCount;
  final int surfaceCount;
  final int progressSurfaceCount;
  final int gaugeSurfaceCount;
  final int sparklineSurfaceCount;
  final int chartSurfaceCount;
  final int semanticNodeCount;
  final int progressSemanticCount;
  final int unsafeFrameCount;
  final int finalTick;
  final String finalProgressLabel;
  final bool correct;
}

final class _OverlayCommandPaletteScenario implements _ScenarioBenchmark {
  const _OverlayCommandPaletteScenario();

  @override
  String get id => 'SB.8';

  @override
  String get name => 'Overlay And Command Palette Churn';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runOverlayCommandPaletteJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_OverlayCommandPaletteJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runOverlayCommandPaletteJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final open = _Stats.from(samples.expand((sample) => sample.openUs));
    final filter = _Stats.from(samples.expand((sample) => sample.filterUs));
    final selection = _Stats.from(
      samples.expand((sample) => sample.selectionUs),
    );
    final action = _Stats.from(samples.expand((sample) => sample.actionUs));
    final settle = _Stats.from(samples.expand((sample) => sample.settleUs));
    final cycle = _Stats.from(samples.expand((sample) => sample.cycleUs));
    final semanticQuery = _Stats.from(
      samples.expand((sample) => sample.semanticQueryUs),
    );
    final disabledSemanticAction = _Stats.from(
      samples.map((sample) => sample.disabledSemanticActionUs),
    );
    final disabledKeyboardAction = _Stats.from(
      samples.map((sample) => sample.disabledKeyboardActionUs),
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'openUs': open.toJson(),
        'filterUs': filter.toJson(),
        'selectionUs': selection.toJson(),
        'actionUs': action.toJson(),
        'settleUs': settle.toJson(),
        'cycleUs': cycle.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'disabledSemanticActionUs': disabledSemanticAction.toJson(),
        'disabledKeyboardActionUs': disabledKeyboardAction.toJson(),
        'commandCount': last.commandCount,
        'cycleCount': last.cycleCount,
        'invokedCount': last.invokedCount,
        'dismissedCount': last.dismissedCount,
        'screenCommandInvokeCount': last.screenCommandInvokeCount,
        'semanticNodeCount': last.semanticNodeCount,
        'paletteSemanticCount': last.paletteSemanticCount,
        'commandSemanticCount': last.commandSemanticCount,
        'disabledCommandEnabledState': last.disabledCommandEnabledState,
        'disabledStayedOpen': last.disabledStayedOpen,
        'disabledSemanticActionStatus': last.disabledSemanticActionStatus,
        'stalePaletteAfterCloseCount': last.stalePaletteAfterCloseCount,
        'routeDepthMismatchCount': last.routeDepthMismatchCount,
        'paletteMismatchCount': last.paletteMismatchCount,
        'selectedMismatchCount': last.selectedMismatchCount,
        'visibleTextMismatchCount': last.visibleTextMismatchCount,
        'actionFailureCount': last.actionFailureCount,
        'semanticMismatchCount': last.semanticMismatchCount,
        'unexpectedInvocationCount': last.unexpectedInvocationCount,
        'homeAnsiBytes': last.homeAnsiBytes,
        'maxOpenAnsiBytes': last.maxOpenAnsiBytes,
        'maxFilteredAnsiBytes': last.maxFilteredAnsiBytes,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateOpenP95Us': 33000,
        'candidateFilterP95Us': 16000,
        'candidateActionP95Us': 16000,
        'candidateCycleP95Us': 50000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Scenario opens AppCommandPalette through Navigator.present so it exercises overlay lifecycle and app command discovery.',
        'Cycles alternate keyboard invocation, semantic submit, semantic activate, Escape dismissal, and semantic dismissal.',
        'A disabled command probe verifies visible-but-inert commands stay open and do not invoke stale actions.',
      ],
    );
  }
}

Future<_OverlayCommandPaletteJourneySample> _runOverlayCommandPaletteJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final fixture = _OverlayCommandFixture(
    seed: config.seed,
    commandCount: _overlayCommandCountFor(config.rowCount),
  );
  final invokedIds = <String>[];
  BuildContext? routeContext;
  final openUs = <int>[];
  final filterUs = <int>[];
  final selectionUs = <int>[];
  final actionUs = <int>[];
  final settleUs = <int>[];
  final cycleUs = <int>[];
  final semanticQueryUs = <int>[];
  var maxOpenAnsiBytes = 0;
  var maxFilteredAnsiBytes = 0;
  var semanticNodeCount = 0;
  var paletteSemanticCount = 0;
  var commandSemanticCount = 0;
  var stalePaletteAfterCloseCount = 0;
  var routeDepthMismatchCount = 0;
  var paletteMismatchCount = 0;
  var selectedMismatchCount = 0;
  var visibleTextMismatchCount = 0;
  var actionFailureCount = 0;
  var semanticMismatchCount = 0;
  var unexpectedInvocationCount = 0;
  var dismissedCount = 0;
  var screenCommandInvokeCount = 0;
  final total = Stopwatch()..start();
  try {
    final mount = Stopwatch()..start();
    tester.pumpWidget(
      FleuryApp(
        title: 'Overlay Benchmark',
        commands: fixture.appCommands(invokedIds.add),
        screens: [
          FleuryScreen(
            id: const ScreenId('overlay-benchmark'),
            title: 'Overlay Benchmark',
            commands: [fixture.screenCommand(invokedIds.add)],
            builder: (_) => const Text('screen'),
          ),
        ],
        child: Navigator(
          home: _OverlayContextCapture((context) {
            routeContext = context;
          }),
        ),
      ),
    );
    mount.stop();

    final firstRender = Stopwatch()..start();
    final homeFrame = tester.render(size: config.terminalSize);
    firstRender.stop();
    final homeAnsiBytes = _ansiBytes(homeFrame, config.terminalSize);
    final cycleCount = _overlayCycleCountFor(config.rowCount);

    for (var cycle = 0; cycle < cycleCount; cycle++) {
      final target = fixture.targetForCycle(cycle);
      final shouldInvoke = cycle % 5 != 3 && cycle % 5 != 4;
      final beforeInvoked = invokedIds.length;
      final route = routeContext;
      if (route == null) {
        semanticMismatchCount += 1;
        continue;
      }

      final cycleWatch = Stopwatch()..start();
      final open = Stopwatch()..start();
      Navigator.of(
        route,
      ).present<void>(const AppCommandPalette(width: 64, maxVisible: 10));
      tester.pump(const Duration(milliseconds: 300));
      final openFrame = tester.render(size: config.terminalSize);
      open.stop();
      openUs.add(open.elapsedMicroseconds);
      maxOpenAnsiBytes = _max(
        maxOpenAnsiBytes,
        _ansiBytes(openFrame, config.terminalSize),
      );

      final filter = Stopwatch()..start();
      tester.type(target.query);
      tester.pump();
      var filteredFrame = tester.render(size: config.terminalSize);
      filter.stop();
      filterUs.add(filter.elapsedMicroseconds);
      maxFilteredAnsiBytes = _max(
        maxFilteredAnsiBytes,
        _ansiBytes(filteredFrame, config.terminalSize),
      );

      final selection = Stopwatch()..start();
      var tree = tester.semantics();
      var commandNodes = tree
          .byRole(SemanticRole.command)
          .where((node) => node.state['rowIndex'] != null)
          .toList();
      var selected = _firstSemanticNode(
        commandNodes.where((node) => node.selected),
      );
      final targetRowIndex = commandNodes.indexWhere(
        (node) => node.state.commandId == target.id,
      );
      if (targetRowIndex > 0 && selected?.state.commandId != target.id) {
        for (var step = 0; step < targetRowIndex; step++) {
          tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
        }
        tester.pump();
        filteredFrame = tester.render(size: config.terminalSize);
      }
      selection.stop();
      selectionUs.add(selection.elapsedMicroseconds);

      final semanticQuery = Stopwatch()..start();
      tree = tester.semantics();
      final paletteNodes = tree.byRole(SemanticRole.commandPalette).toList();
      commandNodes = tree
          .byRole(SemanticRole.command)
          .where((node) => node.state['rowIndex'] != null)
          .toList();
      selected = _firstSemanticNode(
        commandNodes.where((node) => node.selected),
      );
      semanticQuery.stop();
      semanticQueryUs.add(semanticQuery.elapsedMicroseconds);
      semanticNodeCount = tree.nodes.length;
      paletteSemanticCount = paletteNodes.length;
      commandSemanticCount = commandNodes.length;

      final filteredText = _visibleText(filteredFrame, config.terminalSize);
      final palette = _firstSemanticNode(paletteNodes);
      if (paletteNodes.length != 1 ||
          palette?.value != target.query ||
          (palette?.state.collectionRowCount ?? 0) < 1) {
        paletteMismatchCount += 1;
        semanticMismatchCount += 1;
      }
      if (selected?.state.commandId != target.id) {
        selectedMismatchCount += 1;
        semanticMismatchCount += 1;
      }
      if (!filteredText.contains(target.title)) {
        visibleTextMismatchCount += 1;
        semanticMismatchCount += 1;
      }

      final action = Stopwatch()..start();
      if (cycle % 5 == 0) {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      } else if (cycle % 5 == 1) {
        final result = await tester.invokeSemanticAction(
          SemanticAction.submit,
          role: SemanticRole.commandPalette,
        );
        if (!result.completed) {
          actionFailureCount += 1;
          semanticMismatchCount += 1;
        }
      } else if (cycle % 5 == 2) {
        final result = selected == null
            ? SemanticActionInvocationResult.notFound(SemanticAction.activate)
            : await tester.invokeSemanticAction(
                SemanticAction.activate,
                node: selected,
              );
        if (!result.completed) {
          actionFailureCount += 1;
          semanticMismatchCount += 1;
        }
      } else if (cycle % 5 == 3) {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      } else {
        final result = await tester.invokeSemanticAction(
          SemanticAction.dismiss,
          role: SemanticRole.commandPalette,
        );
        if (!result.completed) {
          actionFailureCount += 1;
          semanticMismatchCount += 1;
        }
      }
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      action.stop();
      actionUs.add(action.elapsedMicroseconds);

      final settle = Stopwatch()..start();
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      settle.stop();
      settleUs.add(settle.elapsedMicroseconds);
      cycleWatch.stop();
      cycleUs.add(cycleWatch.elapsedMicroseconds);

      if (Navigator.of(route).depth != 1) {
        routeDepthMismatchCount += 1;
        semanticMismatchCount += 1;
      }
      if (tester.semantics().byRole(SemanticRole.commandPalette).isNotEmpty) {
        stalePaletteAfterCloseCount += 1;
      }

      if (shouldInvoke) {
        final invokedCorrectly =
            invokedIds.length == beforeInvoked + 1 &&
            invokedIds.last == target.id;
        if (!invokedCorrectly) unexpectedInvocationCount += 1;
        if (target.screenCommand && invokedCorrectly) {
          screenCommandInvokeCount += 1;
        }
      } else {
        dismissedCount += 1;
        if (invokedIds.length != beforeInvoked) {
          unexpectedInvocationCount += 1;
        }
      }
    }

    final disabledProbe = await _runDisabledOverlayProbe(
      tester,
      routeContext,
      fixture,
      invokedIds,
      config.terminalSize,
    );
    maxOpenAnsiBytes = _max(maxOpenAnsiBytes, disabledProbe.openAnsiBytes);
    maxFilteredAnsiBytes = _max(
      maxFilteredAnsiBytes,
      disabledProbe.filteredAnsiBytes,
    );
    stalePaletteAfterCloseCount += disabledProbe.stalePaletteAfterClose ? 1 : 0;
    semanticMismatchCount += disabledProbe.semanticMismatch ? 1 : 0;
    unexpectedInvocationCount += disabledProbe.unexpectedInvocation ? 1 : 0;
    total.stop();

    final correct =
        openUs.length == cycleCount &&
        filterUs.length == cycleCount &&
        selectionUs.length == cycleCount &&
        actionUs.length == cycleCount &&
        settleUs.length == cycleCount &&
        cycleUs.length == cycleCount &&
        invokedIds.length == cycleCount - dismissedCount &&
        screenCommandInvokeCount > 0 &&
        disabledProbe.commandEnabledState == false &&
        disabledProbe.stayedOpen &&
        disabledProbe.semanticActionStatus ==
            SemanticActionInvocationStatus.disabled.name &&
        stalePaletteAfterCloseCount == 0 &&
        routeDepthMismatchCount == 0 &&
        paletteMismatchCount == 0 &&
        selectedMismatchCount == 0 &&
        visibleTextMismatchCount == 0 &&
        actionFailureCount == 0 &&
        semanticMismatchCount == 0 &&
        unexpectedInvocationCount == 0;

    return _OverlayCommandPaletteJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      openUs: List<int>.unmodifiable(openUs),
      filterUs: List<int>.unmodifiable(filterUs),
      selectionUs: List<int>.unmodifiable(selectionUs),
      actionUs: List<int>.unmodifiable(actionUs),
      settleUs: List<int>.unmodifiable(settleUs),
      cycleUs: List<int>.unmodifiable(cycleUs),
      semanticQueryUs: List<int>.unmodifiable(semanticQueryUs),
      disabledSemanticActionUs: disabledProbe.semanticActionUs,
      disabledKeyboardActionUs: disabledProbe.keyboardActionUs,
      commandCount: fixture.commandCount,
      cycleCount: cycleCount,
      invokedCount: invokedIds.length,
      dismissedCount: dismissedCount,
      screenCommandInvokeCount: screenCommandInvokeCount,
      semanticNodeCount: semanticNodeCount,
      paletteSemanticCount: paletteSemanticCount,
      commandSemanticCount: commandSemanticCount,
      disabledCommandEnabledState: disabledProbe.commandEnabledState,
      disabledStayedOpen: disabledProbe.stayedOpen,
      disabledSemanticActionStatus: disabledProbe.semanticActionStatus,
      stalePaletteAfterCloseCount: stalePaletteAfterCloseCount,
      routeDepthMismatchCount: routeDepthMismatchCount,
      paletteMismatchCount: paletteMismatchCount,
      selectedMismatchCount: selectedMismatchCount,
      visibleTextMismatchCount: visibleTextMismatchCount,
      actionFailureCount: actionFailureCount,
      semanticMismatchCount: semanticMismatchCount,
      unexpectedInvocationCount: unexpectedInvocationCount,
      homeAnsiBytes: homeAnsiBytes,
      maxOpenAnsiBytes: maxOpenAnsiBytes,
      maxFilteredAnsiBytes: maxFilteredAnsiBytes,
      correct: correct,
    );
  } finally {
    tester.dispose();
  }
}

Future<_DisabledOverlayProbe> _runDisabledOverlayProbe(
  FleuryTester tester,
  BuildContext? routeContext,
  _OverlayCommandFixture fixture,
  List<String> invokedIds,
  CellSize terminalSize,
) async {
  final route = routeContext;
  if (route == null) {
    return const _DisabledOverlayProbe(
      semanticActionUs: 0,
      keyboardActionUs: 0,
      openAnsiBytes: 0,
      filteredAnsiBytes: 0,
      commandEnabledState: true,
      stayedOpen: false,
      semanticActionStatus: 'notFound',
      stalePaletteAfterClose: false,
      semanticMismatch: true,
      unexpectedInvocation: false,
    );
  }

  Navigator.of(
    route,
  ).present<void>(const AppCommandPalette(width: 64, maxVisible: 10));
  tester.pump(const Duration(milliseconds: 300));
  final openFrame = tester.render(size: terminalSize);
  final target = fixture.disabledTarget;
  tester.type(target.query);
  tester.pump();
  final filteredFrame = tester.render(size: terminalSize);
  final tree = tester.semantics();
  final command = _firstSemanticNode(
    tree
        .byRole(SemanticRole.command)
        .where(
          (node) =>
              node.label == target.title && node.state['rowIndex'] != null,
        ),
  );
  final beforeInvoked = invokedIds.length;

  final semanticAction = Stopwatch()..start();
  final semanticResult = command == null
      ? SemanticActionInvocationResult.notFound(SemanticAction.activate)
      : await tester.invokeSemanticAction(
          SemanticAction.activate,
          node: command,
        );
  await Future<void>.delayed(Duration.zero);
  tester.pump();
  semanticAction.stop();

  final keyboardAction = Stopwatch()..start();
  tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
  await Future<void>.delayed(Duration.zero);
  tester.pump();
  keyboardAction.stop();

  final stayedOpen = Navigator.of(route).depth == 2;
  final semanticMismatch =
      command == null ||
      command.enabled != false ||
      command.state.commandId != target.id ||
      semanticResult.status != SemanticActionInvocationStatus.disabled;
  final unexpectedInvocation = invokedIds.length != beforeInvoked;

  await tester.invokeSemanticAction(
    SemanticAction.dismiss,
    role: SemanticRole.commandPalette,
  );
  await Future<void>.delayed(Duration.zero);
  tester.pump(const Duration(milliseconds: 300));
  tester.pump();
  final stalePaletteAfterClose = tester
      .semantics()
      .byRole(SemanticRole.commandPalette)
      .isNotEmpty;

  return _DisabledOverlayProbe(
    semanticActionUs: semanticAction.elapsedMicroseconds,
    keyboardActionUs: keyboardAction.elapsedMicroseconds,
    openAnsiBytes: _ansiBytes(openFrame, terminalSize),
    filteredAnsiBytes: _ansiBytes(filteredFrame, terminalSize),
    commandEnabledState: command?.enabled ?? true,
    stayedOpen: stayedOpen,
    semanticActionStatus: semanticResult.status.name,
    stalePaletteAfterClose: stalePaletteAfterClose,
    semanticMismatch: semanticMismatch,
    unexpectedInvocation: unexpectedInvocation,
  );
}

final class _OverlayContextCapture extends StatelessWidget {
  const _OverlayContextCapture(this.sink);

  final void Function(BuildContext context) sink;

  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('overlay benchmark home');
  }
}

final class _OverlayCommandFixture {
  const _OverlayCommandFixture({
    required this.seed,
    required this.commandCount,
  });

  final int seed;
  final int commandCount;

  _OverlayCommandTarget get screenTarget {
    return const _OverlayCommandTarget(
      id: 'screen.refresh',
      title: 'Active Screen Refresh',
      query: 'screen.refresh',
      screenCommand: true,
    );
  }

  _OverlayCommandTarget get disabledTarget {
    final index = _firstDisabledIndex;
    return _OverlayCommandTarget(
      id: id(index),
      title: title(index),
      query: id(index),
      screenCommand: false,
    );
  }

  AppCommand screenCommand(void Function(String id) onInvoke) {
    final target = screenTarget;
    return AppCommand(
      id: CommandId(target.id),
      title: target.title,
      description: 'Active screen command for overlay churn.',
      category: 'Screen',
      run: (_) {
        onInvoke(target.id);
      },
    );
  }

  List<AppCommand> appCommands(void Function(String id) onInvoke) {
    return List<AppCommand>.generate(commandCount, (index) {
      final disabled = isDisabled(index);
      final commandId = id(index);
      return AppCommand(
        id: CommandId(commandId),
        title: title(index),
        description: 'Command $index benchmark action.',
        category:
            _commandCategories[(index + seed) % _commandCategories.length],
        enabled: (_) => !disabled,
        run: (_) {
          onInvoke(commandId);
        },
      );
    }, growable: false);
  }

  _OverlayCommandTarget targetForCycle(int cycle) {
    if (cycle % 11 == 0) return screenTarget;
    final index = enabledIndexFor(cycle);
    return _OverlayCommandTarget(
      id: id(index),
      title: title(index),
      query: id(index),
      screenCommand: false,
    );
  }

  int enabledIndexFor(int cycle) {
    var index = (cycle * 37 + seed * 11) % commandCount;
    while (isDisabled(index)) {
      index = (index + 1) % commandCount;
    }
    return index;
  }

  bool isDisabled(int index) => index % 17 == 0;

  String id(int index) => 'scenario.command.${_digits(index)}';

  String title(int index) => 'Scenario Command ${_digits(index)}';

  int get _firstDisabledIndex => 0;
}

const _commandCategories = ['File', 'Edit', 'View', 'Run', 'Deploy', 'Agent'];

String _digits(int value) => value.toString().padLeft(5, '0');

int _overlayCommandCountFor(int rowCount) {
  final scaled = rowCount ~/ 100;
  if (scaled < 128) return 128;
  if (scaled > 1200) return 1200;
  return scaled;
}

int _overlayCycleCountFor(int rowCount) {
  final scaled = rowCount ~/ 2500;
  if (scaled < 16) return 16;
  if (scaled > 64) return 64;
  return scaled;
}

SemanticNode? _firstSemanticNode(Iterable<SemanticNode> nodes) {
  for (final node in nodes) {
    return node;
  }
  return null;
}

final class _OverlayCommandTarget {
  const _OverlayCommandTarget({
    required this.id,
    required this.title,
    required this.query,
    required this.screenCommand,
  });

  final String id;
  final String title;
  final String query;
  final bool screenCommand;
}

final class _DisabledOverlayProbe {
  const _DisabledOverlayProbe({
    required this.semanticActionUs,
    required this.keyboardActionUs,
    required this.openAnsiBytes,
    required this.filteredAnsiBytes,
    required this.commandEnabledState,
    required this.stayedOpen,
    required this.semanticActionStatus,
    required this.stalePaletteAfterClose,
    required this.semanticMismatch,
    required this.unexpectedInvocation,
  });

  final int semanticActionUs;
  final int keyboardActionUs;
  final int openAnsiBytes;
  final int filteredAnsiBytes;
  final bool commandEnabledState;
  final bool stayedOpen;
  final String semanticActionStatus;
  final bool stalePaletteAfterClose;
  final bool semanticMismatch;
  final bool unexpectedInvocation;
}

final class _OverlayCommandPaletteJourneySample {
  const _OverlayCommandPaletteJourneySample({
    required this.totalJourneyUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.openUs,
    required this.filterUs,
    required this.selectionUs,
    required this.actionUs,
    required this.settleUs,
    required this.cycleUs,
    required this.semanticQueryUs,
    required this.disabledSemanticActionUs,
    required this.disabledKeyboardActionUs,
    required this.commandCount,
    required this.cycleCount,
    required this.invokedCount,
    required this.dismissedCount,
    required this.screenCommandInvokeCount,
    required this.semanticNodeCount,
    required this.paletteSemanticCount,
    required this.commandSemanticCount,
    required this.disabledCommandEnabledState,
    required this.disabledStayedOpen,
    required this.disabledSemanticActionStatus,
    required this.stalePaletteAfterCloseCount,
    required this.routeDepthMismatchCount,
    required this.paletteMismatchCount,
    required this.selectedMismatchCount,
    required this.visibleTextMismatchCount,
    required this.actionFailureCount,
    required this.semanticMismatchCount,
    required this.unexpectedInvocationCount,
    required this.homeAnsiBytes,
    required this.maxOpenAnsiBytes,
    required this.maxFilteredAnsiBytes,
    required this.correct,
  });

  final int totalJourneyUs;
  final int mountUs;
  final int firstRenderUs;
  final List<int> openUs;
  final List<int> filterUs;
  final List<int> selectionUs;
  final List<int> actionUs;
  final List<int> settleUs;
  final List<int> cycleUs;
  final List<int> semanticQueryUs;
  final int disabledSemanticActionUs;
  final int disabledKeyboardActionUs;
  final int commandCount;
  final int cycleCount;
  final int invokedCount;
  final int dismissedCount;
  final int screenCommandInvokeCount;
  final int semanticNodeCount;
  final int paletteSemanticCount;
  final int commandSemanticCount;
  final bool disabledCommandEnabledState;
  final bool disabledStayedOpen;
  final String disabledSemanticActionStatus;
  final int stalePaletteAfterCloseCount;
  final int routeDepthMismatchCount;
  final int paletteMismatchCount;
  final int selectedMismatchCount;
  final int visibleTextMismatchCount;
  final int actionFailureCount;
  final int semanticMismatchCount;
  final int unexpectedInvocationCount;
  final int homeAnsiBytes;
  final int maxOpenAnsiBytes;
  final int maxFilteredAnsiBytes;
  final bool correct;
}

final class _ResizeStormScenario implements _ScenarioBenchmark {
  const _ResizeStormScenario();

  @override
  String get id => 'SB.7';

  @override
  String get name => 'Resize Storm';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runResizeStormJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_ResizeStormJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runResizeStormJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final resizeFrame = _Stats.from(
      samples.expand((sample) => sample.resizeFrameUs),
    );
    final semanticQuery = _Stats.from(
      samples.expand((sample) => sample.semanticQueryUs),
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'resizeFrameUs': resizeFrame.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'resizeEventCount': config.resizeEvents,
        'sizesValidated': last.sizesValidated,
        'distinctSizeCount': last.distinctSizeCount,
        'minColumns': last.minColumns,
        'maxColumns': last.maxColumns,
        'minRows': last.minRows,
        'maxRows': last.maxRows,
        'firstFrameAnsiBytes': last.firstFrameAnsiBytes,
        'maxResizeAnsiBytes': last.maxResizeAnsiBytes,
        'semanticNodeCount': last.semanticNodeCount,
        'tableVisibleRangeStart': last.tableVisibleRangeStart,
        'tableVisibleRangeEnd': last.tableVisibleRangeEnd,
        'logVisibleRangeStart': last.logVisibleRangeStart,
        'logVisibleRangeEnd': last.logVisibleRangeEnd,
        'selectedTableKey': last.selectedTableKey,
        'selectedLogKey': last.selectedLogKey,
        'logEntryCount': last.logEntryCount,
        'unsafeFrameCount': last.unsafeFrameCount,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateResizeFrameP95Us': 50000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Scenario alternates normal, wide, narrow, and short terminal sizes while a table/log/editor surface stays mounted.',
        'Correctness requires no unsafe terminal payload leakage and valid semantic table/log/text-field nodes after every resize.',
      ],
    );
  }
}

Future<_ResizeStormJourneySample> _runResizeStormJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final total = Stopwatch()..start();
  try {
    final fixture = _RunFixture(seed: config.seed);
    final logFixture = _LogFixture(seed: config.seed);
    final logEntryCount = _resizeLogCountFor(config.rowCount);
    final logEntries = List<LogEntry>.generate(
      logEntryCount,
      logFixture.entry,
      growable: false,
    );
    final tableController = DataTableController();
    final logController = LogRegionController();
    final inputController = TextEditingController(text: 'status:failed');

    final mount = Stopwatch()..start();
    tester.pumpWidget(
      _ResizeStormHarness(
        rowCount: config.rowCount,
        runFixture: fixture,
        logEntries: logEntries,
        tableController: tableController,
        logController: logController,
        inputController: inputController,
      ),
    );
    mount.stop();

    final firstRender = Stopwatch()..start();
    final firstFrame = tester.render(size: config.terminalSize);
    firstRender.stop();

    final sizes = _resizeStormSizes(config);
    final resizeFrameUs = <int>[];
    final semanticQueryUs = <int>[];
    var maxResizeAnsiBytes = 0;
    var unsafeFrameCount = 0;
    var semanticNodeCount = 0;
    var tableVisibleStart = -1;
    var tableVisibleEnd = -1;
    var logVisibleStart = -1;
    var logVisibleEnd = -1;
    var selectedTableKey = '';
    var selectedLogKey = '';
    var correct = sizes.isNotEmpty;

    for (final size in sizes) {
      final render = Stopwatch()..start();
      final frame = tester.render(size: size);
      render.stop();
      resizeFrameUs.add(render.elapsedMicroseconds);

      final ansiBytes = _ansiBytes(frame, size);
      if (ansiBytes > maxResizeAnsiBytes) maxResizeAnsiBytes = ansiBytes;
      final visible = _visibleText(frame, size);
      final unsafe = visible.contains('secret') || visible.contains('\x1b');
      if (unsafe) unsafeFrameCount += 1;

      final semantics = Stopwatch()..start();
      final tree = tester.semantics();
      final table = tree.single(role: SemanticRole.table);
      final log = tree.single(role: SemanticRole.log);
      final field = tree.single(role: SemanticRole.textField);
      semantics.stop();
      semanticQueryUs.add(semantics.elapsedMicroseconds);

      semanticNodeCount = tree.nodes.length;
      tableVisibleStart = table.state.visibleRangeStart ?? -1;
      tableVisibleEnd = table.state.visibleRangeEnd ?? -1;
      logVisibleStart = logController.visibleRange?.first ?? -1;
      logVisibleEnd = logController.visibleRange?.last ?? -1;
      selectedTableKey = table.state.selectedKey?.toString() ?? '';
      selectedLogKey = log.state.selectedKey?.toString() ?? '';

      correct =
          correct &&
          !unsafe &&
          frame.size == size &&
          table.state.collectionRowCount == config.rowCount &&
          table.state.collectionColumnCount == _columns.length &&
          table.state.values['virtualized'] == true &&
          table.state.filterText == inputController.text &&
          log.state['totalEntryCount'] == logEntryCount &&
          log.state['followTail'] == true &&
          field.value == inputController.text &&
          tableVisibleStart <= tableVisibleEnd &&
          logVisibleStart <= logVisibleEnd;
    }
    total.stop();

    final distinctSizes = <String>{
      for (final size in sizes) '${size.cols}x${size.rows}',
    };
    return _ResizeStormJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      resizeFrameUs: List<int>.unmodifiable(resizeFrameUs),
      semanticQueryUs: List<int>.unmodifiable(semanticQueryUs),
      firstFrameAnsiBytes: _ansiBytes(firstFrame, config.terminalSize),
      maxResizeAnsiBytes: maxResizeAnsiBytes,
      semanticNodeCount: semanticNodeCount,
      tableVisibleRangeStart: tableVisibleStart,
      tableVisibleRangeEnd: tableVisibleEnd,
      logVisibleRangeStart: logVisibleStart,
      logVisibleRangeEnd: logVisibleEnd,
      selectedTableKey: selectedTableKey,
      selectedLogKey: selectedLogKey,
      logEntryCount: logEntryCount,
      sizesValidated: sizes.length,
      distinctSizeCount: distinctSizes.length,
      minColumns: sizes.map((size) => size.cols).reduce(_min),
      maxColumns: sizes.map((size) => size.cols).reduce(_max),
      minRows: sizes.map((size) => size.rows).reduce(_min),
      maxRows: sizes.map((size) => size.rows).reduce(_max),
      unsafeFrameCount: unsafeFrameCount,
      correct: correct,
    );
  } finally {
    tester.dispose();
  }
}

final class _ResizeStormHarness extends StatelessWidget {
  const _ResizeStormHarness({
    required this.rowCount,
    required this.runFixture,
    required this.logEntries,
    required this.tableController,
    required this.logController,
    required this.inputController,
  });

  final int rowCount;
  final _RunFixture runFixture;
  final List<LogEntry> logEntries;
  final DataTableController tableController;
  final LogRegionController logController;
  final TextEditingController inputController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Resize Storm $rowCount rows'),
        SizedBox(
          height: 1,
          child: TextInput(
            controller: inputController,
            placeholder: 'filter',
            autofocus: true,
          ),
        ),
        Expanded(
          flex: 2,
          child: DataTable(
            rowCount: rowCount,
            columns: _columns,
            controller: tableController,
            rowKeyBuilder: runFixture.rowKey,
            filterText: inputController.text,
            cellBuilder: runFixture.cell,
          ),
        ),
        Expanded(
          child: LogRegion(
            entries: logEntries,
            controller: logController,
            label: 'Resize logs',
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
      ],
    );
  }
}

List<CellSize> _resizeStormSizes(_ScenarioConfig config) {
  final pattern = <CellSize>[
    config.terminalSize,
    const CellSize(80, 24),
    const CellSize(120, 40),
    const CellSize(200, 60),
    const CellSize(64, 18),
    const CellSize(48, 12),
    const CellSize(32, 8),
    const CellSize(160, 20),
  ];
  return List<CellSize>.generate(
    config.resizeEvents,
    (index) => pattern[(index + config.seed) % pattern.length],
    growable: false,
  );
}

int _resizeLogCountFor(int rowCount) {
  final scaled = rowCount ~/ 20;
  if (scaled < 128) return 128;
  if (scaled > 5000) return 5000;
  return scaled;
}

int _min(int a, int b) => a < b ? a : b;

final class _ResizeStormJourneySample {
  const _ResizeStormJourneySample({
    required this.totalJourneyUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.resizeFrameUs,
    required this.semanticQueryUs,
    required this.firstFrameAnsiBytes,
    required this.maxResizeAnsiBytes,
    required this.semanticNodeCount,
    required this.tableVisibleRangeStart,
    required this.tableVisibleRangeEnd,
    required this.logVisibleRangeStart,
    required this.logVisibleRangeEnd,
    required this.selectedTableKey,
    required this.selectedLogKey,
    required this.logEntryCount,
    required this.sizesValidated,
    required this.distinctSizeCount,
    required this.minColumns,
    required this.maxColumns,
    required this.minRows,
    required this.maxRows,
    required this.unsafeFrameCount,
    required this.correct,
  });

  final int totalJourneyUs;
  final int mountUs;
  final int firstRenderUs;
  final List<int> resizeFrameUs;
  final List<int> semanticQueryUs;
  final int firstFrameAnsiBytes;
  final int maxResizeAnsiBytes;
  final int semanticNodeCount;
  final int tableVisibleRangeStart;
  final int tableVisibleRangeEnd;
  final int logVisibleRangeStart;
  final int logVisibleRangeEnd;
  final String selectedTableKey;
  final String selectedLogKey;
  final int logEntryCount;
  final int sizesValidated;
  final int distinctSizeCount;
  final int minColumns;
  final int maxColumns;
  final int minRows;
  final int maxRows;
  final int unsafeFrameCount;
  final bool correct;
}

final class _SubprocessOutputScenario implements _ScenarioBenchmark {
  const _SubprocessOutputScenario();

  @override
  String get id => 'SB.9';

  @override
  String get name => 'Subprocess Handoff And Untrusted Output';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runSubprocessOutputJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_SubprocessOutputJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runSubprocessOutputJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final processRun = _Stats.from(
      samples.map((sample) => sample.processRunUs),
    );
    final failureRun = _Stats.from(
      samples.map((sample) => sample.failureRunUs),
    );
    final cancelLatency = _Stats.from(
      samples.map((sample) => sample.cancelLatencyUs),
    );
    final editorHandoff = _Stats.from(
      samples.map((sample) => sample.editorHandoffUs),
    );
    final streamFrame = _Stats.from(
      samples.expand((sample) => sample.streamFrameUs),
    );
    final processPanelRender = _Stats.from(
      samples.map((sample) => sample.processPanelRenderUs),
    );
    final terminalOutputRender = _Stats.from(
      samples.map((sample) => sample.terminalOutputRenderUs),
    );
    final copy = _Stats.from(samples.map((sample) => sample.copySelectedUs));
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'processRunUs': processRun.toJson(),
        'failureRunUs': failureRun.toJson(),
        'cancelLatencyUs': cancelLatency.toJson(),
        'editorHandoffUs': editorHandoff.toJson(),
        'streamFrameUs': streamFrame.toJson(),
        'processPanelRenderUs': processPanelRender.toJson(),
        'terminalOutputRenderUs': terminalOutputRender.toJson(),
        'copySelectedUs': copy.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'processLineCount': last.processLineCount,
        'processTargetBytes': last.processTargetBytes,
        'capturedOutputBytes': last.capturedOutputBytes,
        'capturedOriginalBytes': last.capturedOriginalBytes,
        'processOutputCount': last.processOutputCount,
        'stderrOutputCount': last.stderrOutputCount,
        'sanitizedOutputCount': last.sanitizedOutputCount,
        'truncatedOutputCount': last.truncatedOutputCount,
        'unsafeSequenceBlockCount': last.unsafeSequenceBlockCount,
        'failureExitCode': last.failureExitCode,
        'failureOutputCount': last.failureOutputCount,
        'cancelOutputObserved': last.cancelOutputObserved,
        'cancelProcessExitCode': last.cancelProcessExitCode,
        'terminalModeRestored': last.terminalModeRestored,
        'handoffCallCount': last.handoffCallCount,
        'handoffSuspendCallCount': last.handoffSuspendCallCount,
        'handoffResumeCallCount': last.handoffResumeCallCount,
        'terminalOutputLineCount': last.terminalOutputLineCount,
        'terminalStreamBatchCount': last.terminalStreamBatchCount,
        'semanticNodeCount': last.semanticNodeCount,
        'taskSemanticCount': last.taskSemanticCount,
        'logSemanticCount': last.logSemanticCount,
        'initialAnsiBytes': last.initialAnsiBytes,
        'maxStreamAnsiBytes': last.maxStreamAnsiBytes,
        'processPanelAnsiBytes': last.processPanelAnsiBytes,
        'terminalOutputAnsiBytes': last.terminalOutputAnsiBytes,
        'unsafeFrameCount': last.unsafeFrameCount,
        'unsafeArtifactLeakCount': last.unsafeArtifactLeakCount,
        'copiedByteCount': last.copiedByteCount,
        'editorChanged': last.editorChanged,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateProcessRunP95Us': 1000000,
        'candidateCancelLatencyP95Us': 200000,
        'candidateStreamFrameP95Us': 33000,
        'candidateSemanticQueryP95Us': 16000,
        'terminalModeRestoredRequired': true,
        'unsafeArtifactLeakCountRequired': 0,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Scenario runs real Dart subprocesses for success, non-zero exit, cancellation, and terminal handoff.',
        'Streaming frame timing is measured through TerminalOutputRegion with unsafe stdout/stderr-like lines.',
        'Correctness requires restored terminal handoff state and no unsafe payload leakage into visible, copied, or semantic artifacts.',
      ],
    );
  }
}

Future<_SubprocessOutputJourneySample> _runSubprocessOutputJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final originalClipboard = Clipboard.instance;
  final clipboard = TestClipboard();
  Clipboard.instance = clipboard;
  final total = Stopwatch()..start();
  final tempDir = await Directory.systemTemp.createTemp('fleury_sb9_');
  final driver = FakeTerminalDriver(size: config.terminalSize);
  var cancelProcessExitCode = -999;

  try {
    await driver.enter(TerminalMode.interactive);
    final script = await _writeSubprocessScenarioScript(tempDir);
    final processTargetBytes = _processTargetBytesFor(config.rowCount);
    final processLineCount = _processLineCountFor(processTargetBytes);
    final successController = ProcessTaskController(
      id: 'sb9-success',
      label: 'SB.9 success',
      maxOutputEntries: processLineCount + (processLineCount ~/ 4) + 128,
      maxEventEntries: processLineCount + (processLineCount ~/ 4) + 256,
      maxOutputLineLength: 512,
    );
    final failureController = ProcessTaskController(
      id: 'sb9-failure',
      label: 'SB.9 failure',
      maxOutputEntries: 64,
      maxEventEntries: 128,
      maxOutputLineLength: 512,
    );
    final cancelController = ProcessTaskController(
      id: 'sb9-cancel',
      label: 'SB.9 cancel',
      maxOutputEntries: 64,
      maxEventEntries: 128,
      maxOutputLineLength: 512,
    );
    final terminalBuffer = LogBuffer(
      capacity: _terminalOutputLineCountFor(config.rowCount) + 64,
    );
    final successOutputController = LogRegionController(
      selectedIndex: processLineCount,
      followTail: false,
    );
    final terminalOutputController = LogRegionController(followTail: true);

    final processRun = Stopwatch()..start();
    final successResult = await successController.startProcess(
      _subprocessCommand(script, 'success', ['$processLineCount']),
      terminalDriver: driver,
      handoffTerminal: true,
    );
    processRun.stop();
    successOutputController.selectedIndex = successController.output.isEmpty
        ? 0
        : successController.output.length - 1;

    final failureRun = Stopwatch()..start();
    final failureResult = await failureController.startProcess(
      _subprocessCommand(script, 'failure'),
      terminalDriver: driver,
      handoffTerminal: true,
    );
    failureRun.stop();

    final cancelFuture = cancelController.startProcess(
      _subprocessCommand(script, 'slow'),
      terminalDriver: driver,
      handoffTerminal: true,
    );
    final cancelOutputObserved = await _waitForTaskOutput(
      cancelController,
      (entry) => entry.text == 'ready',
    );
    final cancelProcess = cancelController.process;
    final expectedResumeCount = driver.handoffResumeCallCount + 1;
    final cancelLatency = Stopwatch()..start();
    cancelController.cancel();
    final cancelResult = await cancelFuture;
    if (cancelProcess != null) {
      cancelProcessExitCode = await cancelProcess.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          cancelProcess.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    final cancelHandoffRestored = await _waitForHandoffResume(
      driver,
      expectedResumeCount,
    );
    cancelLatency.stop();

    final editorHandoff = Stopwatch()..start();
    final editorResult = await editTextInExternalEditor(
      initialText: 'draft',
      terminalDriver: driver,
      command: const ExternalEditorCommand.executable('fake-editor', [
        '--wait',
      ]),
      fileName: 'sb9-edit.txt',
      tempFileFactory: (_) async {
        final file = File('${tempDir.path}${Platform.pathSeparator}edit.txt');
        return ExternalEditorTempFile(file: file);
      },
      processRunner: (command) async {
        final file = File(command.arguments.last);
        await file.writeAsString('${await file.readAsString()} edited');
        return 0;
      },
    );
    editorHandoff.stop();

    final terminalLineCount = _terminalOutputLineCountFor(config.rowCount);
    final terminalBatchSize = _terminalStreamBatchSizeFor(terminalLineCount);
    final streamFrameUs = <int>[];
    var maxStreamAnsiBytes = 0;
    var unsafeFrameCount = 0;

    tester.pumpWidget(
      _TerminalOutputHarness(
        buffer: terminalBuffer,
        controller: terminalOutputController,
      ),
    );
    final initialFrame = tester.render(size: config.terminalSize);
    for (var start = 0; start < terminalLineCount; start += terminalBatchSize) {
      final end = _min(start + terminalBatchSize, terminalLineCount);
      for (var index = start; index < end; index++) {
        terminalBuffer.add(_terminalOutputLine(index, config.seed));
      }
      final frameWatch = Stopwatch()..start();
      tester.pump();
      final frame = tester.render(size: config.terminalSize);
      frameWatch.stop();
      streamFrameUs.add(frameWatch.elapsedMicroseconds);
      final ansiBytes = _ansiBytes(frame, config.terminalSize);
      if (ansiBytes > maxStreamAnsiBytes) maxStreamAnsiBytes = ansiBytes;
      if (_containsUnsafeTerminalPayload(
        _visibleText(frame, config.terminalSize),
      )) {
        unsafeFrameCount += 1;
      }
    }

    final processPanelRender = Stopwatch()..start();
    tester.pumpWidget(
      _SubprocessOutputHarness(
        successController: successController,
        failureController: failureController,
        cancelController: cancelController,
        terminalBuffer: terminalBuffer,
        successOutputController: successOutputController,
        terminalOutputController: terminalOutputController,
      ),
    );
    final processPanelFrame = tester.render(size: config.terminalSize);
    processPanelRender.stop();

    final copy = Stopwatch()..start();
    tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await Future<void>.delayed(Duration.zero);
    copy.stop();

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final taskNodes = tree.byRole(SemanticRole.task).toList(growable: false);
    final logNodes = tree.byRole(SemanticRole.log).toList(growable: false);
    semantics.stop();

    final terminalOutputRender = Stopwatch()..start();
    tester.pumpWidget(
      _TerminalOutputHarness(
        buffer: terminalBuffer,
        controller: terminalOutputController,
      ),
    );
    final terminalOutputFrame = tester.render(size: config.terminalSize);
    terminalOutputRender.stop();
    total.stop();

    final visibleProcess = _visibleText(processPanelFrame, config.terminalSize);
    final visibleTerminal = _visibleText(
      terminalOutputFrame,
      config.terminalSize,
    );
    final copiedText = clipboard.lastWritten ?? '';
    final unsafeArtifactLeakCount =
        _unsafeLeakCount(visibleProcess) +
        _unsafeLeakCount(visibleTerminal) +
        _unsafeLeakCount(copiedText) +
        _semanticUnsafeLeakCount(tree);
    final sanitizedOutputCount = _sanitizedTaskOutputCount(successController);
    final truncatedOutputCount = _truncatedTaskOutputCount(successController);
    final terminalModeRestored =
        driver.isActive &&
        cancelHandoffRestored &&
        driver.handoffCallCount == 4 &&
        driver.handoffSuspendCallCount == 4 &&
        driver.handoffResumeCallCount == 4;
    final failureExitCode = _processExitCode(failureController);
    final correct =
        successResult.succeeded &&
        failureResult.failed &&
        cancelResult.canceled &&
        editorResult.succeeded &&
        editorResult.changed &&
        failureExitCode == 7 &&
        cancelOutputObserved &&
        terminalModeRestored &&
        processPanelFrame.size == config.terminalSize &&
        terminalOutputFrame.size == config.terminalSize &&
        taskNodes.length == 3 &&
        logNodes.isNotEmpty &&
        successController.output.isNotEmpty &&
        failureController.output.isNotEmpty &&
        cancelController.output.isNotEmpty &&
        sanitizedOutputCount > 0 &&
        _stderrTaskOutputCount(successController) > 0 &&
        unsafeArtifactLeakCount == 0 &&
        unsafeFrameCount == 0 &&
        copiedText.isNotEmpty &&
        !_containsUnsafeTerminalPayload(copiedText) &&
        streamFrameUs.isNotEmpty;

    successController.dispose();
    failureController.dispose();
    cancelController.dispose();

    return _SubprocessOutputJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      processRunUs: processRun.elapsedMicroseconds,
      failureRunUs: failureRun.elapsedMicroseconds,
      cancelLatencyUs: cancelLatency.elapsedMicroseconds,
      editorHandoffUs: editorHandoff.elapsedMicroseconds,
      streamFrameUs: List<int>.unmodifiable(streamFrameUs),
      processPanelRenderUs: processPanelRender.elapsedMicroseconds,
      terminalOutputRenderUs: terminalOutputRender.elapsedMicroseconds,
      copySelectedUs: copy.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      processLineCount: processLineCount,
      processTargetBytes: processTargetBytes,
      capturedOutputBytes: _taskOutputUtf8Bytes(successController),
      capturedOriginalBytes: _taskOutputOriginalBytes(successController),
      processOutputCount: successController.output.length,
      stderrOutputCount: _stderrTaskOutputCount(successController),
      sanitizedOutputCount: sanitizedOutputCount,
      truncatedOutputCount: truncatedOutputCount,
      unsafeSequenceBlockCount: sanitizedOutputCount,
      failureExitCode: failureExitCode,
      failureOutputCount: failureController.output.length,
      cancelOutputObserved: cancelOutputObserved,
      cancelProcessExitCode: cancelProcessExitCode,
      terminalModeRestored: terminalModeRestored,
      handoffCallCount: driver.handoffCallCount,
      handoffSuspendCallCount: driver.handoffSuspendCallCount,
      handoffResumeCallCount: driver.handoffResumeCallCount,
      terminalOutputLineCount: terminalLineCount,
      terminalStreamBatchCount: streamFrameUs.length,
      semanticNodeCount: tree.nodes.length,
      taskSemanticCount: taskNodes.length,
      logSemanticCount: logNodes.length,
      initialAnsiBytes: _ansiBytes(initialFrame, config.terminalSize),
      maxStreamAnsiBytes: maxStreamAnsiBytes,
      processPanelAnsiBytes: _ansiBytes(processPanelFrame, config.terminalSize),
      terminalOutputAnsiBytes: _ansiBytes(
        terminalOutputFrame,
        config.terminalSize,
      ),
      unsafeFrameCount: unsafeFrameCount,
      unsafeArtifactLeakCount: unsafeArtifactLeakCount,
      copiedByteCount: utf8.encode(copiedText).length,
      editorChanged: editorResult.changed,
      correct: correct,
    );
  } finally {
    Clipboard.instance = originalClipboard;
    await driver.restore();
    await driver.dispose();
    tester.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

final class _SubprocessOutputHarness extends StatelessWidget {
  const _SubprocessOutputHarness({
    required this.successController,
    required this.failureController,
    required this.cancelController,
    required this.terminalBuffer,
    required this.successOutputController,
    required this.terminalOutputController,
  });

  final ProcessTaskController successController;
  final ProcessTaskController failureController;
  final ProcessTaskController cancelController;
  final LogBuffer terminalBuffer;
  final LogRegionController successOutputController;
  final LogRegionController terminalOutputController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('SB.9 subprocess handoff and untrusted output'),
        Expanded(
          child: ProcessPanel(
            controller: successController,
            outputController: successOutputController,
            autofocus: true,
            showProgress: false,
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
        Expanded(
          child: ProcessPanel(
            controller: failureController,
            showProgress: false,
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
        Expanded(
          child: ProcessPanel(
            controller: cancelController,
            showProgress: false,
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
        Expanded(
          child: TerminalOutputRegion(
            buffer: terminalBuffer,
            controller: terminalOutputController,
            label: 'Captured terminal output',
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
      ],
    );
  }
}

final class _TerminalOutputHarness extends StatelessWidget {
  const _TerminalOutputHarness({
    required this.buffer,
    required this.controller,
  });

  final LogBuffer buffer;
  final LogRegionController controller;

  @override
  Widget build(BuildContext context) {
    return TerminalOutputRegion(
      buffer: buffer,
      controller: controller,
      autofocus: true,
      label: 'Streaming terminal output',
      copyOptions: const LogRegionCopyOptions(
        clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
      ),
    );
  }
}

Future<File> _writeSubprocessScenarioScript(Directory directory) async {
  final file = File(
    '${directory.path}${Platform.pathSeparator}sb9_process_fixture.dart',
  );
  await file.writeAsString(r'''
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'success' : args.first;
  switch (mode) {
    case 'success':
      final lineCount = args.length > 1 ? int.parse(args[1]) : 256;
      final fill = List<String>.filled(180, 'x').join();
      for (var i = 0; i < lineCount; i++) {
        stdout.writeln('\x1B[32mOUT $i\x1B[0m payload=$fill');
        if (i % 17 == 0) {
          stderr.writeln('\x1B]52;c;SECRET_STREAM_$i\x07 stderr payload $fill');
        }
        if (i % 41 == 0) {
          stdout.writeln('\x1BPqDCS_SECRET_$i\x1B\\ dcs payload');
        }
        if (i % 73 == 0) {
          stdout.writeln('\x1B_APC_SECRET_$i\x1B\\ apc payload');
        }
      }
      stdout.writeln('\x1B]52;c;SECRET_FINAL\x07 final unsafe line');
      return;
    case 'failure':
      stderr.writeln('\x1B]52;c;SECRET_FAILURE\x07 non-zero exit');
      exitCode = 7;
      return;
    case 'slow':
      stdout.writeln('ready');
      await stdout.flush();
      await Future<void>.delayed(const Duration(seconds: 30));
      return;
    default:
      stderr.writeln('unknown mode $mode');
      exitCode = 64;
      return;
  }
}
''');
  return file;
}

ProcessTaskCommand _subprocessCommand(
  File script,
  String mode, [
  List<String> arguments = const <String>[],
]) {
  return ProcessTaskCommand(Platform.resolvedExecutable, [
    script.path,
    mode,
    ...arguments,
  ]);
}

int _processTargetBytesFor(int rowCount) {
  final scaled = rowCount * 10;
  if (scaled < 64 * 1024) return 64 * 1024;
  if (scaled > 1024 * 1024) return 1024 * 1024;
  return scaled;
}

int _processLineCountFor(int targetBytes) {
  final count = (targetBytes / 256).ceil();
  if (count < 128) return 128;
  return count;
}

int _terminalOutputLineCountFor(int rowCount) {
  final scaled = rowCount ~/ 50;
  if (scaled < 128) return 128;
  if (scaled > 2048) return 2048;
  return scaled;
}

int _terminalStreamBatchSizeFor(int lineCount) {
  final scaled = lineCount ~/ 16;
  if (scaled < 16) return 16;
  if (scaled > 128) return 128;
  return scaled;
}

LogLine _terminalOutputLine(int index, int seed) {
  final source = index % 11 == 0 ? LogSource.stderr : LogSource.stdout;
  final unsafe = index % 19 == 0 || index % 43 == 0;
  final prefix = source == LogSource.stderr ? 'ERR' : 'OUT';
  final payload = unsafe
      ? '$prefix-$index \x1b]52;c;SECRET_TERMINAL_${index + seed}\x07 payload\ncontinued'
      : '$prefix-$index streamed output shard ${(index + seed) % 97}';
  return LogLine(payload, source);
}

Future<bool> _waitForTaskOutput(
  ProcessTaskController controller,
  bool Function(TaskOutput entry) predicate,
) async {
  if (controller.output.any(predicate)) return true;
  final completer = Completer<bool>();
  late final Timer timer;
  void listener() {
    if (completer.isCompleted) return;
    if (controller.output.any(predicate)) {
      timer.cancel();
      controller.removeListener(listener);
      completer.complete(true);
    }
  }

  timer = Timer(const Duration(seconds: 5), () {
    if (completer.isCompleted) return;
    controller.removeListener(listener);
    completer.complete(false);
  });
  controller.addListener(listener);
  listener();
  return completer.future;
}

Future<bool> _waitForHandoffResume(
  FakeTerminalDriver driver,
  int expectedResumeCount,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (driver.handoffResumeCallCount >= expectedResumeCount &&
        driver.isActive) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return driver.handoffResumeCallCount >= expectedResumeCount &&
      driver.isActive;
}

int _taskOutputUtf8Bytes(ProcessTaskController controller) {
  var total = 0;
  for (final entry in controller.output) {
    total += utf8.encode(entry.text).length;
  }
  return total;
}

int _taskOutputOriginalBytes(ProcessTaskController controller) {
  var total = 0;
  for (final entry in controller.output) {
    total += entry.originalLength ?? entry.text.length;
  }
  return total;
}

int _sanitizedTaskOutputCount(ProcessTaskController controller) {
  return controller.output.where((entry) => entry.sanitized).length;
}

int _truncatedTaskOutputCount(ProcessTaskController controller) {
  return controller.output.where((entry) => entry.truncated).length;
}

int _stderrTaskOutputCount(ProcessTaskController controller) {
  return controller.output.where((entry) => entry.source == 'stderr').length;
}

int _processExitCode(ProcessTaskController controller) {
  final value = controller.value;
  if (value != null) return value.exitCode;
  final error = controller.error;
  if (error is ProcessTaskException) return error.result.exitCode;
  return -1;
}

int _unsafeLeakCount(String text) =>
    _containsUnsafeTerminalPayload(text) ? 1 : 0;

int _semanticUnsafeLeakCount(SemanticTree tree) {
  var count = 0;
  for (final node in tree.nodes) {
    if (_semanticValueUnsafe(node.label) ||
        _semanticValueUnsafe(node.value) ||
        _semanticValueUnsafe(node.hint) ||
        _semanticValueUnsafe(node.validationError)) {
      count += 1;
    }
    for (final value in node.state.values.values) {
      if (_semanticValueUnsafe(value)) count += 1;
    }
  }
  return count;
}

bool _semanticValueUnsafe(Object? value) {
  if (value == null) return false;
  return _containsUnsafeTerminalPayload(value.toString());
}

final class _SubprocessOutputJourneySample {
  const _SubprocessOutputJourneySample({
    required this.totalJourneyUs,
    required this.processRunUs,
    required this.failureRunUs,
    required this.cancelLatencyUs,
    required this.editorHandoffUs,
    required this.streamFrameUs,
    required this.processPanelRenderUs,
    required this.terminalOutputRenderUs,
    required this.copySelectedUs,
    required this.semanticQueryUs,
    required this.processLineCount,
    required this.processTargetBytes,
    required this.capturedOutputBytes,
    required this.capturedOriginalBytes,
    required this.processOutputCount,
    required this.stderrOutputCount,
    required this.sanitizedOutputCount,
    required this.truncatedOutputCount,
    required this.unsafeSequenceBlockCount,
    required this.failureExitCode,
    required this.failureOutputCount,
    required this.cancelOutputObserved,
    required this.cancelProcessExitCode,
    required this.terminalModeRestored,
    required this.handoffCallCount,
    required this.handoffSuspendCallCount,
    required this.handoffResumeCallCount,
    required this.terminalOutputLineCount,
    required this.terminalStreamBatchCount,
    required this.semanticNodeCount,
    required this.taskSemanticCount,
    required this.logSemanticCount,
    required this.initialAnsiBytes,
    required this.maxStreamAnsiBytes,
    required this.processPanelAnsiBytes,
    required this.terminalOutputAnsiBytes,
    required this.unsafeFrameCount,
    required this.unsafeArtifactLeakCount,
    required this.copiedByteCount,
    required this.editorChanged,
    required this.correct,
  });

  final int totalJourneyUs;
  final int processRunUs;
  final int failureRunUs;
  final int cancelLatencyUs;
  final int editorHandoffUs;
  final List<int> streamFrameUs;
  final int processPanelRenderUs;
  final int terminalOutputRenderUs;
  final int copySelectedUs;
  final int semanticQueryUs;
  final int processLineCount;
  final int processTargetBytes;
  final int capturedOutputBytes;
  final int capturedOriginalBytes;
  final int processOutputCount;
  final int stderrOutputCount;
  final int sanitizedOutputCount;
  final int truncatedOutputCount;
  final int unsafeSequenceBlockCount;
  final int failureExitCode;
  final int failureOutputCount;
  final bool cancelOutputObserved;
  final int cancelProcessExitCode;
  final bool terminalModeRestored;
  final int handoffCallCount;
  final int handoffSuspendCallCount;
  final int handoffResumeCallCount;
  final int terminalOutputLineCount;
  final int terminalStreamBatchCount;
  final int semanticNodeCount;
  final int taskSemanticCount;
  final int logSemanticCount;
  final int initialAnsiBytes;
  final int maxStreamAnsiBytes;
  final int processPanelAnsiBytes;
  final int terminalOutputAnsiBytes;
  final int unsafeFrameCount;
  final int unsafeArtifactLeakCount;
  final int copiedByteCount;
  final bool editorChanged;
  final bool correct;
}

final class _TreeTableHierarchyScenario implements _ScenarioBenchmark {
  const _TreeTableHierarchyScenario();

  @override
  String get id => 'SB.11';

  @override
  String get name => 'TreeTable Hierarchy Filter And Copy';

  @override
  Future<_ScenarioResult> run(_ScenarioConfig config) async {
    for (var i = 0; i < config.warmupIterations; i++) {
      await _runTreeTableJourney(config);
    }

    final startedAt = DateTime.now().toUtc();
    final rssBefore = ProcessInfo.currentRss;
    final total = Stopwatch()..start();
    final samples = <_TreeTableJourneySample>[];
    for (var i = 0; i < config.measuredIterations; i++) {
      samples.add(await _runTreeTableJourney(config));
    }
    total.stop();
    final rssAfter = ProcessInfo.currentRss;

    final fixtureBuild = _Stats.from(
      samples.map((sample) => sample.fixtureBuildUs),
    );
    final indexBuild = _Stats.from(
      samples.map((sample) => sample.indexBuildUs),
    );
    final mount = _Stats.from(samples.map((sample) => sample.mountUs));
    final firstRender = _Stats.from(
      samples.map((sample) => sample.firstRenderUs),
    );
    final expandBranch = _Stats.from(
      samples.map((sample) => sample.expandBranchUs),
    );
    final pageMove = _Stats.from(samples.map((sample) => sample.pageMoveUs));
    final jumpToEnd = _Stats.from(samples.map((sample) => sample.jumpToEndUs));
    final filterQuery = _Stats.from(
      samples.map((sample) => sample.filterQueryUs),
    );
    final copySelectedRow = _Stats.from(
      samples.map((sample) => sample.copySelectedRowUs),
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
      rowCount: config.rowCount,
      metrics: <String, Object?>{
        'journeyUs': journey.toJson(),
        'fixtureBuildUs': fixtureBuild.toJson(),
        'indexBuildUs': indexBuild.toJson(),
        'mountUs': mount.toJson(),
        'firstRenderUs': firstRender.toJson(),
        'expandBranchUs': expandBranch.toJson(),
        'pageMoveUs': pageMove.toJson(),
        'jumpToEndUs': jumpToEnd.toJson(),
        'filterQueryUs': filterQuery.toJson(),
        'copySelectedRowUs': copySelectedRow.toJson(),
        'semanticQueryUs': semanticQuery.toJson(),
        'initialAnsiBytes': last.initialAnsiBytes,
        'expandedAnsiBytes': last.expandedAnsiBytes,
        'filteredAnsiBytes': last.filteredAnsiBytes,
        'semanticNodeCount': last.semanticNodeCount,
        'initialRowCount': last.initialRowCount,
        'expandedRowCount': last.expandedRowCount,
        'filteredRowCount': last.filteredRowCount,
        'visibleRangeStart': last.visibleRangeStart,
        'visibleRangeEnd': last.visibleRangeEnd,
        'filterVisibleRangeStart': last.filterVisibleRangeStart,
        'filterVisibleRangeEnd': last.filterVisibleRangeEnd,
        'selectedKey': last.selectedKey,
        'targetKey': last.targetKey,
        'rootCount': last.rootCount,
        'treeNodeCount': last.treeNodeCount,
        'searchIndexRowCount': last.searchIndexRowCount,
        'cellBuilderCalls': last.cellBuilderCalls,
        'uniqueNodesRequested': last.uniqueNodesRequested,
        'sanitizingFixtureRows': last.sanitizingFixtureRows,
        'copiedByteCount': last.copiedByteCount,
        'indexTaskEventCount': last.indexTaskEventCount,
        'indexProgressCurrent': last.indexProgressCurrent,
        'rssDeltaBytes': rssAfter - rssBefore,
      },
      thresholds: const <String, Object?>{
        'candidateExpandBranchP95Us': 16000,
        'candidatePageMoveP95Us': 16000,
        'candidateJumpToEndP95Us': 16000,
        'candidateFilterQueryP95Us': 120000,
        'candidateCopySelectedRowP95Us': 16000,
        'candidateSemanticQueryP95Us': 16000,
        'enforced': false,
      },
      pass: correct,
      notes: const <String>[
        'Candidate thresholds are informational until stable baselines exist.',
        'Scenario uses a 100k-leaf hierarchy plus branch nodes.',
        'Scenario uses TreeTableSearchIndex so filterQueryUs measures repeated query cost after index construction.',
        'Search-index build runs cooperatively through TaskController.',
        'Fixture includes ANSI/OSC/newline payloads to verify sanitized visible, copied, and searched output.',
      ],
    );
  }
}

Future<_TreeTableJourneySample> _runTreeTableJourney(
  _ScenarioConfig config,
) async {
  final tester = FleuryTester(viewportSize: config.terminalSize);
  final originalClipboard = Clipboard.instance;
  final clipboard = TestClipboard();
  Clipboard.instance = clipboard;
  final requestedNodes = <Object>{};
  var cellBuilderCalls = 0;
  final total = Stopwatch()..start();
  try {
    final fixture = _TreeFixture(seed: config.seed, leafCount: config.rowCount);
    final fixtureBuild = Stopwatch()..start();
    final roots = fixture.roots();
    fixtureBuild.stop();

    String cellBuilder(TreeTableNode<int> node, String columnId) {
      cellBuilderCalls += 1;
      requestedNodes.add(node.key);
      return node.cells[columnId] ?? '';
    }

    final indexTask = TaskController<TreeTableSearchIndex<int>>(
      id: 'sb11-tree-index',
      label: 'SB.11 tree index',
    );
    final indexBuild = Stopwatch()..start();
    final indexResult = await indexTask.start(
      (context) => TreeTableSearchIndex.buildCooperatively<int>(
        roots: roots,
        columns: _treeColumns,
        cellBuilder: cellBuilder,
        context: context,
        yieldPolicy: _indexYieldPolicy,
        progressLabel: 'index tree',
      ),
    );
    indexBuild.stop();
    final searchIndex = indexResult.value;
    if (searchIndex == null) {
      throw StateError('SB.11 tree index build did not produce an index.');
    }

    final controller = TreeTableController(expandedKeys: {fixture.groupKey(0)});
    final mount = Stopwatch()..start();
    tester.pumpWidget(
      _TreeTableHarness(
        roots: roots,
        controller: controller,
        cellBuilder: cellBuilder,
        searchIndex: searchIndex,
      ),
    );
    mount.stop();

    final firstRender = Stopwatch()..start();
    final initial = tester.render(size: config.terminalSize);
    firstRender.stop();
    final initialRows = buildTreeTableRows<int>(
      roots: roots,
      columns: _treeColumns,
      expandedKeys: controller.expandedKeys,
      cellBuilder: cellBuilder,
    );

    final expand = Stopwatch()..start();
    controller.selectedIndex = initialRows.length;
    tester.pump();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    tester.render(size: config.terminalSize);
    expand.stop();
    final expandedRows = buildTreeTableRows<int>(
      roots: roots,
      columns: _treeColumns,
      expandedKeys: controller.expandedKeys,
      cellBuilder: cellBuilder,
    );

    final page = Stopwatch()..start();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.pageDown));
    tester.render(size: config.terminalSize);
    page.stop();

    final jump = Stopwatch()..start();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
    final expandedFrame = tester.render(size: config.terminalSize);
    jump.stop();

    final targetRow = config.rowCount - 1;
    final targetKey = fixture.leafKey(targetRow);
    final targetQuery = fixture.targetQuery;
    final filterController = TreeTableController(selectedIndex: 1);
    final filter = Stopwatch()..start();
    tester.pumpWidget(
      _TreeTableHarness(
        roots: roots,
        controller: filterController,
        cellBuilder: cellBuilder,
        searchIndex: searchIndex,
        filter: TreeTableFilterDescriptor(
          query: targetQuery,
          mode: TreeTableFilterMode.exactToken,
        ),
      ),
    );
    final filteredFrame = tester.render(size: config.terminalSize);
    filter.stop();
    final filteredRows = buildTreeTableRows<int>(
      roots: roots,
      columns: _treeColumns,
      cellBuilder: cellBuilder,
      filter: TreeTableFilterDescriptor(
        query: targetQuery,
        mode: TreeTableFilterMode.exactToken,
      ),
      searchIndex: searchIndex,
    );

    final copy = Stopwatch()..start();
    tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await Future<void>.delayed(Duration.zero);
    copy.stop();

    final semantics = Stopwatch()..start();
    final tree = tester.semantics();
    final semanticTree = tree.single(role: SemanticRole.tree);
    final selected = tree.single(
      role: SemanticRole.treeItem,
      selected: true,
      action: SemanticAction.copy,
    );
    semantics.stop();
    total.stop();

    final copiedText = clipboard.lastWritten ?? '';
    final filteredText = _visibleText(filteredFrame, config.terminalSize);
    final initialVisibleRange = controller.visibleRange;
    final filterVisibleRange = filterController.visibleRange;
    final visibleStart = initialVisibleRange?.first ?? -1;
    final visibleEnd = initialVisibleRange?.last ?? -1;
    final filterVisibleStart = filterVisibleRange?.first ?? -1;
    final filterVisibleEnd = filterVisibleRange?.last ?? -1;
    final expectedInitialRows = fixture.groupCount + fixture.groupLeafCount(0);
    final expectedExpandedRows =
        fixture.groupCount +
        fixture.groupLeafCount(0) +
        fixture.groupLeafCount(1);
    final correct =
        initialRows.length == expectedInitialRows &&
        expandedRows.length == expectedExpandedRows &&
        filteredRows.length == 2 &&
        searchIndex.rowCount == fixture.nodeCount &&
        semanticTree.state.collectionRowCount == filteredRows.length &&
        semanticTree.state.collectionColumnCount == _treeColumns.length &&
        semanticTree.state.filterText == targetQuery &&
        semanticTree.actions.contains(SemanticAction.copy) &&
        selected.state['rowKey'] == targetKey &&
        selected.state['depth'] == 1 &&
        selected.state['expanded'] == false &&
        copiedText.startsWith('Component\tStatus\tOwner') &&
        copiedText.contains(targetKey) &&
        !copiedText.contains('secret') &&
        !copiedText.contains('\x1b') &&
        filteredText.contains(targetKey) &&
        !filteredText.contains('secret') &&
        !filteredText.contains('\x1b') &&
        visibleStart >= 0 &&
        visibleEnd >= visibleStart &&
        filterVisibleStart >= 0 &&
        filterVisibleStart <= 1 &&
        filterVisibleEnd == 1 &&
        indexTask.status == TaskStatus.succeeded &&
        indexTask.progress?.current == searchIndex.rowCount;

    final sample = _TreeTableJourneySample(
      totalJourneyUs: total.elapsedMicroseconds,
      fixtureBuildUs: fixtureBuild.elapsedMicroseconds,
      indexBuildUs: indexBuild.elapsedMicroseconds,
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      expandBranchUs: expand.elapsedMicroseconds,
      pageMoveUs: page.elapsedMicroseconds,
      jumpToEndUs: jump.elapsedMicroseconds,
      filterQueryUs: filter.elapsedMicroseconds,
      copySelectedRowUs: copy.elapsedMicroseconds,
      semanticQueryUs: semantics.elapsedMicroseconds,
      initialAnsiBytes: _ansiBytes(initial, config.terminalSize),
      expandedAnsiBytes: _ansiBytes(expandedFrame, config.terminalSize),
      filteredAnsiBytes: _ansiBytes(filteredFrame, config.terminalSize),
      semanticNodeCount: tree.nodes.length,
      initialRowCount: initialRows.length,
      expandedRowCount: expandedRows.length,
      filteredRowCount: filteredRows.length,
      visibleRangeStart: visibleStart,
      visibleRangeEnd: visibleEnd,
      filterVisibleRangeStart: filterVisibleStart,
      filterVisibleRangeEnd: filterVisibleEnd,
      selectedKey: selected.state['rowKey'].toString(),
      targetKey: targetKey,
      rootCount: fixture.groupCount,
      treeNodeCount: fixture.nodeCount,
      searchIndexRowCount: searchIndex.rowCount,
      cellBuilderCalls: cellBuilderCalls,
      uniqueNodesRequested: requestedNodes.length,
      sanitizingFixtureRows: fixture.sanitizingLeafCount,
      copiedByteCount: utf8.encode(copiedText).length,
      indexTaskEventCount: indexTask.events.length,
      indexProgressCurrent: (indexTask.progress?.current ?? -1).toInt(),
      correct: correct,
    );
    indexTask.dispose();
    return sample;
  } finally {
    Clipboard.instance = originalClipboard;
    tester.dispose();
  }
}

final class _TreeTableHarness extends StatelessWidget {
  const _TreeTableHarness({
    required this.roots,
    required this.controller,
    required this.cellBuilder,
    required this.searchIndex,
    this.filter,
  });

  final List<TreeTableNode<int>> roots;
  final TreeTableController controller;
  final TreeTableCellBuilder<int> cellBuilder;
  final TreeTableSearchIndex<int> searchIndex;
  final TreeTableFilterDescriptor? filter;

  @override
  Widget build(BuildContext context) {
    return TreeTable<int>(
      roots: roots,
      columns: _treeColumns,
      controller: controller,
      cellBuilder: cellBuilder,
      searchIndex: searchIndex,
      filter: filter,
      autofocus: true,
      label: 'Scenario tree table',
      maxVisible: 24,
      copyOptions: const TreeTableCopyOptions(
        clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
      ),
    );
  }
}

const _treeColumns = [
  DataTableColumn(
    id: 'component',
    title: 'Component',
    width: FixedColumnWidth(36),
  ),
  DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(9)),
  DataTableColumn(id: 'owner', title: 'Owner', width: FixedColumnWidth(10)),
  DataTableColumn(
    id: 'duration',
    title: 'Duration',
    width: FixedColumnWidth(8),
  ),
  DataTableColumn(id: 'notes', title: 'Notes', width: FlexColumnWidth(2)),
];

final class _TreeFixture {
  const _TreeFixture({required this.seed, required this.leafCount});

  static const groupSize = 1000;

  final int seed;
  final int leafCount;

  int get groupCount => (leafCount + groupSize - 1) ~/ groupSize;
  int get nodeCount => leafCount + groupCount;

  int get sanitizingLeafCount {
    var count = 0;
    for (var row = 0; row < leafCount; row++) {
      if (_isSanitizingLeaf(row)) count += 1;
    }
    return count;
  }

  String groupKey(int group) => 'GROUP-${group.toString().padLeft(3, '0')}';
  String leafKey(int row) => 'TASK-${100000 + row}';
  String get targetQuery => 'zz-target-${100000 + leafCount - 1}';

  int groupLeafCount(int group) {
    final start = group * groupSize;
    final remaining = leafCount - start;
    if (remaining <= 0) return 0;
    return remaining < groupSize ? remaining : groupSize;
  }

  List<TreeTableNode<int>> roots() {
    return List<TreeTableNode<int>>.generate(
      groupCount,
      _group,
      growable: false,
    );
  }

  TreeTableNode<int> _group(int group) {
    final start = group * groupSize;
    final count = groupLeafCount(group);
    return TreeTableNode<int>(
      key: groupKey(group),
      label: 'Component group ${group.toString().padLeft(3, '0')}',
      cells: {
        'status': count == groupSize ? 'ready' : 'partial',
        'owner': _owners[(group + seed) % _owners.length],
        'duration': '${(group % 7).toString().padLeft(2, '0')}:00',
        'notes': '$count tasks',
      },
      metadata: {'fixtureGroup': group},
      children: List<TreeTableNode<int>>.generate(
        count,
        (offset) => _leaf(start + offset),
        growable: false,
      ),
    );
  }

  TreeTableNode<int> _leaf(int row) {
    final unsafe = _isSanitizingLeaf(row);
    final key = leafKey(row);
    final lane = _lanes[(row ~/ 13 + seed) % _lanes.length];
    final targetSuffix = row == leafCount - 1 ? ' $targetQuery' : '';
    final suffix = unsafe
        ? ' unsafe\x1b]52;c;secret-$row\x07 payload\ncontinued'
        : ' $lane$targetSuffix';
    return TreeTableNode<int>(
      key: key,
      label: 'Task $key$suffix',
      value: row,
      cells: {
        'status': _statuses[(row + seed) % _statuses.length],
        'owner': _owners[(row + seed * 7) % _owners.length],
        'duration':
            '${(row % 4).toString().padLeft(2, '0')}:'
            '${(row % 60).toString().padLeft(2, '0')}',
        'notes': 'shard ${(row + seed) % 4096} $lane',
      },
      metadata: {'fixtureRow': row, 'unsafeFixture': unsafe},
    );
  }

  bool _isSanitizingLeaf(int row) => row % 97 == 0 || row % 389 == 0;
}

final class _TreeTableJourneySample {
  const _TreeTableJourneySample({
    required this.totalJourneyUs,
    required this.fixtureBuildUs,
    required this.indexBuildUs,
    required this.mountUs,
    required this.firstRenderUs,
    required this.expandBranchUs,
    required this.pageMoveUs,
    required this.jumpToEndUs,
    required this.filterQueryUs,
    required this.copySelectedRowUs,
    required this.semanticQueryUs,
    required this.initialAnsiBytes,
    required this.expandedAnsiBytes,
    required this.filteredAnsiBytes,
    required this.semanticNodeCount,
    required this.initialRowCount,
    required this.expandedRowCount,
    required this.filteredRowCount,
    required this.visibleRangeStart,
    required this.visibleRangeEnd,
    required this.filterVisibleRangeStart,
    required this.filterVisibleRangeEnd,
    required this.selectedKey,
    required this.targetKey,
    required this.rootCount,
    required this.treeNodeCount,
    required this.searchIndexRowCount,
    required this.cellBuilderCalls,
    required this.uniqueNodesRequested,
    required this.sanitizingFixtureRows,
    required this.copiedByteCount,
    required this.indexTaskEventCount,
    required this.indexProgressCurrent,
    required this.correct,
  });

  final int totalJourneyUs;
  final int fixtureBuildUs;
  final int indexBuildUs;
  final int mountUs;
  final int firstRenderUs;
  final int expandBranchUs;
  final int pageMoveUs;
  final int jumpToEndUs;
  final int filterQueryUs;
  final int copySelectedRowUs;
  final int semanticQueryUs;
  final int initialAnsiBytes;
  final int expandedAnsiBytes;
  final int filteredAnsiBytes;
  final int semanticNodeCount;
  final int initialRowCount;
  final int expandedRowCount;
  final int filteredRowCount;
  final int visibleRangeStart;
  final int visibleRangeEnd;
  final int filterVisibleRangeStart;
  final int filterVisibleRangeEnd;
  final String selectedKey;
  final String targetKey;
  final int rootCount;
  final int treeNodeCount;
  final int searchIndexRowCount;
  final int cellBuilderCalls;
  final int uniqueNodesRequested;
  final int sanitizingFixtureRows;
  final int copiedByteCount;
  final int indexTaskEventCount;
  final int indexProgressCurrent;
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
    required this.rowCount,
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
  final int rowCount;
  final Map<String, Object?> metrics;
  final Map<String, Object?> thresholds;
  final bool pass;
  final List<String> notes;

  String get summaryLine {
    final primary = switch (scenarioId) {
      'SB.4' => metrics['appendBurstUs'],
      'SB.5' => metrics['chunkUpdateUs'],
      'SB.6' => metrics['updateTotalUs'],
      'SB.8' => metrics['cycleUs'],
      'SB.7' => metrics['resizeFrameUs'],
      'SB.9' => metrics['processRunUs'],
      'SB.11' => metrics['filterQueryUs'],
      _ => metrics['pageMoveUs'],
    };
    final p95 = primary is Map<String, Object?> ? primary['p95'] : null;
    final status = pass ? 'pass' : 'fail';
    final label = switch (scenarioId) {
      'SB.4' => 'append_burst_p95_us',
      'SB.5' => 'chunk_update_p95_us',
      'SB.6' => 'update_total_p95_us',
      'SB.8' => 'cycle_p95_us',
      'SB.7' => 'resize_frame_p95_us',
      'SB.9' => 'process_run_p95_us',
      'SB.11' => 'filter_query_p95_us',
      _ => 'page_move_p95_us',
    };
    return '$scenarioId $scenarioName: $status, $label=$p95';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _schemaVersion,
    'scenarioId': scenarioId,
    'scenarioName': scenarioName,
    'packageVersion': _fleuryWidgetsVersion,
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
    'rowCount': rowCount,
    if (metrics['resizeEventCount'] != null)
      'resizeEventCount': metrics['resizeEventCount'],
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
  stdout.writeln('  --rows=N               Data rows. Default $_defaultRows.');
  stdout.writeln(
    '  --resize-events=N      Resize events for SB.7. Default 500.',
  );
  stdout.writeln('  --size=COLSxROWS       Terminal size. Default 120x32.');
  exit(exitCodeValue);
}
