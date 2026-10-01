/// Framework building blocks shared by the public API and bundled catalog.
/// Keep this library independent of catalog widgets.
library;

// Foundation
export 'foundation/change_notifier.dart'
    show Listenable, Notifier, ValueListenable, ValueNotifier;
export 'foundation/fleury_error.dart' show FleuryError;
export 'foundation/geometry.dart' show CellSize, CellOffset, CellRect;
export 'foundation/key.dart' show Key, LocalKey, ValueKey, UniqueKey;

// App kernel
export 'app/app.dart'
    show
        AppStatusBuilder,
        FleuryApp,
        FleuryAppController,
        FleuryAppExtension,
        FleuryAppScope,
        FleuryCommandContext;
export 'app/commands.dart'
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
export 'app/status.dart'
    show AppStatusBar, StatusController, StatusItem, StatusSeverity;

// Editing
export 'editing/text_completion.dart'
    show TextCompletionController, TextCompletionOption, TextCompletionState;
export 'editing/text_editing.dart'
    show TextEditingModel, TextEditingValue, TextRange, TextSelection;
export 'editing/text_edit_policy.dart' show TextEditPolicy, TextEditRejection;
export 'editing/text_history.dart' show TextHistoryController;
export 'editing/text_keymap.dart'
    show TextEditingKeyAction, TextEditingKeyBinding, TextEditingKeymap;
export 'editing/text_paste.dart'
    show TextPastePolicy, TextPasteProgress, TextPasteSession;

// Animation
export 'animation/animation_policy.dart' show AnimationPolicy;
export 'animation/clock.dart' show Clock, SystemClock;
export 'animation/curves.dart' show Curve, Curves;
export 'animation/frame_ticker.dart' show FrameTicker;
export 'animation/lerp.dart'
    show DiscreteLerp, Lerp, doubleLerp, intLerp, rgbColorLerp;
export 'animation/animation.dart' show Animation, AnimationType;
export 'animation/spring.dart' show Spring;
export 'animation/ticker.dart' show Ticker, TickerCallback, TickerProvider;
export 'animation/ticker_future.dart' show TickerCanceled, TickerFuture;
export 'animation/ticker_scheduler.dart'
    show FrameCallback, SchedulerTickCallback, TickerScheduler;

// Rendering
export 'rendering/ansi_renderer.dart'
    show AnsiRenderer, AnsiSink, StringAnsiSink, quantizeColor;
export 'rendering/border.dart' show BorderGlyphs, BorderStyle, BoxBorder;
export 'rendering/cell.dart'
    show
        AnsiColor,
        Cell,
        CellRole,
        CellStyle,
        Color,
        Colors,
        IndexedColor,
        RgbColor;
export 'rendering/geometry.dart'
    show RenderGeometry, ScreenGeometrySource, renderSubtree;
export 'rendering/cell_buffer.dart'
    show
        CellBuffer,
        InlineImage,
        InlineImageFit,
        InlineImagePlacement,
        ResolvedImageFit,
        resolveClippedInlineImageFit,
        resolveInlineImageFit;
export 'rendering/edge_insets.dart' show EdgeInsets;
export 'rendering/layout.dart' show CellConstraints;
export 'rendering/link_scheme.dart' show isSafeLinkScheme, kSafeLinkSchemes;
export 'rendering/render_flex.dart'
    show
        Axis,
        CrossAxisAlignment,
        FlexFit,
        MainAxisAlignment,
        MainAxisSize,
        RenderFlex,
        RenderFlexible;
export 'rendering/render_object.dart'
    show
        ParentData,
        RenderObject,
        RenderObjectWithChildren,
        RenderObjectWithSingleChild;
export 'rendering/render_repaint_boundary.dart' show RenderRepaintBoundary;
export 'rendering/width_policy.dart'
    show
        CellWidth,
        CellWidthPolicy,
        ClusterLowering,
        ResolvedTextPresentationPolicy,
        TextPresentationPolicy,
        WidthAxis,
        WidthDecisionSource;
export 'rendering/surface_capabilities.dart'
    show
        ColorMode,
        GlyphTier,
        InlineImageSupport,
        PointerPrecision,
        SurfaceCapabilities;
export 'rendering/render_objects.dart'
    show
        RenderBorder,
        RenderPadding,
        RenderSizedBox,
        RenderText,
        TextAlign,
        TextOverflow;
export 'rendering/render_stack.dart'
    show RenderPositioned, RenderStack, RenderIndexedStack, StackFit;
