import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fleury_peer_nocterm_sb4_log_region/log_region_app.dart';
import 'package:nocterm/nocterm.dart';

const _schemaVersion = 1;
const _peerId = 'nocterm';
const _peerName = 'Nocterm';
const _peerVersion = '0.6.0';
const _peerUrl = 'https://pub.dev/packages/nocterm';
const _scenarioId = 'SB.4';
const _defaultWarmups = 2;
const _defaultIterations = 5;
const _defaultRows = 100000;
const _defaultAppend = 1000;
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
  stdout.writeln('Nocterm SB.4 log region fixture');
  stdout.writeln('Run: ${artifact['runId']}');
  stdout.writeln('Rows: ${options.rows}');
  stdout.writeln('Append: ${options.appendCount}');
  stdout.writeln('Iterations: ${options.measuredIterations}');
  stdout.writeln(
    'appendBurstUs p95: ${(metrics['appendBurstUs']! as Map)['p95']}',
  );
  stdout.writeln(
    'filterQueryUs p95: ${(metrics['filterQueryUs']! as Map)['p95']}',
  );
  stdout.writeln(
    'unsafeArtifactLeakCount: ${metrics['unsafeArtifactLeakCount']}',
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
      Sb4NoctermLogRegion(
        rowCount: options.rows,
        width: options.size.width.toInt(),
        height: options.size.height.toInt(),
      ),
    );
    mount.stop();
    final state = tester.findState<Sb4NoctermLogRegionState>();

    final firstRender = Stopwatch()..start();
    final firstView = tester.terminalState.getText();
    firstRender.stop();

    final append = Stopwatch()..start();
    state.appendBurst(options.appendCount);
    await tester.pump();
    state.scrollToTail();
    await tester.pump();
    append.stop();
    final appendState = state.snapshot();
    final appendView = tester.terminalState.getText();

    final scrollbackIndex = options.rows ~/ 2;
    final scrollback = Stopwatch()..start();
    state.jumpToScrollback(scrollbackIndex);
    await tester.pump();
    scrollback.stop();
    final scrollbackState = state.snapshot();
    final scrollbackView = tester.terminalState.getText();

    final tail = Stopwatch()..start();
    state.scrollToTail();
    await tester.pump();
    tail.stop();
    final tailState = state.snapshot();
    final tailView = tester.terminalState.getText();

    final copy = Stopwatch()..start();
    state.copySelectedEntry();
    copy.stop();
    final copied = state.lastCopiedText;

    final filter = Stopwatch()..start();
    state.filterQuery(appendFilterQuery());
    await tester.pump();
    state.scrollDisplayedToEnd();
    await tester.pump();
    filter.stop();
    final filterState = state.snapshot();
    final filterView = tester.terminalState.getText();

    final query = Stopwatch()..start();
    final selectedKeyVisible = tester.terminalState.containsText(
      filterState.selectedKey,
    );
    final unsafeLeakCount = filterState.unsafeArtifactLeakCount +
        unsafeVisibleTextCount(firstView) +
        unsafeVisibleTextCount(appendView) +
        unsafeVisibleTextCount(scrollbackView) +
        unsafeVisibleTextCount(tailView) +
        unsafeVisibleTextCount(filterView);
    query.stop();

    final expectedLastIndex = options.rows + options.appendCount - 1;
    final expectedLastKey = logKey(expectedLastIndex);

    return _Sample(
      mountUs: mount.elapsedMicroseconds,
      firstRenderUs: firstRender.elapsedMicroseconds,
      appendBurstUs: append.elapsedMicroseconds,
      scrollbackJumpUs: scrollback.elapsedMicroseconds,
      scrollToTailUs: tail.elapsedMicroseconds,
      copySelectedEntryUs: copy.elapsedMicroseconds,
      filterQueryUs: filter.elapsedMicroseconds,
      semanticOrTestQueryUs: query.elapsedMicroseconds,
      rssDeltaBytes: math.max(0, ProcessInfo.currentRss - rssBefore),
      unsafeArtifactLeakCount: unsafeLeakCount,
      entryCountAfterAppend: appendState.entryCount,
      lineCountAfterFilter: filterState.displayedCount,
      filterMatchCount: filterState.displayedCount,
      selectedKey: filterState.selectedKey,
      scrollY: filterState.scrollY,
      maxScrollY: filterState.maxScrollY,
      visibleWindowRows: filterState.visibleWindowRows,
      tailAnchoringCorrect: appendState.tailAnchored &&
          tailState.tailAnchored &&
          tailState.selectedKey == expectedLastKey,
      copyTextSanitized: copied == expectedCopiedText(expectedLastIndex) &&
          unsafeCopyTextCount(copied) == 0,
      filterResultCorrect: filterState.displayedCount == options.appendCount &&
          filterState.selectedKey == expectedLastKey &&
          selectedKeyVisible,
      scrollbackSelectedCorrect:
          scrollbackState.selectedKey == logKey(scrollbackIndex) &&
              scrollbackView.contains(logKey(scrollbackIndex)),
    );
  } finally {
    tester.dispose();
  }
}

