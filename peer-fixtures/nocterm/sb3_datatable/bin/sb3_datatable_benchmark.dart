import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fleury_peer_nocterm_sb3_datatable/table_app.dart';
import 'package:nocterm/nocterm.dart';

const _schemaVersion = 1;
const _peerId = 'nocterm';
const _peerName = 'Nocterm';
const _peerVersion = '0.6.0';
const _peerUrl = 'https://pub.dev/packages/nocterm';
const _scenarioId = 'SB.3';
const _defaultWarmups = 2;
const _defaultIterations = 5;
const _defaultRows = 100000;
const _defaultSize = Size(120, 32);

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  for (var i = 0; i < options.warmupIterations; i += 1) {
    await _runSample(options);
  }

  final samples = <_Sample>[];
  for (var i = 0; i < options.measuredIterations; i += 1) {
    samples.add(await _runSample(options));
  }

  final artifact = _buildArtifact(options, samples);
  final jsonText = const JsonEncoder.withIndent('  ').convert(artifact);
  if (options.outputPath != null) {
    final output = File(options.outputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$jsonText\n');
  }

  if (options.printJson) {
    stdout.writeln(jsonText);
    return;
  }

  final metrics = artifact['metrics']! as Map<String, Object?>;
  stdout.writeln('Nocterm SB.3 data table fixture');
  stdout.writeln('Run: ${artifact['runId']}');
  stdout.writeln('Rows: ${options.rows}');
  stdout.writeln('Iterations: ${options.measuredIterations}');
  stdout.writeln('pageMoveUs p95: ${(metrics['pageMoveUs']! as Map)['p95']}');
  stdout.writeln(
    'copySelectedRowUs p95: '
    '${(metrics['copySelectedRowUs']! as Map)['p95']}',
  );
  if (options.outputPath != null) {
    stdout.writeln('Saved ${options.outputPath}');
  }
}

Future<_Sample> _runSample(_Options options) async {
  final rssBefore = ProcessInfo.currentRss;
  final tester = await NoctermTester.create(size: options.size);
  try {
    final mount = Stopwatch()..start();
    await tester.pumpComponent(
      Sb3NoctermDataTable(
        rowCount: options.rows,
        width: options.size.width.toInt(),
        height: options.size.height.toInt(),
      ),
    );
    mount.stop();
    final state = tester.findState<Sb3NoctermDataTableState>();

    final firstRender = Stopwatch()..start();
    final firstView = tester.terminalState.getText();
    firstRender.stop();

    final arrow = Stopwatch()..start();
    state.arrowDown();
    await tester.pump();
    arrow.stop();
    final arrowState = state.snapshot();
    final arrowView = tester.terminalState.getText();

    final page = Stopwatch()..start();
    state.pageDown();
    await tester.pump();
    page.stop();
    final pageState = state.snapshot();
    final pageView = tester.terminalState.getText();

    final jump = Stopwatch()..start();
    state.jumpToEnd();
    await tester.pump();
    jump.stop();
    final finalState = state.snapshot();
    final finalView = tester.terminalState.getText();

    final copy = Stopwatch()..start();
    state.copySelectedRow();
    copy.stop();
    final copied = state.lastCopiedText;

    final expectedFinalIndex = options.rows - 1;
    final expectedFinalId = rowId(expectedFinalIndex);
    final query = Stopwatch()..start();
    final selectedVisible = tester.terminalState.containsText(expectedFinalId);
    final unsafeLeakCount =
        finalState.unsafeArtifactLeakCount +
        unsafeVisibleTextCount(firstView) +
        unsafeVisibleTextCount(arrowView) +
        unsafeVisibleTextCount(pageView) +
        unsafeVisibleTextCount(finalView);
    query.stop();

    return _Sample(
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      arrowMoveUs: arrow.elapsedMicroseconds,
      pageMoveUs: page.elapsedMicroseconds,
      jumpToEndUs: jump.elapsedMicroseconds,
      copySelectedRowUs: copy.elapsedMicroseconds,
      semanticOrTestQueryUs: query.elapsedMicroseconds,
      rssDeltaBytes: math.max(0, ProcessInfo.currentRss - rssBefore),
      rowCount: finalState.rowCount,
      visibleWindowRows: finalState.visibleWindowRows,
      visibleStart: finalState.visibleStart,
      visibleEnd: finalState.visibleEnd,
      selectedRow: finalState.selectedRow,
      selectedRowId: finalState.selectedRowId,
      unsafeArtifactLeakCount: unsafeLeakCount,
      visibleWindowBounded:
          finalState.visibleWindowRows <= state.visibleCapacity(),
      selectionCorrect:
          finalState.selectedRow == expectedFinalIndex &&
          finalState.selectedRowId == expectedFinalId &&
          selectedVisible,
      copyExact:
          copied == expectedSelectedTsv(expectedFinalIndex) &&
          unsafeCopyTextCount(copied) == 0,
      arrowCorrect: arrowState.selectedRow == 1 && arrowView.contains(rowId(1)),
      pageCorrect:
          pageState.selectedRow > 1 &&
          pageView.contains(pageState.selectedRowId),
    );
  } finally {
    tester.dispose();
  }
}

