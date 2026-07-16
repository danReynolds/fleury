// BrowserPresentationHost: ONE assembly of the browser presentation
// stack — DOM grid surface, cell metrics, DOM input, semantic mirror,
// focus coordinator, clipboard, instrumentation — wired identically no
// matter where frames come from. The frame origin is the only variable,
// behind [BrowserFrameSource]: a local runtime (embed / the web render
// backend) or the serve wire (PR5's WireFrameSource).
//
// This is the anti-drift seam the audit demanded: the serve client can
// never again silently lack a component the embed host has, because both
// receive the same [BrowserHostComponents] from the same constructor.

import 'dart:async';
import 'dart:js_interop';

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import '../clipboard/web_clipboard.dart';
import '../dom_grid/dom_grid_surface.dart';
import '../dom_grid/inline_image_overlay.dart';
import '../focus/web_focus_coordinator.dart';
import '../input/dom_input_source.dart';
import '../instrumentation/web_host_instrumentation.dart';
import '../metrics/dom_cell_metrics.dart';
import '../run_tui_surface.dart';
import '../semantics/semantic_dom_presenter.dart';

/// The assembled component set a [BrowserFrameSource] presents through.
final class BrowserHostComponents {
  const BrowserHostComponents({
    required this.hostElement,
    required this.surface,
    required this.metrics,
    required this.inputSource,
    required this.imageOverlay,
    required this.semanticPresenter,
    required this.focusCoordinator,
    required this.clipboard,
    required this.instrumentation,
    required this.semanticFlushScheduler,
    required this.removeGeneratedRoots,
  });

  final web.Element hostElement;
  final DomGridSurface surface;
  final DomCellMetrics metrics;
  final DomInputSource inputSource;

  /// The true-pixel inline-image layer both frame sources present
  /// placements through — the embed path from the frame buffer, the
  /// serve client from the wire plan. Assembled here so neither source
  /// can silently lack it.
  final InlineImageOverlay imageOverlay;

  /// Null only in the explicitly-opted inaccessible-diagnostics mode.
  final SemanticDomPresenter? semanticPresenter;
  final WebFocusCoordinator focusCoordinator;
  final Clipboard clipboard;
  final WebHostInstrumentation instrumentation;
  final SemanticFlushScheduler? semanticFlushScheduler;

  /// Removes the DOM roots the host generated (no-op for caller-supplied
  /// elements) and the overlay layer. Sources wire this into their
  /// dispose path.
  final void Function() removeGeneratedRoots;
}

/// Where frames come from: a local runtime (embed) or the serve wire.
/// The source starts presenting through the host's components and returns
/// the session handle.
// ignore: one_member_abstracts — the seam IS the single method; PR5's wire
// source is the second implementation.
abstract interface class BrowserFrameSource {
  Future<MountedApp> start(BrowserHostComponents components);
}

/// Runs the app's widget tree in this page (dart2js) and presents through
/// the shared frame driver — the embed path, and the required shape for
/// the web render backend.
final class LocalRuntimeFrameSource implements BrowserFrameSource {
  LocalRuntimeFrameSource(
    this.rootFactory, {
    this.frameInterval = Duration.zero,
    this.flushScheduler,
  });

  final Widget Function() rootFactory;
  final Duration frameInterval;
  final FrameFlushScheduler? flushScheduler;

  @override
  Future<MountedApp> start(BrowserHostComponents components) {
    return runTuiSurface(
      rootFactory,
      surface: components.surface,
      cellMetrics: components.metrics,
      inputSource: components.inputSource,
      imageOverlay: components.imageOverlay,
      semanticPresenter: components.semanticPresenter,
      semanticFlushScheduler: components.semanticFlushScheduler,
      clipboard: components.clipboard,
      frameInterval: frameInterval,
      flushScheduler: flushScheduler,
      instrumentation: components.instrumentation,
      focusCoordinator: components.focusCoordinator,
      disposeHostResources: components.removeGeneratedRoots,
    );
  }
}

