import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:fleury_samples/samples.dart';

import '../sample_frame_host.dart';
import 'catalog.dart';
import 'list_rebuild.dart';

typedef MeasurementHook = Future<void> Function();

class WorkloadFailure implements Exception {
  WorkloadFailure(this.error, this.partial);
  final Object error;
  final Map<String, Object?> partial;
  @override
  String toString() => '$error';
}

/// Raw rows stay in memory until the timed workload ends. No printing, semantic
/// decoding, wire re-encoding, or profiling RPC happens in a timing window.
Future<Map<String, Object?>> runWorkload(LabOptions options,
    {MeasurementHook? start, MeasurementHook? stop}) async {
  final result = isListRebuild(options.scenario)
      ? await runListRebuild(options, start: start, stop: stop)
      : isPipeline(options.scenario)
          ? await _pipeline(options, start, stop)
          : await _interactive(options, start, stop);
  return {
    'schema': labSchema,
    'config': options.toJson(),
    'runtime': Platform.version,
    'status': 'complete',
    ...result,
    // These include setup and harness allocations; not heap or window peaks.
    'processRssAtEndBytes': ProcessInfo.currentRss,
    'processLifetimeMaxRssBytes': ProcessInfo.maxRss,
  };
}

Widget _panes(int count) {
  const columns = 8;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var row = 0; row < (count / columns).ceil(); row++)
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var col = 0; col < columns && row * columns + col < count; col++)
            SizedBox(
                width: 15,
                height: 3,
                child: Text('Pane ${row * columns + col}: wrapping text')),
        ]),
    ],
  );
}

Future<Map<String, Object?>> _pipeline(
    LabOptions o, MeasurementHook? start, MeasurementHook? stop) async {
  final app = switch (o.scenario) {
    'dashboard-leaf' || 'resize' => const DashboardApp(),
    'editor-leaf' => const EditorApp(),
    _ => _panes(int.parse(o.scenario.split('-').last)),
  };
  final host = SampleFrameHost(app, const CellSize(120, 40));
  final rows = <Map<String, num>>[];
  var changed = 0;
  try {
    if (o.scenario != 'resize' && !host.hasLeaf) {
      throw StateError('Fixture has no visible mutable leaf');
    }
    FrameSample frame(int i) {
      if (o.scenario != 'resize') return host.frame('leaf', i);
      // Include invalidation caused by the resize, not only the later layout.
      final watch = Stopwatch()..start();
      host.size = i.isEven ? const CellSize(100, 32) : const CellSize(120, 40);
      final s = host.frame('clean', i);
      return FrameSample(watch.elapsedMicroseconds, s.build, s.layout, s.paint,
          s.prepare, s.finish, s.changed);
    }

    for (var i = 0; i < o.warmup; i++) {
      frame(i);
    }
    await start?.call();
    for (var i = 0; i < o.samples; i++) {
      final s = frame(o.warmup + i);
      if (s.changed) changed++;
      rows.add({
        'id': i,
        'totalUs': s.total,
        'buildUs': s.build,
        'layoutUs': s.layout,
        'paintUs': s.paint,
        'bufferPrepareUs': s.prepare,
        'diffAndPlanUs': s.finish,
      });
    }
    await stop?.call();
    if (changed != o.samples) {
      throw StateError('Only $changed/${o.samples} mutations changed output');
    }
    return {
      'metrics': [
        'totalUs',
        'buildUs',
        'layoutUs',
        'paintUs',
        'bufferPrepareUs',
        'diffAndPlanUs'
      ],
      'samples': rows,
      'checks': {'changedFrames': changed, 'expectedFrames': o.samples},
      'renderObjects': host.renderObjects.length,
    };
  } catch (e) {
    throw WorkloadFailure(e, {'samples': rows, 'changedFrames': changed});
  } finally {
    host.tester.dispose();
  }
}

class _Ticket {
  _Ticket(this.id, this.enqueuedUs);
  final int id, enqueuedUs;
  int dispatchUs = 0, settledUs = 0;
  final done = Completer<void>();
}

