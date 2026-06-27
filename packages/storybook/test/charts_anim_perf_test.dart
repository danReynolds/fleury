@TestOn('vm')
@Tags(['perf'])
library;

// Assesses the served chart animation: drives the real playing BarChart story
// through runApp + the structured serve path for a wall-clock window and
// reports the wire frame rate (the user-visible update rate) and bytes/frame.
// Run with: dart test test/charts_anim_perf_test.dart --tags perf

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/remote_transport.dart';
import 'package:fleury_storybook/storybook.dart';
import 'package:test/test.dart';

class _FakeTransport implements RemoteFrameTransport {
  final _in = StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = [];
  bool closed = false;
  @override
  Stream<RemoteFrame> get incoming => _in.stream;
  @override
  void send(RemoteFrame frame) => sent.add(frame);
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void emit(RemoteFrame frame) {
    if (!_in.isClosed) _in.add(frame);
  }

  Future<void> disconnect() async {
    if (!_in.isClosed) await _in.close();
  }
}

const _init = InitFrame(
  size: CellSize(120, 40),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
);

void main() {
  test('PERF: served BarChart animation wire rate + bytes/frame', () async {
    final transport = _FakeTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));
    final done = runApp(
      StorybookApp(
        initialStoryId: 'visualization.charts.bar-chart',
        initialControlValues: const <String, Object?>{'play': 1},
      ),
      driver: driver,
      requireInteractiveTerminal: false,
    );

    // Let the session settle AND warm the JIT (the first second of an un-AOT'd
    // run recompiles hot paths and skews the rate), then measure a steady-state
    // window. The production serve runs an AOT warm-standby binary, so the warm
    // number is the representative one.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final before = transport.sent.whereType<PlanFrame>().length;
    final sw = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    sw.stop();
    final steady = transport.sent.whereType<PlanFrame>().toList().sublist(
      before,
    );

    final secs = sw.elapsedMilliseconds / 1000.0;
    final fps = steady.length / secs;
    final sizes = steady.map((f) => encodeRemotePlan(f.plan).length).toList()
      ..sort();
    final avgBytes = sizes.isEmpty
        ? 0
        : (sizes.reduce((a, b) => a + b) / sizes.length).round();
    final patchCells = steady
        .map(
          (f) => f.plan.patches.fold<int>(
            0,
            (n, p) => n + p.runs.fold<int>(0, (m, r) => m + r.text.length),
          ),
        )
        .fold<int>(0, (a, b) => a + b);
    // ignore: avoid_print
    print(
      'PERF served BarChart animation:\n'
      '  steady frames: ${steady.length} in ${secs.toStringAsFixed(2)}s '
      '=> ${fps.toStringAsFixed(1)} fps (wire)\n'
      '  bytes/frame: avg=$avgBytes  p50=${sizes.isEmpty ? 0 : sizes[sizes.length ~/ 2]}  '
      'max=${sizes.isEmpty ? 0 : sizes.last}\n'
      '  ~changed glyph cells/frame: '
      '${steady.isEmpty ? 0 : (patchCells / steady.length).round()}',
    );

    expect(steady, isNotEmpty, reason: 'the chart should be animating');

    await transport.disconnect();
    await done;
  });
}
