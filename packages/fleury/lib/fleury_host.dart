/// Fleury host SPI.
///
/// Import this when building a platform host for Fleury rather than an
/// application UI. The library re-exports `fleury_core.dart` plus the
/// host-facing runtime, damage, and semantic-update contracts that native and
/// browser runners need to mount, render, present, and mirror a Fleury tree.
///
/// This library is still platform-neutral and free of `dart:io`.
library;

export 'fleury_core.dart';
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
        boxSegmentWest,
        protocolPlaceholderGlyph,
        protocolPlaceholderKind,
        protocolPlaceholderKindAttribute,
        protocolPlaceholderTitle,
        protocolPlaceholderUnsupported,
        protocolPlaceholderUnsupportedAttribute;
export 'src/runtime/frame_presentation.dart'
    show
        FrameDamageSource,
        FramePresentationDamage,
        FramePresentationPlan,
        FramePresentationPlanner;
export 'src/widgets/framework.dart' show BuildFlushStats;
export 'src/runtime/frame_driver.dart'
    show FrameDriver, FramePresentInfo, FramePresenter;
export 'src/runtime/frame_semantics_pipeline.dart'
    show FrameSemanticsPipeline, SemanticFlushStats;
export 'src/runtime/frame_scheduler.dart'
    show FrameFlushScheduler, FrameRenderCallback, FrameScheduler;
export 'src/runtime/input_dispatcher.dart' show InputDispatcher;
export 'src/runtime/tui_frame_loop.dart'
    show
        TuiDirtyRowRange,
        TuiDirtyRows,
        TuiFrameDamage,
        TuiFrameLoop,
        TuiFramePaintCallback,
        TuiRenderedFrame;
export 'src/runtime/semantic_flush_scheduler.dart'
    show
        MicrotaskSemanticFlushScheduler,
        SemanticFlushScheduler,
        TimerSemanticFlushScheduler;
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

// The remote-render wire: the frame protocol, semantic codec, and transport
// interface a host uses to drive a Fleury app over a connection (and a
// browser/agent host uses to mirror it). Platform-neutral; `dart:io` transports
// live in `fleury_host_io.dart`.
export 'src/remote/remote_protocol.dart'
    show
        ByeFrame,
        FrameDecoder,
        FrameType,
        InitFrame,
        InlineImageFrame,
        InputEventFrame,
        InputFrame,
        OutputFrame,
        PlanFrame,
        RemoteFrame,
        RemoteProtocolException,
        ResizeFrame,
        SemanticActionFrame,
        SemanticActionResultFrame,
        SemanticsFrame,
        defaultMaxRemoteFramePayloadLength,
        encodeFrame,
        remoteProtocolVersion;
export 'src/remote/remote_codec.dart'
    show
        ImagePlacement,
        RemoteCodecException,
        RemotePatchRun,
        RemotePlan,
        RemoteRowPatch,
        applyRemotePlanToBuffer,
        buildRemotePlan,
        decodeInputEvent,
        decodeRemotePlan,
        decodeSemanticAction,
        encodeInputEvent,
        encodeRemotePlan,
        encodeSemanticAction;
export 'src/remote/remote_semantics.dart'
    show
        SemanticsWireDecoder,
        SemanticsWireEncoder,
        maxSemanticTreeDepth,
        semanticsWireVersion;
export 'src/remote/remote_transport.dart' show RemoteFrameTransport;
