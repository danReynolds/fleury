// Build a benchmark scoreboard from PTY captures.
//
// Scans capture_pty.dart outputs (<label>-<scenario>-wire-*.bin/.json),
// aggregates repeated runs by median, and writes a scenario-indexed Markdown
// scoreboard that links back to benchmarks/README.md for scenario intent.

import 'dart:convert';
import 'dart:io';

import 'package:fleury/src/rendering/ansi_byte_budget.dart'
    show AnsiByteBreakdown;

const _axes = <_Axis>[
  _Axis('bytes', higherIsBetter: false),
  _Axis('bytesPerFrame', higherIsBetter: false),
  _Axis('overheadPercent', higherIsBetter: false),
  _Axis('ttfbMs', higherIsBetter: false),
  _Axis('rssMiB', higherIsBetter: false),
  _Axis('cpuLoadPercent', higherIsBetter: false),
  _Axis('fps', higherIsBetter: true),
];

const _scenarios = <_Scenario>[
  _Scenario('P0', 'sb4', 'SB.4 Log region', 'sb4-log-region', [
    'textual',
    'bubbletea',
    'opentui',
  ]),
  _Scenario('P0', 'sb5', 'SB.5 Streaming Markdown', 'sb5-streaming-markdown', [
    'textual',
    'bubbletea',
    'ink',
  ]),
  _Scenario('P1', 'sb2', 'SB.2 Text editing', 'sb2-text-editing', [
    'textual',
    'bubbletea',
    'ink',
  ]),
  _Scenario('P1', 'sb3', 'SB.3 DataTable', 'sb3-datatable', [
    'textual',
    'ratatui',
    'opentui',
  ]),
  _Scenario('P2', 'sb1', 'SB.1 Counter/startup', 'sb1-counterstartup', [
    'bubbletea',
    'textual',
    'ink',
  ]),
  _Scenario('P2', 'sb6', 'SB.6 Dashboard updates', 'sb6-dashboard-updates', [
    'ratatui',
    'opentui',
    'bubbletea',
  ]),
  _Scenario('P2', 'sb12', 'SB.12 Layout dirtiness cache',
      'sb12-layout-dirtiness-cache', [
    'nocterm',
    'ratatui',
    'opentui',
  ]),
  _Scenario(
      'P3', 'sb8', 'SB.8 Overlay/palette churn', 'sb8-overlaypalette-churn', [
    'textual',
    'ink',
    'bubbletea',
  ]),
  _Scenario('P3', 'sb9', 'SB.9 Subprocess/untrusted output',
      'sb9-subprocessuntrusted-output', [
    'textual',
    'bubbletea',
    'opentui',
  ]),
  _Scenario('P3', 'sb10', 'SB.10 Proof-app journey', 'sb10-proof-app-journey', [
    'textual',
    'bubbletea',
    'ink',
  ]),
  _Scenario('P4', 'sb7', 'SB.7 Resize storm', 'sb7-resize-storm', [
    'textual',
    'ratatui',
    'opentui',
  ]),
  _Scenario(
      'P4', 'sb11', 'SB.11 TreeTable/filter/copy', 'sb11-treetablefiltercopy', [
    'textual',
    'ratatui',
    'opentui',
  ]),
];

final _captureNamePattern = RegExp(r'^([a-z0-9]+)-sb([0-9]+)-wire-.*\.json$');

void main(List<String> args) {
  final options = _ScoreboardOptions.parse(args);
  final captures = _loadCaptures(options.inputDir);
  final scoreboard = _buildScoreboard(captures);

  if (options.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(scoreboard));
  }

  final markdown = _scoreboardMarkdown(
    scoreboard,
    inputDir: options.inputDir,
    matrixLink: options.matrixLink,
  );
  if (options.outputPath == null) {
    stdout.write(markdown);
  } else {
    final output = File(options.outputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(markdown);
    stdout.writeln('wrote ${output.path}');
  }
}

