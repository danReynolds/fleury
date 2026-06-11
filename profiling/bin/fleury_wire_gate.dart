/// Fleury-only wire regression gate.
///
/// Re-runs a small scenario subset (SB.1 startup bytes, SB.6 dashboard
/// steady state, SB.9 untrusted-output encoding) under capture_pty and
/// compares the byte axes against `wire_gate_baseline.json`. Byte axes
/// FAIL on regression beyond tolerance; timing axes WARN only (PTY
/// timing is machine/load sensitive — full peer standings come from the
/// scoreboard, not this gate).
///
/// usage (from profiling/):
///   dart run bin/fleury_wire_gate.dart [--runs=3] [--update-baseline]
///     [--baseline=wire_gate_baseline.json] [--keep-captures]
///
/// Exit codes: 0 pass, 1 byte-axis regression, 64 usage/setup error.
import 'dart:convert';
import 'dart:io';

import 'package:fleury/src/rendering/ansi_byte_budget.dart';

final class _GateScenario {
  const _GateScenario({
    required this.id,
    required this.source,
    required this.args,
    required this.frameCount,
    required this.timeoutSeconds,
  });

  final String id;
  final String source;
  final List<String> args;
  final int frameCount;
  final int timeoutSeconds;
}

// Args mirror the harness defaults in tool/fleury_dev.dart so the gate
// measures the same workloads the scoreboard does.
const _scenarios = <_GateScenario>[
  _GateScenario(
    id: 'sb1',
    source: 'bin/fleury_sb1_wire.dart',
    args: ['--steps=1', '--interval-ms=60'],
    frameCount: 2,
    timeoutSeconds: 10,
  ),
  _GateScenario(
    id: 'sb6',
    source: 'bin/fleury_sb6_wire.dart',
    args: ['--rows=100000', '--steps=120', '--interval-ms=16'],
    frameCount: 121,
    timeoutSeconds: 20,
  ),
  _GateScenario(
    id: 'sb9',
    source: 'bin/fleury_sb9_wire.dart',
    args: ['--rows=400', '--steps=10', '--interval-ms=35'],
    frameCount: 11,
    timeoutSeconds: 15,
  ),
];

/// Byte axes fail beyond these relative increases; decreases warn (a real
/// improvement should be locked in with --update-baseline).
const _byteFailFraction = 0.15;

/// Overhead percent fails on more than this many percentage points up.
const _overheadFailPoints = 5.0;

/// Timing axes warn beyond this relative change, never fail.
const _timingWarnFraction = 0.5;

Future<void> main(List<String> args) async {
  var runs = 3;
  var update = false;
  var keepCaptures = false;
  var baselinePath = 'wire_gate_baseline.json';
  for (final arg in args) {
    if (arg.startsWith('--runs=')) {
      runs = int.parse(arg.substring('--runs='.length));
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (arg == '--keep-captures') {
      keepCaptures = true;
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }

  final baselineFile = File(baselinePath);
  if (!update && !baselineFile.existsSync()) {
    stderr.writeln(
      'no baseline at $baselinePath — run with --update-baseline first',
    );
    exitCode = 64;
    return;
  }

  final workDir = Directory.systemTemp.createTempSync('fleury-wire-gate-');
  final results = <String, Map<String, double>>{};
  try {
    for (final scenario in _scenarios) {
      final binary = '${workDir.path}/fleury-${scenario.id}';
      stdout.writeln('gate: compile ${scenario.source}');
      final compile = await Process.run('dart', [
        'compile',
        'exe',
        scenario.source,
        '-o',
        binary,
      ]);
      if (compile.exitCode != 0) {
        stderr.writeln('compile failed:\n${compile.stderr}');
        exitCode = 64;
        return;
      }
      // Warm the page cache so run 1 doesn't carry the cold-start tail.
      await _capture(scenario, binary, '${workDir.path}/warmup');

      final samples = <Map<String, double>>[];
      for (var run = 1; run <= runs; run++) {
        stdout.writeln('gate: ${scenario.id} run $run/$runs');
        final base = '${workDir.path}/${scenario.id}-r$run';
        await _capture(scenario, binary, base);
        samples.add(_readCapture(base));
      }
      results[scenario.id] = {
        for (final key in samples.first.keys)
          key: _median([for (final s in samples) s[key]!]),
      };
    }
  } finally {
    if (keepCaptures) {
      stdout.writeln('captures kept in ${workDir.path}');
    } else {
      workDir.deleteSync(recursive: true);
    }
  }

  if (update) {
    baselineFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(results)}\n',
    );
    stdout.writeln('baseline written to $baselinePath');
    return;
  }

  final baseline = (jsonDecode(baselineFile.readAsStringSync())
          as Map<String, Object?>)
      .map((id, axes) => MapEntry(
            id,
            (axes as Map<String, Object?>)
                .map((k, v) => MapEntry(k, (v as num).toDouble())),
          ));

  var failed = false;
  for (final scenario in _scenarios) {
    final current = results[scenario.id]!;
    final expected = baseline[scenario.id];
    if (expected == null) {
      stderr.writeln('${scenario.id}: missing from baseline — FAIL '
          '(re-run with --update-baseline)');
      failed = true;
      continue;
    }
    stdout.writeln('\n${scenario.id}:');
    failed |= _checkRelative(
      'totalBytes',
      current['totalBytes']!,
      expected['totalBytes']!,
      failUpFraction: _byteFailFraction,
    );
    failed |= _checkRelative(
      'bytesPerFrame',
      current['bytesPerFrame']!,
      expected['bytesPerFrame']!,
      failUpFraction: _byteFailFraction,
    );
    failed |= _checkPoints(
      'overheadPercent',
      current['overheadPercent']!,
      expected['overheadPercent']!,
      failUpPoints: _overheadFailPoints,
    );
    _checkRelative(
      'ttfbMs',
      current['ttfbMs']!,
      expected['ttfbMs']!,
      failUpFraction: null, // warn-only
    );
    _checkRelative(
      'frames',
      current['frames']!,
      expected['frames']!,
      failUpFraction: null, // warn-only (coalescing varies with timing)
    );
  }

  if (failed) {
    stderr.writeln('\nwire gate: FAIL — byte axes regressed vs '
        '$baselinePath. If the change is intentional and measured, '
        'update the baseline in the same commit.');
    exitCode = 1;
  } else {
    stdout.writeln('\nwire gate: pass');
  }
}

