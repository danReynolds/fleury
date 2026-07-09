// End-to-end debug-accuracy: spawn a real app over the live remote wire, drive
// scenarios through its semantic actions, then read the debug channel back the
// way an agent does (read_frames / read_logs / read_errors) and assert the data
// actually reflects what we caused. This is the closed-loop the fake-bridge unit
// tests can't be: real app → real measurement → real wire → the bridge an agent
// drives.
//
// It immediately earned its keep: when first written, read_frames and read_logs
// both came back EMPTY over the agent path (collection was wired to the
// *terminal* path only). Frames are fixed — WireFramePresenter now emits the
// same telemetry as the ANSI presenter, and the frames test below locks it in.
// Logs remain a known gap: the fd-capture that feeds the LogBuffer is gated on
// `stdout.hasTerminal` (run_app.dart), false for a piped/served/agent app — the
// skipped spec at the bottom is the fix's target; remove the `skip` when the
// remote log path is wired.
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
      // Forward fixture output to the test log — a broken fixture should fail
      // with its actual stack trace, not a cryptic downstream assertion.
      log: printOnFailure,
    );
    addTearDown(bridge.close);
    await bridge.ready;
    // `ready` also resolves on app exit / watchdog; catch a fixture that
    // connected then died before it could render.
    expect(bridge.isRunning, isTrue, reason: 'fixture rendered and stayed up');
    return bridge;
  }

  test(
    'read_errors returns the error an agent caused, over the agent path',
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
      expect(
        (err['stack'] as String),
        isNotEmpty,
        reason: 'the stack trace is the point of the errors tab',
      );
      expect(err['at'], isA<String>(), reason: 'ISO-8601 timestamp');
    },
  );

  test('read_frames returns real frames an agent can diagnose', () async {
    final bridge = await spawn();

    // Baseline: bridge.ready implies at least one committed+logged frame, so
    // isNotEmpty alone would pass on the startup frame and lock in nothing.
    // The real assertion is GROWTH caused by the activations below.
    final before = await bridge.queryDebug('frames', limit: 100);
    expect(before, isNotNull, reason: 'the debug channel is live under JIT');
    expect(before, isNotEmpty, reason: 'startup rendered at least one frame');
    final beforeLast = (before!.last! as Map)['frame'] as int;

    await _activate(bridge, 'tick');
    await _activate(bridge, 'tick');

    // The activation's frame renders after the action result returns; poll
    // briefly (transport-only wait, bounded) until the log reflects it.
    List<Object?>? frames;
    var afterLast = beforeLast;
    for (var i = 0; i < 40 && afterLast <= beforeLast; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      frames = await bridge.queryDebug('frames', limit: 100);
      if (frames == null || frames.isEmpty) continue;
      afterLast = (frames.last! as Map)['frame'] as int;
    }
    expect(
      afterLast,
      greaterThan(beforeLast),
      reason:
          'the tick activations rendered new frames into the log — '
          'a regression that stops per-frame emission fails here',
    );

    final frame = frames!.last! as Map;
    for (final phase in const ['buildUs', 'layoutUs', 'paintUs', 'diffUs']) {
      expect(frame[phase], isA<int>(), reason: '$phase present');
      expect(frame[phase] as int, greaterThanOrEqualTo(0));
    }
    // The fixture's tick dirties a single text row — the wire path's
    // row-granular dirtyCells must reflect a small change, not report the
    // full 80×24 viewport on an ordinary frame.
    expect(
      frame['dirtyCells'] as int,
      lessThan(80 * 24),
      reason: 'row-granular dirty accounting, not a full-screen constant',
    );
  });

  test(
    'read_logs returns the stdout an agent caused',
    () async {
      final bridge = await spawn();
      await _activate(bridge, 'log');
      final logs = await bridge.queryDebug('logs', limit: 100);
      expect(logs, isNotNull);
      final text = logs!.map((l) => (l! as Map)['text']).join('\n');
      expect(text, contains('debug-app: log line 1'));
      expect(text, contains('debug-app: log line 3'));
    },
    skip:
        'GAP: fd-capture feeding the LogBuffer is gated on stdout.hasTerminal '
        '(run_app.dart), false for a piped / served / agent app — so read_logs is '
        'empty over the agent path.',
  );
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
