// Unix-domain-socket transport for the remote-rendering protocol.
//
// Two convenience constructors cover the two ends of an `fleury shell`
// session:
//
//   - `UnixSocketFrameTransport.connect(path)` — app side. Opens the
//     socket the shell already bound to and starts the frame loop.
//   - `UnixSocketFrameTransport.fromSocket(socket)` — shell side. Wraps
//     an already-accepted client socket so the shell process drives
//     the same frame loop.
//
// The framing logic lives in `remote_protocol.dart`; this file is just
// the socket plumbing.

import 'dart:async';
import 'dart:io';

import 'remote_protocol.dart';
import 'remote_transport.dart';

final class UnixSocketFrameTransport implements RemoteFrameTransport {
  UnixSocketFrameTransport._(this._socket, this.sendHighWaterMark)
    : _decoder = FrameDecoder(),
      _incoming = StreamController<RemoteFrame>.broadcast() {
    _socketSub = _socket.listen(
      (chunk) {
        try {
          _decoder.feed(chunk);
          for (final frame in _decoder.drain()) {
            _incoming.add(frame);
          }
        } on Object catch (error, stackTrace) {
          _incoming.addError(error, stackTrace);
          unawaited(close());
        }
      },
      onError: _incoming.addError,
      onDone: _incoming.close,
      cancelOnError: false,
    );
    // [_incoming] is a broadcast controller: frames added while nobody
    // listens are DROPPED. The peer may speak the moment the socket opens
    // (the agent bridge sends INIT on accept), while the app side doesn't
    // subscribe until the driver's enter() — and any await between connect
    // and enter() (fd-capture startup, a future async setup step) opens a
    // window where the peer's first frames would vanish and the handshake
    // would hang forever. Park the socket until the first listener
    // attaches: bytes wait in the kernel buffer / paused subscription,
    // nothing is decoded-and-dropped.
    _socketSub!.pause();
    _incoming.onListen = _socketSub!.resume;
  }

