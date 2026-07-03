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
      final v = int.tryParse(arg.substring('--runs='.length));
      if (v == null || v <= 0) {
        stderr.writeln('invalid --runs (want a positive integer)');
        exitCode = 64;
        return;
      }
      runs = v;
    } else if (arg == '--update-baseline') {
      update = true;
    }
  }

  final scriptDir = File(Platform.script.toFilePath()).parent; // profiling/bin
  final profiler = '${scriptDir.path}/serve_wire_live_profile.dart';
  // The committed baseline lives in profiling/, resolved from the script dir so
  // it's read/written correctly regardless of the caller's CWD.
  final baselinePath = '${scriptDir.parent.path}/serve_wire_live_baseline.json';
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

  final baselineFile = File(baselinePath);
  if (update) {
    baselineFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(results)}\n',
    );
    stdout.writeln('baseline written to $baselinePath');
    return;
  }
  if (!baselineFile.existsSync()) {
    stderr.writeln('no baseline at $baselinePath — run --update-baseline');
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
    // stable within a small coalescing margin run-to-run (empirically ±0.3%, far
    // under the tolerance). Per-frame splits are informational only — bytes/frame
    // swings with coalescing/timing on a live socket, so gating it would be
    // flaky. A semantics regression still trips the gate because semantics
    // dominate the total (5–13× plan). A broken wire is caught upstream: the
    // profiler exits non-zero when a run captures no frames.
    for (final axis in ['totalBytes', 'deflatedBytes']) {
      failed |= _checkByte(axis, _axis(cur, axis, s.id, 'result'),
          _axis(base, axis, s.id, 'baseline'));
    }
    for (final axis in [
      'planBytesPerFrame',
      'semanticsBytesPerFrame',
      'cadenceP95Ms',
    ]) {
      _warn(axis, _axis(cur, axis, s.id, 'result'),
          _axis(base, axis, s.id, 'baseline'));
    }
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

/// Reads a numeric [key] from a result/baseline map with a clear error instead
/// of a bare `Null is not a subtype of num` when a stale baseline lacks the key.
double _axis(Map<String, Object?> m, String key, String scenario, String which) {
  final v = m[key];
  if (v is! num) {
    stderr.writeln('$which JSON for "$scenario" is missing numeric axis "$key" '
        '— rebaseline with --update-baseline.');
    exit(65);
  }
  return v.toDouble();
}
