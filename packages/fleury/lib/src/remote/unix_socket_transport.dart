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
  UnixSocketFrameTransport._(this._socket)
    : _decoder = FrameDecoder(),
      _incoming = StreamController<RemoteFrame>.broadcast() {
    _socketSub = _socket.listen(
      (chunk) {
        _decoder.feed(chunk);
        for (final frame in _decoder.drain()) {
          _incoming.add(frame);
        }
      },
      onError: _incoming.addError,
      onDone: _incoming.close,
      cancelOnError: false,
    );
  }

  /// Opens the Unix socket at [path] and wraps it as a transport.
  /// Used by the app side after detecting a `shell_handle` file.
  static Future<UnixSocketFrameTransport> connect(String path) async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return UnixSocketFrameTransport._(socket);
  }

  /// Wraps an already-accepted [Socket]. Used by the shell side once a
  /// client connects.
  factory UnixSocketFrameTransport.fromSocket(Socket socket) =>
      UnixSocketFrameTransport._(socket);

  final Socket _socket;
  final FrameDecoder _decoder;
  final StreamController<RemoteFrame> _incoming;
  StreamSubscription<List<int>>? _socketSub;
  bool _closed = false;

  @override
  Stream<RemoteFrame> get incoming => _incoming.stream;

  @override
  void send(RemoteFrame frame) {
    if (_closed) return;
    _socket.add(encodeFrame(frame));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.flush();
    } catch (_) {
      /* peer may already be gone */
    }
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket.close();
    } catch (_) {
      /* idem */
    }
    if (!_incoming.isClosed) await _incoming.close();
  }
}
