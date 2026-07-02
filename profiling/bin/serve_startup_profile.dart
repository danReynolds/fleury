// Measures the startup a browser feels hitting `fleury serve`: connect the
// WebSocket, send the v2 INIT handshake, and time until the first PLAN frame
// (the first paint). Run against a live serve on the given port. Repeats to
// capture the per-connection cost (in spawn mode, every connection spawns a
// fresh app — that cold start is what we're attacking).
//
//   dart run bin/serve_startup_profile.dart [port] [reps]

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';

Future<Duration> _connectToFirstPaint(int port) async {
  final sw = Stopwatch()..start();
  final ws = await WebSocket.connect(
    'ws://127.0.0.1:$port/ws',
    headers: {'origin': 'http://127.0.0.1:$port'},
  );
  final firstPlan = Completer<Duration>();
  final decoder = FrameDecoder();
  ws.listen((data) {
    decoder.feed(data is List<int> ? data : <int>[]);
    for (final frame in decoder.drain()) {
      if (frame is PlanFrame && !firstPlan.isCompleted) {
        firstPlan.complete(sw.elapsed);
      }
    }
  });
  // Send INIT exactly as the browser client does on WS open.
  ws.add(
    encodeFrame(
      const InitFrame(
        size: CellSize(120, 40),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        protocolVersion: remoteProtocolVersion,
      ),
    ),
  );
  final elapsed = await firstPlan.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () => const Duration(seconds: -1),
  );
  await ws.close();
  return elapsed;
}

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 5777;
  final reps = args.length > 1 ? int.parse(args[1]) : 5;
  // Seconds between connections — the realistic reload cadence. A human is
  // slower than the warm-standby replenish; a tight loop can outrun it.
  final gapSeconds = args.length > 2 ? int.parse(args[2]) : 1;

  stdout.writeln('serve startup: WS connect → first PLAN frame, port $port');
  stdout.writeln('(each connection = one served session)');
  stdout.writeln('');
  final samples = <Duration>[];
  for (var i = 0; i < reps; i++) {
    final d = await _connectToFirstPaint(port);
    samples.add(d);
    stdout.writeln(
      'connection ${i + 1}: ${d.inMilliseconds} ms'
      '${d.isNegative ? '  (TIMEOUT)' : ''}',
    );
    // Gap between connections so the server can replenish any warm standby.
    await Future<void>.delayed(Duration(seconds: gapSeconds));
  }
  final ok = samples.where((d) => !d.isNegative).toList()..sort();
  if (ok.isNotEmpty) {
    final median = ok[ok.length ~/ 2].inMilliseconds;
    final best = ok.first.inMilliseconds;
    stdout.writeln('');
    stdout.writeln('median ${median} ms · best ${best} ms · n=${ok.length}');
  }
}
