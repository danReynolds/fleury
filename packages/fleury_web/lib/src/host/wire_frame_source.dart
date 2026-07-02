// WireFrameSource: frames come from a `fleury serve` WebSocket instead of
// a local runtime — the serve client, presenting through the SAME
// BrowserPresentationHost assembly as the embed path. That shared
// assembly is what closes the serve parity gaps structurally: this
// client gets the focus coordinator, the clipboard (paste fallback AND
// app-initiated copy via the wire), and IME caret sync because the host
// built them, not because this file remembered to.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import '../focus/web_focus_coordinator.dart';
import '../metrics/cell_metrics.dart';
import '../dom_grid/inline_image_overlay.dart';
import '../remote_client/plan_adapter.dart';
import '../run_tui_surface.dart';
import 'browser_presentation_host.dart';

/// Connects to a `fleury serve` WebSocket and presents the session
/// through the host's components.
final class WireFrameSource implements BrowserFrameSource {
  WireFrameSource({required String url}) : _url = url;

  final String _url;

  web.WebSocket? _socket;
  BrowserHostComponents? _components;
  final FrameDecoder _decoder = FrameDecoder();
  final SemanticsWireDecoder _semanticsDecoder = SemanticsWireDecoder();
  CellSize _size = const CellSize(80, 24);
  CellBuffer _mirror = CellBuffer(const CellSize(80, 24));
  bool _handshakeSent = false;
  bool _closed = false;
  web.HTMLElement? _disconnectBanner;

  /// The host-assembled inline-image layer (shared with the embed path).
  InlineImageOverlay? get _imageOverlay => _components?.imageOverlay;

  @override
  Future<MountedApp> start(BrowserHostComponents components) async {
    _components = components;
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

    return MountedApp.forFrameSource(
      surface: components.surface,
      cellMetrics: components.metrics,
      inputSource: components.inputSource,
      semanticPresenter: components.semanticPresenter,
      semanticFlushScheduler: components.semanticFlushScheduler,
      disposeHostResources: () {
        _teardown('The fleury session was disposed.', banner: false);
        components.removeGeneratedRoots();
      },
    );
  }

  void _onOpen() {
    final components = _components!;
    // A degenerate first measurement falls back to a conventional 80×24 so
    // the session never opens collapsed; the ResizeObserver corrects it
    // once the container has a real layout.
    _size = _measureViewport() ?? const CellSize(80, 24);
    // Thread the measured cell box into the surface so rows lay out at
    // device-pixel-snapped cell heights (fractional line-heights show as
    // scan lines across full-cell image content).
    components.surface.resize(_size, metrics: _cellBox());
    // Activating a node in the accessible DOM (screen reader / agent)
    // sends the action back to the host, which invokes it on the live
    // tree — the semantics round trip that keeps a served session operable
    // through the a11y tree, not just the visual grid.
    components.semanticPresenter?.onSemanticActionRequest = (id, action) {
      _send(encodeFrame(SemanticActionFrame(id, action)));
    };
    _mirror = CellBuffer(_size);
    components.inputSource.start(_sendInput);
    _sendInit();
    _observeResize();
  }

  /// Reconciles the inline-image overlay against this frame's
  /// [placements] (no-op until metrics exist).
  void _applyPlacements(List<ImagePlacement> placements) {
    final box = _components?.metrics.measure();
    if (box != null) _imageOverlay?.apply(placements, box);
  }

  CellSize? _measureViewport() {
    // DomCellMetrics.measure() owns the browser layout read and derives
    // the cols/rows that fit the container — the host read phase. The
    // client never reads layout directly (boundary contract).
    return viewportSizeForMeasurement(_components!.metrics.measure());
  }

  /// The measured per-cell pixel box (device-pixel snapped). Null only
  /// before metrics exist.
  MeasuredCellBox? _cellBox() => _components?.metrics.measure();