Map<String, Object?> _buildArtifact(_Options options, List<_Sample> samples) {
  final packageRoot = _packageRoot();
  final appLines = _sourceLineCount('${packageRoot.path}/lib/table_app.dart');
  final benchmarkLines = _sourceLineCount(
    '${packageRoot.path}/bin/sb3_datatable_benchmark.dart',
  );
  final testLines = _sourceLineCount(
    '${packageRoot.path}/test/table_benchmark_test.dart',
  );
  final capturedAt = DateTime.now().toUtc();
  final runId = 'nocterm-sb3-datatable-${_timestampForId(capturedAt)}';
  final unsafeLeakCount = samples
      .map((sample) => sample.unsafeArtifactLeakCount)
      .reduce(math.max);
  final last = samples.last;

  return <String, Object?>{
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
      'workingDirectory': 'peer-fixtures/nocterm/sb3_datatable',
      'command': <String>[
        'dart',
        'run',
        'bin/sb3_datatable_benchmark.dart',
        '--warmup=${options.warmupIterations}',
        '--iterations=${options.measuredIterations}',
        '--rows=${options.rows}',
        '--json',
      ],
      'warmupIterations': options.warmupIterations,
      'measuredIterations': options.measuredIterations,
    },
    'metrics': <String, Object?>{
      'mountUs': _stats(samples.map((sample) => sample.mountUs)),
      'firstRenderUs': _stats(samples.map((sample) => sample.firstRenderUs)),
      'arrowMoveUs': _stats(samples.map((sample) => sample.arrowMoveUs)),
      'pageMoveUs': _stats(samples.map((sample) => sample.pageMoveUs)),
      'jumpToEndUs': _stats(samples.map((sample) => sample.jumpToEndUs)),
      'copySelectedRowUs': _stats(
        samples.map((sample) => sample.copySelectedRowUs),
      ),
      'semanticOrTestQueryUs': _stats(
        samples.map((sample) => sample.semanticOrTestQueryUs),
      ),
      'rssDeltaBytes': samples
          .map((sample) => sample.rssDeltaBytes)
          .reduce(math.max),
      'lineOfCodeCount': appLines,
      'benchmarkLineOfCodeCount': benchmarkLines,
      'testLineOfCodeCount': testLines,
      'rowCount': options.rows,
      'observedRowCount': last.rowCount,
      'visibleWindowRowEstimate': last.visibleWindowRows,
      'visibleRangeStart': last.visibleStart,
      'visibleRangeEnd': last.visibleEnd,
      'finalSelectedRow': last.selectedRow,
      'finalSelectedRowId': last.selectedRowId,
      'unsafeArtifactLeakCount': unsafeLeakCount,
    },
    'correctness': <Object?>[
      <String, Object?>{
        'gate': 'visible window stays bounded',
        'pass': samples.every((sample) => sample.visibleWindowBounded),
        'evidence':
            'Nocterm ListView rendered a bounded viewport around fixture-owned table rows.',
      },
      <String, Object?>{
        'gate': 'selection is correct after jump',
        'pass': samples.every((sample) => sample.selectionCorrect),
        'evidence':
            'Jump-to-end selected ${rowId(options.rows - 1)} and rendered it in terminal state.',
      },
      <String, Object?>{
        'gate': 'copy/export is sanitized and exact',
        'pass':
            samples.every((sample) => sample.copyExact) && unsafeLeakCount == 0,
        'evidence':
            'Selected row TSV matched generated source row and contained no escape/control/secret leakage.',
      },
    ],
    'ergonomics': <String, Object?>{
      'lineOfCodeCount': appLines,
      'benchmarkLineOfCodeCount': benchmarkLines,
      'testLineOfCodeCount': testLines,
      'appFile': 'lib/table_app.dart',
      'benchmarkFile': 'bin/sb3_datatable_benchmark.dart',
      'testFile': 'test/table_benchmark_test.dart',
      'peerOwnedListView': true,
      'peerOwnedScrollController': true,
      'peerOwnedText': true,
      'appOwnedTableFormatting': true,
      'appOwnedRetainedRows': true,
      'appOwnedSelectionState': true,
      'appOwnedCopyExport': true,
      'semanticGraphAvailable': false,
      'testQueryViaTerminalStateAndAppState': true,
    },
    'artifacts': <Object?>[
      <String, Object?>{
        'kind': 'source',
        'path': 'peer-fixtures/nocterm/sb3_datatable/lib/table_app.dart',
      },
      <String, Object?>{
        'kind': 'benchmark',
        'path':
            'peer-fixtures/nocterm/sb3_datatable/bin/sb3_datatable_benchmark.dart',
      },
      <String, Object?>{
        'kind': 'test',
        'path':
            'peer-fixtures/nocterm/sb3_datatable/test/table_benchmark_test.dart',
      },
    ],
    'notes': <String>[
      'This is a Nocterm test-harness peer fixture, not a real-terminal run.',
      'Nocterm 0.6.0 supplies ListView.builder, lazy list rendering, ScrollController, Text rendering, and terminal-state test queries.',
      'Nocterm 0.6.0 does not expose a dedicated DataTable widget in this package source, so table formatting, retained rows, selection, visible-window policy, and copy/export are app-owned fixture code.',
      'Nocterm exposes terminal/app state for this fixture, not a Fleury-style semantic app graph.',
      'Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.',
    ],
  };
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
  final lines = File(path).readAsLinesSync();
  var count = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
    count += 1;
  }
  return count;
}