export 'rendering/render_wrap.dart' show RenderWrap;
export 'rendering/text_sanitizer.dart'
    show
        isSanitizedForDisplay,
        isSanitizedMultiline,
        isUnsafeRune,
        replacementCharacter,
        sanitizeForDisplay,
        sanitizeMultiline,
        sanitizeSingleLine;
export 'rendering/width_resolver.dart'
    show DefaultWidthResolver, WidthResolver, hasUncertainWidth;

// Semantics
export 'semantics/accessibility.dart'
    show
        AccessibilityNode,
        AccessibilitySnapshot,
        AccessibilitySnapshotSummary,
        SemanticTreeAccessibility,
        buildAccessibilitySnapshot;
export 'semantics/inspection.dart'
    show
        SemanticInspectionNode,
        SemanticInspectionSnapshot,
        SemanticTreeInspection;
export 'semantics/semantic_coercion.dart'
    show coerceSemanticBool, coerceSemanticInt, coerceSemanticNum;
export 'semantics/semantics.dart'
    show
        SemanticAction,
        SemanticActionCallback,
        SemanticActionContributor,
        SemanticActionDeclined,
        SemanticChildrenProvider,
        SemanticContributor,
        SemanticNode,
        SemanticNodeId,
        SemanticRole,
        humanizeSemanticRoleName,
        isValidSemanticRoleName,
        SemanticSetValueCallback,
        SemanticState,
        SemanticTree,
        SemanticQueryError,
        SemanticValueContributor,
        Semantics,
        ExcludeSemantics,
        escapeSemanticIdSegment,
        isPositionalSemanticId,
        semanticAnchorOf;

// Terminal
export 'terminal/capabilities.dart'
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
        evidencedAmbiguousCharWidth,
        parseEnvFlag;
export 'terminal/capability_requirements.dart'
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
export 'terminal/diagnostics.dart'
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
export 'terminal/terminal_probe.dart'
    show
        WidthMeasurements,
        WidthProbeClass,
        WidthProbeGlyph,
        widthProbeBattery,
        TerminalProbeReport,
        TerminalProbeResult,
        TerminalProbeStatus,
        TerminalProbeTransport,
        probeGlyphWidths,
        runTerminalProbeSuite;
export 'input/events.dart'
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
export 'input/key_tables.dart' show positionByDomCode;
export 'input/keyboard_layout.dart'
    show KeyLabel, KeyLabelSource, KeyboardLayout;
export 'input/keyboard_state.dart' show KeyboardCapabilities, KeyboardSnapshot;
export 'terminal/fake_driver.dart' show FakeTerminalDriver;
export 'terminal/input_parser.dart' show InputParser, TuiEventSink;
export 'terminal/legacy_key_sequences.dart' show LegacyKeySequence;
export 'terminal/terminal_response.dart'
    show
        TerminalResponse,
        TerminalResponseExpectation,
        TerminalResponseKind,
        TerminalResponseSink;
export 'runtime/remote_surface_sink.dart'
    show
        RemoteClipboardStatus,
        RemoteDebugRequestHandler,
        RemoteSemanticActionHandler,
        RemoteSurfaceSink;
export 'terminal/terminal_driver.dart'
    show
        OutputFlowControl,
        AnsiTerminalPresentation,
        StructuredTerminalPresentation,
        TerminalAttentionDriver,
        TerminalDriver,
        TerminalHandoffDriver,
        InlineTerminalDriver,
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
export 'widgets/focus.dart'
    show
        CaretHost,
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
export 'widgets/focus_traversal.dart'
    show FocusTraversalGroup, TraversalDirection, nearestFocusableInDirection;
export 'widgets/intrinsic.dart' show IntrinsicHeight, IntrinsicWidth;
export 'widgets/keyboard.dart'
    show Keyboard, KeyboardScope, KeyboardStateNotifier, KeyDetector;
export 'widgets/key_bindings.dart'
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
export 'widgets/list_view.dart'
    show EdgeBehavior, ListController, ListItemKeyBuilder, ListView;
export 'widgets/navigator.dart'
    show Navigator, NavigatorContext, NavigatorState, PopScope, RouteTransition;
export 'widgets/layout_builder.dart' show LayoutBuilder, LayoutWidgetBuilder;
export 'widgets/media_query.dart' show MediaQuery, MediaQueryData;
export 'widgets/overlay.dart'
    show Overlay, OverlayEntry, OverlayMount, OverlayState;
