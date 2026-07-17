/// Package-neutral harness support for `fleury_test` and framework tooling.
///
/// Most application tests should import `package:fleury_test/fleury_test.dart`
/// instead. This lower-level library intentionally has no dependency on
/// package:test or matcher, which also makes it suitable for benchmarks,
/// snapshot tools, and other deterministic harnesses.
library;

export 'src/animation/clock.dart' show FakeClock;
export 'src/animation/ticker_scheduler.dart' show FakeTickerScheduler;
// Repaint-boundary paint diagnostics: lets downstream widget packages assert
// cache engagement (e.g. a lazily-mounted overlay layer staying pass-through
// while idle) without reaching into src/.
export 'src/rendering/render_repaint_boundary.dart'
    show RepaintBoundaryDebugStats, RepaintBoundaryFrameStats;
export 'src/testing/fleury_tester.dart'
    show FleuryTestFailure, FleuryTestFailureHandler, FleuryTester;
export 'src/testing/finders.dart'
    show Finder, byKey, byPredicate, byType, descendantOf, text;
export 'src/semantics/semantics.dart'
    show
        SemanticAction,
        SemanticActionCallback,
        SemanticActionContributor,
        SemanticActionInvocationResult,
        SemanticActionInvocationStatus,
        SemanticNode,
        SemanticNodeId,
        SemanticRole,
        SemanticState,
        SemanticTree,
        Semantics,
        invokeSemanticActionFromElement;
export 'src/semantics/accessibility.dart'
    show
        AccessibilityNode,
        AccessibilitySnapshot,
        AccessibilitySnapshotSummary,
        SemanticTreeAccessibility,
        buildAccessibilitySnapshot;
export 'src/semantics/inspection.dart'
    show
        SemanticInspectionNode,
        SemanticInspectionSnapshot,
        SemanticTreeInspection;
export 'src/semantics/semantics_owner.dart'
    show SemanticsOwner, SemanticTreeUpdate;
export 'src/debug/debug_capture.dart'
    show
        DebugCaptureArtifact,
        DebugCaptureRecorder,
        DebugCaptureSemanticNode,
        DebugCaptureSnapshot,
        DebugOutputSummary,
        DebugTaskEventSummary,
        DebugTimeMarker;
export 'src/debug/debug_events.dart'
    show
        DebugEvent,
        DebugEvents,
        DirtySpanFrameStats,
        FrameDebugEvent,
        FrameEvent,
        InputDebugEvent;
export 'src/rendering/render_layout_stats.dart'
    show RenderLayoutDebugStats, RenderLayoutFrameStats;
export 'src/rendering/ansi_byte_budget.dart'
    show AnsiByteBreakdown, CountingAnsiSink, TransportProfile;
