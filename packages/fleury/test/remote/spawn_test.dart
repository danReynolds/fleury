// spawnFleuryApp's attach contract: why an attach failed, the guidance that
// failure carries, and the slow-start notice a host shows while a cold
// `dart run` compiles the app.
@TestOn('posix')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury_host_io.dart';
import 'package:test/test.dart';

void main() {
  final fixture = '${Directory.current.path}/test/fixtures/spawn_app.dart';

  test('a slow start is reported once and the app still attaches', () async {
    var notices = 0;
    final app = await spawnFleuryApp(
      command: [
        Platform.resolvedExecutable,
        'run',
        fixture,
        'slow-app',
        '--connect-delay-ms=1500',
      ],
      slowStartAfter: const Duration(milliseconds: 300),
      onSlowStart: () => notices++,
    );
    addTearDown(app.dispose);
    expect(notices, 1);
  });

  test('a command that never connects fails as timedOut', () async {
    final error = await _spawnError(
      command: const ['sleep', '30'],
      connectTimeout: const Duration(seconds: 1),
    );
    expect(error.failure, FleurySpawnFailure.timedOut);
    expect(
      error.message,
      allOf(
        contains('did not connect within 1s'),
        contains('runApp(...)'),
        contains('dart compile exe'),
      ),
    );
  });

  test('an app that exits before connecting fails as exited', () async {
    final error = await _spawnError(
      command: [Platform.resolvedExecutable, '--version'],
    );
    expect(error.failure, FleurySpawnFailure.exited);
    expect(
      error.message,
      allOf(contains('exited (code 0) before connecting'), contains('runApp')),
    );
  });

  test('an abort before the app connects fails as aborted', () async {
    final error = await _spawnError(
      command: const ['sleep', '30'],
      abort: Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(error.failure, FleurySpawnFailure.aborted);
  });

  test('the default deadline leaves room for a cold compile', () {
    // A cold `dart run` of a Fleury app took 5–8 s on an M1 Pro and up to
    // 22 s in a container; a deadline in that range fails healthy apps.
    expect(defaultSpawnConnectTimeout, greaterThanOrEqualTo(_slowColdStart));
  });
}

const _slowColdStart = Duration(seconds: 30);

Future<FleurySpawnException> _spawnError({
  required List<String> command,
  Duration connectTimeout = defaultSpawnConnectTimeout,
  Future<void>? abort,
}) async {
  try {
    final app = await spawnFleuryApp(
      command: command,
      connectTimeout: connectTimeout,
      abort: abort,
    );
    await app.dispose();
  } on FleurySpawnException catch (error) {
    return error;
  }
  fail('expected `${command.join(' ')}` to fail to attach');
}