Map<String, Object?> _buildScoreboard(List<_CaptureAxes> captures) {
  final byScenario = <String, List<_CaptureAxes>>{};
  for (final capture in captures) {
    (byScenario[capture.scenarioId] ??= <_CaptureAxes>[]).add(capture);
  }

  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryBenchmarkScoreboard',
    'scenarios': [
      for (final scenario in _scenarios)
        _scenarioScore(scenario, byScenario[scenario.id] ?? const []),
    ],
  };
}

Map<String, Object?> _scenarioScore(
  _Scenario scenario,
  List<_CaptureAxes> captures,
) {
  final byLabel = <String, List<_CaptureAxes>>{};
  for (final capture in captures) {
    (byLabel[capture.label] ??= <_CaptureAxes>[]).add(capture);
  }

  final aggregates = <String, _Aggregate>{
    for (final entry in byLabel.entries)
      entry.key: _Aggregate.from(entry.value),
  };
  final fleury = aggregates['fleury'];
  final expectedPeersSeen =
      scenario.primaryPeers.where(aggregates.containsKey).toList();

  final axisScores = <String, Object?>{};
  for (final axis in _axes) {
    axisScores[axis.id] = _axisScore(axis, aggregates, fleury);
  }

  return <String, Object?>{
    'priority': scenario.priority,
    'id': scenario.id,
    'name': scenario.name,
    'matrixAnchor': scenario.anchor,
    'expectedPeers': scenario.primaryPeers,
    'observedLabels': aggregates.keys.toList()..sort(),
    'expectedPeersSeen': expectedPeersSeen,
    'runCount': {
      for (final entry in aggregates.entries) entry.key: entry.value.runCount,
    },
    'byteSplits': {
      for (final entry in aggregates.entries)
        entry.key: entry.value.byteSplit.toJson(),
    },
    'runtimeMarkers': {
      for (final entry in aggregates.entries)
        if (entry.value.runtimeMarkersMs.isNotEmpty)
          entry.key: entry.value.runtimeMarkersMs,
    },
    'axes': axisScores,
    'position': _position(axisScores, fleury, expectedPeersSeen),
  };
}

Map<String, Object?> _axisScore(
  _Axis axis,
  Map<String, _Aggregate> aggregates,
  _Aggregate? fleury,
) {
  final values = <String, double>{};
  for (final entry in aggregates.entries) {
    final value = entry.value.value(axis.id);
    if (value != null && value.isFinite && value > 0) {
      values[entry.key] = value;
    }
  }
  final fleuryValue = fleury?.value(axis.id);
  if (fleuryValue == null || !fleuryValue.isFinite || fleuryValue <= 0) {
    return <String, Object?>{'status': 'missing'};
  }
  if (values.length <= 1) {
    return <String, Object?>{
      'status': 'needs-peer',
      'fleury': fleuryValue,
    };
  }

  var bestLabel = values.keys.first;
  var bestValue = values[bestLabel]!;
  for (final entry in values.entries.skip(1)) {
    final better =
        axis.higherIsBetter ? entry.value > bestValue : entry.value < bestValue;
    if (better) {
      bestLabel = entry.key;
      bestValue = entry.value;
    }
  }
  final band = _band(
    fleuryValue,
    bestValue,
    higherIsBetter: axis.higherIsBetter,
  );
  return <String, Object?>{
    'status': band,
    'fleury': fleuryValue,
    'bestLabel': bestLabel,
    'best': bestValue,
  };
}

