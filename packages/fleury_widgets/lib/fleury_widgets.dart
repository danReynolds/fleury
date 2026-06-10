/// Batteries-included widgets for fleury.
///
/// A sister library to `fleury`: opinionated, composable widgets —
/// tabs, tables, trees, menus, form controls, and more — built entirely
/// on the core primitives (layout, focus, keybindings, overlay,
/// scrolling, anchoring). The core stays lean and terminal-true; this is
/// where the higher-level patterns live.
library;

export 'src/autocomplete.dart' show Autocomplete;
export 'src/approval_prompt.dart'
    show ApprovalDecision, ApprovalPrompt, ApprovalRequest, ApprovalSeverity;
export 'src/bar_chart.dart' show Bar, BarChart;
export 'src/calendar_heatmap.dart' show CalendarHeatmap, CalendarWeekStart;
export 'src/canvas.dart'
    show Canvas, CanvasBounds, CanvasContext, CanvasMarker, CanvasPainter;
export 'src/color_picker.dart' show ColorPicker;
export 'src/command_palette.dart' show Command, CommandPalette;
export 'src/component_theme.dart' show FleuryWidgetTheme;
export 'src/completion_text_input.dart'
    show
        CompletionTextInput,
        TextCompletionProvider,
        TextCompletionRequest,
        TextCompletionRequestBuilder,
        defaultTextCompletionRequest;
export 'src/controls.dart'
    show Button, ButtonVariant, Checkbox, Radio, Switch, Toggle;
export 'src/conversation_navigator.dart'
    show
        ConversationEntry,
        ConversationMatcher,
        ConversationNavigator,
        ConversationNavigatorController,
        ConversationNavigatorCopyOptions,
        ConversationNavigatorCopyResult,
        ConversationNavigatorSelectResult,
        ConversationStatus,
        buildConversationOrder,
        exportConversation;
export 'src/context_panel.dart'
    show
        ContextItem,
        ContextItemKind,
        ContextItemPriority,
        ContextPanel,
        ContextPanelController,
        ContextPanelCopyOptions,
        ContextPanelCopyResult,
        ContextPanelSelectResult,
        exportContextItem;
export 'src/code_view.dart'
    show
        CodeDocument,
        CodeLine,
        CodeLineKind,
        CodeView,
        CodeViewController,
        CodeViewCopyMode,
        CodeViewCopyOptions,
        CodeViewCopyResult,
        exportCodeSelection,
        parseCodeDocument;
export 'src/date_picker.dart' show DatePicker;
export 'src/data_table.dart'
    show
        DataTable,
        DataTableCellBuilder,
        DataTableColumn,
        DataTableController,
        DataTableCopyOptions,
        DataTableCopyResult,
        DataTableFilterDescriptor,
        DataTableExportFormat,
        DataTableExportOptions,
        DataTableExportResult,
        DataTableRowKeyBuilder,
        DataTableSelectionMode,
        DataTableSelectionRange,
        DataTableSortDescriptor,
        DataTableSortDirection,
        DataTableViewportMetrics,
        buildDataTableRowOrder,
        exportDataTableRows;
export 'src/dialog.dart' show Dialog;
export 'src/diff_view.dart'
    show
        DiffDocument,
        DiffLine,
        DiffLineKind,
        DiffView,
        DiffViewController,
        DiffViewCopyMode,
        DiffViewCopyOptions,
        DiffViewCopyResult,
        exportDiffSelection,
        parseUnifiedDiff;
export 'src/file_browser.dart'
    show
        FileBrowser,
        FileBrowserController,
        FileBrowserCopyOptions,
        FileBrowserCopyResult,
        FileBrowserEntityFilter,
        FileBrowserEntry,
        FileBrowserEntryType,
        FileBrowserFilterDescriptor,
        buildFileBrowserEntryOrder,
        exportFileBrowserEntry;
export 'src/file_mention_picker.dart'
    show
        FileMentionCopyOptions,
        FileMentionCopyResult,
        FileMentionEntry,
        FileMentionKind,
        FileMentionMatcher,
        FileMentionPickResult,
        FileMentionPicker,
        FileMentionPickerController,
        buildFileMentionOrder,
        exportFileMention;
export 'src/file_picker.dart' show FilePicker;
export 'src/form.dart'
    show
        FormController,
        FormDefinition,
        FormFieldSnapshot,
        FormFieldAsyncValidator,
        FormFieldSpec,
        FormFieldType,
        FormFieldValidator,
        FormOption,
        FormPanel,
        FormPanelLayout,
        FormPathKind,
        FormPrompt,
        FormPromptSession,
        FormSnapshot,
        FormSubmitResult,
        FormValues,
        FormWizard,
        FormWizardController,
        FormWizardStep;
export 'src/digits.dart' show Digits;
export 'src/gauge.dart' show Gauge;
export 'src/heatmap.dart' show Heatmap;
export 'src/histogram.dart' show Histogram;
export 'src/image.dart' show Image, ImageFit, ImageGlyph, ImageSource;
export 'src/line_chart.dart'
    show
        LineChart,
        LineSeries,
        LineType,
        Palettes,
        ReferenceLine,
        ReferenceStyle,
        TickFormat,
        TickFormatter;