String _timestampForId(DateTime value) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}T'
      '${two(value.hour)}-${two(value.minute)}-${two(value.second)}Z';
}

final class _Sample {
  const _Sample({
    required this.mountUs,
    required this.firstRenderUs,
    required this.arrowMoveUs,
    required this.pageMoveUs,
    required this.jumpToEndUs,
    required this.copySelectedRowUs,
    required this.semanticOrTestQueryUs,
    required this.rssDeltaBytes,
    required this.rowCount,
    required this.visibleWindowRows,
    required this.visibleStart,
    required this.visibleEnd,
    required this.selectedRow,
    required this.selectedRowId,
    required this.unsafeArtifactLeakCount,
    required this.visibleWindowBounded,
    required this.selectionCorrect,
    required this.copyExact,
    required this.arrowCorrect,
    required this.pageCorrect,
  });

  final int mountUs;
  final int firstRenderUs;
  final int arrowMoveUs;
  final int pageMoveUs;
  final int jumpToEndUs;
  final int copySelectedRowUs;
  final int semanticOrTestQueryUs;
  final int rssDeltaBytes;
  final int rowCount;
  final int visibleWindowRows;
  final int visibleStart;
  final int visibleEnd;
  final int selectedRow;
  final String selectedRowId;
  final int unsafeArtifactLeakCount;
  final bool visibleWindowBounded;
  final bool selectionCorrect;
  final bool copyExact;
  final bool arrowCorrect;
  final bool pageCorrect;
}

final class _Options {
  const _Options({
    required this.warmupIterations,
    required this.measuredIterations,
    required this.rows,
    required this.size,
    required this.printJson,
    required this.outputPath,
  });

  final int warmupIterations;
  final int measuredIterations;
  final int rows;
  final Size size;
  final bool printJson;
  final String? outputPath;

  static _Options parse(List<String> args) {
    var warmupIterations = _defaultWarmups;
    var measuredIterations = _defaultIterations;
    var rows = _defaultRows;
    var size = _defaultSize;
    var printJson = false;
    String? outputPath;

    for (final arg in args) {
      if (arg == '--json') {
        printJson = true;
      } else if (arg.startsWith('--warmup=')) {
        warmupIterations = _parseNonNegativeInt(arg, '--warmup=');
      } else if (arg.startsWith('--iterations=')) {
        measuredIterations = _parsePositiveInt(arg, '--iterations=');
      } else if (arg.startsWith('--rows=')) {
        rows = _parsePositiveInt(arg, '--rows=');
      } else if (arg.startsWith('--size=')) {
        size = _parseSize(arg.substring('--size='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else {
        throw ArgumentError('Unknown argument: $arg');
      }
    }

    return _Options(
      warmupIterations: warmupIterations,
      measuredIterations: measuredIterations,
      rows: rows,
      size: size,
      printJson: printJson,
      outputPath: outputPath,
    );
  }

  static int _parsePositiveInt(String arg, String prefix) {
    final value = int.tryParse(arg.substring(prefix.length));
    if (value == null || value <= 0) {
      throw ArgumentError('$prefix requires a positive integer.');
    }
    return value;
  }

  static int _parseNonNegativeInt(String arg, String prefix) {
    final value = int.tryParse(arg.substring(prefix.length));
    if (value == null || value < 0) {
      throw ArgumentError('$prefix requires a non-negative integer.');
    }
    return value;
  }

  static Size _parseSize(String value) {
    final parts = value.split('x');
    if (parts.length != 2) {
      throw ArgumentError('--size requires COLUMNSxROWS.');
    }
    final columns = int.tryParse(parts[0]);
    final rows = int.tryParse(parts[1]);
    if (columns == null || rows == null || columns <= 0 || rows <= 0) {
      throw ArgumentError('--size requires positive integer dimensions.');
    }
    return Size(columns.toDouble(), rows.toDouble());
  }
}