String _position(
  Map<String, Object?> axisScores,
  _Aggregate? fleury,
  List<String> peersSeen,
) {
  if (fleury == null) return 'needs data';
  if (peersSeen.isEmpty) return 'needs peer';

  String status(String axisId) =>
      ((axisScores[axisId] as Map<String, Object?>?)?['status'] as String?) ??
      'missing';

  final severe = <String>[
    status('bytes'),
    status('bytesPerFrame'),
    status('rssMiB'),
    status('cpuLoadPercent'),
  ];
  if (severe.contains('WAY OFF')) return 'catch up';

  final leadingCount = _axes
      .map((axis) => status(axis.id))
      .where((value) => value == 'leading')
      .length;
  final bytesStrong =
      status('bytes') == 'leading' || status('bytes') == 'competitive';
  final overheadWeak = status('overheadPercent') == 'WAY OFF';
  if (bytesStrong && (leadingCount >= 3 || overheadWeak)) {
    return overheadWeak ? 'push leading: overhead cleanup' : 'push leading';
  }

  final allMeasured = _axes
      .map((axis) => status(axis.id))
      .where((value) => value != 'missing' && value != 'needs-peer')
      .toList();
  if (allMeasured.isNotEmpty && !allMeasured.contains('WAY OFF')) {
    return 'parity ok';
  }
  return 'needs data';
}