export 'src/log_region.dart'
    show
        LogEntry,
        LogRegion,
        LogRegionController,
        LogRegionCopyOptions,
        LogRegionCopyResult,
        LogRegionExportOptions,
        LogRegionExportResult,
        LogRegionFilterDescriptor,
        LogRegionSearchIndex,
        LogSeverity,
        buildLogRegionEntryOrder,
        exportLogEntries;
export 'src/message_list.dart'
    show
        MessageEntry,
        MessageList,
        MessageListController,
        MessageListCopyOptions,
        MessageListCopyResult,
        MessageListExportOptions,
        MessageListExportResult,
        MessageRole,
        MessageStatus,
        exportMessages;
export 'src/model_status_bar.dart'
    show
        ModelRuntimeStatus,
        ModelStatusBar,
        ModelStatusInfo,
        TokenMeter,
        TokenUsage;
export 'src/json_view.dart'
    show
        JsonValueType,
        JsonView,
        JsonViewController,
        JsonViewCopyMode,
        JsonViewCopyOptions,
        JsonViewCopyResult,
        JsonViewDocument,
        JsonViewRow,
        buildJsonViewRows,
        exportJsonViewRow;
export 'src/markdown_text.dart'
    show
        MarkdownBlock,
        MarkdownBlockKind,
        MarkdownDocument,
        MarkdownLink,
        MarkdownText,
        MarkdownView,
        MarkdownViewController,
        MarkdownViewCopyMode,
        MarkdownViewCopyOptions,
        MarkdownViewCopyResult,
        exportMarkdownSelection,
        parseMarkdownDocument;
export 'src/menu.dart' show Menu, MenuEntry, MenuItem, MenuSeparator, SubMenu;
export 'src/number_input.dart' show NumberInput;
export 'src/patch_review.dart'
    show
        PatchReview,
        PatchReviewController,
        PatchReviewCopyOptions,
        PatchReviewCopyResult,
        PatchReviewFile,
        PatchReviewFileSelectResult,
        PatchReviewStatus,
        buildPatchReviewFiles,
        exportPatchReviewFile;
export 'src/password_input.dart' show PasswordInput;
export 'src/progress_bar.dart' show ProgressBar;
export 'src/process_panel.dart' show ProcessPanel, buildProcessOutputLogEntries;
export 'src/range_slider.dart' show RangeSlider;
export 'src/search_panel.dart'
    show
        SearchPanel,
        SearchPanelCopyOptions,
        SearchPanelCopyResult,
        SearchResult,
        SearchResultIndex,
        SearchResultMatcher,
        buildSearchResultOrder,
        exportSearchResult;
export 'src/select.dart' show MultiSelect, Select, SelectOption;
export 'src/sparkline.dart' show Sparkline;
export 'src/stepper.dart' show Stepper;
export 'src/table.dart'
    show
        FixedColumnWidth,
        FlexColumnWidth,
        IntrinsicColumnWidth,
        Table,
        TableColumnWidth,
        TableController;
export 'src/terminal_output_region.dart'
    show TerminalOutputRegion, buildTerminalOutputLogEntries;
export 'src/task_graph.dart'
    show
        TaskGraph,
        TaskGraphController,
        TaskGraphCopyOptions,
        TaskGraphCopyResult,
        TaskGraphNode,
        TaskGraphStatus,
        exportTaskGraphNode;
export 'src/trace_timeline.dart'
    show
        TraceTimeline,
        TraceTimelineController,
        TraceTimelineCopyOptions,
        TraceTimelineCopyResult,
        TraceTimelineEntry,
        TraceTimelineKind,
        TraceTimelineSelectResult,
        TraceTimelineStatus,
        exportTraceTimelineEntry,
        traceTimelineEntriesForTaskEvents,
        traceTimelineEntryForTaskEvent;
export 'src/tool_call_card.dart'
    show
        ToolCallCard,
        ToolCallCopyOptions,
        ToolCallCopyResult,
        ToolCallRecord,
        ToolCallStatus,
        exportToolCallSummary;
export 'src/workflow_snapshot.dart'
    show WorkflowHealth, WorkflowSnapshot, WorkflowSummary;
export 'src/tabs.dart' show TabController, TabItem, Tabs;
export 'src/toaster.dart' show Toaster, ToastAction, ToastSeverity;
export 'src/tooltip.dart' show Tooltip;
export 'src/tree.dart' show Tree, TreeNode;
export 'src/tree_table.dart'
    show
        TreeTable,
        TreeTableCellBuilder,
        TreeTableController,
        TreeTableCopyOptions,
        TreeTableCopyResult,
        TreeTableExportOptions,
        TreeTableExportResult,
        TreeTableFilterDescriptor,
        TreeTableFilterMode,
        TreeTableNode,
        TreeTableRow,
        TreeTableSearchIndex,
        buildTreeTableRows,
        exportTreeTableRows;
