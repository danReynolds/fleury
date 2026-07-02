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
import '../rendering/surface_capabilities.dart';
import '../runtime/frame_presentation.dart';
import '../runtime/remote_surface_sink.dart';
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import '../terminal/capabilities.dart';
import '../input/events.dart';
import '../terminal/input_parser.dart';
import '../terminal/terminal_driver.dart';
import 'remote_codec.dart';
import 'remote_protocol.dart';
import 'remote_semantics.dart';
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
/// version and is read by [runApp] after [enter] completes.
final class RemoteTerminalDriver
    implements TerminalDriver, RemoteSurfaceSink, SurfaceCapabilitiesProvider {
  RemoteTerminalDriver(this._transport);

  final RemoteFrameTransport _transport;
  final InputParser _parser = InputParser();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  final _RemoteParserSink _sink = _RemoteParserSink();
  final SemanticsWireEncoder _semanticsEncoder = SemanticsWireEncoder();
  RemoteSemanticActionHandler? _onSemanticAction;
  void Function(int seq, RemoteClipboardStatus status)? _onClipboardResult;

  StreamSubscription<RemoteFrame>? _frameSub;
  CellSize _size = const CellSize(80, 24);
  TerminalCapabilities _capabilities = TerminalCapabilities.defaultCapabilities;
  SurfaceCapabilities? _peerSurfaceCapabilities;

  /// What the PEER's surface can do: from the v3 `images=` INIT param when
  /// present, else the terminal projection (a v1 `fleury shell` peer is a
  /// real terminal). A structured browser peer gets sub-cell pointer
  /// fidelity — its input source reports real mouse geometry.
  @override
  SurfaceCapabilities get surfaceCapabilities =>
      _peerSurfaceCapabilities ?? _capabilities.toSurfaceCapabilities();

  // Content-hash ids of inline images placed on the PREVIOUS frame. An image's
  // bytes are (re)shipped whenever it appears or re-appears — i.e. its id is
  // placed this frame but was not last frame — never per-session "once ever".
  // This keeps the host's notion of what the peer has bounded by the on-screen
  // set and consistent with the client, which freely evicts off-screen blobs:
  // a scrolled-back image is always re-sent. (A continuously on-screen image
  // ships once and is not re-sent while it stays placed.)
  Set<String> _prevPlacedImageIds = <String>{};
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
    // are correct before the first paint. Without this, `runApp` would
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
    final remotePlan = buildRemotePlan(
      prev,
      next,
      fullRepaint: plan.fullRepaint,
    );
    // Ship the bytes for each image that (re)appears this frame — placed now but
    // not on the previous frame — before the plan that references it. An image
    // that stays on screen ships once; one that scrolls away and back is re-sent
    // (the client may have evicted its blob in the meantime). Each distinct id
    // ships at most once per frame even if placed several times.
    final placedIds = <String>{};
    for (final placement in remotePlan.placements) {
      if (!placedIds.add(placement.id)) continue; // already sent this frame
      if (_prevPlacedImageIds.contains(placement.id)) continue; // peer has it
      final image = next.images[placement.id];
      if (image != null) {
        _transport.send(InlineImageFrame(placement.id, image.bytes));
      }
    }
    _prevPlacedImageIds = placedIds;
    _transport.send(PlanFrame(remotePlan));
  }

  /// Diffs the semantic [snapshot] against the last one sent to this peer and
  /// ships only what changed (a full frame once, patches after). No-op on the
  /// ANSI path, and a no-op send when the exposed semantics are unchanged.
  @override
  void presentSemantics(SemanticInspectionSnapshot snapshot) {
    if (!_active || !wantsPresentationPlans) return;
    final bytes = _semanticsEncoder.encode(snapshot);
    if (bytes == null) return;
    _transport.send(SemanticsFrame(bytes));
  }

  @override
  void presentSemanticActionResult(
    SemanticNodeId id,
    SemanticAction action,
    SemanticActionInvocationStatus status,
  ) {
    if (!_active || !wantsPresentationPlans) return;
    _transport.send(SemanticActionResultFrame(id, action, status));
  }

  @override
  set onSemanticAction(RemoteSemanticActionHandler? handler) {
    _onSemanticAction = handler;
  }

  @override
  void presentCaret(CellRect? caret) {
    if (!_active || !wantsPresentationPlans) return;
    _transport.send(CaretFrame(caret));
  }

  @override
  void sendClipboardWrite(int seq, String text) {
    if (!_active || !wantsPresentationPlans) return;
    _transport.send(ClipboardWriteFrame(seq, text));
  }

  @override
  set onClipboardResult(
    void Function(int seq, RemoteClipboardStatus status)? handler,
  ) {
    _onClipboardResult = handler;
  }

  void _onFrame(RemoteFrame frame) {
    switch (frame) {
      case InitFrame f:
        _size = _clampSize(f.size);
        _protocolVersion = f.protocolVersion;
        _capabilities = TerminalCapabilities(
          colorMode: f.colorMode,
          glyphTier: f.glyphTier,
          imageProtocol: f.imageProtocol,
          tmuxPassthrough: f.tmuxPassthrough,
        );
        final peerImages = f.images;
        _peerSurfaceCapabilities = peerImages == null
            ? null
            : SurfaceCapabilities(
                colorMode: f.colorMode,
                glyphTier: f.glyphTier,
                images: peerImages,
                pointer: f.protocolVersion >= 2
                    ? PointerPrecision.subCell
                    : PointerPrecision.cell,
              );
        if (!_handshakeReceived) {
          _handshakeReceived = true;
          // v3: echo INIT back with the app's protocol version so the
          // peer can detect version skew (e.g. a cached client bundle).
          // The echoed size/capabilities restate what the peer sent;
          // only `v` carries new information. A v2 peer ignores it.
          if (f.protocolVersion >= 3) {
            _transport.send(
              InitFrame(
                size: _size,
                colorMode: f.colorMode,
                glyphTier: f.glyphTier,
                imageProtocol: f.imageProtocol,
                tmuxPassthrough: f.tmuxPassthrough,
              ),
            );
          }
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
      case InlineImageFrame _:
      case SemanticActionResultFrame _:
      case CaretFrame _:
      case ClipboardWriteFrame _:
        // App→peer render frames; an app never receives them. Ignore so a
        // malformed peer can't crash the session.
        break;
      case ClipboardResultFrame f:
        if (_active) _onClipboardResult?.call(f.seq, f.status);
      case SemanticActionFrame f:
        // The peer activated a node in its accessible DOM; invoke it on the
        // live tree (only on the structured path, like the other v2 input).
        if (_active && wantsPresentationPlans) {
          _onSemanticAction?.call(f.id, f.action, f.value);
        }
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
    // Closing the events stream surfaces as `onDone` in `runApp`, which
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