String _scoreboardMarkdown(
  Map<String, Object?> scoreboard, {
  required String inputDir,
  required String matrixLink,
}) {
  final scenarios =
      (scoreboard['scenarios'] as List<Object?>).cast<Map<String, Object?>>();
  final now = DateTime.now().toUtc().toIso8601String();
  final buffer = StringBuffer()
    ..writeln('# Fleury Benchmark Scoreboard')
    ..writeln()
    ..writeln('Generated from `$inputDir` at `$now`.')
    ..writeln()
    ..writeln(
      'Each row links back to the benchmark matrix for scenario intent and peer selection rationale. '
      'Bands compare Fleury against the best observed capture for that axis: '
      '`leading <=1.15x`, `competitive <=1.5x`, `ballpark <=3x`, else `WAY OFF`. '
      'RSS/CPU remain runtime-confounded.',
    )
    ..writeln()
    ..writeln(
      '| Priority | Benchmark | Runs | Peers seen | Bytes | B/frame | Overhead | TTFB | RSS | CPU | FPS | Position |',
    )
    ..writeln(
      '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    );

  for (final scenario in scenarios) {
    final axes =
        (scenario['axes'] as Map<String, Object?>).cast<String, Object?>();
    final runs =
        (scenario['runCount'] as Map<String, Object?>).cast<String, Object?>();
    final peersSeen = (scenario['expectedPeersSeen'] as List<Object?>)
        .map((value) => value.toString())
        .toList();
    final benchmark =
        '[${scenario['name']}]($matrixLink#${scenario['matrixAnchor']})';
    buffer.writeln(
      '| ${scenario['priority']} | $benchmark | ${_runsCell(runs)} | '
      '${peersSeen.isEmpty ? '-' : peersSeen.join(', ')} | '
      '${_axisCell(axes['bytes'], _fmtBytes)} | '
      '${_axisCell(axes['bytesPerFrame'], _fmtNumber)} | '
      '${_axisCell(axes['overheadPercent'], _fmtPercent)} | '
      '${_axisCell(axes['ttfbMs'], _fmtMs)} | '
      '${_axisCell(axes['rssMiB'], _fmtMiB)} | '
      '${_axisCell(axes['cpuLoadPercent'], _fmtPercent)} | '
      '${_axisCell(axes['fps'], _fmtFps)} | '
      '${scenario['position']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Byte Splits')
    ..writeln()
    ..writeln(
      'Median-total-run split per label: `content/sgr/cursor/sync/other`. '
      'This is diagnostic only; the axis bands above remain the decision surface.',
    )
    ..writeln()
    ..writeln(
      '| Priority | Benchmark | Fleury split | Best-by-bytes split | Dominant Fleury overhead |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final scenario in scenarios) {
    final axes =
        (scenario['axes'] as Map<String, Object?>).cast<String, Object?>();
    final bytesAxis =
        (axes['bytes'] as Map<String, Object?>?) ?? const <String, Object?>{};
    final byteSplits = (scenario['byteSplits'] as Map<String, Object?>?)
            ?.cast<String, Object?>() ??
        const <String, Object?>{};
    final benchmark =
        '[${scenario['name']}]($matrixLink#${scenario['matrixAnchor']})';
    final fleurySplit = _splitMap(byteSplits['fleury']);
    final bestLabel = (bytesAxis['bestLabel'] as String?) ??
        (fleurySplit == null ? null : 'fleury');
    final bestSplit = _splitMap(byteSplits[bestLabel]);
    final bestCell =
        bestLabel == null ? '-' : '$bestLabel<br>${_splitCell(bestSplit)}';
    buffer.writeln(
      '| ${scenario['priority']} | $benchmark | ${_splitCell(fleurySplit)} | '
      '$bestCell | ${_dominantOverheadCell(fleurySplit)} |',
    );
  }

  final markerRows = scenarios.where((scenario) {
    final markers = scenario['runtimeMarkers'];
    return markers is Map<String, Object?> && markers.isNotEmpty;
  }).toList();
  if (markerRows.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Runtime Markers')
      ..writeln()
      ..writeln(
        'Fleury-only capture offsets from the PTY spawn. These decompose raw TTFB without affecting peer byte streams.',
      )
      ..writeln()
      ..writeln('| Priority | Benchmark | Fleury deltas | Fleury markers |')
      ..writeln('| --- | --- | --- | --- |');

    for (final scenario in markerRows) {
      final benchmark =
          '[${scenario['name']}]($matrixLink#${scenario['matrixAnchor']})';
      final runtimeMarkers =
          (scenario['runtimeMarkers'] as Map<String, Object?>)
              .cast<String, Object?>();
      final fleuryMarkers = runtimeMarkers['fleury'];
      buffer.writeln(
        '| ${scenario['priority']} | $benchmark | '
        '${_markerDeltaCell(fleuryMarkers)} | ${_markerCell(fleuryMarkers)} |',
      );
    }
  }

  void bucket(String title, String positionPrefix) {
    final rows = scenarios
        .where(
          (scenario) =>
              scenario['position'].toString().startsWith(positionPrefix),
        )
        .toList();
    buffer
      ..writeln()
      ..writeln('## $title')
      ..writeln();
    if (rows.isEmpty) {
      buffer.writeln('- None with current captures.');
    } else {
      for (final scenario in rows) {
        buffer.writeln(
          '- [${scenario['name']}]($matrixLink#${scenario['matrixAnchor']}): '
          '${scenario['position']}',
        );
      }
    }
  }

  bucket('Catch Up', 'catch up');
  bucket('Parity OK', 'parity ok');
  bucket('Push For Leading', 'push leading');
  bucket('Needs Data', 'needs');
  return buffer.toString();
}

String _runsCell(Map<String, Object?> runs) {
  if (runs.isEmpty) return '-';
  final entries = runs.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}:${entry.value}').join('<br>');
}

String _axisCell(Object? raw, String Function(double) format) {
  final score = (raw as Map<String, Object?>?) ?? const <String, Object?>{};
  final status = score['status'] as String? ?? 'missing';
  final fleury = (score['fleury'] as num?)?.toDouble();
  if (fleury == null) return status;
  final bestLabel = score['bestLabel'] as String?;
  final best = (score['best'] as num?)?.toDouble();
  final comparison = bestLabel == null || best == null || bestLabel == 'fleury'
      ? ''
      : '<br>best $bestLabel ${format(best)}';
  return '$status<br>${format(fleury)}$comparison';
}

Map<String, Object?>? _splitMap(Object? raw) {
  if (raw is! Map) return null;
  return raw.cast<String, Object?>();
}

String _splitCell(Map<String, Object?>? split) {
  if (split == null) return '-';
  return [
    _splitPart(split, 'content'),
    _splitPart(split, 'sgr'),
    _splitPart(split, 'cursor'),
    _splitPart(split, 'sync'),
    _splitPart(split, 'other'),
  ].join('/');
}

String _splitPart(Map<String, Object?> split, String key) {
  final value = (split[key] as num?)?.round();
  return value == null ? '-' : '$value';
}

String _dominantOverheadCell(Map<String, Object?>? split) {
  if (split == null) return '-';
  final overhead = <String, double>{
    'sgr': _splitValue(split, 'sgr'),
    'cursor': _splitValue(split, 'cursor'),
    'sync': _splitValue(split, 'sync'),
    'other': _splitValue(split, 'other'),
  };
  final largest = overhead.entries.reduce(
    (a, b) => a.value >= b.value ? a : b,
  );
  if (largest.value <= 0) return '-';
  final other = overhead['other']!;
  final otherNote = other > 0 && largest.key != 'other'
      ? '<br>other ${_fmtBytes(other)}'
      : '';
  return '${largest.key} ${_fmtBytes(largest.value)}$otherNote';
}

String _markerCell(Object? value) {
  if (value is! Map<String, Object?> || value.isEmpty) return '-';
  const order = <String>[
    'runTui.entry',
    'terminal.enter.start',
    'terminal.enter.end',
    'root.mounted',
    'first.render.start',
    'first.output.write',
    'first.render.end',
  ];
  final parts = <String>[];
  for (final label in order) {
    final marker = value[label];
    if (marker is num) {
      parts.add('$label ${_fmtMs(marker.toDouble())}');
    }
  }
  for (final entry in value.entries) {
    if (order.contains(entry.key)) continue;
    final marker = entry.value;
    if (marker is num) {
      parts.add('${entry.key} ${_fmtMs(marker.toDouble())}');
    }
  }
  return parts.isEmpty ? '-' : parts.join('<br>');
}

String _markerDeltaCell(Object? value) {
  if (value is! Map<String, Object?> || value.isEmpty) return '-';
  double? marker(String label) => (value[label] as num?)?.toDouble();

  final entry = marker('runTui.entry');
  final firstOutput = marker('first.output.write');
  final firstRenderEnd = marker('first.render.end');
  final cleanup = marker('runTui.cleanup.complete');
  final parts = <String>[];

  if (entry != null) {
    parts.add('pre-runTui ${_fmtMs(entry)}');
  }
  if (entry != null && firstOutput != null) {
    parts.add('entry->first output ${_fmtMs(firstOutput - entry)}');
  }
  if (entry != null && firstRenderEnd != null) {
    parts.add('entry->first render end ${_fmtMs(firstRenderEnd - entry)}');
  }
  if (entry != null && cleanup != null) {
    parts.add('entry->cleanup ${_fmtMs(cleanup - entry)}');
  }
  return parts.isEmpty ? '-' : parts.join('<br>');
}

double _splitValue(Map<String, Object?> split, String key) {
  return (split[key] as num?)?.toDouble() ?? 0;
}

List<_CaptureAxes> _loadCaptures(String inputDir) {
  final root = Directory(inputDir);
  if (!root.existsSync()) return const [];
  final captures = <_CaptureAxes>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    if (entity.path.split(Platform.pathSeparator).contains('bin')) continue;
    final name = _fileName(entity.path);
    final match = _captureNamePattern.firstMatch(name);
    if (match == null) continue;
    final binPath = entity.path.substring(0, entity.path.length - 5) + '.bin';
    if (!File(binPath).existsSync()) continue;
    captures.add(
      _CaptureAxes.load(
        label: match.group(1)!,
        scenarioId: 'sb${match.group(2)!}',
        binPath: binPath,
        jsonPath: entity.path,
      ),
    );
  }
  return captures;
}

