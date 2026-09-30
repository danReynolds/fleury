// Object-creation regression gate using bounded VM allocation trace windows.
// Heap inventories are not churn counters on Dart 3.12.2. Counts include
// discarded objects and survive GC; the public trace API does not expose
// allocation sizes, so these are objects, never mislabeled bytes.
// Run through fleury_dev.dart benchmark for the required profiler flags.
// Old byte baselines are intentionally incompatible with this measurement.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service_io.dart';

import 'alloc_scenario.dart';
import 'gate_support.dart';
import 'allocation_trace_measure.dart';

const _defaultFrames = 40;
const _defaultWarmup = 300;

/// objects/frame fails beyond this relative increase; a decrease should be locked
/// in with --update-baseline. Deterministic measurement, so this headroom is
/// for SDK / machine drift, not run noise.
const _failFraction = 0.10;

/// Includes core containers and strings created inside the tagged work window.
/// Profiler traffic is excluded. Keep the existing 5% headroom; refresh
/// the baseline after an intentional workload or SDK change.
const _totalFailFraction = 0.05;

Future<void> main(List<String> args) async {
  var frames = _defaultFrames;
  var warmup = _defaultWarmup;
  var top = 12;
  var gate = false;
  var update = false;
  var baselinePath = 'alloc_gate_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (parsePositiveIntFlag(arg, 'frames') case final v?) {
      frames = v;
    } else if (parseIntFlag(arg, 'warmup') case final v?) {
      warmup = v;
    } else if (parseIntFlag(arg, 'top') case final v?) {
      top = v;
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  if (warmup < 0 || top < 0) {
    stderr.writeln('--warmup and --top must be nonnegative');
    exitCode = 64;
    return;
  }

  final info = await developer.Service.getInfo();
  final server = info.serverUri;
  if (server == null) {
    stderr.writeln(
      'alloc_gate: no VM service. Launch with '
      '`dart --enable-vm-service=0 --disable-service-auth-codes '
      'bin/alloc_gate.dart ...` (fleury benchmark alloc-gate does this).',
    );
    exitCode = 64;
    return;
  }
  final wsUri = server.replace(
    scheme: 'ws',
    pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString();

  final service = await vmServiceConnectUri(wsUri);
  try {
    final vm = await service.getVM();
    final isolateId = vm.isolates!.first.id!;

    final owner = BuildOwner();
    final model = AllocModel();
    final root = owner.mountRoot(allocScenario(model));
    final frame = allocFrameDriver(owner: owner, model: model, root: root);

    for (var i = 0; i < warmup; i++) {
      frame();
    }

    final result =
        await measureAllocations(isolateId, iterations: frames, work: frame);
    final perFrame = result.total / frames;
    final projectPerFrame = result.project / frames;

    if (update) {
      writeBaselineJson(baselinePath, {
        'measurement': 'allocation-traces-v1-objects',
        'sdk': Platform.version.split(' ').first,
        'objectsPerFrame': perFrame,
        'projectObjectsPerFrame': projectPerFrame,
        'totalObjects': result.total,
        'projectObjects': result.project,
        'frames': frames,
      });
      stdout.writeln('alloc gate: wrote baseline $baselinePath '
          '(${perFrame.toStringAsFixed(1)} objects/frame total, '
          '${projectPerFrame.toStringAsFixed(1)} objects/frame project, '
          'over $frames frames).');
      return;
    }

    stdout.writeln('per-frame allocation churn over $frames frames:');
    stdout.writeln('  total   ${perFrame.toStringAsFixed(1)} objects/frame '
        '(${result.total} objects)');
    stdout.writeln(
        '  project ${projectPerFrame.toStringAsFixed(1)} objects/frame '
        '(${result.project} objects, '
        '${(result.project * 100 / result.total).toStringAsFixed(1)}%'
        ' of total)');
    stdout.writeln('  top $top allocating classes (window):');
    final ranked = result.classes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final c in ranked.take(top)) {
      stdout.writeln('    ${c.value.toString().padLeft(9)} objects  ${c.key}');
    }

    if (!gate) return;

    final base = readBaselineOrNull(baselinePath, gateName: 'alloc gate');
    if (base == null || base['measurement'] != 'allocation-traces-v1-objects') {
      stderr.writeln('Missing or incompatible trace-count baseline.');
      exitCode = 64;
      return;
    }

    var failed = false;
    void check(
      String axis,
      double measured,
      num? baseline,
      double failFraction,
      String hint,
    ) {
      if (baseline == null) {
        stdout.writeln('alloc gate [$axis]: no baseline recorded — '
            're-baseline with --update-baseline.');
        failed = true;
        return;
      }
      final basePerFrame = baseline.toDouble();
      final limit = basePerFrame * (1 + failFraction);
      final delta = (measured - basePerFrame) / basePerFrame * 100;
      final line =
          'alloc gate [$axis]: ${measured.toStringAsFixed(1)} objects/frame '
          'vs baseline ${basePerFrame.toStringAsFixed(1)} '
          '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%, '
          'limit +${(failFraction * 100).toStringAsFixed(0)}%)';
      if (measured <= limit) {
        stdout.writeln('$line — pass.');
        if (measured < basePerFrame * (1 - failFraction)) {
          stdout.writeln('alloc gate [$axis]: per-frame churn improved '
              '${delta.toStringAsFixed(1)}% below baseline — lock it in with '
              '--update-baseline so the ceiling drops and a later regression '
              "back up to today's baseline can't slip through.");
        }
      } else {
        stdout.writeln('$line — FAIL.');
        stderr.writeln('alloc gate [$axis]: $hint');
        failed = true;
      }
    }

    check(
      'total',
      perFrame,
      base['objectsPerFrame'] as num?,
      _totalFailFraction,
      'measured Dart allocation churn regressed past tolerance. This includes the '
          'dart:core lists, strings and iterators that framework code creates '
          'but does not own — inspect the top-classes breakdown above for the '
          'classes, then use alloc-trace to locate call sites. If the change is '
          'intentional, re-baseline with '
          '--update-baseline.',
    );
    check(
      'project',
      projectPerFrame,
      base['projectObjectsPerFrame'] as num?,
      _failFraction,
      'package:fleury per-frame allocation churn regressed past tolerance. A '
          'new per-frame allocation in build/reconcile/layout/paint/diff? '
          'Inspect the top-classes breakdown above; if the change is '
          'intentional, re-baseline with --update-baseline.',
    );
    if (failed) exitCode = 1;
  } finally {
    await service.dispose();
  }
}
