/// Fleury's supported, platform-neutral host SPI.
///
/// Import this when building a platform host for Fleury rather than an
/// application UI. The library re-exports `fleury_core.dart` plus the
/// host-facing runtime, damage, and semantic-update contracts that native and
/// browser runners need to mount, render, present, and mirror a Fleury tree.
///
/// The remote frame protocol and codecs are intentionally not part of this
/// stable host surface. First-party lockstep peers import `fleury_wire.dart`.
///
/// This library is still platform-neutral and free of `dart:io`.
library;

export 'fleury_core.dart';
export 'src/rendering/render_error_boundary.dart'
    show RenderErrorBoundary, RenderErrorContainment;
export 'src/rendering/render_object.dart' show RenderDamageTracker;
export 'src/rendering/scroll_detection.dart'
    show detectBeneficialScrollUp, rowsEqual, screenDiffStats;
export 'src/rendering/cell_span.dart'
    show
        CellRunKind,
        CellSpanBuilder,
        CellSpanRun,
        RowSpanModel,
        WidthCorrection,
        boxDrawingMask,
        boxSegmentEast,
        boxSegmentNorth,
        boxSegmentSouth,
        boxSegmentWest;
export 'src/runtime/frame_presentation.dart'
    show
        FrameDamageSource,
        FramePresentationDamage,
        PresentationFullRepaint,
        PresentationChanged,
        PresentationScrolled,
        FramePresentationPlan,
        FramePresentationPlanner;
export 'src/widgets/framework.dart' show BuildFlushStats;
export 'src/runtime/frame_driver.dart'
    show
        FrameDiffStats,
        FrameDriver,
        FramePresentInfo,
        FramePresenter,
        FrameViewportSnapshot;
export 'src/runtime/frame_semantics_pipeline.dart'
    show FrameSemanticsPipeline, SemanticFlushStats;
export 'src/runtime/frame_scheduler.dart'
    show
        FrameFlushCancellation,
        FrameFlushScheduler,
        FrameRenderCallback,
        FrameScheduler;
// KeyPhaseObserverRegistration rides along because InputDispatcher's
// addKeyObserver returns it — an exported method must not return an
// unexported type.
export 'src/runtime/input_dispatcher.dart'
    show InputDispatcher, KeyPhaseObserverRegistration;
export 'src/runtime/tui_frame_loop.dart'
    show
        TuiDirtyRowRange,
        TuiDirtyRows,
        TuiFrameDamage,
        FrameFullRepaint,
        FrameUnchanged,
        FrameChanged,
        FrameScrolled,
        TuiFrameLoop,
        TuiFramePaintCallback,
        TuiRenderedFrame;
export 'src/runtime/semantic_flush_scheduler.dart'
    show
        MicrotaskSemanticFlushScheduler,
        SemanticFlushScheduler,
        TimerSemanticFlushScheduler;
export 'src/runtime/tui_root.dart' show buildTuiRoot;
export 'src/runtime/tui_runtime.dart' show TuiRuntime;
export 'src/runtime/wire_frame_presenter.dart' show WireFramePresenter;
export 'src/remote/wire_semantic_frame_presenter.dart'
    show WireSemanticFramePresenter;
export 'src/semantics/semantic_coverage.dart'
    show
        SemanticCoverageAudit,
        SemanticCoverageResult,
        applySemanticTextFallback;
export 'src/semantics/semantic_presenter.dart'
    show
        SemanticActionRequestHandler,
        SemanticActionRequestSink,
        SemanticFramePresenter,
        SemanticPresentationStats;
export 'src/semantics/semantics_owner.dart'
    show SemanticsOwner, SemanticTreeUpdate, debugSemanticTreeDivergence;
export 'src/semantics/semantics.dart'
    show
        SemanticActionInvocationResult,
        SemanticActionInvocationStatus,
        SemanticDirtyOwner,
        SemanticDirtySnapshot,
        SemanticDirtyTracker,
        SemanticsElement,
        invokeSemanticActionFromElement;