/// Assembles the browser presentation stack and attaches a frame source.
final class BrowserPresentationHost {
  BrowserPresentationHost({
    required web.Element into,
    web.Element? surfaceElement,
    web.Element? semanticElement,
    bool semanticsEnabled = true,
    bool allowInaccessibleDiagnostics = false,
    Clipboard? clipboard,
    WebFocusCoordinator? focusCoordinator,
    WebHostInstrumentation instrumentation = const NoopWebHostInstrumentation(),
    SemanticFlushScheduler? semanticFlushScheduler,
  }) : _into = into,
       _surfaceElement = surfaceElement,
       _semanticElement = semanticElement,
       _semanticsEnabled = semanticsEnabled,
       _allowInaccessibleDiagnostics = allowInaccessibleDiagnostics,
       _clipboard = clipboard,
       _focusCoordinator = focusCoordinator,
       _instrumentation = instrumentation,
       _semanticFlushScheduler = semanticFlushScheduler;

  final web.Element _into;
  final web.Element? _surfaceElement;
  final web.Element? _semanticElement;
  final bool _semanticsEnabled;
  final bool _allowInaccessibleDiagnostics;
  final Clipboard? _clipboard;
  final WebFocusCoordinator? _focusCoordinator;
  final WebHostInstrumentation _instrumentation;
  final SemanticFlushScheduler? _semanticFlushScheduler;

  /// Builds the component set. Exposed separately from [attach] so tests
  /// can assert the assembly is identical across source kinds.
  BrowserHostComponents assemble() {
    if (!_semanticsEnabled) {
      if (!_allowInaccessibleDiagnostics) {
        throw StateError(
          'The browser host disables accessibility when semanticsEnabled is '
          'false. Keep semantics enabled for product use, or pass '
          'allowInaccessibleDiagnostics: true for focused local diagnostics.',
        );
      }
      if (_semanticElement != null) {
        throw ArgumentError.value(
          _semanticElement,
          'semanticElement',
          'Cannot supply a semantic root when semanticsEnabled is false.',
        );
      }
    }

    final host = _into;
    final surfaceRoot = _surfaceElement ?? web.document.createElement('div');
    // We remove exactly what we appended: an element we attach because it
    // was detached (a generated root, or a caller-supplied element not yet
    // in the DOM). A caller-supplied element that is ALREADY attached is
    // the caller's to place and remove — we never touch it. Removing on
    // teardown restores the pre-mount state, so re-mounting the same
    // element into a different host works instead of leaving it orphaned
    // in the old one.
    final removeSurfaceRoot = surfaceRoot.parentNode == null;
    if (removeSurfaceRoot) host.appendChild(surfaceRoot);
    final semanticRoot = _semanticsEnabled
        ? _semanticElement ?? web.document.createElement('div')
        : null;
    final removeSemanticRoot =
        semanticRoot != null && semanticRoot.parentNode == null;
    if (removeSemanticRoot) {
      host.appendChild(semanticRoot);
    }

    DomCellMetrics? metricsForCleanup;
    DomGridSurface? surfaceForCleanup;
    InlineImageOverlay? imageOverlay;
    SemanticDomPresenter? semanticPresenterForCleanup;
    DomInputSource? inputForCleanup;
    void removeGeneratedRoots() {
      imageOverlay?.dispose();
      if (removeSemanticRoot) {
        semanticRoot.parentNode?.removeChild(semanticRoot);
      }
      if (removeSurfaceRoot) surfaceRoot.parentNode?.removeChild(surfaceRoot);
    }

    try {
      final metrics = metricsForCleanup = DomCellMetrics(container: host);
      final surface = surfaceForCleanup = DomGridSurface(
        root: surfaceRoot,
        size: CellSize.zero,
      );
      if (!host.isA<web.HTMLElement>()) {
        throw ArgumentError.value(
          host,
          'into',
          'BrowserPresentationHost requires an HTML element.',
        );
      }
      final overlay = imageOverlay = InlineImageOverlay(
        host as web.HTMLElement,
      );
      final semanticPresenter = semanticPresenterForCleanup =
          semanticRoot == null
          ? null
          : SemanticDomPresenter(root: semanticRoot);
      final webFocusCoordinator = _focusCoordinator ?? WebFocusCoordinator();
      final webClipboard = _clipboard ?? WebClipboard();
      final input = inputForCleanup = DomInputSource(
        hostElement: host,
        pointerTarget: surfaceRoot,
        cellMetrics: metrics,
        focusCoordinator: webFocusCoordinator,
        clipboard: webClipboard,
      );
      return BrowserHostComponents(
        hostElement: host,
        surface: surface,
        metrics: metrics,
        inputSource: input,
        imageOverlay: overlay,
        semanticPresenter: semanticPresenter,
        focusCoordinator: webFocusCoordinator,
        clipboard: webClipboard,
        instrumentation: _instrumentation,
        semanticFlushScheduler: _semanticFlushScheduler,
        removeGeneratedRoots: removeGeneratedRoots,
      );
    } catch (_) {
      // Assembly is synchronous, so start every cleanup step before returning
      // the original error. The helper swallows cleanup failures and completes
      // any asynchronous disposals in the background.
      unawaited(
        _disposeBrowserHostComponentsBestEffort(
          inputSource: inputForCleanup,
          metrics: metricsForCleanup,
          semanticPresenter: semanticPresenterForCleanup,
          surface: surfaceForCleanup,
          imageOverlay: imageOverlay,
          removeGeneratedRoots: removeGeneratedRoots,
        ),
      );
      rethrow;
    }
  }

