import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

/// A cancellable borrow of an existing POSIX input descriptor.
///
/// Does not subscribe to Dart stdin, reopen a terminal, parse input, or change
/// termios. The owner stores the lease before awaiting [start], and awaits
/// [stop] before returning input to a prompt, child process, or another UI.
///
/// One UI-owning isolate is supported. Destruction of that isolate while the
/// process survives requires external recovery of both input flags and termios.
@internal
final class PosixInputLease {
  PosixInputLease({
    required this.onBytes,
    required this.onDone,
    required this.onError,
    this.source = 0,
    @visibleForTesting this.beforeSpawn,
  });

  final void Function(Uint8List bytes) onBytes;
  final void Function() onDone;
  final void Function(Object error, StackTrace stack) onError;
  final int source;
  @visibleForTesting
  final void Function()? beforeSpawn;

  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _startFinished = Completer<void>();
  _InputResources? _resources;
  ReceivePort? _messages;
  Future<Isolate>? _spawn;
  Isolate? _worker;
  Future<void>? _startFuture;
  Future<void>? _stopFuture;
  bool _callerStopped = false;
  bool _accepting = false;
  bool _started = false;
  bool _ended = false;
  (Object, StackTrace)? _failure;

  Future<void> start() {
    if (_stopFuture != null) {
      return Future<void>.error(StateError('Input lease already stopped.'));
    }
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    try {
      if (_callerStopped) throw StateError('Input lease already stopped.');
      final resources = _resources = _InputResources();
      // All handles and allocations belong to this isolate, including partial
      // acquisition. The worker only borrows them until its actual exit.
      resources.acquire(source);
      beforeSpawn?.call();
      final messages = _messages = ReceivePort();
      messages.listen(_receive);
      _accepting = true;
      _spawn = Isolate.spawn(
        _readInput,
        (
          messages.sendPort,
          resources.input,
          resources.wakeRead,
          resources.watches.address,
          resources.bytes.address,
        ),
        onExit: messages.sendPort,
        onError: messages.sendPort,
      );
      _worker = await _spawn;
      await _ready.future;
      if (_callerStopped) throw StateError('Input lease stopped during start.');
      final failure = _failure;
      if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
      _started = true;
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      _startFinished.complete();
    }
  }

  void _receive(dynamic message) {
    if (message == null) {
      if (!_ended && !_callerStopped && _failure == null) {
        _failure = (
          StateError('Native input worker exited unexpectedly.'),
          StackTrace.current,
        );
      }
      _exited.complete();
      if (!_ready.isCompleted) _ready.complete();
      unawaited(_notifyEnd());
    } else if (message == 'ready') {
      if (!_ready.isCompleted) _ready.complete();
    } else if (message == 'eof') {
      _ended = true;
    } else if (message is Uint8List) {
      if (!_accepting) return;
      try {
        onBytes(message);
        // A callback may itself initiate stop. Never acknowledge into a lease
        // whose owner has already fenced delivery.
        if (_accepting) _resources!.command(_ack);
      } catch (error, stack) {
        _failure ??= (error, stack);
        unawaited(
          _shutdown().catchError((Object error, StackTrace stack) {
            _failure ??= (error, stack);
          }),
        );
      }
    } else if (message is List && message.length == 3) {
      _failure ??= (
        OSError(message[1] as String, message[2] as int),
        StackTrace.current,
      );
    } else if (message is List && message.length == 2) {
      // Uncaught isolate errors (including failures before its try block).
      _failure ??= (
        StateError('Native input worker failed: ${message[0]}'),
        StackTrace.fromString('${message[1]}'),
      );
    }
  }

  Future<void> _notifyEnd() async {
    try {
      await _shutdown();
    } catch (error, stack) {
      _failure ??= (error, stack);
    }
    await _startFinished.future;
    if (_callerStopped || !_started) return;
    final failure = _failure;
    if (failure != null) {
      onError(failure.$1, failure.$2);
    } else {
      onDone();
    }
  }

  /// Fences delivery immediately; completes only after the worker has exited,
  /// shared input flags are restored, and all owned resources are released.
  Future<void> stop() {
    _callerStopped = true;
    return _shutdown();
  }

  Future<void> _shutdown() {
    _accepting = false;
    return _stopFuture ??= _release();
  }

  Future<void> _release() async {
    final spawning = _spawn;
    if (spawning != null) {
      Isolate? worker;
      try {
        worker = await spawning;
      } catch (_) {
        // No worker was created; the owner still releases partial acquisition.
      }
      if (worker != null) {
        if (!_exited.isCompleted) {
          try {
            _resources!.command(_stop);
          } catch (_) {
            // A broken wake channel must not strand the reader. Bounded,
            // non-leaf poll lets VM cancellation interrupt it at the next
            // return. Memory and descriptors remain owned until onExit.
            worker.kill(priority: Isolate.immediate);
          }
        }
        await _exited.future;
      }
    }
    try {
      _resources?.release();
    } finally {
      _messages?.close();
      _worker = null;
    }
  }

