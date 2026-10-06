// spawnFleuryApp's attach contract: waiting out a slow start (with or without
// a deadline), the guidance each failure carries, and that a failed spawn
// leaves no child, socket, or late notice behind.
@TestOn('posix')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_host_io.dart';
import 'package:test/test.dart';

void main() {
  final fixtures = '${Directory.current.path}/test/fixtures';

  test('a slow start with no deadline is reported once and attaches', () async {
    var notices = 0;
    final app = await spawnFleuryApp(
      command: [
        Platform.resolvedExecutable,
        'run',
        '$fixtures/spawn_app.dart',
        'slow-app',
        '--connect-delay-ms=1500',
      ],
      connectTimeout: null,
      slowStartAfter: const Duration(milliseconds: 300),
      onSlowStart: () => notices++,
    );
    addTearDown(app.dispose);
    expect(notices, 1);
  });

  test('a command that never connects fails with how apps connect', () async {
    final error = await _spawnError(
      command: const ['sleep', '30'],
      connectTimeout: const Duration(milliseconds: 1500),
    );
    expect(
      error.message,
      allOf(
        contains('did not connect within 1500ms'),
        contains('FLEURY_HANDLE'),
        contains('runApp(...)'),
      ),
    );
  });

  test('an app that exits before connecting says so', () async {
    final error = await _spawnError(
      command: [Platform.resolvedExecutable, '--version'],
    );
    expect(
      error.message,
      allOf(
        contains('exited (code 0) before connecting'),
        contains('FLEURY_HANDLE'),
      ),
    );
  });

  test('an abort that fails still tears the app down', () async {
    final dir = Directory.systemTemp.createTempSync('fleury_spawn_abort_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final stateFile = File('${dir.path}/state.json');
    final abort = Completer<void>();
    var notices = 0;
    final spawned = _spawnError(
      command: [
        Platform.resolvedExecutable,
        'run',
        '$fixtures/spawn_never_connect.dart',
        stateFile.path,
      ],
      abort: abort.future,
      slowStartAfter: const Duration(seconds: 20),
      onSlowStart: () => notices++,
    );

    // Fail the abort only once the child is running and has recorded itself.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!stateFile.existsSync() || stateFile.lengthSync() == 0) {
      if (DateTime.now().isAfter(deadline)) fail('the child never started');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final state = jsonDecode(stateFile.readAsStringSync()) as Map;
    abort.completeError(StateError('the abort source failed'));

    final error = await spawned;
    expect(error.message, contains('aborted before the app connected'));
    expect(_isAlive(state['pid'] as int), isFalse, reason: 'child reaped');
    expect(File(state['handle'] as String).existsSync(), isFalse);
    expect(notices, 0);
  });
}

Future<FleurySpawnException> _spawnError({
  required List<String> command,
  Duration? connectTimeout = const Duration(seconds: 20),
  Future<void>? abort,
  Duration slowStartAfter = const Duration(seconds: 10),
  void Function()? onSlowStart,
}) async {
  try {
    final app = await spawnFleuryApp(
      command: command,
      connectTimeout: connectTimeout,
      abort: abort,
      slowStartAfter: slowStartAfter,
      onSlowStart: onSlowStart,
    );
    await app.dispose();
  } on FleurySpawnException catch (error) {
    return error;
  }
  fail('expected `${command.join(' ')}` to fail to attach');
}

bool _isAlive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
