// Shared fakes for tests that drive runApp through the structured serve
// path: a peer-side transport that records everything the app sends and
// lets the test inject peer frames.

import 'dart:async';

import 'package:fleury/fleury_host.dart';

class FakeFrameTransport implements RemoteFrameTransport {
  final _in = StreamController<RemoteFrame>.broadcast();

  /// Every frame the app sent, in order.
  final List<RemoteFrame> sent = [];
  bool closed = false;

  @override
  Stream<RemoteFrame> get incoming => _in.stream;

  @override
  void send(RemoteFrame frame) => sent.add(frame);

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  /// Injects a peer frame into the app.
  void emit(RemoteFrame frame) {
    if (!_in.isClosed) _in.add(frame);
  }

  /// Simulates the peer dropping the connection.
  Future<void> disconnect() async {
    if (!_in.isClosed) await _in.close();
  }
}
