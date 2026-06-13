import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:web/web.dart' as web;

import '../dom_grid/dom_grid_surface.dart';
import '../input/dom_input_source.dart';
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
  RemoteSurfaceClient({
    required web.Element hostElement,
    required String url,
  }) : _host = hostElement,
       _url = url;

  final web.Element _host;
  final String _url;

  web.WebSocket? _socket;
  DomGridSurface? _surface;
  SemanticDomPresenter? _semantics;
  web.Element? _surfaceRoot;
  web.Element? _semanticRoot;
  DomCellMetrics? _metrics;
  DomInputSource? _input;
  final FrameDecoder _decoder = FrameDecoder();
  CellSize _size = const CellSize(80, 24);
  bool _handshakeSent = false;
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
      _dispose();
    }).toJS;
    await opened.future;
  }

  void _onOpen() {
    _size = _measureViewport();
    // The grid surface owns its own root — `resize` calls `replaceChildren`
    // on it — so the accessible semantic tree must live in a sibling element,
    // not inside the grid root. This mirrors the in-browser host's layout
    // (a surface div + a semantic div under one host).
    final surfaceRoot = web.document.createElement('div');
    _host.appendChild(surfaceRoot);
    _surfaceRoot = surfaceRoot;
    _surface = DomGridSurface(root: surfaceRoot, size: _size);
    final semanticRoot = web.document.createElement('div');
    _host.appendChild(semanticRoot);
    _semanticRoot = semanticRoot;
    _semantics = SemanticDomPresenter(root: semanticRoot);
    _mirror = CellBuffer(_size);
    _input = DomInputSource(
      hostElement: _host,
      pointerTarget: surfaceRoot,
      cellMetrics: _metrics!,
    )..start(_sendInput);
    _sendInit();
    _observeResize();
  }

  CellSize _measureViewport() {
    // DomCellMetrics.measure() owns the browser layout read and derives
    // the cols/rows that fit the container — the host read phase. The
    // client never reads layout directly (boundary contract).
    final box = _metrics!.measure();
    return CellSize(box.cols.clamp(1, 1000), box.rows.clamp(1, 1000));
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
        final next = _measureViewport();
        if (next == _size) return;
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
    for (final frame in _decoder.drain()) {
      _handleFrame(frame);
    }
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
        _dispose();
      case InitFrame _:
      case ResizeFrame _:
      case InputFrame _:
      case OutputFrame _:
      case InputEventFrame _:
        // Not part of the server→client contract; ignore.
        break;
    }
  }

  /// Decodes a [SemanticsFrame] and drives the accessible DOM tree. A
  /// malformed snapshot is swallowed: semantics are an accessibility
  /// backstop, never a reason to tear down a rendering session.
  void _presentSemantics(SemanticsFrame frame) {
    final semantics = _semantics;
    if (semantics == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(frame.json));
      if (decoded is! Map<String, Object?>) return;
      final snapshot = SemanticInspectionSnapshot.fromJson(decoded);
      semantics.present(snapshot.toSemanticTree());
    } on Object {
      // Drop a malformed/oversized semantics frame; the visual surface and
      // the last good semantic tree both remain intact.
    }
  }

  void _send(Uint8List bytes) {
    _socket?.send(bytes.toJS);
  }

  void _dispose() {
    _input?.dispose();
    _input = null;
    unawaited(_surface?.dispose());
    _surface = null;
    unawaited(_semantics?.dispose());
    _semantics = null;
    _surfaceRoot?.remove();
    _surfaceRoot = null;
    _semanticRoot?.remove();
    _semanticRoot = null;
    _socket = null;
  }
}
