// A separate bundle in an iframe: the native debugger's isolate-wide event
// stream must not collect frames from other documentation examples.
import 'dart:js_interop';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_doc_examples/debugging/playground.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_web/src/run_tui_surface.dart' show runTuiSurface;
import 'package:web/web.dart' as web;

Future<void> main() async {
  await web.document.fonts.ready.toDart;
  final element = web.document.querySelector('#surface')!;
  final toggle = web.document.querySelector('#toggle')!;
  final expand = web.document.querySelector('#expand')!;
  final status = web.document.querySelector('#status')!;
  final logs = LogBuffer();
  final errors = RuntimeErrorReporter(
    onLog: (line) => logs.add(LogLine(line, LogSource.stderr)),
  );
  final debug =
      DebugController(
          const DebugConfig(
            enabled: true,
            startMode: DebugMode.docked,
            panelWidth: 57,
          ),
        )
        ..paintFlashAvailable = false
        ..selectTab(DebugTab.rebuilds);

  void updateControls() {
    final open = debug.mode != DebugMode.off;
    toggle.textContent = open ? 'Hide debugger' : 'Show debugger';
    toggle.setAttribute('aria-pressed', '$open');
    expand.textContent = debug.mode == DebugMode.fullscreen
        ? 'Dock panel'
        : 'Expand panel';
  }

  final components = BrowserPresentationHost(into: element).assemble();
  try {
    await runTuiSurface(
      () => Theme(
        data: ThemeData.dark(),
        child: FocusTraversalGroup(child: DebuggingPlayground(logs: logs)),
      ),
      surface: components.surface,
      cellMetrics: components.metrics,
      inputSource: components.inputSource,
      imageOverlay: components.imageOverlay,
      semanticPresenter: components.semanticPresenter,
      semanticFlushScheduler: components.semanticFlushScheduler,
      clipboard: components.clipboard,
      focusCoordinator: components.focusCoordinator,
      disposeHostResources: () {
        components.removeGeneratedRoots();
        debug.dispose();
        errors.dispose();
        logs.dispose();
      },
      debugController: debug,
      logBuffer: logs,
      errorReporter: errors,
    );
    debug.addListener(updateControls);
    toggle.onClick.listen((_) => debug.toggleOnOff());
    expand.onClick.listen((_) {
      if (debug.mode == DebugMode.off) debug.toggleOnOff();
      debug.toggleExpand();
    });
    updateControls();
    status.textContent = 'Live · actual browser frame measurements';
  } catch (error) {
    status.textContent = 'The demo could not start. Reset to try again.';
  }
  // Reload the isolated context to reset recordings, counters, and source
  // collectors together. A panel toggle deliberately preserves that evidence.
  web.document
      .querySelector('#reset')!
      .onClick
      .listen((_) => web.window.location.reload());
}
