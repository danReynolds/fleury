// Architecture experiment, not a production input backend.
// Run with packages/fleury/.dart_tool/package_config.json; see README.md.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fleury/src/terminal/posix_driver.dart';

final class PollFd extends Struct {
  @Int32()
  external int fd;
  @Int16()
  external int events;
  @Int16()
  external int revents;
}

final class Sys {
  final library = DynamicLibrary.process();
  late final pipe = library
      .lookupFunction<
        Int32 Function(Pointer<Int32>),
        int Function(Pointer<Int32>)
      >('pipe');
  late final close = library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final fcntl = library
      .lookupFunction<
        Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
        int Function(int, int, int)
      >('fcntl');
  late final ttyname = library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Char>, UintPtr),
        int Function(int, Pointer<Char>, int)
      >('ttyname_r');
  late final open = library
      .lookupFunction<
        Int32 Function(Pointer<Char>, Int32, VarArgs<(Int32,)>),
        int Function(Pointer<Char>, int, int)
      >('open');
  late final read = library
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read');
  late final write = library
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  late final int Function(Pointer<PollFd>, int, int) poll = Platform.isMacOS
      ? library.lookupFunction<
          Int32 Function(Pointer<PollFd>, Uint32, Int32),
          int Function(Pointer<PollFd>, int, int)
        >('poll')
      : library.lookupFunction<
          Int32 Function(Pointer<PollFd>, Uint64, Int32),
          int Function(Pointer<PollFd>, int, int)
        >('poll');
  late final errno = library
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );
  int get duplicateCommand => Platform.isMacOS ? 67 : 1030;
}

// The worker is blocked in an OS wait, so a SendPort alone cannot wake it.
// Commands travel through a private pipe. Acknowledgments travel back through
// one port, ordered with data. Stop/pause take priority over terminal reads.
void reader((SendPort, int, int, bool) args) {
  final (parent, control, source, reopen) = args;
  final sys = Sys();
  final watches = calloc<PollFd>(2);
  final bytes = calloc<Uint8>(4096);
  final command = calloc<Uint8>();
  var input = -1;
  final nonblocking = Platform.isMacOS ? 4 : 2048;
  int? savedBlockingBit;
  void restoreBlocking() {
    final original = savedBlockingBit;
    if (original == null) return;
    final current = sys.fcntl(input, 3, 0);
    if (current < 0 ||
        sys.fcntl(input, 4, (current & ~nonblocking) | original) < 0) {
      throw StateError('cannot restore input flags');
    }
    savedBlockingBit = null;
  }

  try {
    input = sys.fcntl(source, sys.duplicateCommand, 0);
    if (input < 0) throw StateError('duplicate failed: ${sys.errno().value}');
    if (reopen) {
      final path = calloc<Char>(4096);
      try {
        if (sys.ttyname(input, path, 4096) != 0) {
          throw StateError('ttyname failed');
        }
        // O_RDONLY | O_NOCTTY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW.
        final flags = Platform.isMacOS
            ? 0x20000 | 4 | 0x1000000 | 0x100
            : 0x100 | 2048 | 0x80000 | 0x20000;
        final reopened = sys.open(path, flags, 0);
        if (reopened < 0)
          throw StateError('reopen failed: ${sys.errno().value}');
        sys.close(input);
        input = reopened;
      } finally {
        calloc.free(path);
      }
    }
    parent.send('ready');
    var paused = true;
    var waitingForAck = false;
    while (true) {
      watches[0].fd = control;
      watches[0].events = 1; // POLLIN
      watches[1].fd = paused || waitingForAck ? -1 : input;
      watches[1].events = 1;
      final result = sys.poll(watches, 2, -1);
      if (result < 0) {
        if (sys.errno().value == 4) continue; // EINTR
        throw StateError('poll failed: ${sys.errno().value}');
      }
      if (watches[0].revents != 0) {
        final n = sys.read(control, command, 1);
        if (n == 0 || command.value == 83) break; // Stop / owner EOF.
        if (n < 0) {
          if (sys.errno().value == 4) continue;
          throw StateError('control read failed');
        }
        switch (command.value) {
          case 80: // Pause barrier.
            paused = true;
            restoreBlocking();
            parent.send('paused');
          case 82: // Resume after modes have been set.
            final current = sys.fcntl(input, 3, 0);
            savedBlockingBit = current & nonblocking;
            if (current < 0 || sys.fcntl(input, 4, current | nonblocking) < 0) {
              throw StateError('cannot enable nonblocking input');
            }
            paused = false;
            parent.send('resumed');
          case 65: // One chunk consumed; permit another.
            waitingForAck = false;
        }
        continue;
      }
      if (watches[1].revents != 0) {
        final n = sys.read(input, bytes, 4096);
        if (n == 0) {
          parent.send('eof');
          break;
        }
        if (n < 0) {
          final error = sys.errno().value;
          if (error == 4 || error == 11 || error == 35) continue;
          throw StateError('input read failed: $error');
        }
        parent.send(Uint8List.fromList(bytes.asTypedList(n)));
        waitingForAck = true;
      }
    }
  } catch (error, stack) {
    parent.send(['error', '$error', '$stack']);
  } finally {
    restoreBlocking();
    if (input >= 0) sys.close(input);
    sys.close(control);
    calloc.free(watches);
    calloc.free(bytes);
    calloc.free(command);
    parent.send('stopped');
  }
}