Map<String, Object?> _buildArtifact(_Options options, List<_Sample> samples) {
  final packageRoot = _packageRoot();
  final appLines = _sourceLineCount(
    '${packageRoot.path}/lib/log_region_app.dart',
  );
  final benchmarkLines = _sourceLineCount(
    '${packageRoot.path}/bin/sb4_log_region_benchmark.dart',
  );
  final testLines = _sourceLineCount(
    '${packageRoot.path}/test/log_region_benchmark_test.dart',
  );
  final capturedAt = DateTime.now().toUtc();
  final runId = 'nocterm-sb4-log-region-${_timestampForId(capturedAt)}';
  final unsafeLeakCount =
      samples.map((sample) => sample.unsafeArtifactLeakCount).reduce(math.max);
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
      'workingDirectory': 'peer-fixtures/nocterm/sb4_log_region',
      'command': <String>[
        'dart',
        'run',
        'bin/sb4_log_region_benchmark.dart',
        '--warmup=${options.warmupIterations}',
        '--iterations=${options.measuredIterations}',
        '--rows=${options.rows}',
        '--append=${options.appendCount}',
        '--json',
      ],
      'warmupIterations': options.warmupIterations,
      'measuredIterations': options.measuredIterations,
    },
    'metrics': <String, Object?>{
      'mountUs': _stats(samples.map((sample) => sample.mountUs)),
      'firstRenderUs': _stats(samples.map((sample) => sample.firstRenderUs)),
      'appendBurstUs': _stats(samples.map((sample) => sample.appendBurstUs)),
      'scrollbackJumpUs': _stats(
        samples.map((sample) => sample.scrollbackJumpUs),
      ),
      'scrollToTailUs': _stats(samples.map((sample) => sample.scrollToTailUs)),
      'copySelectedEntryUs': _stats(
        samples.map((sample) => sample.copySelectedEntryUs),
      ),
      'filterQueryUs': _stats(samples.map((sample) => sample.filterQueryUs)),
      'semanticOrTestQueryUs': _stats(
        samples.map((sample) => sample.semanticOrTestQueryUs),
      ),
      'unsafeArtifactLeakCount': unsafeLeakCount,
      'rssDeltaBytes':
          samples.map((sample) => sample.rssDeltaBytes).reduce(math.max),
      'lineOfCodeCount': appLines,
      'benchmarkLineOfCodeCount': benchmarkLines,
      'testLineOfCodeCount': testLines,
      'entryCountAfterAppend': last.entryCountAfterAppend,
      'appendCount': options.appendCount,
      'lineCountAfterFilter': last.lineCountAfterFilter,
      'filterMatchCount': last.filterMatchCount,
      'selectedKey': last.selectedKey,
      'finalScrollY': last.scrollY,
      'finalMaxScrollY': last.maxScrollY,
      'visibleWindowRowEstimate': last.visibleWindowRows,
    },
    'correctness': <Object?>[
      <String, Object?>{
        'gate': 'tail anchoring is correct',
        'pass': samples.every((sample) => sample.tailAnchoringCorrect),
        'evidence':
            'After append and explicit tail scroll, the Nocterm ListView stayed anchored at ${logKey(options.rows + options.appendCount - 1)}.',
      },
      <String, Object?>{
        'gate': 'copy text is sanitized',
        'pass': samples.every((sample) => sample.copyTextSanitized),
        'evidence':
            'Selected-entry copy matched the generated sanitized log line and contained no escape, secret, or newline artifacts.',
      },
      <String, Object?>{
        'gate': 'unsafe output leak count is zero',
        'pass': unsafeLeakCount == 0,
        'evidence':
            'Fixture-owned sanitizer removed ANSI/OSC/control payloads before Nocterm Text/ListView rendering.',
      },
    ],
    'ergonomics': <String, Object?>{
      'lineOfCodeCount': appLines,
      'benchmarkLineOfCodeCount': benchmarkLines,
      'testLineOfCodeCount': testLines,
      'appFile': 'lib/log_region_app.dart',
      'benchmarkFile': 'bin/sb4_log_region_benchmark.dart',
      'testFile': 'test/log_region_benchmark_test.dart',
      'peerOwnedListView': true,
      'peerOwnedScrollController': true,
      'appOwnedSanitization': true,
      'appOwnedFiltering': true,
      'appOwnedSelectedEntryCopy': true,
      'semanticGraphAvailable': false,
      'testQueryViaTerminalStateAndAppState': true,
    },
    'artifacts': <Object?>[
      <String, Object?>{
        'kind': 'source',
        'path': 'peer-fixtures/nocterm/sb4_log_region/lib/log_region_app.dart',
      },
      <String, Object?>{
        'kind': 'benchmark',
        'path':
            'peer-fixtures/nocterm/sb4_log_region/bin/sb4_log_region_benchmark.dart',
      },
      <String, Object?>{
        'kind': 'test',
        'path':
            'peer-fixtures/nocterm/sb4_log_region/test/log_region_benchmark_test.dart',
      },
    ],
    'notes': <String>[
      'This is a Nocterm test-harness peer fixture, not a real-terminal run.',
      'Nocterm 0.6.0 supplies ListView.builder, lazy list rendering, ScrollController, Text rendering, and terminal-state test queries.',
      'Sanitization/redaction, filtering, selected-entry state, and copy/export are app-owned fixture code because Nocterm 0.6.0 does not expose Fleury-equivalent built-in primitives for those SB.4 behaviors.',
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
  return value.toIso8601String().split('.').first.replaceAll(':', '-');
}

