import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import 'clipboard/web_clipboard.dart';
import 'dom_grid/dom_grid_surface.dart';
import 'focus/web_focus_coordinator.dart';
import 'input/dom_input_source.dart';
import 'instrumentation/web_host_instrumentation.dart';
import 'metrics/dom_cell_metrics.dart';
import 'run_tui_surface.dart';
import 'semantics/semantic_dom_presenter.dart';

/// Mounts a Fleury app into a browser DOM element.
///
/// This is the assembled DOM-host path: retained row DOM for presentation,
/// browser cell metrics for resize, DOM input events for keyboard/pointer/paste,
/// browser clipboard writes through [WebClipboard], and a semantic DOM mirror
/// when [semanticsEnabled] is true.
///
/// The visual DOM grid is `aria-hidden`, so disabling semantics makes the
/// retained DOM surface inaccessible. Keep [semanticsEnabled] on for product
/// use. Passing `semanticsEnabled: false` requires
/// [allowInaccessibleDiagnostics] and is intended only for focused local
/// performance diagnostics.
///
/// This is the public browser entry point for Fleury-owned apps. The
/// serve/remote paths reuse the same core runtime contracts behind their own
/// hosts.
Future<MountedApp> mountApp(
  Widget Function() rootFactory, {
  required web.Element into,
  web.Element? surfaceElement,
  web.Element? semanticElement,
  bool semanticsEnabled = true,
  bool allowInaccessibleDiagnostics = false,
  Clipboard? clipboard,
  Duration frameInterval = Duration.zero,
  FrameFlushScheduler? flushScheduler,
  SemanticFlushScheduler? semanticFlushScheduler,
  WebHostInstrumentation instrumentation = const NoopWebHostInstrumentation(),
  WebFocusCoordinator? focusCoordinator,
}) async {
  if (!semanticsEnabled) {
    if (!allowInaccessibleDiagnostics) {
      throw StateError(
        'mountApp disables accessibility when semanticsEnabled is false. '
        'Keep semantics enabled for product use, or pass '
        'allowInaccessibleDiagnostics: true for focused local diagnostics.',
      );
    }
    if (semanticElement != null) {
      throw ArgumentError.value(
        semanticElement,
        'semanticElement',
        'Cannot supply a semantic root when semanticsEnabled is false.',
      );
    }
  }

  final host = into;
  final surfaceRoot = surfaceElement ?? web.document.createElement('div');
  final removeSurfaceRoot = surfaceElement == null;
  if (surfaceRoot.parentNode == null) host.appendChild(surfaceRoot);
  final semanticRoot = semanticsEnabled
      ? semanticElement ?? web.document.createElement('div')
      : null;
  final removeSemanticRoot = semanticsEnabled && semanticElement == null;
  if (semanticRoot != null && semanticRoot.parentNode == null) {
    host.appendChild(semanticRoot);
  }

  void removeGeneratedRoots() {
    if (removeSemanticRoot) semanticRoot?.parentNode?.removeChild(semanticRoot);
    if (removeSurfaceRoot) surfaceRoot.parentNode?.removeChild(surfaceRoot);
  }

  try {
    final metrics = DomCellMetrics(container: host);
    final surface = DomGridSurface(root: surfaceRoot, size: CellSize.zero);
    final semanticPresenter = semanticRoot == null
        ? null
        : SemanticDomPresenter(root: semanticRoot);
    final webFocusCoordinator = focusCoordinator ?? WebFocusCoordinator();
    final webClipboard = clipboard ?? WebClipboard();
    final input = DomInputSource(
      hostElement: host,
      pointerTarget: surfaceRoot,
      cellMetrics: metrics,
      focusCoordinator: webFocusCoordinator,
      clipboard: webClipboard,
    );

    return await runTuiSurface(
      rootFactory,
      surface: surface,
      cellMetrics: metrics,
      inputSource: input,
      semanticPresenter: semanticPresenter,
      semanticFlushScheduler: semanticFlushScheduler,
      clipboard: webClipboard,
      frameInterval: frameInterval,
      flushScheduler: flushScheduler,
      instrumentation: instrumentation,
      focusCoordinator: webFocusCoordinator,
      disposeHostResources: removeGeneratedRoots,
    );
  } catch (_) {
    removeGeneratedRoots();
    rethrow;
  }
}