String _fileName(String path) {
  final separator = Platform.pathSeparator;
  final index = path.lastIndexOf(separator);
  return index < 0 ? path : path.substring(index + 1);
}

String _band(num value, num best, {required bool higherIsBetter}) {
  if (best <= 0 || value <= 0) return '-';
  final ratio = higherIsBetter ? best / value : value / best;
  if (ratio <= 1.15) return 'leading';
  if (ratio <= 1.5) return 'competitive';
  if (ratio <= 3.0) return 'ballpark';
  return 'WAY OFF';
}

String _fmtBytes(double value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) {
    return '${(value / 1024).toStringAsFixed(1)} KiB';
  }
  return '${value.toStringAsFixed(0)} B';
}

String _fmtNumber(double value) => value.toStringAsFixed(0);
String _fmtPercent(double value) => '${value.toStringAsFixed(0)}%';
String _fmtMs(double value) => '${value.toStringAsFixed(1)} ms';
String _fmtMiB(double value) => '${value.toStringAsFixed(1)} MiB';
String _fmtFps(double value) => '${value.toStringAsFixed(1)} fps';

double? _median(List<double?> values) {
  final present = values
      .whereType<double>()
      .where((value) => value.isFinite)
      .toList()
    ..sort();
  if (present.isEmpty) return null;
  final mid = present.length ~/ 2;
  if (present.length.isOdd) return present[mid];
  return (present[mid - 1] + present[mid]) / 2;
}