  @visibleForTesting
  void debugKillWorker() => _worker?.kill(priority: Isolate.immediate);
}

const _ack = 65;
const _stop = 83;
const _batchSize = 4096;
const _pollIntervalMs = 250;

/// A zero-timeout observation of physical hangup on this exact descriptor.
/// SIGHUP, EOF, EIO, and POLLERR alone do not prove terminal loss. Invalid
/// descriptors remain ownership errors. This does not consume pending input.
@internal
bool posixDescriptorHungUp(int fd) {
  if (!Platform.isMacOS && !Platform.isLinux) return false;
  final sys = _PosixInputSystem();
  final watch = calloc<_PollFd>();
  try {
    watch.ref.fd = fd;
    // Darwin does not report HUP with an empty requested event mask.
    watch.ref.events = 1; // POLLIN
    return sys.poll(watch, 1, 0) > 0 &&
        watch.ref.revents & 0x10 != 0 && // POLLHUP
        watch.ref.revents & 0x20 == 0; // not POLLNVAL
  } finally {
    calloc.free(watch);
  }
}

/// Saved shared blocking state, also retained by the development supervisor
/// before it spawns a child. Closing a duplicated fd does not restore this bit.
/// The caller owns the descriptor's lifetime; this snapshot owns no handles.
@internal
final class PosixInputFlags {
  PosixInputFlags._(this._nonblocking, this._wasTerminal);

  factory PosixInputFlags.capture(int fd) {
    final sys = _PosixInputSystem();
    final flags = sys.fcntl(fd, 3, 0);
    if (flags < 0) throw sys.error('Cannot snapshot terminal input flags');
    return PosixInputFlags._(flags & sys.nonblocking, sys.isatty(fd) == 1);
  }

  final int _nonblocking;
  final bool _wasTerminal;

  void restore(int fd) {
    final sys = _PosixInputSystem();
    final current = sys.fcntl(fd, 3, 0);
    if (current < 0 ||
        sys.fcntl(fd, 4, (current & ~sys.nonblocking) | _nonblocking) < 0) {
      final error = sys.error('Cannot restore terminal input flags');
      // Darwin may reject F_SETFL with ENOTTY after revoking a controlling
      // terminal. The worker has stopped; there is no usable terminal owner
      // to return the flags to. Pipes and invalid fds retain normal errors.
      if (!_wasTerminal || !posixDescriptorHungUp(fd)) throw error;
    }
  }
}

// These allocations and handles have a single closer, in the owning isolate.
// Closing in the worker and again after its crash could close an unrelated fd
// that reused the number. An error message is not proof the worker has exited.
final class _InputResources {
  final _sys = _PosixInputSystem();
  int input = -1;
  int wakeRead = -1;
  int wakeWrite = -1;
  PosixInputFlags? _originalFlags;
  Pointer<_PollFd> watches = nullptr;
  Pointer<Uint8> bytes = nullptr;
  Pointer<Uint8> _command = nullptr;

  void acquire(int source) {
    input = _sys.fcntl(source, _sys.duplicateCommand, 0);
    if (input < 0) throw _sys.error('Cannot duplicate terminal input');
    final flags = _sys.fcntl(input, 3, 0); // F_GETFL
    if (flags < 0) throw _sys.error('Cannot read terminal input flags');
    _originalFlags = PosixInputFlags._(
      flags & _sys.nonblocking,
      _sys.isatty(input) == 1,
    );
    if (_sys.fcntl(input, 4, flags | _sys.nonblocking) < 0) {
      throw _sys.error('Cannot enable nonblocking terminal input');
    }
    final pair = calloc<Int32>(2);
    try {
      // Linux has atomic pipe2. Darwin has no pipe2; its pipe + fcntl sequence
      // contains no Dart yield, and both ends are marked before spawning work.
      final result = Platform.isLinux
          ? _sys.pipe2(pair, 0x80000 | _sys.nonblocking) // O_CLOEXEC
          : _sys.pipe(pair);
      if (result < 0) throw _sys.error('Cannot create input wake pipe');
      wakeRead = pair[0];
      wakeWrite = pair[1];
      if (!Platform.isLinux) {
        for (final fd in [wakeRead, wakeWrite]) {
          if (_sys.fcntl(fd, 2, 1) < 0 || // F_SETFD, FD_CLOEXEC
              _sys.fcntl(fd, 4, _sys.nonblocking) < 0) {
            throw _sys.error('Cannot configure input wake pipe');
          }
        }
      }
    } finally {
      calloc.free(pair);
    }
    watches = calloc<_PollFd>(2);
    bytes = calloc<Uint8>(_batchSize);
    _command = calloc<Uint8>();
  }

