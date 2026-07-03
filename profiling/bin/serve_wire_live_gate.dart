// Regression gate for the live `fleury serve` wire. Runs the live-wire profiler
// across a fixed scenario set and compares plan + semantics bytes/frame against
// serve_wire_live_baseline.json. Byte axes FAIL beyond the tolerance; cadence
// is warn-only (it's timing-sensitive on a live socket). On-demand, not CI —
// each scenario boots a real serve process.
//
//   dart run bin/serve_wire_live_gate.dart [--runs=R] [--update-baseline]
//
// Unlike the synthetic serve_wire_profile, this catches regressions in the
// WHOLE served surface — including the semantics stream, which dominates the
// wire (5–13× plan bytes) and is invisible to the in-process tool.

import 'dart:convert';
import 'dart:io';

const _baselinePath = 'serve_wire_live_baseline.json';

// Byte axes fail beyond this relative increase. Generous: a live socket + real
// frame loop is noisier than the in-process wire gate.
const _byteFailFraction = 0.20;

const _scenarios = <({String id, int steps, int intervalMs})>[
  (id: 'dashboard', steps: 120, intervalMs: 16),
  (id: 'log', steps: 120, intervalMs: 16),
  (id: 'counter', steps: 120, intervalMs: 16),
];

Future<void> main(List<String> args) async {
  var runs = 3;
  var update = false;
  for (final arg in args) {
    if (arg.startsWith('--runs=')) {
      runs = int.parse(arg.substring('--runs='.length));
    } else if (arg == '--update-baseline') {
      update = true;
    }
  }

  final profiler = '${File(Platform.script.toFilePath()).parent.path}'
      '/serve_wire_live_profile.dart';
  final workDir = Directory.systemTemp.createTempSync('serve-wire-gate-');
  final results = <String, Map<String, Object?>>{};
  try {
    for (final s in _scenarios) {
      stdout.writeln('gate: ${s.id}');
      final out = '${workDir.path}/${s.id}.json';
      final r = await Process.run(Platform.resolvedExecutable, [
        'run',
        profiler,
        '--scenario=${s.id}',
        '--steps=${s.steps}',
        '--interval-ms=${s.intervalMs}',
        '--runs=$runs',
        '--out=$out',
      ]);
      if (r.exitCode != 0) {
        stderr.writeln('profiler failed for ${s.id}:\n${r.stdout}\n${r.stderr}');
        exitCode = 1;
        return;
      }
      results[s.id] =
          jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
    }
  } finally {
    workDir.deleteSync(recursive: true);
  }

  final baselineFile = File(_baselinePath);
  if (update) {
    baselineFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(results)}\n',
    );
    stdout.writeln('baseline written to $_baselinePath');
    return;
  }
  if (!baselineFile.existsSync()) {
    stderr.writeln('no baseline at $_baselinePath — run --update-baseline');
    exitCode = 64;
    return;
  }

  final baseline =
      jsonDecode(baselineFile.readAsStringSync()) as Map<String, Object?>;
  var failed = false;
  for (final s in _scenarios) {
    final cur = results[s.id]!;
    final base = baseline[s.id] as Map<String, Object?>?;
    stdout.writeln('\n${s.id}:');
    if (base == null) {
      stdout.writeln('  (no baseline entry — skipped)');
      continue;
    }
    // Gate the STABLE totals: raw + deflated bytes over the fixed scenario are
    // deterministic (identical run-to-run). Per-frame splits are informational
    // only — bytes/frame swings with coalescing/timing on a live socket, so
    // gating it would be flaky. A semantics regression still trips the gate
    // because semantics dominate the total (5–13× plan).
    for (final axis in ['totalBytes', 'deflatedBytes']) {
      failed |= _checkByte(axis, (cur[axis] as num).toDouble(),
          (base[axis] as num).toDouble());
    }
    _warn('planBytesPerFrame', (cur['planBytesPerFrame'] as num).toDouble(),
        (base['planBytesPerFrame'] as num).toDouble());
    _warn('semanticsBytesPerFrame',
        (cur['semanticsBytesPerFrame'] as num).toDouble(),
        (base['semanticsBytesPerFrame'] as num).toDouble());
    _warn('cadenceP95Ms', (cur['cadenceP95Ms'] as num).toDouble(),
        (base['cadenceP95Ms'] as num).toDouble());
  }

  if (failed) {
    stdout.writeln('\nserve wire gate: FAIL — a byte axis regressed beyond '
        '${(_byteFailFraction * 100).toStringAsFixed(0)}%. If intentional, '
        'update the baseline in the same commit.');
    exitCode = 1;
  } else {
    stdout.writeln('\nserve wire gate: pass');
  }
}

bool _checkByte(String axis, double cur, double base) {
  final delta = base == 0 ? 0.0 : (cur - base) / base;
  final fail = delta > _byteFailFraction;
  stdout.writeln('  $axis: ${cur.toStringAsFixed(1)} vs baseline '
      '${base.toStringAsFixed(1)} (${_pct(delta)}) ${fail ? 'FAIL' : 'ok'}');
  return fail;
}

void _warn(String axis, double cur, double base) {
  final delta = base == 0 ? 0.0 : (cur - base) / base;
  stdout.writeln('  $axis: ${cur.toStringAsFixed(1)} vs baseline '
      '${base.toStringAsFixed(1)} (${_pct(delta)}) warn-only');
}

String _pct(double d) =>
    '${d >= 0 ? '+' : ''}${(d * 100).toStringAsFixed(1)}%';