Future<void> _capture(
  _GateScenario scenario,
  String binary,
  String outBase,
) async {
  final result = await Process.run('dart', [
    'run',
    'capture_pty.dart',
    '--out',
    outBase,
    '--timeout',
    '${scenario.timeoutSeconds}',
    '--cols',
    '120',
    '--rows',
    '32',
    '--ui-mode',
    'full-ui',
    '--frame-count',
    '${scenario.frameCount}',
    '--',
    binary,
    ...scenario.args,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'capture failed for ${scenario.id}:\n${result.stderr}',
    );
  }
}

Map<String, double> _readCapture(String base) {
  final meta =
      jsonDecode(File('$base.json').readAsStringSync()) as Map<String, Object?>;
  final transcript = File('$base.bin').readAsBytesSync();
  final breakdown = AnsiByteBreakdown.analyze(utf8.decode(
    transcript,
    allowMalformed: true,
  ));
  final totalBytes = (meta['totalBytes'] as num).toDouble();
  final frames = (meta['logicalFrameCount'] as num).toDouble();
  return {
    'totalBytes': totalBytes,
    'bytesPerFrame': frames == 0 ? 0 : totalBytes / frames,
    'overheadPercent': breakdown.overheadFraction * 100,
    'ttfbMs': (meta['ttfbMs'] as num).toDouble(),
    'frames': frames,
  };
}

/// Prints the comparison; returns true when the axis FAILS. Pass
/// [failUpFraction] null for warn-only axes.
bool _checkRelative(
  String axis,
  double current,
  double expected, {
  required double? failUpFraction,
}) {
  final delta = expected == 0 ? 0.0 : (current - expected) / expected;
  final summary =
      '  $axis: ${_fmt(current)} vs baseline ${_fmt(expected)} '
      '(${delta >= 0 ? '+' : ''}${(delta * 100).toStringAsFixed(1)}%)';
  if (failUpFraction != null && delta > failUpFraction) {
    stdout.writeln('$summary FAIL');
    return true;
  }
  final warnAt = failUpFraction ?? _timingWarnFraction;
  if (delta.abs() > warnAt) {
    stdout.writeln('$summary warn');
  } else {
    stdout.writeln('$summary ok');
  }
  return false;
}

bool _checkPoints(
  String axis,
  double current,
  double expected, {
  required double failUpPoints,
}) {
  final delta = current - expected;
  final summary =
      '  $axis: ${current.toStringAsFixed(1)} vs baseline '
      '${expected.toStringAsFixed(1)} '
      '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}pt)';
  if (delta > failUpPoints) {
    stdout.writeln('$summary FAIL');
    return true;
  }
  stdout.writeln('$summary ok');
  return false;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