final class _ScoreboardOptions {
  const _ScoreboardOptions({
    required this.inputDir,
    required this.outputPath,
    required this.json,
    required this.matrixLink,
  });

  final String inputDir;
  final String? outputPath;
  final bool json;
  final String matrixLink;

  static _ScoreboardOptions parse(List<String> args) {
    var inputDir = 'caps';
    String? outputPath;
    var json = false;
    var matrixLink = 'README.md';
    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputDir = arg.substring('--input='.length);
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg == '--json') {
        json = true;
      } else if (arg.startsWith('--matrix-link=')) {
        matrixLink = arg.substring('--matrix-link='.length);
      } else {
        stderr.writeln('Unknown option for scoreboard: $arg');
        _printUsage();
        exit(64);
      }
    }
    return _ScoreboardOptions(
      inputDir: inputDir,
      outputPath: outputPath,
      json: json,
      matrixLink: matrixLink,
    );
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run scoreboard.dart [--input=profiling/caps] [--output=PATH] [--json] [--matrix-link=PATH]',
  );
}

final class _Scenario {
  const _Scenario(
    this.priority,
    this.id,
    this.name,
    this.anchor,
    this.primaryPeers,
  );

  final String priority;
  final String id;
  final String name;
  final String anchor;
  final List<String> primaryPeers;
}

final class _Axis {
  const _Axis(this.id, {required this.higherIsBetter});

  final String id;
  final bool higherIsBetter;
}

final class _CaptureAxes {
  const _CaptureAxes({
    required this.label,
    required this.scenarioId,
    required this.bytes,
    required this.frames,
    required this.ttfbMs,
    required this.durationMs,
    required this.rssMiB,
    required this.cpuLoadPercent,
    required this.fps,
    required this.runtimeMarkersMs,
  });

  final String label;
  final String scenarioId;
  final AnsiByteBreakdown bytes;
  final int frames;
  final double? ttfbMs;
  final double? durationMs;
  final double? rssMiB;
  final double? cpuLoadPercent;
  final double? fps;
  final Map<String, double> runtimeMarkersMs;

  double get bytesPerFrame =>
      frames == 0 ? bytes.total.toDouble() : bytes.total / frames;
  double get overheadPercent => bytes.overheadFraction * 100;

