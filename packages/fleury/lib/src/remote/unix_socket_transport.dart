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
  // bytes.
  final List<List<int>> _sendQueue = <List<int>>[];
  int _pendingSendBytes = 0;
  bool _pumpRunning = false;
  Future<void>? _pumpFuture;
  Completer<void>? _drained;

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
    _sendQueue.add(bytes);
    _pendingSendBytes += bytes.length;
    if (!_pumpRunning) {
      _pumpRunning = true;
      // Kept so a graceful [close] can await the in-flight flush. _sendPump
      // never throws (it catches flush errors), so this future never rejects.
      _pumpFuture = _sendPump();
    }
  }

  Future<void> _sendPump() async {
    try {
      while (!_closed && _sendQueue.isNotEmpty) {
        // Hand the whole queue over, then flush. Sends that arrive while
        // the flush pends land in the queue and drive the next lap.
        var handed = 0;
        for (final chunk in _sendQueue) {
          _socket.add(chunk);
          handed += chunk.length;
        }
        _sendQueue.clear();
        try {
          await _socket.flush();
        } catch (_) {
          // Peer vanished mid-flush; the incoming stream's error/done
          // path drives the session teardown. Stop counting so gated
          // hosts wake instead of waiting on a dead pipe.
          _sendQueue.clear();
          _pendingSendBytes = 0;
          break;
        }
        _pendingSendBytes -= handed;
        if (_pendingSendBytes < 0) _pendingSendBytes = 0;
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
  Future<void> close() async {
    if (_closed) return;
    // Snapshot the backlog BEFORE flipping _closed (which forces
    // isSendBacklogged false): only a genuine over-HWM stall justifies
    // dropping unsent bytes.
    final wasBacklogged = _pendingSendBytes > sendHighWaterMark;
    _closed = true;
    // Wake any host gated on the backlog — it must never wait on a dead
    // peer (the drain future's contract).
    _completeDrained();
    await _socketSub?.cancel();
    _socketSub = null;
    if (wasBacklogged) {
      // The peer stalled past the high-water mark; a graceful flush could
      // block forever. Reset the connection — undelivered bytes are lost
      // either way once we're closing on a backlog.
      _socket.destroy();
    } else {
      // Setting _closed stops the pump from starting NEW laps, but it
      // finishes flushing the bytes it already handed to the socket — the
      // final ByeFrame / plan. Wait that out (bounded) so a clean shutdown
      // delivers them instead of resetting the connection under them.
      final pump = _pumpFuture;
      if (pump != null) {
        var timedOut = false;
        await pump.timeout(
          _closeFlushTimeout,
          onTimeout: () => timedOut = true,
        );
        if (timedOut) {
          _socket.destroy();
          if (!_incoming.isClosed) await _incoming.close();
          return;
        }
      }
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
    }
    if (!_incoming.isClosed) await _incoming.close();
  }
}