export 'widgets/repaint_boundary.dart' show RepaintBoundary;
export 'widgets/rich_text.dart' show RichText, TextSpan;
export 'widgets/pointer.dart'
    show
        AbsorbPointer,
        GestureDetector,
        MouseRegion,
        MouseCursor,
        PointerRouter,
        PointerRouterScope,
        PointerCallback,
        PointerDetails,
        PointerDragCallback,
        PointerDragDetails,
        PointerScrollCallback,
        PointerScrollDetails,
        PointerTapCallback;
export 'widgets/scroll_view.dart' show ScrollController, ScrollView;
export 'widgets/scrollbar.dart' show Scrollbar;
export 'widgets/blinking_cursor.dart' show BlinkingCursor;
export 'widgets/clipboard_scope.dart' show ClipboardScope;
export 'widgets/error_boundary.dart'
    show ErrorBoundary, FrameContainmentError, FrameContainmentPhase;
export 'widgets/frame_builder.dart' show FrameBuilder;
export 'widgets/animation_builder.dart' show AnimationBuilder;
export 'widgets/effects.dart'
    show Animate, AnimateExtension, Edge, Effect, Effects;
export 'widgets/animated_visibility.dart' show AnimatedVisibility;
export 'widgets/selection/selectable.dart'
    show Selectable, SelectionRegistrant, SelectionRegistrar, SelectionScope;
export 'widgets/selection/selection.dart'
    show Selection, SelectedContent, SelectionGeometry, SelectionStatus;
export 'runtime/clipboard.dart'
    show
        Clipboard,
        ClipboardWritePolicy,
        ClipboardWriteReport,
        ClipboardWriteResult,
        InProcessClipboard;
// The captured-output record and its views. Capture itself is native; the
// buffer is plain data, so browser apps can feed one (a streamed build log,
// a remote process) and show it with the same widgets.
export 'runtime/output_capture.dart' show LogBuffer, LogLine, LogSource;
export 'widgets/output_capture_view.dart'
    show LogBufferScope, OutputCaptureConsole, OutputCaptureView;
export 'widgets/selection/selection_area.dart'
    show SelectionArea, SelectionChangedCallback;
export 'widgets/selection/selection_container_delegate.dart'
    show SelectionContainerDelegate;
export 'widgets/selection/selection_event.dart'
    show
        SelectionClearEvent,
        SelectionEdgeUpdateEvent,
        SelectionEvent,
        SelectionGranularEvent,
        SelectionGranularity,
        SelectionResult;
export 'widgets/button.dart' show Button, ButtonAppearance, ButtonVariant;
export 'widgets/spinner.dart' show Spinner, SpinnerStyle;
export 'widgets/text_area.dart' show TextArea;
export 'widgets/text_input.dart'
    show
        TextClipboardPolicy,
        TextEditingController,
        TextEditingPaste,
        TextInput;
export 'widgets/ticker_mode.dart' show TickerMode;
export 'widgets/theme.dart'
    show
        Brightness,
        BrightnessPick,
        ColorScheme,
        DefaultTextStyle,
        FleuryThemeContext,
        Theme,
        ThemeData;
export 'widgets/tui_binding.dart'
    show SingleTickerProviderStateMixin, TuiBinding, TuiBindingScope;
export 'widgets/align.dart' show Align, Alignment, Center, RenderAlign;
export 'widgets/anchored.dart' show Anchored, AnchoredFloat;
export 'widgets/bounds.dart'
    show
        BoundsAnchor,
        BoundsNotifier,
        BoundsObserver,
        defaultAnchorAlignment,
        resolveAnchoredOffset;
export 'widgets/async.dart'
    show
        AsyncSnapshot,
        AsyncWidgetBuilder,
        ConnectionState,
        FutureBuilder,
        StreamBuilder;
export 'widgets/terminal_session.dart';
export 'widgets/basic.dart'
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
export 'widgets/framework.dart'
    show
        BuildContext,
        BuildOwner,
        ComponentElement,
        Element,
        GlobalKey,
        LeafRenderObjectElement,
        LeafRenderObjectWidget,
        MultiChildRenderObjectElement,
        MultiChildRenderObjectWidget,
        ProxyWidget,
        RenderObjectElement,
        RenderObjectWidget,
        Scope,
        ScopeElement,
        SingleChildRenderObjectElement,
        SingleChildRenderObjectWidget,
        State,
        StatefulElement,
        StatefulWidget,
        StatelessElement,
        StatelessWidget,
        VoidCallback,
        Widget;

export 'widgets/notifier_builder.dart' show NotifierBuilder;
export 'widgets/scope.dart' show ScopeBuilder;
