import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/remote_semantics.dart';
import 'package:web/web.dart' as web;

import '../dom_grid/dom_grid_surface.dart';
import '../input/dom_input_source.dart';
import '../metrics/cell_metrics.dart';
import '../metrics/dom_cell_metrics.dart';
import '../semantics/semantic_dom_presenter.dart';
import 'plan_adapter.dart';

/// Browser-side client for the structured serve path.
///
/// Connects to a `fleury serve` WebSocket, performs the v2 INIT handshake,
/// applies inbound [PlanFrame]s to a retained [DomGridSurface], and sends
/// browser input back as structured [InputEventFrame]s. This is the
/// renderer that replaces xterm.js: a served session renders through the
/// same DOM surface the in-browser host uses, with the same span/scroll
/// machinery.
final class RemoteSurfaceClient {
  RemoteSurfaceClient({required web.Element hostElement, required String url})
    : _host = hostElement,
      _url = url;

  final web.Element _host;
  final String _url;

  web.WebSocket? _socket;
  DomGridSurface? _surface;
  SemanticDomPresenter? _semantics;
  DomCellMetrics? _metrics;
  DomInputSource? _input;
  final FrameDecoder _decoder = FrameDecoder();
  final SemanticsWireDecoder _semanticsDecoder = SemanticsWireDecoder();
  CellSize _size = const CellSize(80, 24);
  bool _handshakeSent = false;
  bool _closed = false;
  web.HTMLElement? _disconnectBanner;
  CellBuffer _mirror = CellBuffer(const CellSize(80, 24));

  /// Connects and begins rendering. Resolves once the socket is open and
  /// the INIT handshake has been sent.
  Future<void> start() async {
    _metrics = DomCellMetrics(container: _host);
    final socket = web.WebSocket(_url);
    socket.binaryType = 'arraybuffer';
    _socket = socket;

    final opened = Completer<void>();
    socket.onopen = ((web.Event _) {
      _onOpen();
      if (!opened.isCompleted) opened.complete();
    }).toJS;
    socket.onmessage = ((web.MessageEvent event) {
      _onMessage(event);
    }).toJS;
    socket.onclose = ((web.CloseEvent _) {
      _teardown('Disconnected from the fleury session.');
    }).toJS;
    await opened.future;
  }

  void _onOpen() {
    // A degenerate first measurement falls back to a conventional 80×24 so the
    // session never opens collapsed; the ResizeObserver corrects it once the
    // container has a real layout.
    _size = _measureViewport() ?? const CellSize(80, 24);
    // The grid surface owns its own root — `resize` calls `replaceChildren`
    // on it — so the accessible semantic tree must live in a sibling element,
    // not inside the grid root. This mirrors the in-browser host's layout
    // (a surface div + a semantic div under one host).
    final surfaceRoot = web.document.createElement('div');
    _host.appendChild(surfaceRoot);
    _surface = DomGridSurface(root: surfaceRoot, size: _size);
    final semanticRoot = web.document.createElement('div');
    _host.appendChild(semanticRoot);
    _semantics = SemanticDomPresenter(root: semanticRoot)
      // Activating a node in the accessible DOM (screen reader / agent) sends
      // the action back to the host, which invokes it on the live tree —
      // completing the semantics round trip so a served session is operable
      // through the a11y tree, not just the visual grid.
      ..onSemanticActionRequest = (id, action) {
        _send(encodeFrame(SemanticActionFrame(id, action)));
      };
    _mirror = CellBuffer(_size);
    _input = DomInputSource(
      hostElement: _host,
      pointerTarget: surfaceRoot,
      cellMetrics: _metrics!,
    )..start(_sendInput);
    _sendInit();
    _observeResize();
  }

  CellSize? _measureViewport() {
    // DomCellMetrics.measure() owns the browser layout read and derives
    // the cols/rows that fit the container — the host read phase. The
    // client never reads layout directly (boundary contract).
    return viewportSizeForMeasurement(_metrics!.measure());
  }

  void _sendInit() {
    if (_handshakeSent) return;
    _handshakeSent = true;
    _send(
      encodeFrame(
        InitFrame(
          size: _size,
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: remoteProtocolVersion,
        ),
      ),
    );
  }

  void _sendInput(TuiEvent event) {
    try {
      _send(encodeFrame(InputEventFrame(event)));
    } on Object {
      // An event the serve protocol doesn't carry: drop it rather than
      // tearing down the session.
    }
  }

  void _observeResize() {
    final observer = web.ResizeObserver(
      ((JSArray<JSAny?> _, web.ResizeObserver __) {
        // A ResizeObserver callback can fire mid-reflow with the container
        // momentarily collapsed; [_measureViewport] returns null for such a
        // degenerate read. Adopting it would resize the grid to a one-row
        // sliver and blank the screen (with no guarantee a corrective callback
        // follows), so we ignore it and keep the last good size.
        final next = _measureViewport();
        if (next == null || next == _size) return;
        _size = next;
        _surface?.resize(next);
        _mirror = CellBuffer(next);
        _send(encodeFrame(ResizeFrame(next)));
      }).toJS,
    );
    observer.observe(_host);
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data;
    if (data == null) return;
    final buffer = (data as JSArrayBuffer).toDart;
    _decoder.feed(buffer.asUint8List());
    // This runs at the JS onmessage boundary, where an uncaught throw silently
    // stops processing — a single malformed frame or render edge case would
    // wedge the session blank with no recovery. So decode and apply each frame
    // defensively: log the failure and repair the screen from the mirror.
    final List<RemoteFrame> frames;
    try {
      frames = _decoder.drain().toList();
    } catch (error) {
      web.console.error('fleury: remote frame decode failed: $error'.toJS);
      _resyncFromMirror();
      return;
    }
    for (final frame in frames) {
      try {
        _handleFrame(frame);
      } catch (error) {
        web.console.error('fleury: remote frame apply failed: $error'.toJS);
        _resyncFromMirror();
      }
    }
  }

