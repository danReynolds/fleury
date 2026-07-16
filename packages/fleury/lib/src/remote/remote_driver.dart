// A `TerminalDriver` whose I/O backs onto a `RemoteFrameTransport`
// rather than `dart:io` stdin/stdout. Used by `fleury shell` (Unix
// socket transport, app rendering into a separate shell terminal) and
// `fleury serve` (websocket transport, app rendering into the retained-DOM
// browser client). Same widget tree, same renderer, same input
// dispatch — only the boundary moves.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/surface_capabilities.dart';
import '../runtime/frame_presentation.dart';
import '../runtime/remote_surface_sink.dart';
import '../semantics/semantics.dart';
import '../semantics/semantics_owner.dart' show SemanticTreeUpdate;
import '../terminal/capabilities.dart';
import '../input/events.dart';
import '../terminal/input_parser.dart';
import '../terminal/terminal_driver.dart';
import 'inline_image_cache.dart';
import 'remote_codec.dart';
import 'remote_protocol.dart';
import 'remote_semantics.dart';
import 'remote_transport.dart';

/// Maximum grid dimensions the server will honor from a remote peer.
/// A real terminal/browser viewport is well within this; the bound exists
/// only to cap the cell-buffer allocation against a hostile RESIZE/INIT.
/// The independent dimension caps accommodate extreme-wide display walls, and
/// the area cap is the real allocation boundary: two retained 1M-cell buffers
/// are already far beyond an ordinary TUI while remaining finite.
const int maxRemoteGridCols = maxRemotePlanGridCols;
const int maxRemoteGridRows = maxRemotePlanGridRows;
const int maxRemoteGridCells = maxRemotePlanGridCells;