  static _CaptureAxes load({
    required String label,
    required String scenarioId,
    required String binPath,
    required String jsonPath,
  }) {
    final text = utf8.decode(
      File(binPath).readAsBytesSync(),
      allowMalformed: true,
    );
    final bytes = AnsiByteBreakdown.analyze(text);
    final meta =
        jsonDecode(File(jsonPath).readAsStringSync()) as Map<String, Object?>;
    final logicalFrames = (meta['logicalFrameCount'] as num?)?.toInt() ?? 0;
    final bsu = '\x1B[?2026h'.allMatches(text).length;
    final reads = (meta['reads'] as List?)?.length ?? 0;
    final frames = logicalFrames > 0 ? logicalFrames : (bsu > 0 ? bsu : reads);
    final durationMs = (meta['durationMs'] as num?)?.toDouble();
    final rssBytes = (meta['maxRssBytes'] as num?)?.toDouble();
    final cpuMs = (meta['cpuMs'] as num?)?.toDouble();
    final fps = durationMs == null || durationMs <= 0
        ? null
        : frames * 1000 / durationMs;
    final cpuLoad = cpuMs == null || durationMs == null || durationMs <= 0
        ? null
        : cpuMs * 100 / durationMs;
    return _CaptureAxes(
      label: label,
      scenarioId: scenarioId,
      bytes: bytes,
      frames: frames,
      ttfbMs: (meta['ttfbMs'] as num?)?.toDouble(),
      durationMs: durationMs,
      rssMiB: rssBytes == null ? null : rssBytes / (1024 * 1024),
      cpuLoadPercent: cpuLoad,
      fps: fps,
      runtimeMarkersMs: _runtimeMarkersMs(meta['runtimeMarkers']),
    );
  }
}

final class _Aggregate {
  _Aggregate({
    required this.runCount,
    required this.bytes,
    required this.byteSplit,
    required this.bytesPerFrame,
    required this.overheadPercent,
    required this.ttfbMs,
    required this.rssMiB,
    required this.cpuLoadPercent,
    required this.fps,
    required this.runtimeMarkersMs,
  });

  final int runCount;
  final double? bytes;
  final AnsiByteBreakdown byteSplit;
  final double? bytesPerFrame;
  final double? overheadPercent;
  final double? ttfbMs;
  final double? rssMiB;
  final double? cpuLoadPercent;
  final double? fps;
  final Map<String, double> runtimeMarkersMs;

  double? value(String axisId) {
    return switch (axisId) {
      'bytes' => bytes,
      'bytesPerFrame' => bytesPerFrame,
      'overheadPercent' => overheadPercent,
      'ttfbMs' => ttfbMs,
      'rssMiB' => rssMiB,
      'cpuLoadPercent' => cpuLoadPercent,
      'fps' => fps,
      _ => null,
    };
  }

  factory _Aggregate.from(List<_CaptureAxes> captures) {
    final markerLabels = <String>{
      for (final capture in captures) ...capture.runtimeMarkersMs.keys,
    };
    return _Aggregate(
      runCount: captures.length,
      bytes: _median(
          [for (final capture in captures) capture.bytes.total.toDouble()]),
      byteSplit: _representativeByteSplit(captures),
      bytesPerFrame: _median([
        for (final capture in captures) capture.bytesPerFrame,
      ]),
      overheadPercent: _median([
        for (final capture in captures) capture.overheadPercent,
      ]),
      ttfbMs: _median([for (final capture in captures) capture.ttfbMs]),
      rssMiB: _median([for (final capture in captures) capture.rssMiB]),
      cpuLoadPercent: _median([
        for (final capture in captures) capture.cpuLoadPercent,
      ]),
      fps: _median([for (final capture in captures) capture.fps]),
      runtimeMarkersMs: <String, double>{
        for (final label in markerLabels)
          if (_median([
            for (final capture in captures) capture.runtimeMarkersMs[label],
          ])
              case final value?)
            label: value,
      },
    );
  }
}

Map<String, double> _runtimeMarkersMs(Object? value) {
  if (value is! List<Object?>) return const <String, double>{};
  final result = <String, double>{};
  for (final marker in value) {
    if (marker is! Map<String, Object?>) continue;
    final label = marker['label'];
    final offset = marker['captureOffsetMs'];
    if (label is String && offset is num) {
      result[label] = offset.toDouble();
    }
  }
  return result;
}

AnsiByteBreakdown _representativeByteSplit(List<_CaptureAxes> captures) {
  if (captures.isEmpty) return const AnsiByteBreakdown();
  final sorted = [...captures]
    ..sort((a, b) => a.bytes.total.compareTo(b.bytes.total));
  return sorted[sorted.length ~/ 2].bytes;
}
