// Where a one-label (leaf) frame actually spends paint time, on the
// production path: clear the buffer, paint, diff.
//
// FrameDriver already skips true-idle frames (no rebuild, no invalidation).
// This probe forces a render so we can split a *dirty* localized update:
//   - phase times: build / layout / paint / buffer-prepare / diff-finish
//   - repaint-boundary mix: cache misses vs hits vs cells blitted
//
// Modes:
//   clean  — nothing dirty (forced paint; production FrameDriver skips this)
//   leaf   — first visible RenderText, often chrome outside any boundary
//   inside — first visible RenderText under a caching RepaintBoundary
//   full   — every render object marked dirty
//
// Read `inside` as the incremental-cache question: if that frame is a single
// cache miss whose paint is close to `full`, carry-inside-the-cache might
// pay. If `repaintedCount` is 1 and paint is close to `leaf`/`clean`, it
// will not.
//
//   dart run bin/leaf_frame_probe.dart [--cols 120] [--rows 40] [--frames 300]
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' show RepaintBoundaryDebugStats;
import 'package:fleury_samples/samples.dart';

import 'sample_frame_host.dart';

void main(List<String> args) {
  var cols = 120;
  var rows = 40;
  var frames = 300;
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 == args.length) throw ArgumentError('Missing value: ${args[i]}');
    final value = int.parse(args[i + 1]);
    if (value <= 0) throw ArgumentError('Values must be positive');
    switch (args[i]) {
      case '--cols':
        cols = value;
      case '--rows':
        rows = value;
      case '--frames':
        frames = value;
      default:
        throw ArgumentError('Unknown flag: ${args[i]}');
    }
  }
  final size = CellSize(cols, rows);
  stdout.writeln(
    jsonEncode({
      'kind': 'environment',
      'dart': Platform.version,
      'os': Platform.operatingSystem,
      'columns': cols,
      'rows': rows,
      'framesPerMode': frames,
    }),
  );

  final apps = <(String, Widget)>[
    ('dashboard', const DashboardApp()),
    ('agent', const AgentApp()),
    ('files', const FileManagerApp()),
    ('editor', const EditorApp()),
    ('finance', const FinanceApp()),
  ];

  Map<String, int> distribution(List<int> values) {
    final sorted = [...values]..sort();
    return {
      'median': sorted[sorted.length ~/ 2],
      'p95': sorted[(sorted.length * .95).ceil() - 1],
    };
  }

  for (final (name, app) in apps) {
    final host = SampleFrameHost(app, size);
    try {
      for (var i = 0; i < 30; i++) {
        host.frame(host.hasLeaf ? 'leaf' : 'full', i);
      }
      final modes = [
        'clean',
        if (host.hasLeaf) 'leaf',
        if (host.hasInside) 'inside',
        'full',
      ];
      for (final mode in modes) {
        final totals = <int>[];
        final builds = <int>[];
        final layouts = <int>[];
        final paints = <int>[];
        final prepares = <int>[];
        final finishes = <int>[];
        final boundaries = <int>[];
        final repainted = <int>[];
        final cached = <int>[];
        final copied = <int>[];
        var changed = 0;
        for (var i = 0; i < frames; i++) {
          RepaintBoundaryDebugStats.beginFrame(enabled: true);
          final sample = host.frame(mode, i);
          final stats = RepaintBoundaryDebugStats.takeFrameStats();
          totals.add(sample.total);
          builds.add(sample.build);
          layouts.add(sample.layout);
          paints.add(sample.paint);
          prepares.add(sample.prepare);
          finishes.add(sample.finish);
          boundaries.add(stats.boundaryCount);
          repainted.add(stats.repaintedCount);
          cached.add(stats.cachedCount);
          copied.add(stats.copiedCellCount);
          if (sample.changed) changed++;
        }
        stdout.writeln(
          jsonEncode({
            'app': name,
            'mode': mode,
            'renderObjects': host.renderObjects.length,
            'hasLeaf': host.hasLeaf,
            'hasInside': host.hasInside,
            'insideBoundarySize': host.insideBoundarySize == null
                ? null
                : {
                    'cols': host.insideBoundarySize!.cols,
                    'rows': host.insideBoundarySize!.rows,
                  },
            'changedFrames': changed,
            'totalUs': distribution(totals),
            'buildUs': distribution(builds),
            'layoutUs': distribution(layouts),
            'paintUs': distribution(paints),
            'bufferPrepareUs': distribution(prepares),
            'finishUs': distribution(finishes),
            'boundaryCount': distribution(boundaries),
            'repaintedCount': distribution(repainted),
            'cachedCount': distribution(cached),
            'copiedCellCount': distribution(copied),
          }),
        );
      }
    } finally {
      host.tester.dispose();
    }
  }
}
