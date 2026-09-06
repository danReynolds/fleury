// Informational AOT probe for ordinary app mount and widget-state updates.
// Timings include reconciliation and frame construction, excluding terminal
// encoding/transport/display. Labels are short; there is no document fixture.
import 'dart:convert';
import 'dart:io';
import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_host.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury_samples/samples.dart';
import 'sample_frame_host.dart';

void report(String scenario, String mode, List<int> values, int changed,
    {String surface = 'terminal', int? fingerprint, Map<String, int>? phases}) {
  values.sort();
  stdout.writeln(jsonEncode({
    'scenario': scenario,
    'mode': mode,
    'iterations': values.length,
    'medianUs': values[values.length ~/ 2],
    'p95Us': values[(values.length * .95).ceil() - 1],
    'changedFrames': changed,
    'surface': surface,
    'fingerprint': fingerprint,
    if (phases != null) 'phasesUs': phases,
  }));
}

void main(List<String> args) {
  final iterations = args.isEmpty ? 100 : int.parse(args.first);
  stdout.writeln(
      jsonEncode({'dart': Platform.version, 'iterations': iterations}));
  if (iterations <= 0) throw ArgumentError('iterations must be positive');
  final structured = args.length > 1 && args[1] == 'structured';
  final surface = structured ? 'structured' : 'terminal';
  const size = CellSize(120, 40);
  if (!structured)
    for (final (name, app) in <(String, Widget)>[
      ('dashboard', const DashboardApp()),
      ('agent', const AgentApp()),
      ('files', const FileManagerApp()),
      ('editor', const EditorApp()),
      ('finance', const FinanceApp()),
    ]) {
      final values = <int>[];
      for (var i = -15; i < iterations; i++) {
        final watch = Stopwatch()..start();
        final host = SampleFrameHost(app, size, settle: false);
        host.frame('clean', 0);
        watch.stop();
        if (i >= 0) values.add(watch.elapsedMicroseconds);
        host.tester.dispose();
      }
      report(name, 'mount-first-frame', values, iterations);
    }
  for (final count in [16, 64, 256]) {
    for (final keyed in [false, true]) {
      final key = GlobalKey<_BoardState>();
      final host =
          SampleFrameHost(_Board(key: key, count: count, keyed: keyed), size);
      final semantics = structured ? _SemanticHost(host) : null;
      if (semantics != null) {
        host.frame('clean', 0, onFramePresented: semantics.presentFrame);
        semantics.pipeline.flushNow('initial');
      }
      try {
        for (final mode in [
          'one-label',
          'all-labels',
          'reverse',
          'replace-subtree'
        ]) {
          final values = <int>[];
          var changed = 0;
          final phaseValues = <String, List<int>>{
            for (final phase in [
              'build',
              'layout',
              'paint',
              'semantics',
              'semanticTree',
              'coverage',
              'semanticDiff',
              'semanticEncode'
            ])
              phase: [],
          };
          for (var i = -30; i < iterations; i++) {
            final watch = Stopwatch()..start();
            semantics?.pipeline.markSemanticsDirty();
            key.currentState!.advance(mode);
            final frame = host.frame('clean', i,
                onFramePresented: semantics?.presentFrame);
            semantics?.pipeline.flushNow('input');
            watch.stop();
            if (i >= 0) {
              values.add(watch.elapsedMicroseconds);
              if (frame.changed) changed++;
              phaseValues['build']!.add(frame.build);
              phaseValues['layout']!.add(frame.layout);
              phaseValues['paint']!.add(frame.paint);
              final stats = semantics?.lastStats;
              phaseValues['semantics']!
                  .add(stats?.totalFlushTime.inMicroseconds ?? 0);
              phaseValues['semanticTree']!
                  .add(stats?.treeBuildTime.inMicroseconds ?? 0);
              phaseValues['coverage']!
                  .add(stats?.coverageTime.inMicroseconds ?? 0);
              phaseValues['semanticDiff']!
                  .add(stats?.diffTime.inMicroseconds ?? 0);
              phaseValues['semanticEncode']!
                  .add(stats?.presenterTime.inMicroseconds ?? 0);
            }
          }
          final output = host.tester.renderToString();
          report('board-$count-keyed-$keyed', mode, values, changed,
              surface: surface,
              fingerprint: _fingerprint(output),
              phases: {
                for (final entry in phaseValues.entries)
                  entry.key: _median(entry.value)
              });
        }
      } finally {
        semantics?.pipeline.dispose();
        host.tester.dispose();
      }
    }
  }
}

class _Board extends StatefulWidget {
  const _Board({super.key, required this.count, required this.keyed});
  final int count;
  final bool keyed;
  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> {
  int tick = 0;
  String mode = 'one-label';
  void advance(String next) => setState(() {
        tick++;
        mode = next;
      });
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var slot = 0; slot < widget.count; slot++)
          _StatusRow(
            key: widget.keyed
                ? ValueKey(mode == 'reverse' && tick.isOdd
                    ? widget.count - slot - 1
                    : slot)
                : null,
            index: mode == 'reverse' && tick.isOdd
                ? widget.count - slot - 1
                : slot,
            value: mode == 'all-labels' || slot == 0 ? tick & 1 : 0,
            nested: mode == 'replace-subtree' && tick.isOdd,
          ),
      ]);
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(
      {super.key,
      required this.index,
      required this.value,
      required this.nested});
  final int index, value;
  final bool nested;
  @override
  Widget build(BuildContext context) {
    final content = Text('Service $index: $value');
    return nested
        ? Padding(padding: const EdgeInsets.only(left: 1), child: content)
        : content;
  }
}

int _median(List<int> values) {
  values.sort();
  return values[values.length ~/ 2];
}

int _fingerprint(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

class _ManualSemanticScheduler implements SemanticFlushScheduler {
  @override
  void schedule(
      void Function()
          flush) {} // The probe explicitly flushes after each committed frame.
  @override
  void dispose() {}
}

class _EncodingPresenter implements SemanticFramePresenter {
  final encoder = SemanticsWireEncoder();
  int bytes = 0;
  @override
  SemanticPresentationStats present(SemanticTree tree,
      {SemanticTreeUpdate? update}) {
    bytes += encoder.encodeTree(tree, update: update)?.length ?? 0;
    return SemanticPresentationStats(
      nodeCount: tree.nodeCount,
      addedNodeCount: update?.added.length ?? 0,
      removedNodeCount: update?.removed.length ?? 0,
      updatedNodeCount: update?.updated.length ?? 0,
      createdElementCount: 0,
      reusedElementCount: 0,
      replacedElementCount: 0,
      attributesSetCount: 0,
      attributesRemovedCount: 0,
    );
  }

  @override
  Future<void> dispose() async {}
}

class _SemanticHost {
  _SemanticHost(SampleFrameHost host) {
    pipeline = FrameSemanticsPipeline(
      presenter: _EncodingPresenter(),
      dirtyTracker: host.tester.owner.semanticDirtyTracker,
      readRoot: () => host.tester.root,
      flushScheduler: _ManualSemanticScheduler(),
      onFlushStats: (stats) => lastStats = stats,
    );
  }
  late final FrameSemanticsPipeline pipeline;
  SemanticFlushStats? lastStats;
  void presentFrame(TuiRenderedFrame frame) => pipeline.onFramePresented(frame,
      const FramePresentationPlanner().build(reason: 'probe', frame: frame));
}