final class InputLease {
  static bool reopenTty = false;
  InputLease._(this._control, this._port, this._exit, this.onBytes);
  final int _control;
  final ReceivePort _port;
  final ReceivePort _exit;
  final void Function(Uint8List) onBytes;
  final _waits = <String, Completer<void>>{};
  final _sys = Sys();
  bool _stopping = false;
  Object? error;

  static Future<InputLease> acquire(
    void Function(Uint8List) onBytes, {
    int source = 0,
  }) async {
    final sys = Sys();
    final pair = calloc<Int32>(2);
    if (sys.pipe(pair) != 0) throw StateError('pipe failed');
    final (readEnd, writeEnd) = (pair[0], pair[1]);
    calloc.free(pair);
    // Prototype uses pipe + fcntl. Production must close the spawn race
    // (pipe2(O_CLOEXEC) where available, platform-safe acquisition elsewhere).
    sys.fcntl(readEnd, 2, 1);
    sys.fcntl(writeEnd, 2, 1);
    final port = ReceivePort();
    final exit = ReceivePort();
    final lease = InputLease._(writeEnd, port, exit, onBytes);
    final ready = lease.waitFor('ready');
    lease.waitFor('stopped');
    lease.waitFor('exited');
    port.listen((dynamic message) {
      if (message is Uint8List) {
        if (!lease._stopping) {
          onBytes(message);
          lease.send(65);
        }
      } else if (message is String) {
        final done = lease._waits[message];
        if (done != null && !done.isCompleted) done.complete();
      } else {
        lease.error = message;
        final done = lease._waits['ready']!;
        if (!done.isCompleted) done.complete();
      }
    });
    exit.listen((_) => lease._waits['exited']!.complete());
    await Isolate.spawn(reader, (
      port.sendPort,
      readEnd,
      source,
      reopenTty,
    ), onExit: exit.sendPort);
    await ready;
    if (lease.error != null) {
      await lease.stop(alreadyStopping: true);
      throw StateError('${lease.error}');
    }
    return lease;
  }

  Future<void> waitFor(String name) =>
      (_waits[name] = Completer<void>()).future;

  void send(int byte) {
    final buffer = calloc<Uint8>()..value = byte;
    try {
      if (_sys.write(_control, buffer, 1) != 1) {
        throw StateError('control write failed');
      }
    } finally {
      calloc.free(buffer);
    }
  }

  Future<void> resume() async {
    final done = waitFor('resumed');
    send(82);
    await done;
  }

  Future<void> pause() async {
    final done = waitFor('paused');
    send(80);
    await done;
  }

  Future<void> stop({bool alreadyStopping = false}) async {
    _stopping = true;
    if (!alreadyStopping) send(83);
    await _waits['stopped']!.future;
    await _waits['exited']!.future;
    _sys.close(_control);
    _port.close();
    _exit.close();
  }
}

int fdCount() {
  final sys = Sys();
  var count = 0;
  for (var fd = 0; fd < 4096; fd++) {
    if (sys.fcntl(fd, 1, 0) >= 0) count++; // F_GETFD, no new descriptors.
  }
  return count;
}

