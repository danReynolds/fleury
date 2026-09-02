import 'dart:async';
import 'dart:io';

/// One app-side connection of a `fleury serve` bridge session, read from the
/// moment it connects.
///
/// Serve used to leave a pending app socket unread until a browser paired
/// with it. Two failures followed: an app that died while pending was never
/// noticed (its socket stayed "pending" and every later app was dropped —
/// the wedge), and an app that painted while waiting filled the socket
/// buffer with nobody draining it. This link subscribes once, at accept:
/// before [attach] it DISCARDS what the app sends (the app repaints in full
/// when the browser's real INIT lands, so nothing is lost), and after
/// [attach] it forwards to the browser with pause/resume propagated back to
/// the socket. [closed] completes the moment the app goes away, paired or
/// not.
final class BridgeAppLink {
  BridgeAppLink(Socket socket)
    : this.forStream(socket, sink: socket, destroySource: socket.destroy);

  /// Test seam: any byte stream plus a sink stands in for the socket.
  BridgeAppLink.forStream(
    Stream<List<int>> source, {
    required this.sink,
    required void Function() destroySource,
  }) : _destroySource = destroySource {
    _subscription = source.listen(
      _onData,
      onError: (Object _, StackTrace _) => _finish(),
      onDone: _finish,
      cancelOnError: false,
    );
  }

  /// Bytes TO the app (the browser's frames).
  final IOSink sink;

  final void Function() _destroySource;
  late final StreamSubscription<List<int>> _subscription;
  final Completer<void> _closed = Completer<void>();
  StreamController<List<int>>? _output;
  var _discardedBytes = 0;

  /// Bytes the app sent before a browser attached, dropped.
  int get discardedBytes => _discardedBytes;

  /// Whether the app side has gone away.
  bool get isClosed => _closed.isCompleted;

  /// Completes when the app disconnects, errors, or is destroyed.
  Future<void> get closed => _closed.future;

  /// Starts forwarding the app's bytes; returns the stream a browser pump
  /// consumes. Single-subscription; may be called once.
  Stream<List<int>> attach() {
    if (_output != null) {
      throw StateError('BridgeAppLink.attach() called twice.');
    }
    final controller = StreamController<List<int>>(
      onPause: _subscription.pause,
      onResume: _subscription.resume,
      onCancel: () => _subscription.cancel(),
    );
    _output = controller;
    if (isClosed) unawaited(controller.close());
    return controller.stream;
  }

  /// Tears the app side down. Idempotent.
  void destroy() {
    _destroySource();
    _finish();
    unawaited(_subscription.cancel());
  }

  void _onData(List<int> bytes) {
    final out = _output;
    if (out == null) {
      _discardedBytes += bytes.length;
      return;
    }
    if (!out.isClosed) out.add(bytes);
  }

  void _finish() {
    if (_closed.isCompleted) return;
    _closed.complete();
    final out = _output;
    if (out != null && !out.isClosed) unawaited(out.close());
  }
}
