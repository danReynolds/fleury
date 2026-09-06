// Full semantic snapshot construction after a settled visual frame.
// Informational AOT timings; excludes visual frames, coverage and transport.
// Idle/retained-leaf flushes do not normally perform this full walk.
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

import 'sample_frame_host.dart';

void main(List<String> args) {
  final frames = args.isEmpty ? 300 : int.parse(args.single);
  if (frames <= 0) throw ArgumentError('frames must be positive');
  final cases = <(String, Widget)>[
    ('dashboard', const DashboardApp()),
    ('agent', const AgentApp()),
    ('files', const FileManagerApp()),
    ('editor', const EditorApp()),
    ('finance', const FinanceApp()),
    for (final count in [50, 200, 1000])
      for (final keyedRows in [false, true])
        (
          'rows-$count-keyed-$keyedRows',
          ScrollView(
              child: Column(
            key: const ValueKey('rows'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < count; i++)
                Text('row $i: a settled log message',
                    key: keyedRows ? ValueKey(i) : null),
            ],
          ))
        ),
  ];
  for (final (name, app) in cases) {
    final host = SampleFrameHost(app, const CellSize(120, 40));
    try {
      final times = <int>[];
      SemanticTree? tree;
      for (var i = -30; i < frames; i++) {
        final watch = Stopwatch()..start();
        tree = SemanticTree.fromElement(host.tester.root!);
        watch.stop();
        if (i >= 0) times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      stdout.writeln(jsonEncode({
        'case': name,
        'frames': frames,
        'nodes': tree!.nodeCount,
        'medianUs': times[times.length ~/ 2],
        'p95Us': times[(times.length * .95).ceil() - 1],
        'dart': Platform.version,
      }));
    } finally {
      host.tester.dispose();
    }
  }
}
