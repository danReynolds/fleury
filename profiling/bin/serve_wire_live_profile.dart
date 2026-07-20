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
// time, then send the next. Injection starts only after the initial paint
// burst QUIESCES (real frame silence, not a fixed pause), so a trailing
// autofocus/semantics repaint can't masquerade as key 1's response. One key ⟹
// exactly one plan (the scenario app repaints deterministically per keystroke
// and never self-ticks; closed-loop pacing means the frame loop can't merge
// two keys), so an unsolicited plan is detectable. A violated run — a key
// missing its PLAN within the per-key timeout, an unsolicited plan, a dropped
// socket — is DISCARDED and the next run proceeds, exactly like a byte run
// that captures no frames; the probe exits non-zero only when EVERY run
// fails, and the failure kinds distinguish an input→paint break that
// reproduces across runs from repeated socket/infra trouble. The latency
// numbers themselves are machine-sensitive live-socket wall-clock → recorded
// as warn-only axes. Cadence is omitted for this scenario: plan spacing in a
// closed loop measures the injection pacing, not UI cadence.
//
//   dart run bin/serve_wire_live_profile.dart \
//     [--scenario=dashboard|log|counter|input-latency] [--steps=N]
//     [--interval-ms=M] [--samples=N] [--key-timeout-ms=T]
//     [--first-paint-timeout-ms=T] [--runs=R] [--out=path.json]

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';

import 'gate_support.dart';