  void _sendInit() {
    if (_handshakeSent) return;
    _handshakeSent = true;
    _send(
      encodeFrame(
        InitFrame(
          // The browser renders real images via an <img> overlay (the
          // serve path lifts inline-image payloads out of the cell grid):
          // the neutral capability is `images=placements`. The legacy
          // terminal-projection field stays halfBlock — a browser has no
          // escape protocol.
          size: _size,
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          images: InlineImageSupport.placements,
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
        // momentarily collapsed; [_measureViewport] returns null for such
        // a degenerate read. Adopting it would resize the grid to a
        // one-row sliver and blank the screen, so we ignore it and keep
        // the last good size.
        final next = _measureViewport();
        if (next == null || next == _size) return;
        _size = next;
        _components?.surface.resize(next, metrics: _cellBox());
        _mirror = CellBuffer(next);
        // Reposition the overlay images to the new cell pitch now, so they
        // stay pinned to their cells even if the host doesn't send a fresh
        // plan; the next PlanFrame (the usual case) supersedes this.
        final box = _cellBox();
        if (box != null) _imageOverlay?.reapply(box);
        _send(encodeFrame(ResizeFrame(next)));
      }).toJS,
    );
    observer.observe(_components!.hostElement);
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data;
    if (data == null) return;
    final buffer = (data as JSArrayBuffer).toDart;
    _decoder.feed(buffer.asUint8List());
    // This runs at the JS onmessage boundary, where an uncaught throw
    // silently stops processing — a single malformed frame would wedge the
    // session blank with no recovery. Decode and apply each frame
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

  /// Repaints the whole grid from the mirror after a frame failed to
  /// apply. The mirror is the authoritative cell state (the
  /// transport-parity tests guarantee it tracks the server), so a full
  /// local repaint restores any DOM a half-applied frame left broken —
  /// without needing the server to resend.
  void _resyncFromMirror() {
    final surface = _components?.surface;
    if (surface == null) return;
    try {
      surface.present(_mirror, _mirror, _fullRepaintPlan(_mirror));
    } catch (error) {
      // A repaint that itself fails can't be recovered locally; log and
      // leave the last good DOM rather than loop.
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
    final components = _components!;
    switch (frame) {
      case PlanFrame f:
        if (f.plan.size != _mirror.size) {
          // The server is rendering at a new size; reset the mirror so the
          // (full-repaint) frame lands on a correctly-sized buffer.
          _mirror = CellBuffer(f.plan.size);
          _size = f.plan.size;
          components.surface.resize(f.plan.size, metrics: _cellBox());
        }
        final plan = applyRemotePlan(f.plan, _mirror);
        components.surface.present(_mirror, _mirror, plan);
        _applyPlacements(f.plan.placements);
      case InlineImageFrame f:
        _imageOverlay?.cacheImage(f.id, f.bytes);
      case SemanticsFrame f:
        _presentSemantics(f);
      case CaretFrame f:
        // The app's focused editable moved: position the hidden IME
        // capture element at the caret so composition candidate windows
        // appear where the user is typing — parity with the embed host's
        // per-frame syncCaretGeometry.
        components.inputSource.syncCaretGeometry(f.caret, _cellBox());
      case ClipboardWriteFrame f:
        // The app copied: place the text on THIS machine's clipboard and
        // answer with how it went.
        unawaited(() async {
          RemoteClipboardStatus status;
          try {
            final report = await components.clipboard.writeWithReport(f.text);
            status = report.result == ClipboardWriteResult.inProcessOnly
                ? RemoteClipboardStatus.denied
                : RemoteClipboardStatus.written;
          } catch (_) {
            status = RemoteClipboardStatus.unavailable;
          }
          _send(encodeFrame(ClipboardResultFrame(f.seq, status)));
        }());
      case ByeFrame():
        _teardown('The fleury session ended.');
      case InitFrame f:
        // v3 apps echo INIT with their protocol version after receiving
        // ours, so a stale cached client bundle is detectable instead of
        // silently mis-decoding. Same major version: silence.
        if (f.protocolVersion != remoteProtocolVersion) {
          web.console.warn(
            'fleury: protocol version skew — client v$remoteProtocolVersion, '
                    'app v${f.protocolVersion}. Reload with a fresh bundle '
                    '(the serve asset is no-store; check any caching proxy).'
                .toJS,
          );
        }
      case SemanticActionResultFrame f:
        // Outcome of a semantic action this client (AT mirror) fired.
        // Restore keyboard capture the way the embed host does after an
        // activation, and surface app-side failures instead of letting
        // them vanish.
        if (components.focusCoordinator
            .shouldRestoreKeyboardCaptureAfterSemanticActivation()) {
          try {
            components.inputSource.ensureKeyboardCapture();
            components.focusCoordinator.handleBrowserFocusIn(
              WebFocusTarget.keyboardCapture,
            );
          } catch (_) {
            // Browser focus restoration is best-effort.
          }
        }
        if (f.status == SemanticActionInvocationStatus.failed) {
          web.console.error(
            'fleury: semantic action ${f.action.name} on ${f.id.value} '
                    'failed in the app (see server logs).'
                .toJS,
          );
        }
      case ResizeFrame _:
      case InputFrame _:
      case OutputFrame _:
      case InputEventFrame _:
      case SemanticActionFrame _:
      case ClipboardResultFrame _:
        // Not part of the server→client contract; ignore.
        break;
    }
  }

  /// Decodes a [SemanticsFrame] (full snapshot or diff patch) and drives
  /// the accessible DOM tree. A malformed or out-of-order frame is
  /// swallowed: the decoder returns null and the last good semantic tree
  /// stays on screen — semantics are an accessibility backstop, never a
  /// reason to tear down a rendering session.
  void _presentSemantics(SemanticsFrame frame) {
    final semantics = _components?.semanticPresenter;
    if (semantics == null) return;
    final tree = _semanticsDecoder.apply(frame.json);
    if (tree == null) return;
    semantics.present(tree);
  }

  void _send(Uint8List bytes) {
    final socket = _socket;
    if (socket == null) {
      sentForTest.add(bytes);
      return;
    }
    socket.send(bytes.toJS);
  }

  /// Frames [_send] captured while no socket exists — test-only.
  final List<Uint8List> sentForTest = [];

  /// Drives the frame handler directly — test-only (production frames
  /// arrive through the socket's onmessage).
  void handleFrameForTest(RemoteFrame frame) => _handleFrame(frame);

  /// Attaches [components] without a socket — test-only.
  void attachComponentsForTest(BrowserHostComponents components) {
    _components = components;
  }

  /// The session has ended — a dropped socket or a BYE from the host.
  /// Stop interacting, keep the last rendered frame on screen, and overlay
  /// a clear message instead of emptying the DOM.
  void _teardown(String message, {bool banner = true}) {
    if (_closed) return;
    _closed = true;
    _components?.inputSource.dispose();
    try {
      _socket?.close();
    } catch (_) {
      // Already closing.
    }
    _socket = null;
    // Drop the pixel layer so ghost images don't sit over the banner; the
    // overlay tolerates the host's later dispose call.
    _imageOverlay?.dispose();
    if (banner) _showDisconnected(message);
  }

  void _showDisconnected(String message) {
    if (_disconnectBanner != null) return;
    final host = _components?.hostElement;
    if (host == null) return;
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
    host.appendChild(banner);
    _disconnectBanner = banner;
  }
}

/// The viewport size to adopt from a cell measurement, or null when the
/// measurement is degenerate — fewer than two rows or columns. A
/// degenerate read means the container has no usable layout yet: a
/// ResizeObserver firing mid-reflow, the monospace probe measured before
/// the font loaded, or a momentarily-collapsed host. Adopting it would
/// resize the served grid down to a one-row sliver and blank the screen —
/// so callers ignore it and keep the last good size.
CellSize? viewportSizeForMeasurement(MeasuredCellBox box) {
  if (box.cols < 2 || box.rows < 2) return null;
  return CellSize(box.cols.clamp(1, 1000), box.rows.clamp(1, 1000));
}
