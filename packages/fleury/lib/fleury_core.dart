/// Fleury — the platform-agnostic core.
///
/// Everything here is free of `dart:io`, so it compiles to the web (and any
/// other Dart target). The native umbrella `fleury.dart` re-exports this
/// plus the `dart:io`-backed pieces (native POSIX and Windows terminal drivers,
/// `runApp`, and stray-output capture). Platform hosts that mount and present a
/// Fleury tree should import `fleury_host.dart`, which re-exports this library
/// plus host-only runtime and presentation contracts.
///
/// See `docs/rfcs/0007-fleury-framework.md` for scope and gates.
library;

// Foundation
export 'src/foundation/change_notifier.dart' show ChangeNotifier, Listenable;
export 'src/foundation/fleury_error.dart' show FleuryError;
export 'src/foundation/geometry.dart' show CellSize, CellOffset, CellRect;
export 'src/foundation/key.dart' show Key, LocalKey, ValueKey, UniqueKey;

// App kernel
export 'src/app/app.dart'
    show
        AppStatusBuilder,
        FleuryApp,
        FleuryAppController,
        FleuryAppExtension,
        FleuryAppScope,
        FleuryCommandContext;
export 'src/app/commands.dart'
    show
        AppCommand,
        AppCommandCallback,
        AppCommandPredicate,
        CommandContext,
        CommandId,
        CommandInvocationResult,
        CommandInvocationStatus,
        CommandRegistry,
        CommandRegistryScope,
        CommandScope;
export 'src/app/status.dart'
    show AppStatusBar, StatusController, StatusItem, StatusSeverity;

// Editing
export 'src/editing/text_completion.dart'
    show TextCompletionController, TextCompletionOption, TextCompletionState;
export 'src/editing/text_editing.dart'
    show TextEditingModel, TextEditingValue, TextRange, TextSelection;
export 'src/editing/text_history.dart' show TextHistoryController;
export 'src/editing/text_keymap.dart'
    show TextEditingKeyAction, TextEditingKeyBinding, TextEditingKeymap;
export 'src/editing/text_paste.dart'
    show TextPastePolicy, TextPasteProgress, TextPasteSession;

// Effects
export 'src/effects/task.dart'
    show
        DebouncedTaskController,
        TaskCanceled,
        TaskContext,
        TaskController,
        TaskEvent,
        TaskEventKind,
        TaskOutput,
        TaskOutputSeverity,
        TaskProgress,
        TaskResult,
        TaskRunner,
        TaskStatus,
        TaskStatusView,
        TaskYieldCheckpoint,
        TaskYieldPolicy;

// Animation
export 'src/animation/animation_policy.dart' show AnimationPolicy;
export 'src/animation/clock.dart' show Clock, SystemClock;
export 'src/animation/curves.dart' show Curve, Curves;
export 'src/animation/frame_ticker.dart' show FrameTicker;
export 'src/animation/lerp.dart'
    show DiscreteLerp, Lerp, doubleLerp, intLerp, rgbColorLerp;
export 'src/animation/animation.dart'
    show Animation, AnimationStep, AnimationType;
export 'src/animation/spring.dart' show Spring;
export 'src/animation/ticker.dart' show Ticker, TickerCallback, TickerProvider;
export 'src/animation/ticker_future.dart' show TickerCanceled, TickerFuture;
export 'src/animation/ticker_scheduler.dart'
    show FrameCallback, SchedulerTickCallback, TickerScheduler;

// Rendering
export 'src/rendering/ansi_renderer.dart'
    show AnsiRenderer, AnsiSink, StringAnsiSink, quantizeColor;
export 'src/rendering/border.dart' show BorderGlyphs, BorderStyle, BoxBorder;
export 'src/rendering/cell.dart'
    show
        AnsiColor,
        Cell,
        CellRole,
        CellStyle,
        Color,
        Colors,
        ControlState,
        IndexedColor,
        resolveControlStyle,
        RgbColor,
        StatefulCellStyle;
export 'src/rendering/cell_buffer.dart'
    show
        CellBuffer,
        InlineImage,
        InlineImageFit,
        InlineImagePlacement,
        ResolvedImageFit,
        resolveClippedInlineImageFit,
        resolveInlineImageFit;