Future<void> main(List<String> args) async {
  var scenario = 'dashboard';
  var steps = 120;
  var intervalMs = 16;
  var latencySamples = 50;
  var keyTimeoutMs = 2000;
  var firstPaintTimeoutMs = 30000;
  var runs = 3;
  String? outPath;
  for (final arg in args) {
    if (arg.startsWith('--scenario=')) {
      scenario = arg.substring('--scenario='.length);
    } else if (parsePositiveIntFlag(arg, 'steps') case final v?) {
      steps = v;
    } else if (parsePositiveIntFlag(arg, 'interval-ms') case final v?) {
      intervalMs = v;
    } else if (parsePositiveIntFlag(arg, 'samples') case final v?) {
      latencySamples = v;
    } else if (parsePositiveIntFlag(arg, 'key-timeout-ms') case final v?) {
      keyTimeoutMs = v;
    } else if (parsePositiveIntFlag(arg, 'first-paint-timeout-ms')
        case final v?) {
      firstPaintTimeoutMs = v;
    } else if (parsePositiveIntFlag(arg, 'runs') case final v?) {
      runs = v;
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
  final latencyFailures = <_LatencyFailure>[];
  try {
    for (var run = 1; run <= runs; run++) {
      _RunMetrics? m;
      if (latencyMode) {
        final (metrics, failure) = await _captureLatencyRun(
          port,
          samples: latencySamples,
          keyTimeout: Duration(milliseconds: keyTimeoutMs),
          firstPaintTimeout: Duration(milliseconds: firstPaintTimeoutMs),
        );
        m = metrics;
        if (m == null) {
          // One bad run is DISCARDED and the next session tried — a live
          // socket can drop for reasons that aren't an input-path regression
          // (same policy as a byte run that captures no frames). The probe
          // hard-fails below only when every run failed, and the collected
          // kinds tell a reproducing break from repeated infra trouble.
          latencyFailures.add(failure!);
          stderr.writeln('run $run/$runs: input-latency run discarded '
              '(${failure.label}).');
          continue;
        }
      } else {
        m = await _captureOneRun(port, steps, intervalMs);
        if (m == null) {
          stderr.writeln('run $run/$runs: captured NO frames (serve up but no '
              'wire) — treating as a failure.');
          continue;
        }
      }
      samples.add(m);
      final timing = m.latencyP50Ms != null
          ? 'input→paint p50 ${m.latencyP50Ms!.toStringAsFixed(1)} '
              'p95 ${m.latencyP95Ms!.toStringAsFixed(1)} '
              'max ${m.latencyMaxMs!.toStringAsFixed(1)} ms '
              '(${m.latencySamples} keys)'
          : 'cadence p50 ${m.cadenceP50Ms!.toStringAsFixed(1)} '
              'p95 ${m.cadenceP95Ms!.toStringAsFixed(1)} ms';
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
    if (latencyMode) {
      // Every run was discarded — classify so a reproducing input-path break
      // reads differently from an unlucky environment.
      final String why;
      if (latencyFailures.every((f) => f == _LatencyFailure.keyTimeout)) {
        why = 'every run lost a key to the per-key timeout — the input→paint '
            'path is broken (reproduces across $runs run(s)).';
      } else if (latencyFailures
          .every((f) => f == _LatencyFailure.extraPlans)) {
        why = 'every run saw unsolicited PLAN frames — one-key⟹one-plan '
            'attribution is broken: either the scenario app self-ticks, or '
            'the frame loop now emits more than one plan per input event.';
      } else if (latencyFailures.every((f) =>
          f == _LatencyFailure.infra || f == _LatencyFailure.noInitialPaint)) {
        why = 'every run died on socket/infra failures before any key timed '
            'out — suspect the serve process or environment, not the input '
            'path.';
      } else {
        why = 'every run was discarded for mixed reasons '
            '(${latencyFailures.map((f) => f.label).join(', ')}) — see the '
            'per-run lines above.';
      }
      stderr.writeln('serve live-wire: input-latency FAILED — $why');
    } else {
      stderr.writeln('serve live-wire: FAILED — no run captured any frames. '
          'Baseline NOT written. (serve booted but the wire produced nothing '
          '— a broken INIT handshake or a crashed scenario app.)');
    }
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

/// Why one closed-loop latency run was discarded. The caller retries and
/// hard-fails only when EVERY run is discarded; the kinds separate an
/// input-path break that reproduces from repeated environment trouble.
enum _LatencyFailure {
  /// Socket closed/errored mid-run — infrastructure, not the input path.
  infra('socket dropped'),

  /// INIT never produced a first PLAN (session never painted).
  noInitialPaint('no initial paint'),

  /// An injected key was never answered by a PLAN within the per-key timeout.
  keyTimeout('per-key timeout'),

  /// More PLANs than keys — one-key⟹one-plan attribution broke.
  extraPlans('unsolicited plan');

  const _LatencyFailure(this.label);
  final String label;
}

/// Keys injected before sampling starts, to warm the input path's JIT.
const _latencyWarmupKeys = 5;

/// One closed-loop G4 latency session against the `input-latency` scenario:
/// connect (deflate off), INIT, wait for the initial paint burst to QUIESCE,
/// then inject keys one at a time — arm a waiter, timestamp, send the
/// INPUT_EVENT, await the PLAN it provokes, record elapsed. The next key is
/// only sent after the previous plan (plus a short drain pause), so the frame
/// loop can never coalesce two keystrokes into one frame and every sample
/// attributes cleanly.
///
/// Returns `(metrics, null)` on success, or `(null, kind)` when the run must
/// be DISCARDED: a key with no PLAN within [keyTimeout], an unsolicited PLAN
/// (one-key⟹one-plan broke — the scenario self-ticked or the frame loop
/// emitted more than one plan per event), a dropped socket, or no initial
/// paint within [firstPaintTimeout]. The caller retries discarded runs like
/// the byte scenarios and fails hard only when every run is discarded.
///
/// The first [_latencyWarmupKeys] keys are not recorded. Latency numbers are
/// wall-clock over a live socket — reported and baselined as warn-only axes,
/// never gated. Cadence is not computed here: plan spacing in a closed loop
/// measures the injection pacing, not UI cadence.
Future<(_RunMetrics?, _LatencyFailure?)> _captureLatencyRun(
  int port, {
  required int samples,
  required Duration keyTimeout,
  required Duration firstPaintTimeout,
}) async {
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
  final sw = Stopwatch()..start();
  var lastFrameAtMs = 0.0;
  var socketDown = false;
  Completer<double>? planWaiter;

  final sub = ws.listen(
    (data) {
      if (data is! List<int>) return;
      // Clock FIRST: the sample timestamp must not absorb the byte
      // accounting below — encodeFrame re-encodes every frame in the chunk,
      // and charging that work to the latency axis would couple it to frame
      // sizes and inflate p95.
      final receivedAt = sw.elapsedMicroseconds / 1000.0;
      lastFrameAtMs = receivedAt;
      allBytes.addAll(data);
      decoder.feed(data);
      for (final frame in decoder.drain()) {
        if (frame is PlanFrame) {
          if (planWaiter case final w? when !w.isCompleted) {
            w.complete(receivedAt);
          }
          planBytes.add(encodeFrame(frame).length);
        } else if (frame is SemanticsFrame) {
          semanticsBytes.add(encodeFrame(frame).length);
        } else {
          otherBytes += encodeFrame(frame).length;
        }
      }
    },
    onDone: () {
      socketDown = true;
      if (planWaiter case final w? when !w.isCompleted) {
        w.completeError(StateError('socket closed'));
      }
    },
    onError: (Object e) {
      socketDown = true;
      if (planWaiter case final w? when !w.isCompleted) {
        w.completeError(StateError('socket error: $e'));
      }
    },
  );

  // Awaits the ALREADY-ARMED waiter; callers arm before sending so the
  // responding plan cannot slip through before the completer exists.
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
        '${firstPaintTimeout.inMilliseconds}ms of INIT — session never '
        'painted.');
    await cleanup();
    return (
      null,
      socketDown ? _LatencyFailure.infra : _LatencyFailure.noInitialPaint,
    );
  }
  // Quiesce before injecting: the initial burst is not necessarily one frame
  // — a late autofocus- or semantics-driven repaint can trail the first
  // paint by more than any fixed pause (a cold `dart run` app compounds it),
  // and landing inside key 1's window it would read as an unsolicited plan.
  // Wait for real frame silence, capped — a session that never goes quiet is
  // exactly the self-ticking defect the loop's extra-plan check exists to
  // catch, so the cap hands over to it rather than hanging.
  const quietMs = 300.0;
  const quiesceCapMs = 5000.0;
  final quiesceStart = sw.elapsedMicroseconds / 1000.0;
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final now = sw.elapsedMicroseconds / 1000.0;
    if (now - lastFrameAtMs >= quietMs) break;
    if (now - quiesceStart >= quiesceCapMs) break;
  }

  final latencies = <double>[];
  var extraPlans = 0;
  final totalKeys = _latencyWarmupKeys + samples;
  for (var i = 0; i < totalKeys; i++) {
    final plansBefore = planBytes.length;
    planWaiter = Completer<double>();
    final sentAt = sw.elapsedMicroseconds / 1000.0;
    ws.add(encodeFrame(const InputEventFrame(KeyEvent(KeyCode.char('k')))));
    final arrival = await awaitPlan(keyTimeout);
    if (arrival == null) {
      final infra = socketDown;
      stderr.writeln(infra
          ? 'input-latency: socket dropped at key ${i + 1}/$totalKeys.'
          : 'input-latency: key ${i + 1}/$totalKeys got no PLAN within '
              '${keyTimeout.inMilliseconds}ms.');
      await cleanup();
      return (
        null,
        infra ? _LatencyFailure.infra : _LatencyFailure.keyTimeout,
      );
    }
    if (i >= _latencyWarmupKeys) latencies.add(arrival - sentAt);
    await Future<void>.delayed(drainPause);
    extraPlans += planBytes.length - plansBefore - 1;
  }
  await cleanup();

  if (extraPlans != 0) {
    stderr.writeln('input-latency: $extraPlans unsolicited PLAN frame(s) '
        'during the closed loop — one-key⟹one-plan attribution broke: either '
        'the scenario app self-ticked, or the frame loop emitted more than '
        'one plan for a single input event (e.g. the per-event frame and the '
        'setState frame no longer coalesce).');
    return (null, _LatencyFailure.extraPlans);
  }

  int steadySum(List<int> xs) =>
      xs.length > 1 ? xs.sublist(1).fold<int>(0, (a, b) => a + b) : 0;
  int steadyN(List<int> xs) => xs.length > 1 ? xs.length - 1 : 0;
  final sorted = [...latencies]..sort();

  return (
    _RunMetrics(
      planFrames: planBytes.length,
      semanticsFrames: semanticsBytes.length,
      totalBytes: allBytes.length,
      deflatedBytes: ZLibCodec(raw: true, level: 6).encode(allBytes).length,
      planBytesPerFrame: steadyN(planBytes) == 0
          ? 0
          : steadySum(planBytes) / steadyN(planBytes),
      semanticsBytesPerFrame: steadyN(semanticsBytes) == 0
          ? 0
          : steadySum(semanticsBytes) / steadyN(semanticsBytes),
      otherBytes: otherBytes,
      timedOut: false,
      latencyP50Ms: _percentile(sorted, 0.50),
      latencyP95Ms: _percentile(sorted, 0.95),
      latencyMaxMs: sorted.isEmpty ? 0 : sorted.last,
      latencySamples: sorted.length,
    ),
    null,
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
    'semanticsBytesPerFrame':
        med1(samples.map((s) => s.semanticsBytesPerFrame)),
    'totalBytes': med(samples.map((s) => s.totalBytes)),
    'deflatedBytes': med(samples.map((s) => s.deflatedBytes)),
    'otherBytes': med(samples.map((s) => s.otherBytes)),
    // Omitted for input-latency runs (null there): closed-loop plan spacing
    // is injection pacing, not UI cadence — writing it would invite reading
    // a meaningless number.
    if (samples.every((s) => s.cadenceP50Ms != null)) ...{
      'cadenceP50Ms': med1(samples.map((s) => s.cadenceP50Ms!)),
      'cadenceP95Ms': med1(samples.map((s) => s.cadenceP95Ms!)),
    },
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

final class _RunMetrics {
  _RunMetrics({
    required this.planFrames,
    required this.semanticsFrames,
    required this.totalBytes,
    required this.deflatedBytes,
    required this.planBytesPerFrame,
    required this.semanticsBytesPerFrame,
    required this.otherBytes,
    required this.timedOut,
    this.cadenceP50Ms,
    this.cadenceP95Ms,
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
  final bool timedOut;

  /// Plan-arrival spacing — null for the `input-latency` scenario, where
  /// spacing measures the injection loop's pacing, not UI cadence.
  final double? cadenceP50Ms;
  final double? cadenceP95Ms;

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
