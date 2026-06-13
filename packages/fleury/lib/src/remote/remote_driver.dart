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
import '../rendering/cell_buffer.dart';
import '../runtime/frame_presentation.dart';
import '../runtime/remote_surface_sink.dart';
import '../terminal/capabilities.dart';
import '../terminal/events.dart';
import '../terminal/input_parser.dart';
import '../terminal/terminal_driver.dart';
import 'remote_codec.dart';
import 'remote_protocol.dart';
import 'remote_transport.dart';

/// Maximum grid dimensions the server will honor from a remote peer.
/// A real terminal/browser viewport is well within this; the bound exists
/// only to cap the cell-buffer allocation against a hostile RESIZE/INIT.
/// 4000×4000 = 16M cells, generous and bounded.
const int maxRemoteGridCols = 4000;
const int maxRemoteGridRows = 4000;

/// The remote-rendering driver for `fleury shell` and `fleury serve`.
///
/// One driver covers both legacy (ANSI) and structured (presentation-plan)
/// peers. The handshake's protocol version decides: a v1 peer (a real
/// terminal, e.g. `fleury shell`) receives ANSI via [write]; a v2 peer (the
/// browser surface client) receives [PlanFrame]s via [presentPlan] and
/// sends structured input. [wantsPresentationPlans] reflects the negotiated
/// version and is read by [runTui] after [enter] completes.
final class RemoteTerminalDriver implements TerminalDriver, RemoteSurfaceSink {
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
  int _protocolVersion = 1;
  Completer<void>? _handshake;

  @override
  bool get wantsPresentationPlans => _protocolVersion >= 2;

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
    if (!_active || wantsPresentationPlans) return;
    _transport.send(OutputFrame(Uint8List.fromList(utf8.encode(data))));
  }

  @override
  void presentFrame(
    CellBuffer prev,
    CellBuffer next,
    FramePresentationPlan plan,
  ) {
    if (!_active) return;
    _transport.send(
      PlanFrame(buildRemotePlan(prev, next, fullRepaint: plan.fullRepaint)),
    );
  }

  /// Sends a semantic snapshot (UTF-8 JSON) for the just-presented frame.
  /// No-op on the ANSI path; used by the structured serve host.
  @override
  void presentSemantics(List<int> json) {
    if (!_active || !wantsPresentationPlans) return;
    _transport.send(
      SemanticsFrame(json is Uint8List ? json : Uint8List.fromList(json)),
    );
  }

  void _onFrame(RemoteFrame frame) {
    switch (frame) {
      case InitFrame f:
        _size = _clampSize(f.size);
        _protocolVersion = f.protocolVersion;
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
        _size = _clampSize(f.size);
        if (_active) _events.add(ResizeEvent(_size));
      case InputFrame f:
        _parser.feed(f.bytes, _sink);
      case OutputFrame _:
      case PlanFrame _:
      case SemanticsFrame _:
        // App→peer render frames; an app never receives them. Ignore so a
        // malformed peer can't crash the session.
        break;
      case InputEventFrame f:
        // Structured input from a v2 peer: surface the event directly
        // instead of parsing ANSI. A resize event also updates the cached
        // size so the next plan is built at the new viewport.
        if (_active) {
          var event = f.event;
          if (event is ResizeEvent) {
            event = ResizeEvent(_clampSize(event.size));
            _size = event.size;
          }
          _events.add(event);
        }
      case ByeFrame():
        _onDisconnect();
    }
  }

  /// Clamps a peer-supplied grid size to a sane maximum so a malicious or
  /// buggy client cannot make the app allocate an enormous cell buffer
  /// (`RESIZE cols=100000,rows=100000` → ten billion cells). The bound is
  /// far above any real terminal/browser viewport.
  CellSize _clampSize(CellSize size) => CellSize(
    size.cols.clamp(1, maxRemoteGridCols),
    size.rows.clamp(1, maxRemoteGridRows),
  );

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