export 'src/rendering/edge_insets.dart' show EdgeInsets;
export 'src/rendering/layout.dart' show CellConstraints;
export 'src/rendering/link_scheme.dart' show isSafeLinkScheme, kSafeLinkSchemes;
export 'src/rendering/render_flex.dart'
    show
        Axis,
        CrossAxisAlignment,
        FlexFit,
        MainAxisAlignment,
        MainAxisSize,
        RenderFlex,
        RenderFlexible;
export 'src/rendering/render_object.dart'
    show
        ParentData,
        RenderObject,
        RenderObjectWithChildren,
        RenderObjectWithSingleChild;
export 'src/rendering/render_repaint_boundary.dart' show RenderRepaintBoundary;
export 'src/rendering/width_policy.dart'
    show
        CellWidth,
        CellWidthPolicy,
        ClusterLowering,
        ResolvedTextPresentationPolicy,
        TextPresentationPolicy,
        WidthAxis,
        WidthDecisionSource;
export 'src/rendering/surface_capabilities.dart'
    show
        ColorMode,
        GlyphTier,
        InlineImageSupport,
        PointerPrecision,
        SurfaceCapabilities;
export 'src/rendering/render_objects.dart'
    show
        RenderBorder,
        RenderPadding,
        RenderSizedBox,
        RenderText,
        TextAlign,
        TextOverflow;
export 'src/rendering/render_stack.dart'
    show RenderPositioned, RenderStack, RenderIndexedStack;
export 'src/rendering/render_wrap.dart' show RenderWrap;
export 'src/rendering/text_sanitizer.dart'
    show
        isUnsafeRune,
        replacementCharacter,
        sanitizeForDisplay,
        sanitizeSingleLine;
export 'src/rendering/width_resolver.dart'
    show DefaultWidthResolver, WidthResolver, hasUncertainWidth;

// Semantics
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
export 'src/semantics/semantic_coercion.dart'
    show coerceSemanticBool, coerceSemanticInt, coerceSemanticNum;
export 'src/semantics/semantics.dart'
    show
        SemanticAction,
        SemanticActionCallback,
        SemanticActionContributor,
        SemanticChildrenProvider,
        SemanticContributor,
        SemanticNode,
        SemanticNodeId,
        SemanticRole,
        SemanticSetValueCallback,
        SemanticState,
        SemanticTree,
        SemanticValueContributor,
        Semantics,
        ExcludeSemantics,
        escapeSemanticIdSegment,
        isPositionalSemanticId,
        semanticAnchorOf;

// Terminal
export 'src/terminal/capabilities.dart'
    show
        AmbiguousCharWidth,
        HyperlinkSupport,
        ImageProtocol,
        TerminalCapabilities,
        TerminalSurfaceCapabilities,
        detectColorModeFromEnvironment,
        detectGlyphTierFromEnvironment,
        detectHyperlinkSupportFromEnvironment,
        detectHyperlinksFromEnvironment,
        detectImageProtocolFromEnvironment,
        detectTerminalCapabilitiesFromEnvironment,
        detectTerminalMultiplexerFromEnvironment,
        detectAmbiguousCharWidthFromEnvironment,
        detectClusterModeFromEnvironment,
        detectEmojiWidthFromEnvironment,
        detectVs16WidthFromEnvironment,
        deriveTextPresentationPolicy,
        parseEnvFlag;
export 'src/terminal/capability_requirements.dart'
    show
        CapabilityDelivery,
        CapabilityEnablement,
        CapabilityEvidence,
        CapabilityEvidenceSource,
        CapabilityFallback,
        CapabilityLevel,
        CapabilityRequirement,
        CapabilityResolution,
        CapabilityResolutionState,
        CapabilitySupport,
        CapabilityTruth,
        TerminalFeature,
        resolveCapabilityRequirement,
        resolveCapabilityRequirements;
export 'src/terminal/diagnostics.dart'
    show
        TerminalCapabilityReport,
        TerminalCompatibilityFinding,
        TerminalCompatibilityReport,
        TerminalCompatibilityStatus,
        TerminalDiagnosis,
        TerminalDiagnosticMessage,
        TerminalDiagnosticSeverity,
        TerminalEnvironmentReport,
        TerminalPlatformReport,
        TerminalProfileReport,
        buildTerminalCompatibilityReport,
        diagnoseTerminal;
