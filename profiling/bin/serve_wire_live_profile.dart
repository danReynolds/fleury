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
// Byte accounting is PER DECODED FRAME (each frame's size = encodeFrame(f).length,
// bucketed by type), not per WS message — serve forwards raw socket chunks, so a
// chunk can carry several frames or split one, and message-level bucketing would
// mis-attribute the plan/semantics split. The client connects with permessage-
// deflate OFF, so the bytes it receives are the true pre-deflate on-wire frames;
// the post-deflate size is accounted offline with whole-stream DEFLATE. NOTE:
// whole-stream DEFLATE is a proxy — production permessage-deflate compresses
// per-message, so this over-states achievable compression (it's a stable,
// comparable regression signal, matching serve_wire_profile.dart's method, not a
// production-accurate figure). totalBytes/deflatedBytes are stable within a small
// coalescing margin run-to-run; the gate keys on them, bytes/frame is noisier.
//
// The `input-latency` scenario is the G4 input→paint latency probe and runs a
// different, CLOSED-LOOP session: the app idles until a key arrives, and the
// client injects one key at a time — arm, timestamp, send INPUT_EVENT (0x14),
// wait for the PLAN (0x12) frame that keystroke provokes, record the elapsed
// time, then send the next. One key ⟹ exactly one plan (the scenario app
// changes fixed-width content on every keystroke and never self-ticks), so
// coalescing can't merge samples and an unsolicited plan is detectable — both
// are STRUCTURAL failures (exit 1), as is any key whose plan doesn't arrive
// within a generous per-key timeout. The latency numbers themselves are
// machine-sensitive live-socket timing → recorded as warn-only axes, exactly
// like cadence.
//
//   dart run bin/serve_wire_live_profile.dart \
//     [--scenario=dashboard|log|counter|input-latency] [--steps=N]
//     [--interval-ms=M] [--samples=N] [--runs=R] [--out=path.json]

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  var scenario = 'dashboard';
  var steps = 120;
  var intervalMs = 16;
  var latencySamples = 50;
  var runs = 3;
  String? outPath;
  for (final arg in args) {
    if (arg.startsWith('--scenario=')) {
      scenario = arg.substring('--scenario='.length);
    } else if (arg.startsWith('--steps=')) {
      steps = _intArg(arg, '--steps=');
    } else if (arg.startsWith('--interval-ms=')) {
      intervalMs = _intArg(arg, '--interval-ms=');
    } else if (arg.startsWith('--samples=')) {
      latencySamples = _intArg(arg, '--samples=');
    } else if (arg.startsWith('--runs=')) {
      runs = _intArg(arg, '--runs=');
    } else if (arg.startsWith('--out=')) {
      outPath = arg.substring('--out='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  final latencyMode = scenario == 'input-latency';

  final paths = _resolvePaths();
  final port = await _unusedLoopbackPort();
  stdout.writeln(
    latencyMode
        ? 'serve live-wire: scenario=$scenario samples=$latencySamples '
              'runs=$runs port=$port'
        : 'serve live-wire: scenario=$scenario steps=$steps '
              'interval=${intervalMs}ms runs=$runs port=$port',
  );

  final serve = await _bootServe(paths, port, scenario, steps, intervalMs);
  final samples = <_RunMetrics>[];
  try {
    for (var run = 1; run <= runs; run++) {
      final m = latencyMode
          ? await _captureLatencyRun(port, samples: latencySamples)
          : await _captureOneRun(port, steps, intervalMs);
      if (m == null) {
        if (latencyMode) {
          // A key that got no PLAN (or an unsolicited one) is a broken
          // input→paint path — structural, never retried into passing.
          stderr.writeln('run $run/$runs: input-latency closed loop FAILED '
              'structurally (see above) — aborting.');
          exitCode = 1;
          return;
        }
        stderr.writeln('run $run/$runs: captured NO frames (serve up but no '
            'wire) — treating as a failure.');
        continue;
      }
      samples.add(m);
      final timing = m.latencyP50Ms != null
          ? 'input→paint p50 ${m.latencyP50Ms!.toStringAsFixed(1)} '
                'p95 ${m.latencyP95Ms!.toStringAsFixed(1)} '
                'max ${m.latencyMaxMs!.toStringAsFixed(1)} ms '
                '(${m.latencySamples} keys)'
          : 'cadence p50 ${m.cadenceP50Ms.toStringAsFixed(1)} '
                'p95 ${m.cadenceP95Ms.toStringAsFixed(1)} ms';
      stdout.writeln(
        'run $run/$runs: plan ${m.planFrames}f '
        '${m.planBytesPerFrame.toStringAsFixed(1)} B/f · '
        'semantics ${m.semanticsFrames}f '
        '${m.semanticsBytesPerFrame.toStringAsFixed(1)} B/f · '
        'total ${m.totalBytes} B raw / ${m.deflatedBytes} B deflated · '
        '$timing'
        '${m.timedOut ? '  (hit hard cap)' : ''}',
      );
    }
  } finally {
    await _shutdown(serve);
  }

  if (samples.isEmpty) {
    stderr.writeln('serve live-wire: FAILED — no run captured any frames. '
        'Baseline NOT written. (serve booted but the wire produced nothing — '
        'a broken INIT handshake or a crashed scenario app.)');
    exitCode = 1;
    return;
  }

  final result = _median(scenario, steps, intervalMs, samples);
  stdout.writeln('');
  stdout.writeln(
    latencyMode
        ? 'median: input→paint p50 ${result['latencyP50Ms']} ms · '
              'p95 ${result['latencyP95Ms']} ms · '
              'total ${result['totalBytes']} B raw / '
              '${result['deflatedBytes']} B deflated'
        : 'median: plan ${result['planBytesPerFrame']} B/f · '
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
/// producing frames. Returns null if the session captured no frames at all
/// (a failed capture the caller must not treat as a valid sample).
Future<_RunMetrics?> _captureOneRun(int port, int steps, int intervalMs) async {
  final ws = await WebSocket.connect(
    'ws://127.0.0.1:$port/ws',
    headers: {'origin': 'http://127.0.0.1:$port'},
    compression: CompressionOptions.compressionOff,
  );
  final decoder = FrameDecoder();
  final allBytes = <int>[];
  // Per-decoded-frame wire size (encodeFrame(f).length), bucketed by type —
  // coalescing- and split-immune, unlike bucketing whole-message lengths.
  final planBytes = <int>[];
  final semanticsBytes = <int>[];
  var otherBytes = 0;
  final planArrivalMs = <double>[];
  final sw = Stopwatch()..start();
  var lastFrameMs = 0.0;
  var anyFrame = false;
  var timedOut = false;
  final done = Completer<void>();

  final sub = ws.listen(
    (data) {
      if (data is! List<int>) return;
      allBytes.addAll(data);
      decoder.feed(data);
      for (final frame in decoder.drain()) {
        final bytes = encodeFrame(frame).length;
        final now = sw.elapsedMicroseconds / 1000.0;
        anyFrame = true;
        lastFrameMs = now;
        if (frame is PlanFrame) {
          planBytes.add(bytes);
          planArrivalMs.add(now);
        } else if (frame is SemanticsFrame) {
          semanticsBytes.add(bytes);
        } else {
          otherBytes += bytes;
        }
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

  // The app ticks `steps` times then idles. Complete once frames go quiet for
  // `quietMs` — but only AFTER the nominal run length has elapsed, so a cold-JIT
  // or GC stall early in the run can't truncate the capture. A generous quiet
  // window (>> a typical GC pause) guards mid-run stalls; the hard cap is the
  // backstop for a genuine hang.
  const quietMs = 1500;
  final expectedMs = steps * intervalMs;
  final quietPoll = Timer.periodic(const Duration(milliseconds: 100), (t) {
    final now = sw.elapsedMicroseconds / 1000.0;
    if (anyFrame && now > expectedMs && now - lastFrameMs > quietMs) {
      if (!done.isCompleted) done.complete();
      t.cancel();
    }
  });
  await done.future.timeout(
    Duration(milliseconds: expectedMs * 2 + 10000),
    onTimeout: () {
      timedOut = true;
    },
  );
  quietPoll.cancel();
  await sub.cancel();
  await ws.close();

  if (!anyFrame) return null; // captured nothing — a failed session.

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
    timedOut: timedOut,
  );
}

/// One closed-loop G4 latency session against the `input-latency` scenario:
/// connect (deflate off), INIT, wait for the initial paint, then inject keys
/// one at a time — arm a waiter, timestamp, send the INPUT_EVENT, await the
/// PLAN it provokes, record elapsed. The next key is only sent after the
/// previous plan (plus a short drain pause), so the app can never coalesce
/// two keystrokes into one frame and every sample attributes cleanly.
///
/// Structural guarantees (returns null = FAIL, caller aborts):
///   - every injected key gets a PLAN within [_keyTimeout];
///   - no unsolicited PLAN arrives during the loop (one key ⟹ one plan —
///     an extra plan means the scenario self-ticked or attribution broke).
///
/// The first [_warmupKeys] keys warm the input path's JIT and are not
/// recorded. Latency numbers are wall-clock over a live socket — reported and
/// baselined as warn-only axes, never gated.
Future<_RunMetrics?> _captureLatencyRun(int port, {required int samples}) async {
  const warmupKeys = 5;
  const keyTimeout = Duration(seconds: 2);
  // A fresh session may cold-start the scenario-app subprocess (`dart run`
  // JIT) — the initial paint gets a far larger budget than a keystroke.
  const firstPaintTimeout = Duration(seconds: 30);
  // Post-plan pause before the next key: lets the same-task SEMANTICS frame
  // (and any wrongly unsolicited PLAN) drain so per-key accounting is exact.
  const drainPause = Duration(milliseconds: 10);

  final ws = await WebSocket.connect(
    'ws://127.0.0.1:$port/ws',
    headers: {'origin': 'http://127.0.0.1:$port'},
    compression: CompressionOptions.compressionOff,
  );
  final decoder = FrameDecoder();
  final allBytes = <int>[];
  final planBytes = <int>[];
  final semanticsBytes = <int>[];
  var otherBytes = 0;
  final planArrivalMs = <double>[];
  final sw = Stopwatch()..start();
  Completer<double>? planWaiter;

  final sub = ws.listen(
    (data) {
      if (data is! List<int>) return;
      allBytes.addAll(data);
      decoder.feed(data);
      for (final frame in decoder.drain()) {
        final bytes = encodeFrame(frame).length;
        final now = sw.elapsedMicroseconds / 1000.0;
        if (frame is PlanFrame) {
          planBytes.add(bytes);
          planArrivalMs.add(now);
          if (planWaiter case final w? when !w.isCompleted) w.complete(now);
        } else if (frame is SemanticsFrame) {
          semanticsBytes.add(bytes);
        } else {
          otherBytes += bytes;
        }
      }
    },
    onDone: () {
      if (planWaiter case final w? when !w.isCompleted) {
        w.completeError(StateError('socket closed'));
      }
    },
    onError: (Object e) {
      if (planWaiter case final w? when !w.isCompleted) {
        w.completeError(StateError('socket error: $e'));
      }
    },
  );

  // Arms a fresh waiter; the caller sends AFTER arming so the responding
  // plan cannot slip through before the completer exists.
  Future<double?> awaitPlan(Duration timeout) async {
    try {
      return await planWaiter!.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } on StateError catch (e) {
      stderr.writeln('input-latency: $e while waiting for a PLAN frame.');
      return null;
    } finally {
      planWaiter = null;
    }
  }

  Future<void> cleanup() async {
    await sub.cancel();
    await ws.close();
  }

  planWaiter = Completer<double>();
  ws.add(encodeFrame(const InitFrame(
    size: CellSize(120, 40),
    colorMode: ColorMode.truecolor,
    imageProtocol: ImageProtocol.halfBlock,
    tmuxPassthrough: false,
    protocolVersion: remoteProtocolVersion,
  )));
  if (await awaitPlan(firstPaintTimeout) == null) {
    stderr.writeln('input-latency: no initial PLAN within '
        '${firstPaintTimeout.inSeconds}s of INIT — session never painted.');
    await cleanup();
    return null;
  }
  // Let the initial burst (first semantics tree, any follow-up paint from
  // autofocus) fully drain before the loop starts attributing plans to keys.
  await Future<void>.delayed(const Duration(milliseconds: 500));

  final latencies = <double>[];
  var extraPlans = 0;
  for (var i = 0; i < warmupKeys + samples; i++) {
    final plansBefore = planBytes.length;
    planWaiter = Completer<double>();
    final sentAt = sw.elapsedMicroseconds / 1000.0;
    ws.add(encodeFrame(const InputEventFrame(KeyEvent(char: 'k'))));
    final arrival = await awaitPlan(keyTimeout);
    if (arrival == null) {
      stderr.writeln('input-latency: key ${i + 1}/${warmupKeys + samples} got '
          'no PLAN within ${keyTimeout.inSeconds}s — the input→paint path is '
          'broken (or catastrophically slow).');
      await cleanup();
      return null;
    }
    if (i >= warmupKeys) latencies.add(arrival - sentAt);
    await Future<void>.delayed(drainPause);
    extraPlans += planBytes.length - plansBefore - 1;
  }
  await cleanup();

  if (extraPlans != 0) {
    stderr.writeln('input-latency: $extraPlans unsolicited PLAN frame(s) '
        'during the closed loop — one-key⟹one-plan attribution is broken '
        '(did the scenario start self-ticking?).');
    return null;
  }

  int steadySum(List<int> xs) =>
      xs.length > 1 ? xs.sublist(1).fold<int>(0, (a, b) => a + b) : 0;
  int steadyN(List<int> xs) => xs.length > 1 ? xs.length - 1 : 0;
  final cadences = <double>[
    for (var i = 1; i < planArrivalMs.length; i++)
      planArrivalMs[i] - planArrivalMs[i - 1],
  ]..sort();
  final sorted = [...latencies]..sort();

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
    timedOut: false,
    latencyP50Ms: _percentile(sorted, 0.50),
    latencyP95Ms: _percentile(sorted, 0.95),
    latencyMaxMs: sorted.isEmpty ? 0 : sorted.last,
    latencySamples: sorted.length,
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
  final stderrSub = proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    stderrLines.add(line);
    if (line.contains('spawn mode') && !ready.isCompleted) ready.complete();
  });
  unawaited(proc.stdout.drain<void>().catchError((_) {}));
  try {
    await ready.future.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    // Kill the orphaned serve (and its warm-standby scenario subprocess) rather
    // than leaking them holding the port + CPU.
    await stderrSub.cancel();
    await _shutdown(proc);
    throw StateError(
      'serve did not start within 20s. stderr:\n${stderrLines.join('\n')}',
    );
  }
  return proc;
}

Future<void> _shutdown(Process proc) async {
  proc.kill(ProcessSignal.sigint);
  await proc.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      proc.kill(ProcessSignal.sigkill);
      return -9;
    },
  );
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
    // Closed-loop input→paint axes (input-latency scenario only). Warn-only
    // downstream: wall-clock timing over a live socket is machine-sensitive.
    if (samples.every((s) => s.latencyP50Ms != null)) ...{
      'latencySamples': med(samples.map((s) => s.latencySamples!)),
      'latencyP50Ms': med1(samples.map((s) => s.latencyP50Ms!)),
      'latencyP95Ms': med1(samples.map((s) => s.latencyP95Ms!)),
      'latencyMaxMs': med1(samples.map((s) => s.latencyMaxMs!)),
    },
  };
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  return sorted[(p * (sorted.length - 1)).round()];
}

int _intArg(String arg, String prefix) {
  final raw = arg.substring(prefix.length);
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    stderr.writeln('invalid $prefix value: "$raw" (want a positive integer)');
    exit(64);
  }
  return value;
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
    required this.timedOut,
    this.latencyP50Ms,
    this.latencyP95Ms,
    this.latencyMaxMs,
    this.latencySamples,
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
  final bool timedOut;

  /// Closed-loop input→paint numbers — non-null only for the `input-latency`
  /// scenario ([_captureLatencyRun]).
  final double? latencyP50Ms;
  final double? latencyP95Ms;
  final double? latencyMaxMs;
  final int? latencySamples;
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
  final fleuryCli = '${repo.path}/packages/fleury/bin/fleury.dart';
  final scenarioApp = '${bin.path}/serve_scenario_app.dart';
  for (final p in [fleuryCli, scenarioApp]) {
    if (!File(p).existsSync()) {
      stderr.writeln('cannot resolve harness paths from '
          '${Platform.script} — missing $p. Run via `dart run` from the '
          'profiling package (not a relocated snapshot).');
      exit(70);
    }
  }
  return _Paths(profiling.path, fleuryCli, scenarioApp);
}

Future<int> _unusedLoopbackPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}
