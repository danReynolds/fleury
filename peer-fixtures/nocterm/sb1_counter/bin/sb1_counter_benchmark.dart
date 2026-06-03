import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fleury_peer_nocterm_sb1_counter/counter_app.dart';
import 'package:nocterm/nocterm.dart';

const _schemaVersion = 1;
const _peerId = 'nocterm';
const _peerName = 'Nocterm';
const _peerVersion = '0.6.0';
const _peerUrl = 'https://pub.dev/packages/nocterm';
const _scenarioId = 'SB.1';
const _defaultWarmups = 2;
const _defaultIterations = 20;
const _defaultSize = Size(80, 24);

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  for (var i = 0; i < options.warmupIterations; i += 1) {
    await _runSample(options.size);
  }

  final samples = <_Sample>[];
  for (var i = 0; i < options.measuredIterations; i += 1) {
    samples.add(await _runSample(options.size));
  }

  final packageRoot = _packageRoot();
  final appLines = _sourceLineCount('${packageRoot.path}/lib/counter_app.dart');
  final testLines = _sourceLineCount(
    '${packageRoot.path}/test/counter_benchmark_test.dart',
  );
  final capturedAt = DateTime.now().toUtc();
  final runId = 'nocterm-sb1-counter-${_timestampForId(capturedAt)}';
  final allInitialCorrect = samples.every((sample) => sample.initialCorrect);
  final allIncrementCorrect = samples.every(
    (sample) => sample.incrementCorrect,
  );
  final allQueryCorrect = samples.every((sample) => sample.queryCorrect);

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
      'workingDirectory': 'peer-fixtures/nocterm/sb1_counter',
      'command': <String>[
        'dart',
        'run',
        'bin/sb1_counter_benchmark.dart',
        '--warmup=${options.warmupIterations}',
        '--iterations=${options.measuredIterations}',
        '--json',
      ],
      'warmupIterations': options.warmupIterations,
      'measuredIterations': options.measuredIterations,
    },
    'metrics': <String, Object?>{
      'firstFrameUs': _stats(samples.map((sample) => sample.firstFrameUs)),
      'commandToFrameUs': _stats(
        samples.map((sample) => sample.commandToFrameUs),
      ),
      'semanticOrTestQueryUs': _stats(
        samples.map((sample) => sample.semanticOrTestQueryUs),
      ),
      'rssDeltaBytes':
          samples.map((sample) => sample.rssDeltaBytes).reduce(math.max),
      'lineOfCodeCount': appLines,
      'testLineOfCodeCount': testLines,
    },
    'correctness': <Object?>[
      <String, Object?>{
        'gate': 'counter text updates correctly',
        'pass': allInitialCorrect && allIncrementCorrect,
      },
      <String, Object?>{
        'gate': 'input/action path matches normal app use',
        'pass': allIncrementCorrect,
        'evidence': 'NoctermTester.sendKey(LogicalKey.space)',
      },
      <String, Object?>{
        'gate': 'test shape is documented',
        'pass': testLines > 0 && allQueryCorrect,
        'evidence': 'test/counter_benchmark_test.dart',
      },
    ],
    'ergonomics': <String, Object?>{
      'lineOfCodeCount': appLines,
      'testLineOfCodeCount': testLines,
      'appFile': 'lib/counter_app.dart',
      'testFile': 'test/counter_benchmark_test.dart',
    },
    'artifacts': <Object?>[
      <String, Object?>{
        'kind': 'source',
        'path': 'peer-fixtures/nocterm/sb1_counter/lib/counter_app.dart',
      },
      <String, Object?>{
        'kind': 'test',
        'path':
            'peer-fixtures/nocterm/sb1_counter/test/counter_benchmark_test.dart',
      },
    ],
    'notes': <String>[
      'This is a Nocterm test-harness peer fixture, not a real-terminal run.',
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
    final firstFrame = metrics['firstFrameUs']! as Map<String, Object?>;
    final commandToFrame = metrics['commandToFrameUs']! as Map<String, Object?>;
    final query = metrics['semanticOrTestQueryUs']! as Map<String, Object?>;
    stdout.writeln('Nocterm SB.1 counter fixture');
    stdout.writeln('Run: $runId');
    stdout.writeln('Iterations: ${options.measuredIterations}');
    stdout.writeln('firstFrameUs p95: ${firstFrame['p95']}');
    stdout.writeln('commandToFrameUs p95: ${commandToFrame['p95']}');
    stdout.writeln('semanticOrTestQueryUs p95: ${query['p95']}');
    if (options.outputPath != null) {
      stdout.writeln('Saved ${options.outputPath}');
    }
  }
}

Future<_Sample> _runSample(Size size) async {
  final rssBefore = ProcessInfo.currentRss;
  final tester = await NoctermTester.create(size: size);
  try {
    final firstFrame = Stopwatch()..start();
    await tester.pumpComponent(const Sb1Counter());
    firstFrame.stop();

    final query = Stopwatch()..start();
    final initialCorrect = tester.terminalState.containsText('Count: 0');
    query.stop();

    final commandToFrame = Stopwatch()..start();
    await tester.sendKey(LogicalKey.space);
    commandToFrame.stop();

    final queryAfterCommand = Stopwatch()..start();
    final incrementCorrect = tester.terminalState.containsText('Count: 1');
    queryAfterCommand.stop();

    return _Sample(
      firstFrameUs: firstFrame.elapsedMicroseconds,
      commandToFrameUs: commandToFrame.elapsedMicroseconds,
      semanticOrTestQueryUs:
          query.elapsedMicroseconds + queryAfterCommand.elapsedMicroseconds,
      rssDeltaBytes: math.max(0, ProcessInfo.currentRss - rssBefore),
      initialCorrect: initialCorrect,
      incrementCorrect: incrementCorrect,
      queryCorrect: initialCorrect && incrementCorrect,
    );
  } finally {
    tester.dispose();
  }
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
    required this.firstFrameUs,
    required this.commandToFrameUs,
    required this.semanticOrTestQueryUs,
    required this.rssDeltaBytes,
    required this.initialCorrect,
    required this.incrementCorrect,
    required this.queryCorrect,
  });

  final int firstFrameUs;
  final int commandToFrameUs;
  final int semanticOrTestQueryUs;
  final int rssDeltaBytes;
  final bool initialCorrect;
  final bool incrementCorrect;
  final bool queryCorrect;
}

final class _Options {
  const _Options({
    required this.warmupIterations,
    required this.measuredIterations,
    required this.size,
    required this.printJson,
    required this.outputPath,
  });

  final int warmupIterations;
  final int measuredIterations;
  final Size size;
  final bool printJson;
  final String? outputPath;

  static _Options parse(List<String> args) {
    var warmups = _defaultWarmups;
    var iterations = _defaultIterations;
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
    'Usage: dart run bin/sb1_counter_benchmark.dart '
    '[--warmup=N] [--iterations=N] [--size=COLSxROWS] '
    '[--output=path] [--json]',
  );
}
