// Bounded browser -> app input buffering for `fleury serve`.
//
// A browser can connect before its app process/socket is ready, so serve must
// subscribe immediately and retain the initial INIT frame. The same buffer also
// sits between a paired WebSocket and Socket.addStream. It therefore owns both
// halves of the resource contract: a hard queued-byte ceiling and propagation
// of downstream pause/resume/cancel back to the WebSocket subscription.

import 'dart:async';
import 'dart:io' show WebSocket;
import 'dart:typed_data';

import 'remote_protocol.dart';

/// One maximum legal remote frame including its five-byte frame header.
const int maxBufferedBrowserInputBytes = defaultMaxRemoteFramePayloadLength + 5;

/// Byte bounds alone do not cap the per-event/controller overhead of tiny or
/// empty WebSocket messages.
const int maxBufferedBrowserInputMessages = 4096;

/// Buffers binary WebSocket messages until the app-side byte pump consumes
/// them, while keeping queued memory bounded before and after pairing.
final class BufferedBrowserInput {
  BufferedBrowserInput(
    WebSocket webSocket, {
    int maxMessageBytes = maxBufferedBrowserInputBytes,
    int maxQueuedBytes = maxBufferedBrowserInputBytes,
    int maxQueuedMessages = maxBufferedBrowserInputMessages,
  }) : webSocket = webSocket,
       _closeSource = ((code, reason) async {
         await webSocket.close(code, reason);
       }),
       _maxMessageBytes = maxMessageBytes,
       _maxQueuedBytes = maxQueuedBytes,
       _maxQueuedMessages = maxQueuedMessages {
    _start(webSocket);
  }

  /// Test seam for a controllable source without constructing a real socket.
  BufferedBrowserInput.forStream(
    Stream<dynamic> source, {
    required Future<void> Function(int code, String reason) closeSource,
    int maxMessageBytes = maxBufferedBrowserInputBytes,
    int maxQueuedBytes = maxBufferedBrowserInputBytes,
    int maxQueuedMessages = maxBufferedBrowserInputMessages,
  }) : webSocket = null,
       _closeSource = closeSource,
       _maxMessageBytes = maxMessageBytes,
       _maxQueuedBytes = maxQueuedBytes,
       _maxQueuedMessages = maxQueuedMessages {
    _start(source);
  }

  final WebSocket? webSocket;
  final Future<void> Function(int code, String reason) _closeSource;
  final int _maxMessageBytes;
  final int _maxQueuedBytes;
  final int _maxQueuedMessages;
  final _closed = Completer<void>();

  late final StreamController<_QueuedBrowserInput> _controller;
  StreamSubscription<dynamic>? _subscription;
  var _queuedBytes = 0;
  var _queuedMessages = 0;
  var _rejected = false;
  var _sourceFinished = false;
  var _disposed = false;
  Future<void>? _cancelFuture;

  /// Bytes in arrival order. This is a single-subscription stream: one browser
  /// is paired with one app socket.
  Stream<List<int>> get stream => _controller.stream.transform(
    StreamTransformer<_QueuedBrowserInput, List<int>>.fromHandlers(
      handleData: (queued, sink) {
        try {
          // A transformer forwards this event through the downstream onData
          // callback before returning from add. Keep it in the budget until
          // that callback has advanced.
          sink.add(queued.bytes);
        } finally {
          _queuedBytes -= queued.bytes.length;
          _queuedMessages--;
          assert(_queuedBytes >= 0);
          assert(_queuedMessages >= 0);
        }
      },
    ),
  );

  /// Completes when the browser source ends, is rejected, is cancelled by the
  /// app-side pump, or this buffer is disposed.
  Future<void> get closed => _closed.future;

  void _start(Stream<dynamic> source) {
    assert(_maxMessageBytes > 0);
    assert(_maxQueuedBytes > 0);
    assert(_maxQueuedMessages > 0);
    _controller = StreamController<_QueuedBrowserInput>(
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: () async {
        await _cancelSource();
        _completeClosed();
      },
    );
    _subscription = source.listen(
      _onData,
      onError: (Object error, StackTrace stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
        _finishSource();
      },
      onDone: _finishSource,
      cancelOnError: false,
    );
  }

  void _onData(Object? data) {
    if (_rejected || _sourceFinished || _disposed) {
      return;
    }
    if (data is! List<int>) {
      _reject(
        'browser input must use binary WebSocket messages',
        closeCode: 1003,
        closeReason: 'binary input required',
      );
      return;
    }
    if (data.length > _maxMessageBytes) {
      _reject('browser message exceeded remote frame payload limit');
      return;
    }
    if (_queuedMessages >= _maxQueuedMessages) {
      _reject('queued browser input exceeded remote message count limit');
      return;
    }
    if (_queuedBytes + data.length > _maxQueuedBytes) {
      _reject('queued browser input exceeded remote frame payload limit');
      return;
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    _queuedBytes += bytes.length;
    _queuedMessages++;
    if (_controller.isClosed) {
      _queuedBytes -= bytes.length;
      _queuedMessages--;
      return;
    }
    _controller.add(_QueuedBrowserInput(bytes));
  }

  void _reject(
    String reason, {
    int closeCode = 1009,
    String closeReason = 'input too large',
  }) {
    if (_rejected || _disposed) return;
    _rejected = true;
    if (!_controller.isClosed) {
      _controller.addError(RemoteProtocolException(reason, recoverable: false));
    }
    // A waiting spawn must abort immediately; do not depend on a platform
    // WebSocket implementation completing its close handshake first.
    _completeClosed();
    unawaited(_closeSource(closeCode, closeReason).catchError((Object _) {}));
  }

  void _finishSource() {
    if (_sourceFinished) return;
    _sourceFinished = true;
    if (!_controller.isClosed) unawaited(_controller.close());
    _completeClosed();
  }

  Future<void> _cancelSource() =>
      _cancelFuture ??= _subscription?.cancel() ?? Future<void>.value();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cancelSource();
    if (!_controller.isClosed) {
      final hadListener = _controller.hasListener;
      final closed = _controller.close();
      // A single-subscription controller's close future does not settle until
      // someone listens. Before pairing there intentionally may be no listener.
      if (hadListener) await closed;
    }
    _completeClosed();
  }

  void _completeClosed() {
    if (!_closed.isCompleted) _closed.complete();
  }
}

final class _QueuedBrowserInput {
  const _QueuedBrowserInput(this.bytes);

  final Uint8List bytes;
}