  void command(int value) {
    _command.value = value;
    while (_sys.write(wakeWrite, _command, 1) != 1) {
      final errno = _sys.errno().value;
      if (errno == 4) continue; // EINTR, no byte written.
      // One outstanding batch means at most one ACK and one STOP are queued.
      // EAGAIN cannot legitimately occur; never silently lose the stop byte.
      throw OSError('Cannot wake native input worker', errno);
    }
  }

  void release() {
    Object? failure;
    try {
      _originalFlags?.restore(input);
    } catch (error) {
      failure = error;
    }
    for (final fd in [input, wakeRead, wakeWrite]) {
      if (fd >= 0 && _sys.close(fd) < 0) {
        // Do not retry close after EINTR: the descriptor may have been reused.
        failure ??= _sys.error('Cannot close native input descriptor');
      }
    }
    input = wakeRead = wakeWrite = -1;
    _originalFlags = null;
    if (watches != nullptr) calloc.free(watches);
    if (bytes != nullptr) calloc.free(bytes);
    if (_command != nullptr) calloc.free(_command);
    watches = nullptr;
    bytes = _command = nullptr;
    if (failure != null) throw failure;
  }
}

void _readInput((SendPort, int, int, int, int) args) {
  final (owner, input, wake, watchesAddress, bytesAddress) = args;
  final sys = _PosixInputSystem();
  final watches = Pointer<_PollFd>.fromAddress(watchesAddress);
  final bytes = Pointer<Uint8>.fromAddress(bytesAddress);
  var waitingForAck = false;
  try {
    owner.send('ready');
    while (true) {
      watches[0].fd = wake;
      watches[0].events = 1; // POLLIN
      watches[1].fd = waitingForAck ? -1 : input;
      watches[1].events = 1;
      // A pipe wakes ordinary stop immediately. A finite native wait also lets
      // VM shutdown proceed if main exits/fails without calling stop. Infinite
      // non-leaf poll was verified to strand both JIT and AOT process shutdown.
      final result = sys.poll(watches, 2, _pollIntervalMs);
      if (result < 0) {
        if (sys.errno().value == 4) continue;
        throw sys.error('Native input poll failed');
      }
      if (watches[0].revents != 0) {
        // Drain control first, including a STOP queued behind an ACK. Do not
        // consume terminal input merely because both descriptors are ready.
        while (true) {
          final count = sys.read(wake, bytes, _batchSize);
          if (count == 0) return;
          if (count < 0) {
            final errno = sys.errno().value;
            if (errno == 4) continue;
            if (errno == sys.again) break;
            throw OSError('Native input wake read failed', errno);
          }
          for (var i = 0; i < count; i++) {
            if (bytes[i] == _stop) return;
            if (bytes[i] == _ack) waitingForAck = false;
          }
        }
        continue;
      }
      if (watches[1].revents != 0) {
        final count = sys.read(input, bytes, _batchSize);
        if (count == 0) {
          owner.send('eof');
          return;
        }
        if (count < 0) {
          final errno = sys.errno().value;
          if (errno == 4 || errno == sys.again) continue;
          throw OSError('Native input read failed', errno);
        }
        owner.send(Uint8List.fromList(bytes.asTypedList(count)));
        waitingForAck = true;
      }
    }
  } on OSError catch (error) {
    owner.send(['failure', error.message, error.errorCode]);
  }
  // No close/free here. The owner joins onExit before releasing borrowed data.
}

final class _PollFd extends Struct {
  @Int32()
  external int fd;
  @Int16()
  external int events;
  @Int16()
  external int revents;
}

final class _PosixInputSystem {
  final _library = DynamicLibrary.process();
  int get nonblocking => Platform.isMacOS ? 4 : 2048;
  int get duplicateCommand => Platform.isMacOS ? 67 : 1030;
  int get again => Platform.isMacOS ? 35 : 11;
  late final pipe = _library
      .lookupFunction<
        Int32 Function(Pointer<Int32>),
        int Function(Pointer<Int32>)
      >('pipe');
  late final pipe2 = _library
      .lookupFunction<
        Int32 Function(Pointer<Int32>, Int32),
        int Function(Pointer<Int32>, int)
      >('pipe2');
  late final close = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final isatty = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('isatty');
  late final fcntl = _library
      .lookupFunction<
        Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
        int Function(int, int, int)
      >('fcntl');
  late final read = _library
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read');
  late final write = _library
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  late final int Function(Pointer<_PollFd>, int, int) poll = Platform.isMacOS
      ? _library.lookupFunction<
          Int32 Function(Pointer<_PollFd>, Uint32, Int32),
          int Function(Pointer<_PollFd>, int, int)
        >('poll')
      : _library.lookupFunction<
          Int32 Function(Pointer<_PollFd>, Uint64, Int32),
          int Function(Pointer<_PollFd>, int, int)
        >('poll');
  late final errno = _library
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );
  OSError error(String message) => OSError(message, errno().value);
}
