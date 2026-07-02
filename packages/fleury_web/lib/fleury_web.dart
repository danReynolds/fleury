/// Run fleury in the browser.
///
/// [mountApp] is the retained DOM host: it pairs the framework's host SPI
/// (`fleury_host.dart`) with retained row DOM for presentation, browser cell
/// metrics, DOM input events, browser clipboard, and a semantic DOM mirror for
/// accessibility. The serve/remote paths sit behind the same core runtime
/// contracts as their own hosts.
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
        WebSemanticFlushInstrumentation,
        WebSemanticFlushSummary,
        defaultWebFrameBudgetMs;
export 'src/mount_app.dart' show mountApp;
export 'package:fleury/fleury_host.dart'
    show SemanticFlushScheduler, TimerSemanticFlushScheduler;
export 'src/run_tui_surface.dart' show MountedApp;
