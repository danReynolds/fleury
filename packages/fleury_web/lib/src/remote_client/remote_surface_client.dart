import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_codec.dart' show ImagePlacement;
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

  // Inline-image overlay: a sibling div above the grid holding one <img> per
  // placement. Bytes are cached by content-hash id as blob URLs (_imageBlobUrls,
  // keyed by id — so the same image at several spots shares one decode); the
  // <img> elements and their last-applied geometry are keyed by 'id#occurrence'
  // so repeated placements of one image each get a distinct element.
  web.HTMLElement? _imageOverlay;
  final Map<String, String> _imageBlobUrls = <String, String>{};
  final Map<String, web.HTMLImageElement> _imageEls =
      <String, web.HTMLImageElement>{};
  final Map<String, String> _imageRects = <String, String>{};
  // The most recent frame's placements, re-applied on resize so images track
  // the new cell pitch even if no PlanFrame happens to follow (a paused or
  // static served screen); the next PlanFrame supersedes them.
  List<ImagePlacement> _lastPlacements = const <ImagePlacement>[];

  // Cap on cached blob URLs. The host re-ships an image whenever it (re)appears
  // on screen (it tracks only the previous frame's placed ids), so the client
  // may freely evict ids that are NOT currently placed once the cache grows
  // past this bound — the on-screen working set is never dropped, and an image
  // that scrolls back is re-sent. A normal session stays well under the cap.
  static const int _maxCachedImages = 512;

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
    // Thread the measured cell box into the surface (the in-browser host does
    // this; the serve client used to skip it). Without it the grid lays rows
    // out at the font's natural fractional line-height — never device-pixel
    // snapped — so every row boundary keeps a sub-pixel gap that shows as scan
    // lines across full-cell image content. It also unlocks the block-element
    // fill path, which fills each image cell to its box.
    _surface = DomGridSurface(root: surfaceRoot, size: _size)
      ..resize(_size, metrics: _cellBox());
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
    // Inline-image overlay: a sibling of the grid root (the grid `replaceChildren`s
    // its own root, so overlays must live outside it), absolutely positioned over
    // the grid. pointer-events:none lets clicks fall through to the cell grid.
    (_host as web.HTMLElement).style.setProperty('position', 'relative');
    final overlay = web.document.createElement('div') as web.HTMLElement;
    overlay.style
      ..setProperty('position', 'absolute')
      ..setProperty('left', '0')
      ..setProperty('top', '0')
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      // Clip any image that would extend past the grid (e.g. a placement near
      // the edge) to the host bounds instead of bleeding over the page.
      ..setProperty('overflow', 'hidden')
      ..setProperty('pointer-events', 'none');
    _host.appendChild(overlay);
    _imageOverlay = overlay;
    _input = DomInputSource(
      hostElement: _host,
      pointerTarget: surfaceRoot,
      cellMetrics: _metrics!,
    )..start(_sendInput);
    _sendInit();
    _observeResize();
  }

  /// Caches one inline image's bytes as a blob URL, keyed by content-hash id.
  /// Idempotent — the server ships each id once, but a re-send (after the
  /// server's dedup set is bounded) just keeps the existing URL.
  void _cacheImage(String id, Uint8List bytes) {
    if (_imageBlobUrls.containsKey(id)) return;
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    _imageBlobUrls[id] = web.URL.createObjectURL(blob);
  }

  /// Reconciles the `<img>` overlay against this frame's [placements] (the full
  /// current set). Elements are keyed by id + occurrence, so the same image
  /// drawn at two positions gets two `<img>`s (and a single moving image keeps
  /// one element, repositioned). New ones are created, placed ones positioned at
  /// their cell rect, and elements no longer placed are dropped.
  void _applyPlacements(List<ImagePlacement> placements) {
    _lastPlacements = placements;
    final overlay = _imageOverlay;
    final box = _metrics?.measure();
    if (overlay == null || box == null) return;
    final cw = box.cssCellWidth;
    final ch = box.cssCellHeight;
    // Match the grid's own origin convention (see DomInputSource caret math):
    // the canvas may be inset within the host, so add its offset.
    final ox = box.cssCanvasLeft;
    final oy = box.cssCanvasTop;
    final seen = <String>{};
    final placedIds = <String>{};
    final occurrence = <String, int>{};
    for (final p in placements) {
      placedIds.add(p.id);
      // Distinguish repeated placements of the same bytes within one frame.
      final occ = occurrence[p.id] = (occurrence[p.id] ?? 0) + 1;
      final key = '${p.id}#$occ';
      seen.add(key);
      final url = _imageBlobUrls[p.id];
      if (url == null) continue; // bytes not arrived yet; a later frame retries
      var el = _imageEls[key];
      if (el == null) {
        el = web.document.createElement('img') as web.HTMLImageElement;
        el.style.setProperty('position', 'absolute');
        // Decorative: the overlay is the visual layer only — assistive tech
        // reads the separate semantics DOM, so an empty alt keeps the image
        // from being announced twice (or as a meaningless blob id).
        el.alt = '';
        // A corrupt / undecodable payload would otherwise show the browser's
        // broken-image glyph; hide it instead so a bad frame degrades to blank.
        el.onerror = (web.Event _) {
          _imageEls[key]?.style.setProperty('visibility', 'hidden');
        }.toJS;
        el.src = url;
        overlay.appendChild(el);
        _imageEls[key] = el;
      } else if (el.src != url) {
        // The bytes for this id were re-shipped under a new blob URL (e.g. the
        // image returned after the host re-sent it); point at the fresh URL and
        // clear any error-hidden state so it can render again.
        el.src = url;
        el.style.removeProperty('visibility');
        _imageRects.remove(key);
      }
      // Re-style only when the geometry actually changed: a static image holds
      // its rect across frames, so this skips needless layout on every frame.
      final left = ox + p.col * cw;
      final top = oy + p.row * ch;
      final rect = '$left|$top|${p.cols * cw}|${p.rows * ch}|${p.fit.name}';
      if (_imageRects[key] != rect) {
        _imageRects[key] = rect;
        el.style
          ..setProperty('left', '${left}px')
          ..setProperty('top', '${top}px')
          ..setProperty('width', '${p.cols * cw}px')
          ..setProperty('height', '${p.rows * ch}px')
          // InlineImageFit names ARE the CSS object-fit keywords (contain/cover/
          // fill/none), so the source `fit` maps straight through. Without this
          // the default `fill` would stretch a wrong-aspect cell box.
          ..setProperty('object-fit', p.fit.name);
      }
    }
    for (final key in _imageEls.keys.toList()) {
      if (!seen.contains(key)) {
        _imageEls.remove(key)?.remove();
        _imageRects.remove(key);
      }
    }
    _evictStaleImages(placedIds);
  }

  /// Bounds the blob-URL cache. Bytes for an image off-screen are kept (so it
  /// reappears instantly on scroll-back without a re-ship) until the cache
  /// exceeds [_maxCachedImages]; only ids not in [placed] are then revoked, so
  /// the on-screen working set is never dropped. A normal session stays well
  /// under the cap and never evicts.
  void _evictStaleImages(Set<String> placed) {
    if (_imageBlobUrls.length <= _maxCachedImages) return;
    for (final id in _imageBlobUrls.keys.toList()) {
      if (_imageBlobUrls.length <= _maxCachedImages) break;
      if (placed.contains(id)) continue;
      final url = _imageBlobUrls.remove(id);
      if (url != null) web.URL.revokeObjectURL(url);
    }
  }

  CellSize? _measureViewport() {
    // DomCellMetrics.measure() owns the browser layout read and derives
    // the cols/rows that fit the container — the host read phase. The
    // client never reads layout directly (boundary contract).
    return viewportSizeForMeasurement(_metrics!.measure());
  }

  /// The measured per-cell pixel box (device-pixel snapped), handed to the
  /// surface so rows lay out at exact cell heights and block-element image
  /// cells fill their box. Null only before metrics exist.
  MeasuredCellBox? _cellBox() => _metrics?.measure();

  void _sendInit() {
    if (_handshakeSent) return;
    _handshakeSent = true;
    _send(
      encodeFrame(
        InitFrame(
          // The browser renders real images via an <img> overlay (the serve
          // path lifts inline-image payloads out of the cell grid), so it
          // advertises the `browser` image protocol rather than the half-block
          // glyph fallback.
          size: _size,
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.browser,
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
        _surface?.resize(next, metrics: _cellBox());
        _mirror = CellBuffer(next);
        // Reposition the overlay images to the new cell pitch now, so they stay
        // pinned to their cells even if the host doesn't send a fresh plan; the
        // next PlanFrame (the usual case) supersedes this with the real layout.
        _applyPlacements(_lastPlacements);
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
          surface.resize(f.plan.size, metrics: _cellBox());
        }
        final plan = applyRemotePlan(f.plan, _mirror);
        surface.present(_mirror, _mirror, plan);
        _applyPlacements(f.plan.placements);
      case InlineImageFrame f:
        _cacheImage(f.id, f.bytes);
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
    for (final url in _imageBlobUrls.values) {
      web.URL.revokeObjectURL(url);
    }
    _imageBlobUrls.clear();
    _imageEls.clear();
    _imageRects.clear();
    _imageOverlay?.remove();
    _imageOverlay = null;
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