class _Peer implements RemoteFrameTransport {
  final input = StreamController<RemoteFrame>.broadcast();
  final output = <RemoteFrame>[];
  final ready = Completer<void>();
  Completer<void>? _drain;
  Timer? _timer;
  @override
  Stream<RemoteFrame> get incoming => input.stream;
  @override
  bool get isSendBacklogged => _drain != null;
  @override
  Future<void> get sendDrained => _drain?.future ?? Future<void>.value();
  void stall(Duration duration) {
    if (_drain != null) throw StateError('Overlapping sink stalls');
    _drain = Completer<void>();
    _timer = Timer(duration, _release);
  }

  void _release() {
    final drain = _drain;
    _drain = null;
    drain?.complete();
  }

  @override
  void send(RemoteFrame frame) {
    if (isSendBacklogged) throw StateError('Output produced while backlogged');
    output.add(frame);
    if (frame is SemanticsFrame && !ready.isCompleted) ready.complete();
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _release();
    if (!input.isClosed) await input.close();
  }
}

class _Fixture extends StatefulWidget {
  const _Fixture(this.text, this.list,
      {required this.listMode, required this.withLog, required this.onEdit});
  final TextEditingController text;
  final ListController list;
  final bool listMode, withLog;
  final void Function() onEdit;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  int edits = 0;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.listMode)
            TextInput(
                controller: widget.text,
                autofocus: true,
                enableBlink: false,
                semanticLabel: 'Input',
                onChanged: (_) {
                  widget.onEdit();
                  if (widget.withLog) setState(() => edits++);
                }),
          Expanded(
              child: ListView.builder(
            controller: widget.list,
            autofocus: widget.listMode,
            selectable: widget.listMode,
            itemCount: widget.listMode ? 100000 : 1000 + edits,
            itemBuilder: (_, i, __) => Text(widget.listMode
                ? 'Item $i'
                : 'Log entry $i; input edits: $edits'),
          )),
        ],
      );
}