  /// Opens the Unix socket at [path] and wraps it as a transport.
  /// Used by the app side after detecting a `shell_handle` file.
  static Future<UnixSocketFrameTransport> connect(
    String path, {
    int sendHighWaterMark = defaultSendHighWaterMark,
  }) async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return UnixSocketFrameTransport._(socket, sendHighWaterMark);
  }

  /// Wraps an already-accepted [Socket]. Used by the shell side once a
  /// client connects.
  factory UnixSocketFrameTransport.fromSocket(
    Socket socket, {
    int sendHighWaterMark = defaultSendHighWaterMark,
  }) => UnixSocketFrameTransport._(socket, sendHighWaterMark);

  /// Send bytes accepted but not yet handed to the OS before the
  /// transport reports itself backlogged. 256 KiB holds a few frames of
  /// a busy dashboard without tripping, while bounding app-side memory
  /// when the peer stalls (the kernel socket buffer sits below this).
  static const int defaultSendHighWaterMark = 256 * 1024;

  /// Absolute ceiling for encoded bytes retained by the send pump.
  ///
  /// A structured presentation can legitimately enqueue a complete 32 MiB
  /// inline-image working set followed by an 8 MiB plan before the frame loop
  /// gets another chance to observe [isSendBacklogged]. 64 MiB preserves that
  /// burst (and room for one maximum legal 16 MiB frame) while preventing a
  /// caller that keeps sending into a stalled peer from growing the queue
  /// without bound.
  static const int _maxPendingSendBytes = 64 * 1024 * 1024;

  /// Independent object-count ceiling for tiny frames.
  ///
  /// Byte accounting alone does not bound the heap cost of thousands of
  /// short encoded Uint8Lists. A legitimate presentation emits at most the
  /// 512-image cache working set plus its plan and small side-channel frames,
  /// so 4096 leaves generous burst headroom without permitting object-count
  /// amplification.
  static const int _maxPendingSendFrames = 4096;

  final Socket _socket;
  final FrameDecoder _decoder;
  final StreamController<RemoteFrame> _incoming;

  /// See [defaultSendHighWaterMark].
  final int sendHighWaterMark;

  StreamSubscription<List<int>>? _socketSub;
  bool _closed = false;

  // The send pump owns ALL socket writes: dart:io forbids `add()` while
  // a `flush()` is pending ("StreamSink is bound to a stream"), so
  // [send] only enqueues. The pump hands the queue to the socket, then
  // awaits `flush()` — which completes once the OS accepts the bytes and
  // PENDS while the peer stalls: that pending flush is the backpressure
  // signal. [_pendingSendBytes] counts queued + handed-but-unflushed
  // bytes; [_pendingSendFrames] counts their backing frame objects.
  final List<List<int>> _sendQueue = <List<int>>[];
  int _pendingSendBytes = 0;
  int _pendingSendFrames = 0;
  bool _pumpRunning = false;
  Future<void>? _pumpFuture;
  Completer<void>? _drained;
  Future<void>? _abortTeardown;

  /// The one teardown [close] ever runs, cached on the first call.
  ///
  /// [RemoteFrameTransport.close] is documented idempotent and callers take
  /// that literally — `RemoteTerminalDriver.enter`'s INIT fuse fires
  /// `unawaited(close())` and then throws, and `restore()` awaits `close()`
  /// again. Idempotent has to mean "the second caller waits for the SAME
  /// teardown": the graceful path flips `_closed` before its first await and
  /// leaves [_abortTeardown] null, so without this a concurrent second call
  /// would await nothing and return while the socket was still being flushed
  /// and closed. The `??=` assigns before [_close] can reach an await, so
  /// every concurrent caller gets this exact future.
  Future<void>? _closeFuture;

  /// A graceful [close] waits at most this long for the send pump to flush
  /// already-queued frames (the final ByeFrame / plan) before giving up and
  /// resetting the connection — so shutdown can't hang on a socket that is
  /// slow but not yet over the high-water mark.
  static const Duration _closeFlushTimeout = Duration(seconds: 2);

  @override
  Stream<RemoteFrame> get incoming => _incoming.stream;

  @override
  bool get isSendBacklogged =>
      !_closed && _pendingSendBytes > sendHighWaterMark;

  @override
  Future<void> get sendDrained {
    if (!isSendBacklogged) return Future<void>.value();
    return (_drained ??= Completer<void>()).future;
  }

  @override
  void send(RemoteFrame frame) {
    if (_closed) return;
    final bytes = encodeFrame(frame);
    final nextPendingBytes = _pendingSendBytes + bytes.length;
    final nextPendingFrames = _pendingSendFrames + 1;
    if (nextPendingBytes > _maxPendingSendBytes ||
        nextPendingFrames > _maxPendingSendFrames) {
      final error = StateError(
        'UnixSocketFrameTransport pending output would reach '
        '$nextPendingFrames frames / $nextPendingBytes bytes, exceeding hard '
        'limits of $_maxPendingSendFrames frames / $_maxPendingSendBytes '
        'bytes. The session was terminated instead of dropping a frame and '
        'desynchronizing the peer.',
      );
      final stackTrace = StackTrace.current;
      _abortTeardown = _tearDownPendingOutput(
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    _sendQueue.add(bytes);
    _pendingSendBytes = nextPendingBytes;
    _pendingSendFrames = nextPendingFrames;
    if (!_pumpRunning) {
      _pumpRunning = true;
      // Kept so a graceful [close] can await the in-flight flush. _sendPump
      // never throws (it catches disconnect errors), so this future never
      // rejects.
      _pumpFuture = _sendPump();
    }
  }

  Future<void> _tearDownPendingOutput({
    Object? error,
    StackTrace? stackTrace,
  }) async {
    _closed = true;
    _sendQueue.clear();
    _pendingSendBytes = 0;
    _pendingSendFrames = 0;
    _completeDrained();
    if (error != null && !_incoming.isClosed) {
      try {
        _incoming.addError(error, stackTrace ?? StackTrace.current);
      } catch (_) {
        // Teardown still wins if a concurrently closing controller rejects
        // the diagnostic.
      }
    }

    final socketSub = _socketSub;
    _socketSub = null;
    Future<void>? socketCancel;
    try {
      socketCancel = socketSub?.cancel();
    } catch (_) {
      // The socket is already being failed closed.
    }
    // Cancel input callbacks before destroy so this transport publishes only
    // the deliberate overflow diagnostic. Destroy immediately afterward so an
    // in-flight Socket.flush cannot keep the pump alive. The remainder is
    // awaited by close(), ensuring the pump cannot race accounting back to a
    // non-zero state.
    _socket.destroy();
    if (socketCancel != null) {
      try {
        await socketCancel;
      } catch (_) {
        // The socket is already being failed closed.
      }
    }
    final pump = _pumpFuture;
    if (pump != null) {
      try {
        await pump;
      } catch (_) {
        // _sendPump currently catches socket failures; retain fail-closed
        // teardown even if that implementation detail changes.
      }
    }
    if (!_incoming.isClosed) await _incoming.close();
  }

  Future<void> _sendPump() async {
    try {
      while (!_closed && _sendQueue.isNotEmpty) {
        // Hand the whole queue over, then flush. Sends that arrive while
        // the flush pends land in the queue and drive the next lap.
        var handed = 0;
        var handedFrames = 0;
        try {
          for (final chunk in _sendQueue) {
            _socket.add(chunk);
            handed += chunk.length;
            handedFrames++;
          }
          _sendQueue.clear();
          await _socket.flush();
        } catch (_) {
          // Peer vanished before add() or during flush(); the incoming
          // stream's error/done path drives session teardown. Stop counting
          // so gated hosts wake instead of waiting on a dead pipe.
          _sendQueue.clear();
          _pendingSendBytes = 0;
          _pendingSendFrames = 0;
          break;
        }
        _pendingSendBytes -= handed;
        if (_pendingSendBytes < 0) _pendingSendBytes = 0;
        _pendingSendFrames -= handedFrames;
        if (_pendingSendFrames < 0) _pendingSendFrames = 0;
      }
    } finally {
      _pumpRunning = false;
      _completeDrained();
    }
  }

  void _completeDrained() {
    final completer = _drained;
    _drained = null;
    completer?.complete();
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) {
      // Already torn down by the send-overflow path; wait out ITS teardown.
      await _abortTeardown;
      return;
    }
    final backlogged = _pendingSendBytes > sendHighWaterMark;

    if (backlogged) {
      // The peer stalled past the high-water mark; a graceful flush could
      // block forever. Reset the connection — undelivered bytes are lost
      // either way once we're closing on a backlog.
      _abortTeardown = _tearDownPendingOutput();
      await _abortTeardown;
      return;
    }

    // Clean shutdown: let the pump DRAIN the whole queue first — including a
    // ByeFrame just enqueued behind an in-flight flush — before marking the
    // transport closed. Flipping _closed now would make the pump's
    // `while (!_closed ...)` loop abandon un-handed queued frames. Bounded
    // so a slow-but-not-backlogged socket can't hang shutdown.
    final pump = _pumpFuture;
    if (pump != null) {
      var timedOut = false;
      await pump.timeout(_closeFlushTimeout, onTimeout: () => timedOut = true);
      if (timedOut) {
        _abortTeardown = _tearDownPendingOutput();
        await _abortTeardown;
        return;
      }
    }

    _closed = true;
    _completeDrained();
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket.flush();
    } catch (_) {
      /* peer may already be gone */
    }
    try {
      await _socket.close();
    } catch (_) {
      /* idem */
    }
    if (!_incoming.isClosed) await _incoming.close();
  }
}
