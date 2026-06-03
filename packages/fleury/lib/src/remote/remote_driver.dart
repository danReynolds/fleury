// A `TerminalDriver` whose I/O backs onto a `RemoteFrameTransport`
// rather than `dart:io` stdin/stdout. Used by `fleury shell` (Unix
// socket transport, app rendering into a separate shell terminal) and
// `fleury serve` (websocket transport, app rendering into a browser
// xterm.js client). Same widget tree, same renderer, same input
// dispatch — only the boundary moves.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../terminal/capabilities.dart';
import '../terminal/events.dart';
import '../terminal/input_parser.dart';
import '../terminal/terminal_driver.dart';
import 'remote_protocol.dart';
import 'remote_transport.dart';

final class RemoteTerminalDriver implements TerminalDriver {
  RemoteTerminalDriver(this._transport);

  final RemoteFrameTransport _transport;
  final InputParser _parser = InputParser();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  final _RemoteParserSink _sink = _RemoteParserSink();

  StreamSubscription<RemoteFrame>? _frameSub;
  CellSize _size = const CellSize(80, 24);
  TerminalCapabilities _capabilities = TerminalCapabilities.defaultCapabilities;
  bool _active = false;
  bool _handshakeReceived = false;
  Completer<void>? _handshake;

  @override
  CellSize get size => _size;

  @override
  TerminalCapabilities get capabilities => _capabilities;

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => true;

  @override
  Future<void> enter(TerminalMode mode) async {
    if (_active) {
      throw StateError(
        'RemoteTerminalDriver.enter called on an active driver.',
      );
    }
    _sink.target = _events;

    // The peer is responsible for the actual terminal-mode bookkeeping
    // on its end (raw input, alt screen, hidden cursor). We just pass
    // bytes; the peer applies them.
    _handshake = Completer<void>();
    _frameSub = _transport.incoming.listen(
      _onFrame,
      onError: _onTransportError,
      onDone: _onDisconnect,
      cancelOnError: false,
    );

    // Block until the peer's INIT frame lands so size + capabilities
    // are correct before the first paint. Without this, `runTui` would
    // race the handshake and allocate the buffer pool at the default
    // 80×24, then immediately resize on the first frame.
    await _handshake!.future;
    _active = true;
  }

  @override
  Future<void> restore() async {
    final wasActive = _active;
    _active = false;
    if (wasActive) {
      try {
        _transport.send(const ByeFrame());
      } catch (_) {
        // Best-effort — peer may already be gone.
      }
    }
    await _frameSub?.cancel();
    _frameSub = null;
    await _transport.close();
    if (!_events.isClosed) await _events.close();
  }

  @override
  void write(String data) {
    if (!_active) return;
    _transport.send(OutputFrame(Uint8List.fromList(utf8.encode(data))));
  }

  void _onFrame(RemoteFrame frame) {
    switch (frame) {
      case InitFrame f:
        _size = f.size;
        _capabilities = TerminalCapabilities(
          colorMode: f.colorMode,
          imageProtocol: f.imageProtocol,
          tmuxPassthrough: f.tmuxPassthrough,
        );
        if (!_handshakeReceived) {
          _handshakeReceived = true;
          _handshake?.complete();
        }
      case ResizeFrame f:
        _size = f.size;
        if (_active) _events.add(ResizeEvent(f.size));
      case InputFrame f:
        _parser.feed(f.bytes, _sink);
      case OutputFrame _:
        // App never receives OUTPUT; ignore so a malformed peer can't
        // crash the session.
        break;
      case ByeFrame():
        _onDisconnect();
    }
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    if (!_active) {
      if (!(_handshake?.isCompleted ?? true)) {
        _handshake?.completeError(error, stackTrace);
      }
      return;
    }
    _events.addError(error, stackTrace);
  }

  void _onDisconnect() {
    if (!_active) {
      // Handshake never landed — fail the enter() future so the caller
      // can fall back or report cleanly.
      if (!(_handshake?.isCompleted ?? true)) {
        _handshake?.completeError(
          StateError('Remote peer disconnected before sending INIT.'),
        );
      }
      return;
    }
    _active = false;
    // Closing the events stream surfaces as `onDone` in `runTui`, which
    // completes the exit completer and runs cleanup. No custom event
    // type or out-of-band signaling required.
    _events.close();
  }
}

class _RemoteParserSink implements TuiEventSink {
  StreamController<TuiEvent>? target;

  @override
  void add(TuiEvent event) {
    target?.add(event);
  }
}
