// Transport abstraction beneath the remote-rendering drivers.
//
// A `RemoteFrameTransport` is the only thing the driver knows about
// the outside world. Implementations:
//
//   - `UnixSocketFrameTransport` — `fleury shell` IDE-debug workflow,
//     app side connects to a Unix domain socket the shell created.
//   - `fleury serve` browser delivery — the serve process bridges the
//     app's Unix socket to a WebSocket; the browser end is the embedded
//     structured client (RemoteSurfaceClient), not a transport here.
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

  /// True while bytes accepted by [send] exceed the transport's
  /// high-water mark and have not yet been handed to the OS — the peer
  /// (or the pipe to it) has stalled. Hosts defer frame PRODUCTION while
  /// this is true; frames already sent are never dropped (the wire
  /// protocol's diffs are only valid against the exact previous frame
  /// the peer holds).
  bool get isSendBacklogged;

  /// Completes when the send backlog drains — immediately when not
  /// backlogged, and always on [close] (a gated host must never wait
  /// forever on a dead peer).
  Future<void> get sendDrained;

  /// Tear the connection down. Idempotent.
  Future<void> close();
}

/// Mixin for transports whose [send] hands bytes off synchronously (an
/// in-memory pair, a test fake): they can never back up.
mixin SynchronousSendTransport implements RemoteFrameTransport {
  @override
  bool get isSendBacklogged => false;

  @override
  Future<void> get sendDrained => Future<void>.value();
}
