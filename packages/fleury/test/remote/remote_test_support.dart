// Shared fakes for tests that drive runApp through the structured serve
// path: a peer-side transport that records everything the app sends and
// lets the test inject peer frames.

import 'dart:async';

import 'package:fleury/fleury_host.dart';

class FakeFrameTransport
    with SynchronousSendTransport
    implements RemoteFrameTransport {
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

/// A [FakeFrameTransport] whose send backlog the test controls — the
/// harness for asserting the frame program's producer gate ("a stalled
/// peer defers frame production; drain resumes with one coalesced
/// frame").
class GatedFakeTransport extends FakeFrameTransport {
  bool _backlogged = false;
  Completer<void>? _drain;

  @override
  bool get isSendBacklogged => _backlogged;

  @override
  Future<void> get sendDrained {
    if (!_backlogged) return Future<void>.value();
    return (_drain ??= Completer<void>()).future;
  }

  /// The peer stalls: sends still record (nothing produced should send
  /// anyway while gated), and the app's frame program defers.
  void stall() => _backlogged = true;

  /// The peer catches up: pending [sendDrained] futures complete.
  void drain() {
    _backlogged = false;
    final completer = _drain;
    _drain = null;
    completer?.complete();
  }
}