final class _Sample {
  const _Sample({
    required this.mountUs,
    required this.firstRenderUs,
    required this.appendBurstUs,
    required this.scrollbackJumpUs,
    required this.scrollToTailUs,
    required this.copySelectedEntryUs,
    required this.filterQueryUs,
    required this.semanticOrTestQueryUs,
    required this.rssDeltaBytes,
    required this.unsafeArtifactLeakCount,
    required this.entryCountAfterAppend,
    required this.lineCountAfterFilter,
    required this.filterMatchCount,
    required this.selectedKey,
    required this.scrollY,
    required this.maxScrollY,
    required this.visibleWindowRows,
    required this.tailAnchoringCorrect,
    required this.copyTextSanitized,
    required this.filterResultCorrect,
    required this.scrollbackSelectedCorrect,
  });

  final int mountUs;
  final int firstRenderUs;
  final int appendBurstUs;
  final int scrollbackJumpUs;
  final int scrollToTailUs;
  final int copySelectedEntryUs;
  final int filterQueryUs;
  final int semanticOrTestQueryUs;
  final int rssDeltaBytes;
  final int unsafeArtifactLeakCount;
  final int entryCountAfterAppend;
  final int lineCountAfterFilter;
  final int filterMatchCount;
  final String selectedKey;
  final int scrollY;
  final int maxScrollY;
  final int visibleWindowRows;
  final bool tailAnchoringCorrect;
  final bool copyTextSanitized;
  final bool filterResultCorrect;
  final bool scrollbackSelectedCorrect;
}

final class _Options {
  const _Options({
    required this.warmupIterations,
    required this.measuredIterations,
    required this.rows,
    required this.appendCount,
    required this.size,
    required this.printJson,
    required this.outputPath,
  });

  final int warmupIterations;
  final int measuredIterations;
  final int rows;
  final int appendCount;
  final Size size;
  final bool printJson;
  final String? outputPath;

  static _Options parse(List<String> args) {
    var warmupIterations = _defaultWarmups;
    var measuredIterations = _defaultIterations;
    var rows = _defaultRows;
    var appendCount = _defaultAppend;
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
      } else if (arg.startsWith('--append=')) {
        appendCount = _parsePositiveInt(arg, '--append=');
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
      appendCount: appendCount,
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