Future<void> main(List<String> args) async {
  InputLease.reopenTty = args.contains('--reopen-tty');
  if (!stdin.hasTerminal) throw StateError('probe requires a PTY');
  final sys = Sys();
  final initialFlags = sys.fcntl(0, 3, 0); // F_GETFL
  final nonblocking = Platform.isMacOS ? 4 : 2048;
  if (args.contains('--file-stream')) {
    final input = File('/dev/fd/0').openRead().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    stdout.writeln('CANCELLING');
    await input.cancel();
    stdout.writeln('CANCELLED');
    return;
  }
  // Warm runtime bookkeeping before measuring descriptors.
  await (await InputLease.acquire((_) {})).stop();
  final baseline = fdCount();
  final opens = <int>[];
  final closes = <int>[];
  for (var i = 0; i < 100; i++) {
    final watch = Stopwatch()..start();
    final lease = await InputLease.acquire((_) {});
    opens.add(watch.elapsedMicroseconds);
    await lease.resume();
    watch.reset();
    await lease.stop();
    closes.add(watch.elapsedMicroseconds);
  }
  if (fdCount() != baseline) throw StateError('descriptor leak');
  try {
    await InputLease.acquire((_) {}, source: -1);
    throw StateError('invalid input unexpectedly succeeded');
  } on StateError catch (error) {
    if (!'$error'.contains('duplicate failed')) rethrow;
  }
  if (fdCount() != baseline) throw StateError('failed entry leak');
  stdout.writeln('STRESS OK flags=$initialFlags fds=$baseline');

  final first = Completer<void>();
  final raw = NativePosixTerminalModeController();
  if (!raw.enableRawMode()) throw StateError('raw mode unavailable');
  final lease = await InputLease.acquire((bytes) {
    if (utf8.decode(bytes).contains('a') && !first.isCompleted)
      first.complete();
  });
  await lease.resume();
  if (InputLease.reopenTty &&
      (sys.fcntl(0, 3, 0) & nonblocking) != (initialFlags & nonblocking)) {
    throw StateError('reopened input changed caller flags while active');
  }
  stdout.writeln('FIRST READY');
  await first.future;
  final pauseHandoff = args.contains('--pause-handoff');
  if (pauseHandoff) {
    await lease.pause();
  } else {
    await lease.stop();
  }
  raw.restoreMode();
  stdout.writeln('PLAIN READY');
  final line = stdin.readLineSync();
  if (line != 'plain') throw StateError('plain input: $line');
  stdout.writeln('CHILD READY');
  final child = await Process.start('/bin/sh', [
    '-c',
    r'IFS= read -r reply; test "$reply" = child',
  ], mode: ProcessStartMode.inheritStdio);
  if (await child.exitCode != 0) throw StateError('child input failed');
  if (pauseHandoff) await lease.stop();
  stdout.writeln('BETWEEN READY');
  final between = stdin.readLineSync();
  if (between != 'between') throw StateError('between input: $between');
  final second = Completer<void>();
  final raw2 = NativePosixTerminalModeController();
  if (!raw2.enableRawMode()) throw StateError('second raw mode unavailable');
  final lease2 = await InputLease.acquire((bytes) {
    if (utf8.decode(bytes).contains('b') && !second.isCompleted) {
      second.complete();
    }
  });
  await lease2.resume();
  stdout.writeln('SECOND READY');
  await second.future;
  await lease2.stop();
  raw2.restoreMode();
  if ((sys.fcntl(0, 3, 0) & nonblocking) != (initialFlags & nonblocking))
    throw StateError(
      'stdin flags changed: $initialFlags -> ${sys.fcntl(0, 3, 0)}',
    );
  if (fdCount() != baseline) throw StateError('final descriptor leak');
  // Prove Fleury's alternative never subscribed to Dart's stdin: the caller
  // can still be its first async subscriber after both leases have ended.
  stdout.writeln('ASYNC READY');
  final asyncLine = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  if (asyncLine != 'async') throw StateError('async input: $asyncLine');
  opens.sort();
  closes.sort();
  stdout.writeln(
    jsonEncode({
      'result': 'PASS',
      'handoff': pauseHandoff ? 'pause' : 'release',
      'handle': InputLease.reopenTty ? 'reopened-tty' : 'duplicate',
      'cycles': 100,
      'acquireP50Us': opens[50],
      'acquireP99Us': opens[99],
      'releaseP50Us': closes[50],
      'releaseP99Us': closes[99],
    }),
  );
}
