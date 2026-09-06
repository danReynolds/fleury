// Informational AOT probe for the shared buffer lifecycle on sample apps.
// Measures mutation -> clear -> build/layout/paint -> exact diff -> commit,
// with debug counters disabled. No ANSI encoding, transport or terminal paint.
// A clean frame is FORCED here; production idle skips rendering altogether.
//
// dart compile exe bin/frame_pipeline_probe.dart -o /tmp/frame-pipeline
// /tmp/frame-pipeline --cols 120 --rows 40 --frames 300
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
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
  stdout.writeln(jsonEncode({
    'kind': 'environment',
    'dart': Platform.version,
    'os': Platform.operatingSystem,
    'cpus': Platform.numberOfProcessors,
    'columns': cols,
    'rows': rows,
    'framesPerMode': frames,
    'warmupFrames': 30,
    'initializationFrames': 30,
  }));
  for (final (name, app) in <(String, Widget)>[
    ('dashboard', const DashboardApp()),
    ('agent', const AgentApp()),
    ('files', const FileManagerApp()),
    ('editor', const EditorApp()),
    ('finance', const FinanceApp()),
  ]) {
    final host = SampleFrameHost(app, size);
    try {
      for (var i = 0; i < 30; i++) {
        host.frame(host.hasLeaf ? 'leaf' : 'full', i);
      }
      final samples = {
        for (final mode in ['clean', if (host.hasLeaf) 'leaf', 'full'])
          mode: <FrameSample>[],
      };
      for (var i = 0; i < frames; i++) {
        for (final mode in samples.keys) {
          samples[mode]!.add(host.frame(mode, i));
        }
      }
      for (final MapEntry(key: mode, value: values) in samples.entries) {
        Map<String, int> distribution(int Function(FrameSample) read) {
          final sorted = values.map(read).toList()..sort();
          return {
            'median': sorted[sorted.length ~/ 2],
            'p95': sorted[(sorted.length * .95).ceil() - 1]
          };
        }

        stdout.writeln(jsonEncode({
          'app': name,
          'mode': mode,
          'renderObjects': host.renderObjects.length,
          'leafRenderObjectIndex': host.leafRenderObjectIndex,
          'changedFrames': values.where((s) => s.changed).length,
          'totalUs': distribution((s) => s.total),
          'buildUs': distribution((s) => s.build),
          'layoutUs': distribution((s) => s.layout),
          'paintUs': distribution((s) => s.paint),
          'bufferPrepareUs': distribution((s) => s.prepare),
          'finishUs': distribution((s) => s.finish),
        }));
      }
    } finally {
      host.tester.dispose();
    }
  }
}