Future<Map<String, Object?>> _interactive(
    LabOptions o, MeasurementHook? start, MeasurementHook? stop) async {
  final text = TextEditingController();
  final list = ListController();
  final peer = _Peer();
  final clock = Stopwatch()..start();
  final pending = Queue<_Ticket>();
  final decoder = SemanticsWireDecoder();
  SemanticTree? tree;
  final batch = o.scenario == 'burst' || o.scenario == 'slow-output';
  final rows = <Map<String, num>>[];
  final batches = <Map<String, num>>[];
  var nextId = 0, plans = 0, semanticBytes = 0, wireBytes = 0;
  var appliedEdits = 0;
  final done = runApp(
    TickerMode(
        enabled: false,
        child: _Fixture(text, list,
            listMode: o.scenario == 'list',
            withLog: batch,
            onEdit: () => appliedEdits++)),
    driver: RemoteTerminalDriver(peer),
    enableHotReload: false,
    requireInteractiveTerminal: false,
    debug: const DebugConfig(enabled: false),
    onEvent: (event) {
      // INIT/resize events are setup, not workload tickets.
      if (event is ResizeEvent) return null;
      if (pending.isEmpty) throw StateError('Unexpected input: $event');
      final ticket = pending.removeFirst();
      ticket.dispatchUs = clock.elapsedMicroseconds;
      Timer.run(() {
        ticket.settledUs = clock.elapsedMicroseconds;
        ticket.done.complete();
      });
      return null;
    },
  );
  scheduleMicrotask(() => peer.input.add(const InitFrame(
      size: CellSize(120, 40),
      colorMode: ColorMode.truecolor,
      imageProtocol: ImageProtocol.halfBlock,
      tmuxPassthrough: false)));
  void consume({required bool measured}) {
    for (final frame in peer.output) {
      if (frame is SemanticsFrame) {
        tree = decoder.apply(frame.json);
        if (tree == null) throw StateError('Broken semantic delta chain');
        if (measured) semanticBytes += frame.json.length;
      }
      if (measured) {
        if (frame is PlanFrame) plans++;
        wireBytes += encodeFrame(frame).length;
      }
    }
    peer.output.clear();
  }

  try {
    await peer.ready.future.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    consume(measured: false);
    var expectedText = '';
    for (var iteration = -o.warmup; iteration < o.samples; iteration++) {
      if (iteration == 0) await start?.call();
      final measured = iteration >= 0;
      final events = <TuiEvent>[];
      if (batch) {
        for (var j = 0; j < 16; j++) {
          events.add(j.isEven
              ? const TextInputEvent('a')
              : const KeyEvent(KeyCode.backspace));
        }
        expectedText = '';
      } else if (o.scenario == 'list') {
        events.add(const KeyEvent(KeyCode.arrowDown));
      } else if (o.scenario == 'paste') {
        // Clear outside the timing window, then measure the real paste path.
        text.text = '';
        await Future<void>.delayed(Duration.zero);
        consume(measured: false);
        expectedText = List.filled(4096, 'p').join();
        events.add(PasteEvent(expectedText));
      } else {
        expectedText = expectedText.isEmpty ? 'a' : '';
        events.add(expectedText.isEmpty
            ? const KeyEvent(KeyCode.backspace)
            : const TextInputEvent('a'));
      }
      final batchStart = clock.elapsedMicroseconds;
      if (o.scenario == 'slow-output') {
        peer.stall(const Duration(milliseconds: 10));
      }
      final tickets = <_Ticket>[];
      for (final event in events) {
        final ticket = _Ticket(nextId++, clock.elapsedMicroseconds);
        pending.add(ticket);
        tickets.add(ticket);
        peer.input.add(InputEventFrame(event));
      }
      await Future.wait(tickets.map((t) => t.done.future))
          .timeout(const Duration(seconds: 10));
      await peer.sendDrained.timeout(const Duration(seconds: 10));
      // Backpressure's resume frame may run after the dispatch checkpoints.
      await Future<void>.delayed(Duration.zero);
      final drainedUs = clock.elapsedMicroseconds - batchStart;
      consume(measured: measured);
      if (o.scenario == 'list') {
        final expected = iteration + o.warmup + 1;
        if (list.currentIndex != expected) {
          throw StateError(
              'Lost navigation: ${list.currentIndex} != $expected');
        }
      } else {
        if (appliedEdits != nextId ||
            text.text != expectedText ||
            tree?.byLabel('Input').single.value != expectedText) {
          throw StateError('Lost input or stale final semantic output');
        }
      }
      if (measured) {
        batches.add({'id': iteration, 'drainUs': drainedUs});
        for (final t in tickets) {
          rows.add({
            'id': rows.length,
            'totalUs': t.settledUs - t.enqueuedUs,
            'queueUs': t.dispatchUs - t.enqueuedUs,
            'dispatchToCheckpointUs': t.settledUs - t.dispatchUs
          });
        }
      }
    }
    await stop?.call();
    if (pending.isNotEmpty) throw StateError('Undispatched inputs remain');
    return {
      'metrics': ['totalUs', 'queueUs', 'dispatchToCheckpointUs'],
      'samples': rows,
      'batches': batches,
      'checks': {
        'processedInputs': rows.length,
        'expectedInputs': o.samples * (batch ? 16 : 1),
        if (o.scenario != 'list')
          'appliedEdits': appliedEdits - o.warmup * (batch ? 16 : 1),
        'finalStateVerified': true,
        'semanticChainVerified': true
      },
      'output': {
        'plans': plans,
        'semanticBytes': semanticBytes,
        'encodedWireBytes': wireBytes
      },
    };
  } catch (e) {
    throw WorkloadFailure(e, {
      'samples': rows,
      'batches': batches,
      'undispatchedInputs': pending.length,
      'output': {
        'plans': plans,
        'semanticBytes': semanticBytes,
        'encodedWireBytes': wireBytes
      }
    });
  } finally {
    await peer.close();
    await done.timeout(const Duration(seconds: 5));
    text.dispose();
    list.dispose();
  }
}
