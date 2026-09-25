@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fleury/src/terminal/posix_input_lease.dart';
import 'package:test/test.dart';

void main() {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  late _Pipe pipe;
  setUp(() => pipe = _Pipe());
  tearDown(() => pipe.close());

  test('hangup probe does not confuse a live or invalid descriptor', () {
    expect(posixDescriptorHungUp(pipe.reader), isFalse);
    expect(posixDescriptorHungUp(-1), isFalse);
    expect(posixDescriptorHungUp(0x7fffffff), isFalse);
  });

  PosixInputLease lease({
    void Function(Uint8List)? bytes,
    void Function()? done,
    void Function(Object, StackTrace)? error,
    int? source,
  }) => PosixInputLease(
    source: source ?? pipe.reader,
    onBytes: bytes ?? (_) => fail('Unexpected input'),
    onDone: done ?? () => fail('Intentional stop must not emit EOF'),
    onError: error ?? (e, s) => fail('Unexpected reader error: $e\n$s'),
  );

  test(
    'isolated process releases descriptors after cycles and failed startup',
    () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        '--packages=.dart_tool/package_config.json',
        'test/fixtures/posix_input_resources_fixture.dart',
      ]);
      // Keep its input open while idle leases run, without feeding any bytes.
      final output = process.stdout.drain<void>();
      final errors = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          throw TimeoutException('Input resource fixture did not exit');
        },
      );
      await output;
      await process.stdin.close();
      expect(code, 0, reason: await errors);
    },
  );

  test('root failure cannot strand VM shutdown in native poll', () async {
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=.dart_tool/package_config.json',
      'test/fixtures/posix_input_resources_fixture.dart',
      '--fatal-owner',
    ]);
    final output = process.stdout.drain<void>();
    final errors = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('Native poll stranded process shutdown');
      },
    );
    await output;
    await process.stdin.close();
    expect(code, isNot(0));
    expect(await errors, contains('intentional owner failure'));
  });

  test('synchronous acquisition hooks can stop or rejoin safely', () async {
    // Run the actual native worker in isolation: lending released pointers
    // used to crash the VM before a Dart exception could reach this runner.
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=.dart_tool/package_config.json',
      'test/fixtures/posix_input_resources_fixture.dart',
      '--reentrant-acquisition',
    ]);
    final output = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final errors = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('Reentrant input acquisition did not exit');
      },
    );
    await process.stdin.close();
    expect(code, 0, reason: await errors);
    expect(await output, contains('REENTRANT ACQUISITION PASS'));
  });

  test('stop returns descriptor flags and permits synchronous reads', () async {
    final original = _sys.flags(pipe.reader);
    final first = Completer<void>();
    final input = lease(
      bytes: (bytes) {
        expect(bytes, [97]);
        first.complete();
      },
    );
    await input.start();
    expect(_sys.flags(pipe.reader) & _sys.nonblocking, isNonZero);
    await pipe.send([97]);
    await first.future;
    await input.stop();
    expect(_sys.flags(pipe.reader), original);
    await pipe.send([98]);
    expect(pipe.readOne(), 98);
    // A second lease is independently owned, not a resumed Dart stream.
    final second = lease();
    await second.start();
    await second.stop();
    expect(_sys.flags(pipe.reader), original);
  });

  test(
    'restores initial nonblocking bit without clobbering other flags',
    () async {
      _sys.setFlags(pipe.reader, _sys.flags(pipe.reader) | _sys.nonblocking);
      final input = lease();
      await input.start();
      // O_APPEND is another shared file-status bit, set by an outside owner.
      final append = Platform.isMacOS ? 8 : 1024;
      _sys.setFlags(pipe.reader, _sys.flags(pipe.reader) | append);
      await input.stop();
      expect(_sys.flags(pipe.reader) & _sys.nonblocking, isNonZero);
      expect(_sys.flags(pipe.reader) & append, isNonZero);
    },
  );

  test('stop during acquisition is a barrier and is idempotent', () async {
    final flags = _sys.flags(pipe.reader);
    final input = lease();
    final starting = input.start();
    final rejected = expectLater(starting, throwsStateError);
    final stopping = input.stop();
    expect(identical(stopping, input.stop()), isTrue);
    await stopping;
    await rejected;
    expect(_sys.flags(pipe.reader), flags);
    await pipe.send([99]);
    expect(pipe.readOne(), 99);
  });

  test('a spent lease cannot report successful restart', () async {
    final input = lease();
    await input.start();
    await input.stop();
    await expectLater(input.start(), throwsStateError);
  });

  test('stop before start allocates nothing and rejects start', () async {
    final input = lease();
    await input.stop();
    await expectLater(input.start(), throwsStateError);
  });

  test(
    'invalid input rejects acquisition and permits idempotent stop',
    () async {
      // Warm Dart isolate bookkeeping before counting native descriptors.
      final warm = lease();
      await warm.start();
      await warm.stop();
      for (var i = 0; i < 20; i++) {
        final input = lease(source: -1);
        await expectLater(input.start(), throwsA(isA<OSError>()));
        await input.stop();
      }
    },
  );

  test('rolls back acquired handles and flags when startup fails', () async {
    final warm = lease();
    await warm.start();
    await warm.stop();
    final flags = _sys.flags(pipe.reader);
    for (var i = 0; i < 20; i++) {
      final input = PosixInputLease(
        source: pipe.reader,
        onBytes: (_) => fail('Unexpected bytes'),
        onDone: () => fail('Unexpected EOF'),
        onError: (_, _) => fail('Startup failure should reject start'),
        beforeSpawn: () => throw StateError('injected startup failure'),
      );
      await expectLater(input.start(), throwsStateError);
      await input.stop();
      expect(_sys.flags(pipe.reader), flags);
    }
  });

  test('EOF is delivered after flags are restored', () async {
    final flags = _sys.flags(pipe.reader);
    final eof = Completer<void>();
    final input = lease(
      done: () {
        expect(_sys.flags(pipe.reader), flags);
        eof.complete();
      },
    );
    await input.start();
    pipe.closeWriter();
    await eof.future;
    await expectLater(input.start(), throwsStateError);
    await input.stop();
  });

  test('worker failure joins then restores handles and flags', () async {
    final flags = _sys.flags(pipe.reader);
    final failed = Completer<void>();
    final input = lease(
      error: (error, stack) {
        expect(error, isA<StateError>());
        expect(_sys.flags(pipe.reader), flags);
        failed.complete();
      },
    );
    await input.start();
    input.debugKillWorker();
    await failed.future;
    await input.stop();
    await pipe.send([100]);
    expect(pipe.readOne(), 100);
  });

  test(
    'a throwing callback stops and reports without leaking a reader',
    () async {
      final failure = StateError('consumer failed');
      final reported = Completer<void>();
      final input = lease(
        bytes: (_) => throw failure,
        error: (error, _) {
          expect(error, same(failure));
          reported.complete();
        },
      );
      await input.start();
      await pipe.send([101]);
      await reported.future;
      await input.stop();
      await pipe.send([102]);
      expect(pipe.readOne(), 102);
    },
  );

  test('stop from callback fences queued input without EOF', () async {
    final stopped = Completer<void>();
    late PosixInputLease input;
    input = lease(
      bytes: (_) {
        input.stop().then((_) => stopped.complete());
      },
    );
    await input.start();
    await pipe.send([103]);
    await stopped.future;
    await pipe.send([104]);
    expect(pipe.readOne(), 104);
  });

  test(
    'one-batch backpressure preserves a large arbitrary byte stream',
    () async {
      final expected = List<int>.generate(1024 * 1024, (i) => i % 256);
      final received = BytesBuilder(copy: false);
      final complete = Completer<void>();
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      final input = lease(
        bytes: (bytes) {
          received.add(bytes);
          if (received.length == expected.length) complete.complete();
        },
      );
      try {
        await input.start();
        await pipe.send(expected);
        await complete.future;
        await input.stop();
        expect(received.takeBytes(), expected);
        expect(
          ticks,
          greaterThan(0),
          reason: 'input must yield to the UI isolate',
        );
      } finally {
        timer.cancel();
        await input.stop();
      }
    },
  );

  test('repeated idle acquisition preserves input flags', () async {
    final warm = lease();
    await warm.start();
    await warm.stop();
    final flags = _sys.flags(pipe.reader);
    for (var i = 0; i < 100; i++) {
      final input = lease();
      await input.start();
      await input.stop();
    }
    expect(_sys.flags(pipe.reader), flags);
  });
}

