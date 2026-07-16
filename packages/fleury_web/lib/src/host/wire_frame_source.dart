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
  // Diffs consecutive decoded trees so the accessibility DOM can be patched
  // incrementally (SemanticDomPresenter's O(changed) path) instead of being
  // torn down and rebuilt from scratch every semantically-dirty frame.
  final SemanticsOwner _semanticsOwner = SemanticsOwner();
  CellSize _size = const CellSize(80, 24);
  CellBuffer _mirror = CellBuffer(const CellSize(80, 24));
  bool _handshakeSent = false;
  bool _closed = false;
  CellRect? _lastCaret;
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
    var handshakeOpened = false;
    socket.onopen = ((web.Event _) {
      if (opened.isCompleted || _closed) return;
      handshakeOpened = true;
      _completeOpen(opened);
    }).toJS;
    socket.onmessage = ((web.MessageEvent event) {
      _onMessage(event);
    }).toJS;
    socket.onclose = ((web.CloseEvent _) {
      // A close BEFORE the socket ever opened is a failed connection
      // (serve down, wrong URL, rejected upgrade). Fail start() so the
      // caller's Future resolves and attach()'s cleanup runs — don't show
      // the mid-session disconnect banner or hang on `opened`.
      if (!handshakeOpened) {
        _failOpen(
          opened,
          StateError('fleury serve connection closed before it opened: $_url'),
          StackTrace.current,
        );
        return;
      }
      _teardown('Disconnected from the fleury session.');
    }).toJS;
    socket.onerror = ((web.Event _) {
      // Errors before open (connection refused, TLS failure) fire error
      // then close; surface the failure through start() rather than
      // stranding it.
      if (!handshakeOpened) {
        _failOpen(
          opened,
          StateError('fleury serve connection failed: $_url'),
          StackTrace.current,
        );
      }
    }).toJS;
    await opened.future;

    return _mountedAppFor(components);
  }

  void _completeOpen(Completer<void> opened) {
    try {
      _onOpen();
    } catch (error, stackTrace) {
      // The event callback sits outside start()'s async stack. Convert any
      // setup failure back into the Future that BrowserPresentationHost.attach
      // is awaiting, and close the partially-started source before the host's
      // own idempotent cleanup runs. Without this catch, the callback throws to
      // JavaScript and `opened.future` remains pending forever.
      _failOpen(opened, error, stackTrace);
      return;
    }
    if (!opened.isCompleted) opened.complete();
  }

  void _failOpen(Completer<void> opened, Object error, StackTrace stackTrace) {
    if (opened.isCompleted) return;
    try {
      _teardown('The fleury session failed to start.', banner: false);
    } catch (_) {
      // Teardown is best-effort here, but the socket must not outlive a
      // failed start and a cleanup error must not strand the Future again.
      _closed = true;
      final socket = _socket;
      _socket = null;
      try {
        socket?.close();
      } catch (_) {}
    }
    // No MountedApp can ever use this component set. BrowserPresentationHost
    // still owns its local reference and completes the idempotent cleanup when
    // this error reaches attach().
    _components = null;
    if (!opened.isCompleted) opened.completeError(error, stackTrace);
  }

  MountedApp _mountedAppFor(BrowserHostComponents components) {
    return MountedApp.forFrameSource(
      surface: components.surface,
      cellMetrics: components.metrics,
      inputSource: components.inputSource,
      semanticPresenter: components.semanticPresenter,
      semanticFlushScheduler: components.semanticFlushScheduler,
      disposeHostResources: () {
        _teardown('The fleury session was disposed.', banner: false);
        _removeDisconnectBanner();
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
    _openSetupHookForTest?.call();
    _sendInit();
    _observeMetrics();
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
          // The DOM grid renders real <a> anchors (dom_row_factory), so tell
          // the server-side app its surface supports links: this is what makes
          // its MarkdownText gate produce a linkUri that the v4 wire then
          // carries. Without it links render underlined-but-not-clickable.
          hyperlinks: true,
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

  void _observeMetrics() {
    // One observer owner for every geometry invalidation. DomCellMetrics
    // combines host ResizeObserver callbacks with font-readiness and window
    // resize/DPR signals, marks its cache dirty, then drives this refresh path.
    // Installing a second host observer here would duplicate resize work while
    // still missing the non-host signals.
    _components!.metrics.startObserving(_handleObservedResize);
  }

  void _handleObservedResize() {
    if (_closed) return;
    final components = _components;
    if (components == null) return;

    // CellMetrics observers mark dirty before invoking us. Keep this idempotent
    // invalidation in the shared path so the direct test seam and any future
    // host-driven refresh cannot accidentally reuse a cached box.
    components.metrics.markDirty();

    // A ResizeObserver callback can fire mid-reflow with the container
    // momentarily collapsed; [_measureViewport] returns null for such a
    // degenerate read. Adopting it would resize the grid to a one-row sliver and
    // blank the screen, so ignore it and keep the last good size.
    final next = _measureViewport();
    if (next == null) return;
    final box = _cellBox();

    // Refresh row pitch, image placement, and the hidden IME capture rectangle
    // even when the grid's integer rows/cols did not change. Font/padding/DPR
    // changes can move the caret in CSS pixels while leaving its cell rect (and
    // therefore the server's deduped CaretFrame) unchanged.
    components.surface.resize(next, metrics: box);
    components.inputSource.syncCaretGeometry(_lastCaret, box);
    if (box != null) _imageOverlay?.reapply(box);

    if (next == _size) return;
    _size = next;
    // Do NOT reset _mirror here: an in-flight plan built against the old size
    // (sent before the server saw our ResizeFrame) must keep applying to the old
    // mirror. The next size-matched full-repaint plan resets it in _handleFrame.
    _send(encodeFrame(ResizeFrame(next)));
  }

  /// Consecutive frame-apply failures tolerated before a persistently failing
  /// stream is treated as hung and torn down (with the reload banner) rather
  /// than resynced yet again. Reset on any successful apply.
  ///
  /// This apply-path counter is the ONLY escalation backstop needed. The
  /// decode path is self-bounding: [FrameDecoder.drain] advances the buffer
  /// past each frame BEFORE decoding its payload, so a recoverable decode
  /// error can never recur on the same bytes (see remote_protocol.dart) — it
  /// therefore does NOT feed this counter. A run of APPLY failures, by
  /// contrast, is a real mirror divergence (later patches are relative to the
  /// diverged mirror), which resync alone cannot recover — so only apply
  /// failures escalate.
  static const int _maxConsecutiveApplyFailures = 3;
  int _consecutiveApplyFailures = 0;

  void _onMessage(web.MessageEvent event) {
    // A message still queued at the socket when we tore down must not repaint
    // over the reload banner on a dead session.
    if (_closed) return;
    final data = event.data;
    if (data == null) return;
    final buffer = (data as JSArrayBuffer).toDart;
    _ingest(buffer.asUint8List());
  }

  /// Feeds raw transport bytes through the decoder and applies each frame,
  /// classifying a failure as recoverable (repair locally, keep the socket
  /// open) or unrecoverable (surface the reload banner and close).
  void _ingest(Uint8List bytes) {
    // Never touch a torn-down session (also covers feedBytesForTest): a late
    // or post-close feed would otherwise resync over the reload banner.
    if (_closed) return;
    _decoder.feed(bytes);
    // This runs at the JS onmessage boundary, where an uncaught throw
    // silently stops processing — a single malformed frame would wedge the
    // session blank with no recovery. Decode and apply each frame
    // defensively.
    //
    // drain() is a lazy generator that removes each frame from the decoder
    // buffer AS it yields, so it must be iterated directly — collecting to
    // a list first would, on a decode error partway through, discard the
    // good frames already pulled (and applied-from) the buffer, leaving the
    // mirror diverged from what the server thinks the peer holds.
    try {
      for (final frame in _decoder.drain()) {
        // A teardown mid-batch — a ByeFrame, or the escalation below — closes
        // the session; stop applying the rest of this drained batch so nothing
        // repaints over the banner.
        if (_closed) return;
        try {
          _handleFrame(frame);
          // A clean apply ends any run of failures — only a *persistent* apply
          // failure (nothing succeeding in between) escalates below.
          _consecutiveApplyFailures = 0;
        } catch (error) {
          web.console.error('fleury: remote frame apply failed: $error'.toJS);
          _consecutiveApplyFailures++;
          if (_consecutiveApplyFailures >= _maxConsecutiveApplyFailures) {
            // A frame that keeps failing to apply is effectively hung too:
            // stop resyncing and surface the same reload banner. _teardown
            // closes the socket, so bail out of the drain.
            _teardown(
              'The session desynchronized — reload to reconnect.',
              banner: true,
            );
            return;
          }
          // A single bad frame with intact stream framing is recoverable:
          // repair the screen from the mirror and keep going.
          _resyncFromMirror();
        }
      }
    } on RemoteProtocolException catch (error) {
      // A decode-level protocol error surfaced from drain(). If the decoder
      // lost stream framing (an oversized length prefix cleared the buffer),
      // the byte stream can never re-synchronize and the mirror will never
      // advance — the "frozen screen, no banner" hang. Surface it: close the
      // now-untrustworthy socket and show the reload banner the user can
      // click, instead of silently resyncing forever.
      if (!error.recoverable) {
        _teardown(
          'The session desynchronized — reload to reconnect.',
          banner: true,
        );
        return;
      }
      // A single malformed frame whose length header was valid: drain()
      // skipped exactly it and framing stayed intact, so this is recoverable.
      // The frames decoded before it were already applied above; repair the
      // screen from the (now-current) mirror.
      web.console.error('fleury: remote frame decode failed: $error'.toJS);
      _resyncFromMirror();
    } catch (error) {
      // A non-protocol decode fault (defensive; shouldn't normally reach here):
      // treat as recoverable and repair from the mirror.
      web.console.error('fleury: remote frame decode failed: $error'.toJS);
      _resyncFromMirror();
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
    // Image bytes precede their plan on the wire. Commit the staged generation
    // at that decoded boundary, before grid mutation/presentation can throw.
    // The sender can then keep treating the id as cached even if this visual
    // apply is recovered locally and the image returns in a later plan.
    if (frame case PlanFrame(:final plan)) {
      _imageOverlay?.commitPendingForPlan(plan.placements);
    }
    if (_shouldFailApplyForTest?.call(frame) ?? false) {
      throw StateError('injected apply failure (test)');
    }
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
        final overlay = _imageOverlay;
        if (overlay != null && !overlay.cacheImage(f.id, f.bytes)) {
          _teardown(
            'The session sent too much pending image data — reload to reconnect.',
            banner: true,
          );
          return;
        }
      case SemanticsFrame f:
        _presentSemantics(f);
      case CaretFrame f:
        // The app's focused editable moved: position the hidden IME
        // capture element at the caret so composition candidate windows
        // appear where the user is typing — parity with the embed host's
        // per-frame syncCaretGeometry.
        _lastCaret = f.caret;
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
        // A clean end-of-session: tear down through the existing path (banner
        // + socket close) and return immediately — the drained batch's
        // _closed guard then stops any trailing frame from repainting over it.
        _teardown('The fleury session ended.');
        return;
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
      // The agent-devtools debug channel (DT1) is a peer↔app concern; the
      // browser client neither queries nor answers it (that's DT4's job),
      // so both frames are outside its server→client contract.
      case DebugRequestFrame _:
      case DebugResponseFrame _:
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
    // The owner advances only on a successful decode, so a swallowed frame
    // leaves the diff anchored at the last good tree. A full (resync) frame
    // diffs to a large added/removed set, so the presenter falls back to a full
    // rebuild; a patch yields updated-only, taking the incremental path.
    semantics.present(tree, update: _semanticsOwner.update(tree));
  }

  void _send(Uint8List bytes) {
    // After teardown the socket is gone for good; drop sends rather than
    // letting a late resize/semantic-action append to the capture list
    // forever. (Tests drive frames through attachComponentsForTest with no
    // socket and without closing, so they still capture into sentForTest.)
    if (_closed) return;
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

  /// Feeds raw bytes through the same decode + apply + failure-classification
  /// pipeline production uses from onmessage — test-only.
  void feedBytesForTest(Uint8List bytes) => _ingest(bytes);

  /// When set, an apply is forced to throw for any frame the predicate accepts,
  /// exercising the resync / escalation path without crafting an unapplyable
  /// frame — test-only.
  bool Function(RemoteFrame frame)? _shouldFailApplyForTest;
  set failApplyForTest(bool Function(RemoteFrame frame)? predicate) =>
      _shouldFailApplyForTest = predicate;

  void Function()? _openSetupHookForTest;

  /// Injects a failure after browser input has partially started — test-only.
  set openSetupHookForTest(void Function()? hook) =>
      _openSetupHookForTest = hook;

  /// Whether the session has been torn down (socket closed) — test-only.
  bool get isClosedForTest => _closed;

  /// Whether the reconnect banner is currently showing — test-only.
  bool get bannerShownForTest => _disconnectBanner != null;

  /// The live socket while start is pending or the session is open — test-only.
  web.WebSocket? get socketForTest => _socket;

  /// Attaches [components] without a socket — test-only.
  MountedApp attachComponentsForTest(BrowserHostComponents components) {
    _components = components;
    return _mountedAppFor(components);
  }

  /// Drives the same cached-metrics invalidation and resize path as the browser
  /// observer — test-only.
  void handleObservedResizeForTest() => _handleObservedResize();

  /// Installs the same combined host/font/window metrics observer as start() —
  /// test-only.
  void startObservingMetricsForTest() => _observeMetrics();

  /// The session has ended — a dropped socket or a BYE from the host.
  /// Stop interacting, keep the last rendered frame on screen, and overlay
  /// a clear message instead of emptying the DOM.
  void _teardown(String message, {bool banner = true}) {
    if (_closed) return;
    _closed = true;
    _components?.inputSource.dispose();
    // Stops the combined host/font/window observers immediately on disconnect;
    // MountedApp.dispose invokes this idempotent disposer again later.
    _components?.metrics.dispose();
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

  void _removeDisconnectBanner() {
    final banner = _disconnectBanner;
    _disconnectBanner = null;
    banner?.remove();
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
