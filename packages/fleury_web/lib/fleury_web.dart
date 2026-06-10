/// Run fleury in the browser.
///
/// [runTuiWeb] pairs the framework's host SPI (`fleury_host.dart`) with a
/// [WebTerminalDriver] over xterm.js. The retained
/// DOM path is available separately as [runTuiWebDom] while it matures behind
/// the same core runtime contracts.
library;

export 'src/frame_presentation.dart' show FrameDamageSource;
export 'src/focus/web_focus_coordinator.dart'
    show WebFocusCoordinator, WebFocusSnapshot, WebFocusTarget;
export 'src/instrumentation/web_host_instrumentation.dart'
    show
        NoopWebHostInstrumentation,
        RecordingWebHostInstrumentation,
        WebFrameInstrumentation,
        WebBrowserPerformanceMetrics,
        WebHostInstrumentation,
        WebInstrumentationSummary,
        WebMetricSummary,
        defaultWebFrameBudgetMs;
export 'src/run_tui_web_dom.dart' show runTuiWebDom;
export 'src/run_tui_surface.dart' show TuiSurfaceHost;
export 'src/run_tui_web.dart' show runTuiWeb;
export 'src/web_terminal_driver.dart' show WebTerminalDriver;
