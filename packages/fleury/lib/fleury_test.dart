/// Test helpers for `fleury`. Import from test files only.
///
///     import 'package:fleury/fleury.dart';
///     import 'package:fleury/fleury_test.dart';
///     import 'package:test/test.dart';
///
///     void main() {
///       testWidgets('autofocus claims focus', (tester) {
///         tester.pumpWidget(TextInput(autofocus: true));
///         expect(tester.find(byType(TextInput)), hasLength(1));
///       });
///     }
///
/// Follows the `flutter_test` convention: a second public library
/// alongside the main one, used only in test files so production
/// builds don't depend on `dart:io` or test harness machinery.
library;

export 'src/animation/clock.dart' show FakeClock;
export 'src/animation/ticker_scheduler.dart' show FakeTickerScheduler;
// Repaint-boundary paint diagnostics: lets downstream widget packages assert
// cache engagement (e.g. a lazily-mounted overlay layer staying pass-through
// while idle) without reaching into src/.
export 'src/rendering/render_repaint_boundary.dart'
    show RepaintBoundaryDebugStats, RepaintBoundaryFrameStats;
export 'src/testing/fleury_tester.dart' show FleuryTester, testWidgets;
export 'src/testing/finders.dart'
    show Finder, byKey, byPredicate, byType, descendantOf, text;
export 'src/testing/goldens.dart' show matchesGolden;
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
export 'src/rendering/render_repaint_boundary.dart'
    show RepaintBoundaryFrameStats;
