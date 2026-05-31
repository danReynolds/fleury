// Transport abstraction beneath the remote-rendering drivers.
//
// A `RemoteFrameTransport` is the only thing the driver knows about
// the outside world. Implementations:
//
//   - `UnixSocketFrameTransport` — `fleury shell` IDE-debug workflow,
//     app side connects to a Unix domain socket the shell created.
//   - (future) `WebSocketFrameTransport` — `fleury serve` browser
//     delivery, app side accepts a websocket from the embedded
//     xterm.js client.
//   - `_FakeFrameTransport` (tests) — a pair of in-memory streams.
//
// Each transport speaks the same wire protocol (`remote_protocol.dart`)
// so the driver doesn't fork per surface.

import 'dart:async';

import 'remote_protocol.dart';

/// Bidirectional frame channel between the app and a peer (a local
/// shell terminal, a browser, a test harness). Frames flow in both
/// directions; lifetime is owned by the caller (typically the driver).
abstract interface class RemoteFrameTransport {
  /// Stream of frames arriving from the peer. Closes when the peer
  /// disconnects or [close] is called locally.
  Stream<RemoteFrame> get incoming;

  /// Send one frame to the peer.
  void send(RemoteFrame frame);

  /// Tear the connection down. Idempotent.
  Future<void> close();
}