export 'src/terminal/terminal_probe.dart'
    show
        WidthMeasurements,
        WidthProbeClass,
        WidthProbeGlyph,
        widthProbeBattery,
        ambiguousWidthFromMeasurements,
        TerminalProbeReport,
        TerminalProbeResult,
        TerminalProbeStatus,
        TerminalProbeTransport,
        probeGlyphWidths,
        runTerminalProbeSuite;
export 'src/input/events.dart'
    show
        AppSignal,
        InputBatch,
        KeyCode,
        KeyEvent,
        KeyEventType,
        KeyModifier,
        KeyPosition,
        KeySelector,
        KeySequence,
        KeySequenceChain,
        MouseButton,
        MouseEvent,
        MouseEventKind,
        PasteEvent,
        PasteEventPhase,
        PendingKeySequence,
        PendingKeySequenceChain,
        ResizeEvent,
        SignalEvent,
        SpecialKey,
        TextCompositionEvent,
        TextCompositionEventKind,
        TerminalFocusEvent,
        TextInputEvent,
        TuiEvent;
// Only the table with a real cross-package consumer (the DOM backend's
// code→position resolution). The kitty-side tables are parser internals;
// exporting them was pure public-surface debt with zero consumers.
export 'src/input/key_tables.dart' show positionByDomCode;
export 'src/input/keyboard_layout.dart'
    show KeyLabel, KeyLabelSource, KeyboardLayout;
export 'src/input/keyboard_state.dart'
    show KeyboardCapabilities, KeyboardSnapshot;
export 'src/terminal/fake_driver.dart' show FakeTerminalDriver;
export 'src/terminal/input_parser.dart' show InputParser, TuiEventSink;
export 'src/terminal/legacy_key_sequences.dart' show LegacyKeySequence;
export 'src/terminal/terminal_response.dart'
    show
        TerminalResponse,
        TerminalResponseExpectation,
        TerminalResponseKind,
        TerminalResponseSink;
export 'src/runtime/remote_surface_sink.dart'
    show
        RemoteClipboardStatus,
        RemoteDebugRequestHandler,
        RemoteSemanticActionHandler,
        RemoteSurfaceSink;
export 'src/terminal/terminal_driver.dart'
    show
        OutputFlowControl,
        AnsiTerminalPresentation,
        StructuredTerminalPresentation,
        TerminalAttentionDriver,
        TerminalDriver,
        TerminalHandoffDriver,
        TerminalPresentation,
        TerminalSessionProfile,
        KeyboardProtocolMode,
        TerminalMode,
        notifyTerminal,
        ringTerminalBell,
        sanitizeTerminalString,
        setTerminalTitle,
        withTerminalHandoff;

// Widgets
export 'src/widgets/focus.dart'
    show
        ExcludeFocus,
        Focus,
        FocusManager,
        FocusManagerScope,
        FocusNode,
        FocusScope,
        FocusScopeRef,
        FocusDetector,
        KeyBindingSource,
        KeyEventResult,
        PasteEventClaimant,
        TextCompositionClaimant,
        TextInputClaimant,
        moveOrEscape;
export 'src/widgets/focus_traversal.dart'
    show FocusTraversalGroup, TraversalDirection, nearestFocusableInDirection;
export 'src/widgets/inherited_notifier.dart' show InheritedNotifier;
export 'src/widgets/intrinsic.dart' show IntrinsicHeight, IntrinsicWidth;
export 'src/widgets/keyboard.dart'
    show Keyboard, KeyboardScope, KeyboardStateNotifier, KeyDetector;
export 'src/widgets/key_bindings.dart'
    show
        ActiveKeyBinding,
        KeyBinding,
        KeyBindingEvent,
        KeyBindingHandler,
        KeyBindings,
        KeyCompletion,
        KeySequenceMatch,
        PendingKeySequenceMatch,
        resolveActiveKeyBindings;
export 'src/widgets/list_view.dart'
    show
        EdgeBehavior,
        ListController,
        ListItemIndexCallback,
        ListItemKeyBuilder,
        ListView;
export 'src/widgets/navigator.dart'
    show Navigator, NavigatorContext, NavigatorState, PopScope, RouteTransition;
export 'src/widgets/layout_builder.dart'
    show LayoutBuilder, LayoutWidgetBuilder;
export 'src/widgets/media_query.dart' show MediaQuery, MediaQueryData;
export 'src/widgets/overlay.dart'
    show Overlay, OverlayEntry, OverlayMount, OverlayState;
