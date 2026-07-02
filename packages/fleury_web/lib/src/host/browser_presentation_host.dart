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

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import '../clipboard/web_clipboard.dart';
import '../dom_grid/dom_grid_surface.dart';
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

  /// Null only in the explicitly-opted inaccessible-diagnostics mode.
  final SemanticDomPresenter? semanticPresenter;
  final WebFocusCoordinator focusCoordinator;
  final Clipboard clipboard;
  final WebHostInstrumentation instrumentation;
  final SemanticFlushScheduler? semanticFlushScheduler;

  /// Removes the DOM roots the host generated (no-op for caller-supplied
  /// elements). Sources wire this into their dispose path.
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
    final removeSurfaceRoot = _surfaceElement == null;
    if (surfaceRoot.parentNode == null) host.appendChild(surfaceRoot);
    final semanticRoot = _semanticsEnabled
        ? _semanticElement ?? web.document.createElement('div')
        : null;
    final removeSemanticRoot = _semanticsEnabled && _semanticElement == null;
    if (semanticRoot != null && semanticRoot.parentNode == null) {
      host.appendChild(semanticRoot);
    }

    void removeGeneratedRoots() {
      if (removeSemanticRoot) {
        semanticRoot?.parentNode?.removeChild(semanticRoot);
      }
      if (removeSurfaceRoot) surfaceRoot.parentNode?.removeChild(surfaceRoot);
    }

    try {
      final metrics = DomCellMetrics(container: host);
      final surface = DomGridSurface(root: surfaceRoot, size: CellSize.zero);
      final semanticPresenter = semanticRoot == null
          ? null
          : SemanticDomPresenter(root: semanticRoot);
      final webFocusCoordinator = _focusCoordinator ?? WebFocusCoordinator();
      final webClipboard = _clipboard ?? WebClipboard();
      final input = DomInputSource(
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
        semanticPresenter: semanticPresenter,
        focusCoordinator: webFocusCoordinator,
        clipboard: webClipboard,
        instrumentation: _instrumentation,
        semanticFlushScheduler: _semanticFlushScheduler,
        removeGeneratedRoots: removeGeneratedRoots,
      );
    } catch (_) {
      removeGeneratedRoots();
      rethrow;
    }
  }

  /// Assembles the stack and starts presenting frames from [source].
  Future<MountedApp> attach(BrowserFrameSource source) async {
    final components = assemble();
    try {
      return await source.start(components);
    } catch (_) {
      components.removeGeneratedRoots();
      rethrow;
    }
  }
}