  /// Assembles the stack and starts presenting frames from [source].
  Future<MountedApp> attach(BrowserFrameSource source) async {
    final components = assemble();
    try {
      return await source.start(components);
    } catch (_) {
      // A source may fail after partially starting the shared host stack. No
      // MountedApp exists to own teardown, so release every assembled resource
      // here. Cleanup is idempotent and best-effort: the source/start error
      // remains the useful failure even if one disposer also fails.
      await _disposeBrowserHostComponentsBestEffort(
        inputSource: components.inputSource,
        metrics: components.metrics,
        semanticPresenter: components.semanticPresenter,
        surface: components.surface,
        imageOverlay: components.imageOverlay,
        removeGeneratedRoots: components.removeGeneratedRoots,
      );
      rethrow;
    }
  }
}

/// Releases a partially or fully assembled browser host without allowing a
/// cleanup failure to replace the setup/start failure that triggered it.
///
/// Every disposer is invoked before the returned future first yields. That
/// keeps the synchronous [BrowserPresentationHost.assemble] failure contract:
/// generated DOM and probes are already gone when the original exception
/// reaches its caller, while asynchronous disposer completions are still
/// observed and swallowed.
Future<void> _disposeBrowserHostComponentsBestEffort({
  required DomInputSource? inputSource,
  required DomCellMetrics? metrics,
  required SemanticDomPresenter? semanticPresenter,
  required DomGridSurface? surface,
  required InlineImageOverlay? imageOverlay,
  required void Function()? removeGeneratedRoots,
}) async {
  Future<void>? semanticDispose;
  Future<void>? surfaceDispose;

  try {
    inputSource?.dispose();
  } catch (_) {}
  try {
    metrics?.dispose();
  } catch (_) {}
  try {
    semanticDispose = semanticPresenter?.dispose();
  } catch (_) {}
  try {
    surfaceDispose = surface?.dispose();
  } catch (_) {}
  try {
    imageOverlay?.dispose();
  } catch (_) {}
  try {
    removeGeneratedRoots?.call();
  } catch (_) {}

  for (final pending in <Future<void>?>[semanticDispose, surfaceDispose]) {
    if (pending == null) continue;
    try {
      await pending;
    } catch (_) {}
  }
}