final _sys = _System();

final class _Pipe {
  _Pipe() {
    final pair = calloc<Int32>(2);
    try {
      if (_sys.pipe(pair) != 0) throw StateError('pipe creation failed');
      reader = pair[0];
      writer = pair[1];
      _sys.setFlags(writer, _sys.flags(writer) | _sys.nonblocking);
    } finally {
      calloc.free(pair);
    }
  }
  late final int reader;
  late int writer;

  Future<void> send(List<int> bytes) async {
    final memory = calloc<Uint8>(bytes.length);
    try {
      memory.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final n = _sys.write(writer, memory + offset, bytes.length - offset);
        if (n > 0) {
          offset += n;
        } else {
          final error = _sys.errno().value;
          if (error != 4 && error != (Platform.isMacOS ? 35 : 11)) {
            throw OSError('pipe write', error);
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
    } finally {
      calloc.free(memory);
    }
  }

  int readOne() {
    final memory = calloc<Uint8>();
    try {
      expect(_sys.read(reader, memory, 1), 1);
      return memory.value;
    } finally {
      calloc.free(memory);
    }
  }

  void closeWriter() {
    if (writer >= 0) _sys.close(writer);
    writer = -1;
  }

  void close() {
    closeWriter();
    _sys.close(reader);
  }
}

final class _System {
  final library = DynamicLibrary.process();
  int get nonblocking => Platform.isMacOS ? 4 : 2048;
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
  late final errno = library
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );
  int flags(int fd) => fcntl(fd, 3, 0);
  void setFlags(int fd, int flags) => expect(fcntl(fd, 4, flags), 0);
}
