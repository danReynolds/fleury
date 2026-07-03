// Live serve-wire profiler — the missing measurement for the `fleury serve`
// surface. Boots the real CLI in `--spawn` mode against an animated runApp
// scenario, connects a headless WebSocket "browser," and records the REAL
// frames serve pushes over the socket: plan vs semantics bytes/frame, frame
// counts, cadence, and the deflate-accounted wire size. Unlike
// serve_wire_profile.dart (which computes buildRemotePlan in-process and only
// counts PLAN bytes), this exercises the whole live path — the frame loop,
// producer gate/backpressure, coalescing, the v2 INIT handshake, AND the
// semantics stream that rides the same socket (invisible to the synthetic tool
// but often the dominant wire cost on text-heavy UIs).
//
// The client connects with permessage-deflate OFF, so the bytes it receives are
// the true pre-deflate on-wire frames; the post-deflate size is accounted
// offline with whole-stream DEFLATE (the same proxy serve_wire_profile uses),
// keeping the two comparable. (True on-wire compressed bytes under production
// permessage-deflate is a v2 raw-socket refinement.)
//
//   dart run bin/serve_wire_live_profile.dart \
//     [--scenario=dashboard|log|counter] [--steps=N] [--interval-ms=M]
//     [--runs=R] [--out=path.json]

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  var scenario = 'dashboard';
  var steps = 120;
  var intervalMs = 16;
  var runs = 3;
  String? outPath;
  for (final arg in args) {
    if (arg.startsWith('--scenario=')) {
      scenario = arg.substring('--scenario='.length);
    } else if (arg.startsWith('--steps=')) {
      steps = int.parse(arg.substring('--steps='.length));
    } else if (arg.startsWith('--interval-ms=')) {
      intervalMs = int.parse(arg.substring('--interval-ms='.length));
    } else if (arg.startsWith('--runs=')) {
      runs = int.parse(arg.substring('--runs='.length));
    } else if (arg.startsWith('--out=')) {
      outPath = arg.substring('--out='.length);
    }
  }

  final paths = _resolvePaths();
  final port = await _unusedLoopbackPort();
  stdout.writeln(
    'serve live-wire: scenario=$scenario steps=$steps interval=${intervalMs}ms '
    'runs=$runs port=$port',
  );

  final serve = await _bootServe(paths, port, scenario, steps, intervalMs);
  final samples = <_RunMetrics>[];
  try {
    for (var run = 1; run <= runs; run++) {
      final m = await _captureOneRun(port, steps, intervalMs);
      samples.add(m);
      stdout.writeln(
        'run $run/$runs: plan ${m.planFrames}f '
        '${m.planBytesPerFrame.toStringAsFixed(1)} B/f · '
        'semantics ${m.semanticsFrames}f '
        '${m.semanticsBytesPerFrame.toStringAsFixed(1)} B/f · '
        'total ${m.totalBytes} B raw / ${m.deflatedBytes} B deflated · '
        'cadence p50 ${m.cadenceP50Ms.toStringAsFixed(1)} '
        'p95 ${m.cadenceP95Ms.toStringAsFixed(1)} ms',
      );
    }
  } finally {
    serve.kill(ProcessSignal.sigint);
    await serve.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        serve.kill(ProcessSignal.sigkill);
        return -9;
      },
    );
  }

  final result = _median(scenario, steps, intervalMs, samples);
  stdout.writeln('');
  stdout.writeln(
    'median: plan ${result['planBytesPerFrame']} B/f · '
    'semantics ${result['semanticsBytesPerFrame']} B/f · '
    'total ${result['totalBytes']} B raw / ${result['deflatedBytes']} B '
    'deflated · p95 cadence ${result['cadenceP95Ms']} ms',
  );
  if (outPath != null) {
    File(outPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
    stdout.writeln('wrote $outPath');
  }
}

