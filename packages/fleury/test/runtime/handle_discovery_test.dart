import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/src/runtime/handle_discovery.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late _LockHolder holder;

  setUpAll(() async {
    holder = await _LockHolder.start();
  });

  tearDownAll(() async {
    await holder.stop();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fleury_handle_discovery_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<File> writeLiveHandle(Directory directory, String socketPath) async {
    final handle = _writeHandle(directory, socketPath);
    await holder.hold('${handle.parent.path}/lock');
    return handle;
  }

  test('finds a package-root handle from a nested working directory', () async {
    _writePubspec(tempDir, 'root_package');
    final handle = await writeLiveHandle(tempDir, '/tmp/fleury-package.sock');
    final nested = Directory('${tempDir.path}/lib/src')
      ..createSync(recursive: true);

    expect(findImplicitFleuryHandle(nested)?.path, handle.path);
  });

  test('stops at the nearest Dart package boundary', () async {
    _writePubspec(tempDir, 'outer_package');
    await writeLiveHandle(tempDir, '/tmp/fleury-outer.sock');
    final inner = Directory('${tempDir.path}/packages/inner')
      ..createSync(recursive: true);
    _writePubspec(inner, 'inner_package');
    final nested = Directory('${inner.path}/bin/nested')
      ..createSync(recursive: true);

    expect(findImplicitFleuryHandle(nested), isNull);

    final innerHandle = await writeLiveHandle(inner, '/tmp/fleury-inner.sock');
    expect(findImplicitFleuryHandle(nested)?.path, innerHandle.path);
  });

  test(
    'outside a Dart package accepts only a current-directory handle',
    () async {
      final ancestor = Directory('${tempDir.path}/shared')..createSync();
      await writeLiveHandle(ancestor, '/tmp/fleury-untrusted.sock');
      final child = Directory('${ancestor.path}/child')..createSync();

      expect(findImplicitFleuryHandle(child), isNull);

      final localHandle = await writeLiveHandle(
        child,
        '/tmp/fleury-local.sock',
      );
      expect(findImplicitFleuryHandle(child)?.path, localHandle.path);
    },
  );

  group('liveness', () {
    test('a handle nobody owns is ignored and reaped', () {
      // The SIGKILL aftermath: `.fleury/handle` and `.fleury/lock` are both on
      // disk, but no process holds the lock. Trusting the file alone turned
      // every later `dart run` in the project into an unsupervised session —
      // no hot reload, no error, project-wide.
      _writePubspec(tempDir, 'root_package');
      final handle = _writeHandle(tempDir, '/tmp/fleury-dead.sock');
      File('${handle.parent.path}/lock').writeAsStringSync('');

      expect(findImplicitFleuryHandle(tempDir), isNull);
      expect(
        handle.existsSync(),
        isFalse,
        reason: 'a handle proved dead is cleaned up, not re-proved every run',
      );
    });

    test('a handle with no lock file at all is ignored', () {
      // The CLI creates `.fleury/lock` before it writes the handle, so a
      // handle without one has no owner by construction.
      _writePubspec(tempDir, 'root_package');
      final handle = _writeHandle(tempDir, '/tmp/fleury-lockless.sock');

      expect(findImplicitFleuryHandle(tempDir), isNull);
      expect(handle.existsSync(), isFalse);
    });

    test('a handle whose owner is SIGKILLed stops being discovered', () async {
      _writePubspec(tempDir, 'root_package');
      final handle = _writeHandle(tempDir, '/tmp/fleury-killed.sock');
      final owner = await _LockHolder.start();
      await owner.hold('${handle.parent.path}/lock');

      expect(
        findImplicitFleuryHandle(tempDir)?.path,
        handle.path,
        reason: 'a live owner keeps its handle discoverable',
      );

      owner.kill();
      await owner.exited;

      expect(findImplicitFleuryHandle(tempDir), isNull);
      expect(handle.existsSync(), isFalse);
    });

    test('a stale handle does not mask a live one further up', () async {
      _writePubspec(tempDir, 'root_package');
      final rootHandle = await writeLiveHandle(tempDir, '/tmp/fleury-up.sock');
      final nested = Directory('${tempDir.path}/lib/src')
        ..createSync(recursive: true);
      final stale = _writeHandle(nested, '/tmp/fleury-stale.sock');
      File('${stale.parent.path}/lock').writeAsStringSync('');

      expect(findImplicitFleuryHandle(nested)?.path, rootHandle.path);
    });
  });
}

void _writePubspec(Directory directory, String name) {
  File('${directory.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
}

File _writeHandle(Directory directory, String socketPath) {
  final handle = File('${directory.path}/.fleury/handle');
  handle.parent.createSync(recursive: true);
  handle.writeAsStringSync(socketPath);
  return handle;
}

/// A separate process that holds exclusive locks, the way `fleury shell` and
/// `fleury serve` hold `.fleury/lock` for as long as they own a handle.
///
/// It has to be a real second process: POSIX record locks belong to the
/// process, so a lock this test isolate held would be freely re-acquirable by
/// the code under test and every handle would read as dead.
class _LockHolder {
  _LockHolder._(this._process, this._script) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final waiter = _waiting;
          _waiting = null;
          if (waiter != null && !waiter.isCompleted) {
            waiter.complete(line);
          } else {
            _pending.add(line);
          }
        });
  }

  final Process _process;
  final Directory _script;
  final List<String> _pending = [];
  Completer<String>? _waiting;

  Future<String> _nextLine() {
    if (_pending.isNotEmpty) return Future.value(_pending.removeAt(0));
    return (_waiting = Completer<String>()).future;
  }

  static Future<_LockHolder> start() async {
    final dir = Directory.systemTemp.createTempSync('fleury_lock_holder_');
    final script = File('${dir.path}/hold.dart')
      ..writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

/// Locks every path handed to it on stdin and never lets go (until killed).
void main() {
  final held = <RandomAccessFile>[];
  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((path) {
    final raf = File(path).openSync(mode: FileMode.append);
    raf.lockSync(FileLock.exclusive);
    held.add(raf);
    stdout.writeln('ok');
  });
}
''');
    final process = await Process.start(Platform.resolvedExecutable, [
      script.path,
    ]);
    unawaited(process.stderr.drain<void>());
    return _LockHolder._(process, dir);
  }

  Future<void> hold(String lockPath) async {
    _process.stdin.writeln(lockPath);
    await _process.stdin.flush();
    final ack = await _nextLine().timeout(const Duration(seconds: 20));
    expect(ack, 'ok');
  }

  void kill() => _process.kill(ProcessSignal.sigkill);

  Future<int> get exited => _process.exitCode;

  Future<void> stop() async {
    kill();
    await _process.exitCode;
    try {
      _script.deleteSync(recursive: true);
    } catch (_) {}
  }
}
