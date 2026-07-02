import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import 'clipboard/web_clipboard.dart';
import 'focus/web_focus_coordinator.dart';
import 'host/browser_presentation_host.dart';
import 'instrumentation/web_host_instrumentation.dart';
import 'run_tui_surface.dart';

/// Mounts a Fleury app into a browser DOM element.
///
/// This is the assembled DOM-host path: retained row DOM for presentation,
/// browser cell metrics for resize, DOM input events for keyboard/pointer/paste,
/// browser clipboard writes through [WebClipboard], and a semantic DOM mirror
/// when [semanticsEnabled] is true. The assembly lives in
/// [BrowserPresentationHost]; this entry point attaches a
/// [LocalRuntimeFrameSource] — the app's widget tree running in this page.
///
/// The visual DOM grid is `aria-hidden`, so disabling semantics makes the
/// retained DOM surface inaccessible. Keep [semanticsEnabled] on for product
/// use. Passing `semanticsEnabled: false` requires
/// [allowInaccessibleDiagnostics] and is intended only for focused local
/// performance diagnostics.
///
/// This is the public browser entry point for Fleury-owned apps. The
/// serve/remote paths present through the same host with a wire-backed
/// frame source.
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
}) {
  return BrowserPresentationHost(
    into: into,
    surfaceElement: surfaceElement,
    semanticElement: semanticElement,
    semanticsEnabled: semanticsEnabled,
    allowInaccessibleDiagnostics: allowInaccessibleDiagnostics,
    clipboard: clipboard,
    focusCoordinator: focusCoordinator,
    instrumentation: instrumentation,
    semanticFlushScheduler: semanticFlushScheduler,
  ).attach(
    LocalRuntimeFrameSource(
      rootFactory,
      frameInterval: frameInterval,
      flushScheduler: flushScheduler,
    ),
  );
}