  /// Repaints the whole grid from the mirror after a frame failed to apply.
  /// The mirror is the authoritative cell state (the transport-parity tests
  /// guarantee it tracks the server), so a full local repaint restores any DOM
  /// a half-applied frame left broken — without needing the server to resend.
  void _resyncFromMirror() {
    final surface = _surface;
    if (surface == null) return;
    try {
      surface.present(_mirror, _mirror, _fullRepaintPlan(_mirror));
    } catch (error) {
      // A repaint that itself fails can't be recovered locally; log and leave
      // the last good DOM rather than loop.
      web.console.error('fleury: resync repaint failed: $error'.toJS);
    }
  }

  FramePresentationPlan _fullRepaintPlan(CellBuffer mirror) {
    const builder = CellSpanBuilder();
    return FramePresentationPlan(
      reason: 'resync',
      fullRepaint: true,
      size: mirror.size,
      damage: FramePresentationDamage(
        fullRepaint: true,
        requiresFullDiff: true,
        dirtyBounds: null,
        dirtyRows: TuiDirtyRows.full(mirror.size.rows),
        source: FrameDamageSource.fullRepaint,
      ),
      dirtyRowModels: [
        for (var r = 0; r < mirror.size.rows; r++) builder.buildRow(mirror, r),
      ],
      metricsChanged: false,
      dirtyRowDiffTime: Duration.zero,
      spanBuildTime: Duration.zero,
    );
  }

  void _handleFrame(RemoteFrame frame) {
    switch (frame) {
      case PlanFrame f:
        final surface = _surface;
        if (surface == null) return;
        if (f.plan.size != _mirror.size) {
          // The server is rendering at a new size; reset the mirror so the
          // (full-repaint) frame lands on a correctly-sized buffer.
          _mirror = CellBuffer(f.plan.size);
          _size = f.plan.size;
          surface.resize(f.plan.size);
        }
        final plan = applyRemotePlan(f.plan, _mirror);
        surface.present(_mirror, _mirror, plan);
      case SemanticsFrame f:
        _presentSemantics(f);
      case ByeFrame():
        _teardown('The fleury session ended.');
      case InitFrame _:
      case ResizeFrame _:
      case InputFrame _:
      case OutputFrame _:
      case InputEventFrame _:
      case SemanticActionFrame _:
        // Not part of the server→client contract; ignore.
        break;
    }
  }

  /// Decodes a [SemanticsFrame] (full snapshot or diff patch) and drives the
  /// accessible DOM tree. A malformed or out-of-order frame is swallowed: the
  /// decoder returns null and the last good semantic tree stays on screen —
  /// semantics are an accessibility backstop, never a reason to tear down a
  /// rendering session.
  void _presentSemantics(SemanticsFrame frame) {
    final semantics = _semantics;
    if (semantics == null) return;
    final tree = _semanticsDecoder.apply(frame.json);
    if (tree == null) return;
    semantics.present(tree);
  }

  void _send(Uint8List bytes) {
    _socket?.send(bytes.toJS);
  }

  /// The session has ended — a dropped socket or a BYE from the host. Stop
  /// interacting, but keep the last rendered frame on screen and overlay a
  /// clear message instead of emptying the DOM. A silent blank (the old
  /// behaviour) is impossible to tell apart from a render bug; this makes the
  /// end-of-session state obvious and recoverable.
  void _teardown(String message) {
    if (_closed) return;
    _closed = true;
    _input?.dispose();
    _input = null;
    _socket = null;
    _showDisconnected(message);
  }

  void _showDisconnected(String message) {
    if (_disconnectBanner != null) return;
    final banner = web.document.createElement('div') as web.HTMLElement;
    banner.textContent = '⚠ $message  Click or reload to reconnect.';
    final style = banner.style;
    style.setProperty('position', 'fixed');
    style.setProperty('left', '0');
    style.setProperty('right', '0');
    style.setProperty('bottom', '0');
    style.setProperty('padding', '8px 12px');
    style.setProperty('background', 'rgba(120, 18, 18, 0.95)');
    style.setProperty('color', '#fff');
    style.setProperty('font', '13px ui-monospace, monospace');
    style.setProperty('text-align', 'center');
    style.setProperty('cursor', 'pointer');
    style.setProperty('z-index', '2147483647');
    banner.addEventListener(
      'click',
      ((web.Event _) => web.window.location.reload()).toJS,
    );
    _host.appendChild(banner);
    _disconnectBanner = banner;
  }
}

/// The viewport size to adopt from a cell measurement, or null when the
/// measurement is degenerate — fewer than two rows or columns. A degenerate
/// read means the container has no usable layout yet: a ResizeObserver firing
/// mid-reflow, the monospace probe measured before the font loaded, or a
/// momentarily-collapsed host. Adopting it would resize the served grid down to
/// a one-row sliver and blank the screen, with no guarantee a corrective
/// measurement follows — so callers ignore it and keep the last good size.
CellSize? viewportSizeForMeasurement(MeasuredCellBox box) {
  if (box.cols < 2 || box.rows < 2) return null;
  return CellSize(box.cols.clamp(1, 1000), box.rows.clamp(1, 1000));
}
