// Ordinary short-label status screens receiving a burst of model updates before
// one frame. Measures notification delivery, rebuild, paint, exact diff and,
// optionally, full semantic delivery. No transport or physical display latency.
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';

import 'sample_frame_host.dart';

class BurstModel extends ChangeNotifier {
  int value = 0;
  void publish(int next) {
    value = next;
    notifyListeners();
  }
}

class BurstScope extends InheritedNotifier<BurstModel> {
  const BurstScope({required super.notifier, required super.child});
  static BurstModel watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BurstScope>()!.notifier;
}

class _Status extends StatelessWidget {
  const _Status(this.index, this.record);
  final int index;
  final void Function(int, int) record;
  @override
  Widget build(BuildContext context) {
    final value = BurstScope.watch(context).value;
    record(index, value);
    return SizedBox(width: 27, child: Text('Service $index: $value'));
  }
}

class BurstWorkload {
  BurstWorkload({required this.count, required this.structured}) {
    host = SampleFrameHost(
      BurstScope(
        notifier: model,
        child: Column(children: [
          const Text('Service status'),
          for (var row = 0; row < (count + 3) ~/ 4; row++)
            Row(children: [
              for (var col = 0; col < 4 && row * 4 + col < count; col++)
                _Status(row * 4 + col, (index, value) {
                  observed[index] = value;
                  builds++;
                }),
            ]),
        ]),
      ),
      const CellSize(120, 40),
    );
    if (structured) {
      pipeline = FrameSemanticsPipeline(
        presenter: presenter,
        dirtyTracker: host.tester.owner.semanticDirtyTracker,
        readRoot: () => host.tester.root,
        flushScheduler: _ManualScheduler(),
      );
      host.frame('clean', 0, onFramePresented: _present);
      pipeline!.flushNow('initial');
    }
  }
  final int count;
  final bool structured;
  final model = BurstModel();
  final observed = <int, int>{};
  final presenter = _Encoder();
  late final SampleFrameHost host;
  FrameSemanticsPipeline? pipeline;
  int builds = 0;

  void _present(TuiRenderedFrame frame) => pipeline!.onFramePresented(frame,
      const FramePresentationPlanner().build(reason: 'probe', frame: frame));

  ({int totalUs, int notifyUs, int buildUs, bool changed, int builds}) frame(
      int iteration, int burst) {
    final beforeBuilds = builds;
    final watch = Stopwatch()..start();
    pipeline?.markSemanticsDirty();
    for (var update = 0; update < burst; update++) {
      // The final value alternates even for even-sized bursts, so every frame
      // changes visible output. Intermediate notifications represent a feed.
      model.publish(update == burst - 1 ? iteration & 1 : 100 + update);
    }
    final notifyUs = watch.elapsedMicroseconds;
    final frame = host.frame('clean', iteration,
        onFramePresented: structured ? _present : null);
    pipeline?.flushNow('model');
    watch.stop();
    if (observed.length != count ||
        observed.values.any((value) => value != (iteration & 1))) {
      throw StateError('A subscriber missed the final model value');
    }
    return (
      totalUs: watch.elapsedMicroseconds,
      notifyUs: notifyUs,
      buildUs: frame.build,
      changed: frame.changed,
      builds: builds - beforeBuilds
    );
  }

  int fingerprint() {
    var hash = 0x811c9dc5;
    for (final unit in host.tester.renderToString().codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  void dispose() {
    pipeline?.dispose();
    host.tester.dispose();
    model.dispose();
  }
}

class _ManualScheduler implements SemanticFlushScheduler {
  @override
  void schedule(void Function() flush) {}
  @override
  void dispose() {}
}

class _Encoder implements SemanticFramePresenter {
  final encoder = SemanticsWireEncoder();
  int frames = 0;
  int bytes = 0;
  @override
  SemanticPresentationStats present(SemanticTree tree,
      {SemanticTreeUpdate? update}) {
    final encoded = encoder.encodeTree(tree, update: update);
    if (encoded != null) {
      frames++;
      bytes += encoded.length;
    }
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

void main(List<String> args) {
  final iterations = args.isEmpty ? 500 : int.parse(args[0]);
  if (iterations < 1) throw ArgumentError('iterations must be positive');
  stdout.writeln(
      jsonEncode({'dart': Platform.version, 'iterations': iterations}));
  for (final structured in [false, true]) {
    for (final count in [16, 64, 128]) {
      for (final burst in [1, 8, 64]) {
        final workload = BurstWorkload(count: count, structured: structured);
        try {
          for (var i = -100; i < 0; i++) workload.frame(i, burst);
          final totals = <int>[], notifications = <int>[], builds = <int>[];
          var changed = 0, rebuilds = 0;
          final beforeFrames = workload.presenter.frames;
          final beforeBytes = workload.presenter.bytes;
          for (var i = 0; i < iterations; i++) {
            final sample = workload.frame(i, burst);
            totals.add(sample.totalUs);
            notifications.add(sample.notifyUs);
            builds.add(sample.buildUs);
            if (sample.changed) changed++;
            rebuilds += sample.builds;
          }
          totals.sort();
          notifications.sort();
          builds.sort();
          stdout.writeln(jsonEncode({
            'surface': structured ? 'structured' : 'terminal',
            'subscribers': count,
            'notifications': burst,
            'iterations': iterations,
            'medianUs': totals[iterations ~/ 2],
            'p95Us': totals[(iterations * .95).ceil() - 1],
            'notifyMedianUs': notifications[iterations ~/ 2],
            'buildMedianUs': builds[iterations ~/ 2],
            'changedFrames': changed,
            'subscriberBuilds': rebuilds,
            'semanticFrames': workload.presenter.frames - beforeFrames,
            'semanticBytes': workload.presenter.bytes - beforeBytes,
            'fingerprint': workload.fingerprint(),
          }));
        } finally {
          workload.dispose();
        }
      }
    }
  }
}
