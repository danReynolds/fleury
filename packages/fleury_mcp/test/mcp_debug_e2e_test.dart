// End-to-end debug-accuracy: spawn a real app over the live remote wire, drive
// scenarios through its semantic actions, then read the debug channel back the
// way an agent does (read_frames / read_logs / read_errors) and assert the data
// actually reflects what we caused. This is the closed-loop the fake-bridge unit
// tests can't be: real app → real measurement → real wire → the bridge an agent
// drives.
//
// It immediately earned its keep: read_errors works over the agent path, but
// read_frames and read_logs come back EMPTY, because their data collection is
// wired to the *terminal* path only:
//   • frames — DebugEvents.emitFrame is called solely by the ANSI (terminal)
//     presenter; the remote render path never emits, so the frame log is empty.
//   • logs   — the fd-capture that feeds the LogBuffer is gated on
//     `stdout.hasTerminal` (run_app.dart), false for a piped/served/agent app.
// Those two are captured below as skipped specs — remove the `skip` when the
// remote paths emit, and they lock the fix in.
//
// Tagged `integration` (spawns `dart run`, takes seconds): `dart test -x
// integration` skips it; it runs by default.
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  final fixture = _fixturePath();

  Future<FleuryAppBridge> spawn() async {
    final bridge = await FleuryAppBridge.spawn(
      command: <String>['dart', 'run', fixture],
      viewport: const CellSize(80, 24),
      log: (_) {},
    );
    addTearDown(bridge.close);
    await bridge.ready;
    return bridge;
  }

  test('read_errors returns the error an agent caused, over the agent path',
      () async {
    final bridge = await spawn();

    // A throwing action is caught by runApp's containment, reported, and read
    // back with a real stack trace + timestamp — the whole loop an agent drives.
    await _activate(bridge, 'boom');
    final errors = await bridge.queryDebug('errors', limit: 100);
    expect(errors, isNotNull, reason: 'the debug channel is live under JIT');
    expect(errors, isNotEmpty, reason: 'the caught throw was recorded');
    final err = errors!.last! as Map;
    expect(err['error'].toString(), contains('debug-app: boom'));
    expect(err['stack'], isA<String>());
    expect((err['stack'] as String), isNotEmpty,
        reason: 'the stack trace is the point of the errors tab');
    expect(err['at'], isA<String>(), reason: 'ISO-8601 timestamp');
  });

  test('read_frames returns real frames an agent can diagnose', () async {
    final bridge = await spawn();
    await _activate(bridge, 'tick');
    await _activate(bridge, 'tick');
    final frames = await bridge.queryDebug('frames', limit: 100);
    expect(frames, isNotNull);
    expect(frames, isNotEmpty, reason: 'the app has rendered frames');
    final frame = frames!.last! as Map;
    for (final phase in const ['buildUs', 'layoutUs', 'paintUs', 'diffUs']) {
      expect(frame[phase], isA<int>(), reason: '$phase present');
      expect(frame[phase] as int, greaterThanOrEqualTo(0));
    }
  });

  test('read_logs returns the stdout an agent caused', () async {
    final bridge = await spawn();
    await _activate(bridge, 'log');
    final logs = await bridge.queryDebug('logs', limit: 100);
    expect(logs, isNotNull);
    final text = logs!.map((l) => (l! as Map)['text']).join('\n');
    expect(text, contains('debug-app: log line 1'));
    expect(text, contains('debug-app: log line 3'));
  }, skip: 'GAP: fd-capture feeding the LogBuffer is gated on stdout.hasTerminal '
      '(run_app.dart), false for a piped / served / agent app — so read_logs is '
      'empty over the agent path.');
}

Future<void> _activate(FleuryAppBridge bridge, String id) async {
  await bridge.invokeAction(SemanticNodeId(id), SemanticAction.activate);
}

String _fixturePath() {
  const rel = 'test/fixtures/debug_app.dart';
  final candidates = <String>[
    '${Directory.current.path}/$rel',
    '${Directory.current.path}/packages/fleury_mcp/$rel',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError(
    'debug_app.dart fixture not found from ${Directory.current.path}',
  );
}