export 'src/widgets/repaint_boundary.dart' show RepaintBoundary;
export 'src/widgets/rich_text.dart' show RichText, TextSpan;
export 'src/widgets/pointer.dart'
    show
        AbsorbPointer,
        GestureDetector,
        MouseRegion,
        PointerRouter,
        PointerRouterScope,
        PointerScrollListener,
        PointerDownCallback,
        PointerDownDetails,
        PointerModifiedTapCallback,
        PointerTapCallback,
        PointerPositionCallback;
export 'src/widgets/scroll_view.dart' show ScrollController, ScrollView;
export 'src/widgets/scrollbar.dart' show Scrollbar;
export 'src/widgets/listenable_builder.dart' show ListenableBuilder;
export 'src/widgets/blinking_cursor.dart' show BlinkingCursor;
export 'src/widgets/clipboard_scope.dart' show ClipboardScope;
export 'src/widgets/error_boundary.dart'
    show ErrorBoundary, FrameContainmentError, FrameContainmentPhase;
export 'src/widgets/frame_builder.dart' show FrameBuilder;
export 'src/widgets/animation_builder.dart' show AnimationBuilder;
export 'src/widgets/effects.dart'
    show Animate, AnimateExtension, Edge, Effect, Effects;
export 'src/widgets/presence.dart' show Reveal;
export 'src/widgets/selection/selectable.dart'
    show Selectable, SelectionRegistrant, SelectionRegistrar, SelectionScope;
export 'src/widgets/selection/selection.dart'
    show Selection, SelectedContent, SelectionGeometry, SelectionStatus;
export 'src/runtime/clipboard.dart'
    show
        Clipboard,
        ClipboardWritePolicy,
        ClipboardWriteReport,
        ClipboardWriteResult,
        InProcessClipboard;
export 'src/widgets/selection/selection_area.dart'
    show SelectionArea, SelectionChangedCallback;
export 'src/widgets/selection/selection_container_delegate.dart'
    show SelectionContainerDelegate;
export 'src/widgets/selection/selection_event.dart'
    show
        SelectionClearEvent,
        SelectionEdgeUpdateEvent,
        SelectionEvent,
        SelectionGranularEvent,
        SelectionGranularity,
        SelectionResult;
export 'src/widgets/spinner.dart' show Spinner, SpinnerStyle;
export 'src/widgets/text_area.dart' show TextArea;
export 'src/widgets/text_input.dart'
    show TextClipboardPolicy, TextEditingController, TextInput;
export 'src/widgets/ticker_mode.dart' show TickerMode;
export 'src/widgets/theme.dart'
    show
        Brightness,
        BrightnessPick,
        ColorScheme,
        DefaultTextStyle,
        FleuryThemeContext,
        Theme,
        ThemeData;
export 'src/widgets/tui_binding.dart'
    show SingleTickerProviderStateMixin, TuiBinding, TuiBindingScope;
export 'src/widgets/align.dart' show Align, Alignment, Center, RenderAlign;
export 'src/widgets/anchored.dart' show Anchored;
export 'src/widgets/bounds.dart'
    show
        BoundsAnchor,
        BoundsNotifier,
        BoundsObserver,
        defaultAnchorAlignment,
        resolveAnchoredOffset;
export 'src/widgets/async.dart'
    show
        AsyncSnapshot,
        AsyncWidgetBuilder,
        ConnectionState,
        FutureBuilder,
        StreamBuilder;
export 'src/widgets/basic.dart'
    show
        AspectRatio,
        Column,
        Container,
        ConstrainedBox,
        EmptyBox,
        ErrorWidget,
        Expanded,
        Flex,
        Flexible,
        IndexedStack,
        Padding,
        Positioned,
        Row,
        SizedBox,
        Spacer,
        Stack,
        resolveSurfaceColor,
        Text,
        Wrap;
export 'src/widgets/framework.dart'
    show
        BuildContext,
        BuildOwner,
        ComponentElement,
        Element,
        GlobalKey,
        InheritedElement,
        InheritedWidget,
        LeafRenderObjectElement,
        LeafRenderObjectWidget,
        MultiChildRenderObjectElement,
        MultiChildRenderObjectWidget,
        ProxyWidget,
        RenderObjectElement,
        RenderObjectWidget,
        SingleChildRenderObjectElement,
        SingleChildRenderObjectWidget,
        State,
        StatefulElement,
        StatefulWidget,
        StatelessElement,
        StatelessWidget,
        VoidCallback,
        Widget;