/// The remote-rendering driver for `fleury shell` and `fleury serve`.
///
/// One driver covers both legacy (ANSI) and structured (presentation-plan)
/// peers. The handshake's protocol version decides: a v1 peer (a real
/// terminal, e.g. `fleury shell`) receives ANSI via [write]; a v2 peer (the
/// browser surface client) receives [PlanFrame]s via [presentPlan] and
/// sends structured input. [wantsPresentationPlans] reflects the negotiated
/// version and is read by [runApp] after [enter] completes.
final class RemoteTerminalDriver
    implements
        TerminalDriver,
        RemoteSurfaceSink,
        SurfaceCapabilitiesProvider,
        OutputFlowControl {
  RemoteTerminalDriver(
    this._transport, {
    InlineImageCachePolicy imageCachePolicy = defaultInlineImageCachePolicy,
  }) : _shippedImages = InlineImageCacheLedger(imageCachePolicy);

  /// The transport's send backlog IS this driver's output backlog: the
  /// frame program defers production while the peer (or the serve bridge
  /// to it) stalls, and resumes with one coalesced frame on drain.
  @override
  bool get isOutputBacklogged => _transport.isSendBacklogged;

  @override
  Future<void> get outputDrained => _transport.sendDrained;

  final RemoteFrameTransport _transport;
  final InputParser _parser = InputParser();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  final _RemoteParserSink _sink = _RemoteParserSink();
  final SemanticsWireEncoder _semanticsEncoder = SemanticsWireEncoder();
  RemoteSemanticActionHandler? _onSemanticAction;
  RemoteDebugRequestHandler? _onDebugRequest;
  void Function(int seq, RemoteClipboardStatus status)? _onClipboardResult;

  StreamSubscription<RemoteFrame>? _frameSub;
  Timer? _parserFlushTimer;
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

  // Content-hash ids and encoded byte lengths the peer is believed to hold — a
  // app-side mirror of the client's blob cache (InlineImageOverlay). Bytes
  // ship once per id and the id stays "held" until it falls out of this
  // bounded, insertion-ordered ledger under the SAME shared policy the client
  // uses (evict oldest ids not placed this frame once over count or bytes). A
  // re-appearing image — including every frame of an animation, which is a
  // fresh id per tick — re-ships bytes only when the client would actually
  // have evicted them, not on every loop.
  final InlineImageCacheLedger _shippedImages;
  bool _active = false;
  bool _handshakeReceived = false;
  int _protocolVersion = 1;
  Completer<void>? _handshake;

  @override
  bool get wantsPresentationPlans => _protocolVersion >= 2;

  /// Whether the negotiated peer can decode OSC 8 links in the PLAN cell-style
  /// entry (protocol v4, RFC 0017 §5). Frozen from the peer's INIT alongside
  /// [_protocolVersion]. A pre-v4 peer (including a stale cached v3 browser
  /// client) reports false, so [presentFrame] builds a plan that omits the
  /// link bytes and stays byte-identical to v3 — the crux that keeps an older
  /// client's decoder from misaligning on an unexpected URI.
  bool get wantsHyperlinks => _protocolVersion >= 4;

  /// Whether the peer understands protocol-v5 inline-image placement windows.
  /// A v4 client still receives the legacy placement shape, while a v5 client
  /// can preserve the original fit when only part of an image box is visible.
  bool get wantsImageWindows => _protocolVersion >= 5;

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
  RemoteSurfaceSink? get surfaceSink => wantsPresentationPlans ? this : null;

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
    //
    // BOUNDED: a peer that connects and then never speaks must not hang
    // the app forever — under `serve --spawn` that is a process leak an
    // attacker can multiply (open sockets, send nothing). A disconnect
    // already fails the handshake; silence now does too. The deadline is
    // generous for real peers (the bridge / serve client sends INIT
    // immediately on accept) while bounding the leak window.
    try {
      await _handshake!.future.timeout(initTimeout);
    } on TimeoutException {
      await _frameSub?.cancel();
      _frameSub = null;
      unawaited(_transport.close());
      throw StateError(
        'RemoteTerminalDriver.enter: the peer connected but sent no INIT '
        'within ${initTimeout.inSeconds}s — closing the session.',
      );
    }
    _active = true;
  }

  /// How long [enter] waits for the peer's INIT before failing closed.
  /// Overridable for tests.
  static Duration initTimeout = const Duration(seconds: 10);

  /// Idle debounce used to disambiguate a lone ESC on the legacy raw-input
  /// path. Overridable for focused tests.
  static Duration inputFlushDelay = const Duration(milliseconds: 30);

  @override
  Future<void> restore() async {
    final wasActive = _active;
    _active = false;
    _parserFlushTimer?.cancel();
    _parserFlushTimer = null;
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
    _shippedImages.clear();
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
    var remotePlan = buildRemotePlan(
      prev,
      next,
      fullRepaint: plan.fullRepaint,
      // The planner's damage covers every changed cell (the invariant the
      // ANSI renderer's bounded diff already rides), so the plan builder
      // skips provably-clean rows instead of re-diffing the whole screen.
      // This makes the damage a wire-correctness boundary: under-covering
      // damage ships an incomplete plan and desyncs the peer's mirror until
      // the next full repaint. buildRemotePlan's debug oracle makes that
      // loud in dev/CI; release trusts the planner.
      dirtyRows: plan.damage.dirtyRows,
      // Serialize OSC 8 links only when the peer negotiated v>=4 (RFC 0017
      // §5). A pre-v4 peer gets bit-6-clear, byte-identical-to-v3 output even
      // if a cell carries a link, so a stale client can't misalign on a URI it
      // doesn't expect.
      includeLinks: wantsHyperlinks,
      includeImageWindows: wantsImageWindows,
    );
    final boundedPlacements = _boundedImagePlacements(remotePlan, next);
    if (boundedPlacements.length != remotePlan.placements.length) {
      remotePlan = RemotePlan(
        size: remotePlan.size,
        fullRepaint: remotePlan.fullRepaint,
        styleTable: remotePlan.styleTable,
        patches: remotePlan.patches,
        scrollUpRows: remotePlan.scrollUpRows,
        placements: boundedPlacements,
        includeLinks: remotePlan.includeLinks,
        includeImageWindows: remotePlan.includeImageWindows,
      );
    }
    // Ship the bytes for each image the peer does not yet hold, before the
    // plan that references it. An id ships at most once per frame even if
    // placed several times, and at most once while the peer keeps it cached
    // (see [_shippedImages]) — so a static or animated image doesn't
    // re-transmit bytes the client already has.
    final placedIds = <String>{for (final p in remotePlan.placements) p.id};
    var additionalEntries = 0;
    var additionalBytes = 0;
    for (final id in placedIds) {
      if (_shippedImages.contains(id)) continue;
      final image = next.images[id];
      if (image == null) continue;
      additionalEntries++;
      additionalBytes += image.bytes.length;
    }
    // Make room against the *next* plan before sending its images. The browser
    // stages those frames and performs this same projected-fit eviction when
    // the PlanFrame arrives, keeping both insertion-ordered ledgers identical
    // without either side temporarily accumulating stale + next-generation
    // blobs in one committed cache.
    _shippedImages.evictStaleToFit(
      placedIds,
      additionalEntries: additionalEntries,
      additionalBytes: additionalBytes,
    );
    final handledIds = <String>{};
    for (final placement in remotePlan.placements) {
      if (!handledIds.add(placement.id)) continue; // already handled this frame
      if (_shippedImages.contains(placement.id)) continue; // peer holds it
      final image = next.images[placement.id];
      if (image != null) {
        _transport.send(InlineImageFrame(placement.id, image.bytes));
        _shippedImages.add(placement.id, image.bytes.length);
      }
    }
    _evictShippedImageIds(placedIds);
    _transport.send(PlanFrame(remotePlan));
  }

  /// Keeps one plan's visible image working set within the shared cache policy
  /// and frame limits. Excess images degrade to blank overlay cells; the normal
  /// case is unchanged and retains every placement. The deterministic paint-
  /// order prefix is also what a skewed/malformed peer can reproduce safely.
  List<ImagePlacement> _boundedImagePlacements(
    RemotePlan plan,
    CellBuffer next,
  ) {
    if (plan.placements.isEmpty) return plan.placements;
    final policy = _shippedImages.policy;
    final acceptedIds = <String>{};
    final rejectedIds = <String>{};
    final placements = <ImagePlacement>[];
    var encodedBytes = 0;

    for (final placement in plan.placements) {
      if (placements.length >= maxRemotePlanPlacements) break;
      if (rejectedIds.contains(placement.id)) continue;
      if (acceptedIds.contains(placement.id)) {
        placements.add(placement);
        continue;
      }

      final image = next.images[placement.id];
      final idBytes = utf8.encode(placement.id);
      final imageBytes = image?.bytes.length ?? 0;
      final validFrame =
          image != null &&
          idBytes.isNotEmpty &&
          idBytes.length <= 256 &&
          imageBytes + idBytes.length + 2 <= maxRemoteImageFramePayloadLength;
      final fitsWorkingSet =
          acceptedIds.length < policy.maxEntries &&
          encodedBytes + imageBytes <= policy.maxBytes;
      if (!validFrame || !fitsWorkingSet) {
        rejectedIds.add(placement.id);
        continue;
      }
      acceptedIds.add(placement.id);
      encodedBytes += imageBytes;
      placements.add(placement);
    }
    return List<ImagePlacement>.unmodifiable(placements);
  }

  /// Applies the shared count-and-byte policy against the same placements the
  /// browser receives, so the app's belief of what the peer holds stays in
  /// step with its actual cache. [_boundedImagePlacements] guarantees the
  /// placed working set itself already fits this policy.
  void _evictShippedImageIds(Set<String> placedThisFrame) {
    _shippedImages.evictStale(placedThisFrame);
  }

  /// Diffs the semantic [tree] against the last one sent to this peer and ships
  /// only what changed (a full frame once, patches after), redacting just the
  /// nodes [update] names. No-op on the ANSI path, and a no-op send when the
  /// exposed semantics are unchanged.
  @override
  void presentSemantics(SemanticTree tree, {SemanticTreeUpdate? update}) {
    if (!_active || !wantsPresentationPlans) return;
    final bytes = _semanticsEncoder.encodeTree(tree, update: update);
    if (bytes == null) return;
    // The encoder advances its retained mirror while producing [bytes]. If the
    // payload cannot pass the same cap the peer enforces, do not emit a frame
    // that will destroy its stream framing; reset so a later, smaller tree is a
    // FULL resync rather than a PATCH against state the peer never received.
    if (bytes.length > remoteFramePayloadLimit(FrameType.semantics)) {
      _semanticsEncoder.reset();
      return;
    }
    try {
      _transport.send(SemanticsFrame(bytes));
    } catch (_) {
      // A synchronous transport rejection has the same state consequence as
      // an oversized payload: delivery did not happen after the encoder moved
      // forward. Restore the only safe next-send contract, then preserve the
      // transport failure for the caller's normal error path.
      _semanticsEncoder.reset();
      rethrow;
    }
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
  set onDebugRequest(RemoteDebugRequestHandler? handler) {
    _onDebugRequest = handler;
  }

  @override
  void presentDebugResponse(int seq, String kind, Uint8List json) {
    _transport.send(DebugResponseFrame(seq, kind, json));
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
        // The handshake is ONE-SHOT: the negotiated protocol version and
        // capabilities are frozen for the session. A later INIT (a buggy or
        // hostile peer) must not flip wantsPresentationPlans, retarget
        // surfaceSink, or restyle MediaQuery under a live session — the
        // size channel after the handshake is ResizeFrame. Ignore repeats.
        if (_handshakeReceived) break;
        _handshakeReceived = true;
        _size = _clampSize(f.size);
        _protocolVersion = f.protocolVersion;
        _capabilities = TerminalCapabilities(
          colorMode: f.colorMode,
          glyphTier: f.glyphTier,
          imageProtocol: f.imageProtocol,
          tmuxPassthrough: f.tmuxPassthrough,
          // Thread the peer's link capability into BOTH capability objects so
          // surfaceCapabilities.hyperlinks reflects the peer whether or not it
          // sent `images=` (the projection fallback below reads this field).
          hyperlinks: f.hyperlinks,
        );
        final peerImages = f.images;
        _peerSurfaceCapabilities = peerImages == null
            ? null
            : SurfaceCapabilities(
                colorMode: f.colorMode,
                glyphTier: f.glyphTier,
                images: peerImages,
                // A browser peer that renders <a> anchors declares this in
                // INIT; without it the server-side MarkdownText gate reads
                // MediaQuery.capabilitiesOf(context).hyperlinks == false and
                // never produces a linkUri (underlined-but-not-clickable).
                hyperlinks: f.hyperlinks,
                pointer: f.protocolVersion >= 2
                    ? PointerPrecision.subCell
                    : PointerPrecision.cell,
              );
        // v3: echo INIT back with the app's protocol version so the peer
        // can detect version skew (e.g. a cached client bundle). The
        // echoed size/capabilities restate what the peer sent; only `v`
        // carries new information. A v2 peer ignores it.
        if (f.protocolVersion >= 3) {
          _transport.send(
            InitFrame(
              size: _size,
              colorMode: f.colorMode,
              glyphTier: f.glyphTier,
              imageProtocol: f.imageProtocol,
              tmuxPassthrough: f.tmuxPassthrough,
              // Restate the peer's own fields (only `v` carries new info). The
              // client reads only `v` from the echo for skew detection, so this
              // value drives no link decision; restating what the peer sent
              // keeps a link-free echo byte-flat (false emits no `hyperlinks=`).
              hyperlinks: f.hyperlinks,
            ),
          );
        }
        _handshake?.complete();
      case ResizeFrame f:
        _size = _clampSize(f.size);
        if (_active) _events.add(ResizeEvent(_size));
      case InputFrame f:
        // Raw ANSI input belongs exclusively to the negotiated v1 terminal
        // path. A structured peer must use INPUT_EVENT; ignoring legacy bytes
        // here prevents it from reaching the stateful escape/paste parser and
        // removes an accidental second input channel after negotiation.
        if (!_handshakeReceived || wantsPresentationPlans) break;
        _parser.feed(f.bytes, _sink);
        _parserFlushTimer?.cancel();
        _parserFlushTimer = Timer(inputFlushDelay, () {
          _parserFlushTimer = null;
          if (_active && !wantsPresentationPlans) _parser.flush(_sink);
        });
      case OutputFrame _:
      case PlanFrame _:
      case SemanticsFrame _:
      case InlineImageFrame _:
      case SemanticActionResultFrame _:
      case DebugResponseFrame _:
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
      case DebugRequestFrame f:
        if (_active) _onDebugRequest?.call(f.seq, f.kind, f.limit);
      case InputEventFrame f:
        // Structured input from a v2 peer: surface the event directly
        // instead of parsing ANSI. A resize event also updates the cached
        // size so the next plan is built at the new viewport.
        if (_active && wantsPresentationPlans) {
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
  CellSize _clampSize(CellSize size) {
    var cols = size.cols.clamp(1, maxRemoteGridCols);
    var rows = size.rows.clamp(1, maxRemoteGridRows);
    if (cols * rows > maxRemoteGridCells) {
      // Preserve the smaller requested dimension and trim the larger one. This
      // keeps common ultrawide/tall layouts closer to their requested shape
      // than independently clamping both dimensions to a huge rectangle.
      if (cols >= rows) {
        cols = (maxRemoteGridCells ~/ rows).clamp(1, maxRemoteGridCols);
      } else {
        rows = (maxRemoteGridCells ~/ cols).clamp(1, maxRemoteGridRows);
      }
    }
    return CellSize(cols, rows);
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    if (!_active) {
      if (!(_handshake?.isCompleted ?? true)) {
        _handshake?.completeError(error, stackTrace);
      }
      return;
    }
    if (!_events.isClosed) _events.addError(error, stackTrace);
  }

  void _onDisconnect() {
    _parserFlushTimer?.cancel();
    _parserFlushTimer = null;
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
    if (!wantsPresentationPlans) _parser.finish(_sink);
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
    final controller = target;
    if (controller != null && !controller.isClosed) controller.add(event);
  }
}