/// One WS session: connect (deflate off), INIT, capture until the app stops
/// producing frames, then classify bytes by frame type and compute metrics.
Future<_RunMetrics> _captureOneRun(int port, int steps, int intervalMs) async {
  final ws = await WebSocket.connect(
    'ws://127.0.0.1:$port/ws',
    headers: {'origin': 'http://127.0.0.1:$port'},
    compression: CompressionOptions.compressionOff,
  );
  final decoder = FrameDecoder();
  final allBytes = <int>[];
  // Raw WS-message size, bucketed by the message's dominant frame type. A
  // message almost always carries one frame; when it carries several, plan
  // wins over semantics wins over other (a conservative attribution).
  final planBytes = <int>[];
  final semanticsBytes = <int>[];
  var otherBytes = 0;
  final planArrivalMs = <double>[];
  final sw = Stopwatch()..start();
  var lastFrameMs = 0.0;
  final done = Completer<void>();

  ws.listen(
    (data) {
      if (data is! List<int>) return;
      allBytes.addAll(data);
      decoder.feed(data);
      var hasPlan = false;
      var hasSemantics = false;
      for (final frame in decoder.drain()) {
        if (frame is PlanFrame) {
          hasPlan = true;
        } else if (frame is SemanticsFrame) {
          hasSemantics = true;
        }
      }
      final now = sw.elapsedMicroseconds / 1000.0;
      if (hasPlan) {
        planBytes.add(data.length);
        planArrivalMs.add(now);
        lastFrameMs = now;
      } else if (hasSemantics) {
        semanticsBytes.add(data.length);
        lastFrameMs = now;
      } else {
        otherBytes += data.length;
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    onError: (_) {
      if (!done.isCompleted) done.complete();
    },
  );

  ws.add(encodeFrame(const InitFrame(
    size: CellSize(120, 40),
    colorMode: ColorMode.truecolor,
    imageProtocol: ImageProtocol.halfBlock,
    tmuxPassthrough: false,
    protocolVersion: remoteProtocolVersion,
  )));

  // The app ticks `steps` times then idles; the run is done once frames go
  // quiet for `quietMs` (after ≥1 PLAN), bounded by a hard cap.
  const quietMs = 500;
  final expectedMs = steps * intervalMs;
  final quietPoll = Timer.periodic(const Duration(milliseconds: 100), (t) {
    final now = sw.elapsedMicroseconds / 1000.0;
    if (planArrivalMs.isNotEmpty && now - lastFrameMs > quietMs) {
      if (!done.isCompleted) done.complete();
      t.cancel();
    }
  });
  await done.future.timeout(
    Duration(milliseconds: expectedMs * 2 + 8000),
    onTimeout: () {},
  );
  quietPoll.cancel();
  await ws.close();

  // Steady-state excludes the first frame of each kind (the initial full paint
  // / first semantic tree after INIT).
  int steadySum(List<int> xs) =>
      xs.length > 1 ? xs.sublist(1).fold<int>(0, (a, b) => a + b) : 0;
  int steadyN(List<int> xs) => xs.length > 1 ? xs.length - 1 : 0;
  final cadences = <double>[
    for (var i = 1; i < planArrivalMs.length; i++)
      planArrivalMs[i] - planArrivalMs[i - 1],
  ]..sort();

  return _RunMetrics(
    planFrames: planBytes.length,
    semanticsFrames: semanticsBytes.length,
    totalBytes: allBytes.length,
    deflatedBytes: ZLibCodec(raw: true, level: 6).encode(allBytes).length,
    planBytesPerFrame:
        steadyN(planBytes) == 0 ? 0 : steadySum(planBytes) / steadyN(planBytes),
    semanticsBytesPerFrame: steadyN(semanticsBytes) == 0
        ? 0
        : steadySum(semanticsBytes) / steadyN(semanticsBytes),
    otherBytes: otherBytes,
    cadenceP50Ms: _percentile(cadences, 0.50),
    cadenceP95Ms: _percentile(cadences, 0.95),
  );
}

Future<Process> _bootServe(
  _Paths paths,
  int port,
  String scenario,
  int steps,
  int intervalMs,
) async {
  final proc = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      paths.fleuryCli,
      'serve',
      '--port=$port',
      '--spawn',
      Platform.resolvedExecutable,
      'run',
      paths.scenarioApp,
      scenario,
      '--steps=$steps',
      '--interval-ms=$intervalMs',
    ],
    workingDirectory: paths.profilingRoot,
  );
  final ready = Completer<void>();
  final stderrLines = <String>[];
  proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    stderrLines.add(line);
    if (line.contains('spawn mode') && !ready.isCompleted) ready.complete();
  });
  proc.stdout.drain<void>();
  await ready.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw StateError(
      'serve did not start within 20s. stderr:\n${stderrLines.join('\n')}',
    ),
  );
  return proc;
}

Map<String, Object?> _median(
  String scenario,
  int steps,
  int intervalMs,
  List<_RunMetrics> samples,
) {
  double med(Iterable<num> xs) {
    final s = xs.map((x) => x.toDouble()).toList()..sort();
    return s.isEmpty ? 0 : s[s.length ~/ 2];
  }

  double med1(Iterable<num> xs) => double.parse(med(xs).toStringAsFixed(1));

  return <String, Object?>{
    'scenario': scenario,
    'steps': steps,
    'intervalMs': intervalMs,
    'runs': samples.length,
    'planFrames': med(samples.map((s) => s.planFrames)),
    'semanticsFrames': med(samples.map((s) => s.semanticsFrames)),
    'planBytesPerFrame': med1(samples.map((s) => s.planBytesPerFrame)),
    'semanticsBytesPerFrame': med1(samples.map((s) => s.semanticsBytesPerFrame)),
    'totalBytes': med(samples.map((s) => s.totalBytes)),
    'deflatedBytes': med(samples.map((s) => s.deflatedBytes)),
    'otherBytes': med(samples.map((s) => s.otherBytes)),
    'cadenceP50Ms': med1(samples.map((s) => s.cadenceP50Ms)),
    'cadenceP95Ms': med1(samples.map((s) => s.cadenceP95Ms)),
  };
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  return sorted[(p * (sorted.length - 1)).round()];
}

final class _RunMetrics {
  _RunMetrics({
    required this.planFrames,
    required this.semanticsFrames,
    required this.totalBytes,
    required this.deflatedBytes,
    required this.planBytesPerFrame,
    required this.semanticsBytesPerFrame,
    required this.otherBytes,
    required this.cadenceP50Ms,
    required this.cadenceP95Ms,
  });
  final int planFrames;
  final int semanticsFrames;
  final int totalBytes;
  final int deflatedBytes;
  final double planBytesPerFrame;
  final double semanticsBytesPerFrame;
  final int otherBytes;
  final double cadenceP50Ms;
  final double cadenceP95Ms;
}

final class _Paths {
  _Paths(this.profilingRoot, this.fleuryCli, this.scenarioApp);
  final String profilingRoot;
  final String fleuryCli;
  final String scenarioApp;
}

_Paths _resolvePaths() {
  // .../profiling/bin/serve_wire_live_profile.dart
  final bin = File(Platform.script.toFilePath()).parent;
  final profiling = bin.parent;
  final repo = profiling.parent;
  return _Paths(
    profiling.path,
    '${repo.path}/packages/fleury/bin/fleury.dart',
    '${bin.path}/serve_scenario_app.dart',
  );
}

Future<int> _unusedLoopbackPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}
