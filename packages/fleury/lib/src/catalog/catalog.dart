/// Composed Fleury widgets, grouped for a possible future extraction.
library;

export 'autocomplete.dart' show Autocomplete;
export 'approval_prompt.dart'
    show ApprovalDecision, ApprovalPrompt, ApprovalRequest, ApprovalSeverity;
export 'bar_chart.dart' show Bar, BarChart;
export 'calendar_heatmap.dart' show CalendarHeatmap, CalendarWeekStart;
export 'canvas.dart'
    show Canvas, CanvasBounds, CanvasContext, CanvasMarker, CanvasPainter;
export 'color_picker.dart' show ColorPicker;
export 'command_button.dart' show CommandButton;
export 'command_palette.dart' show CommandPalette, CommandPaletteItem;
export 'component_theme.dart' show FleuryWidgetTheme;
export 'completion_text_input.dart'
    show
        CompletionTextInput,
        TextCompletionProvider,
        TextCompletionRequest,
        TextCompletionRequestBuilder,
        defaultTextCompletionRequest;
export 'controls.dart'
    show
        Button,
        ButtonAppearance,
        ButtonVariant,
        Checkbox,
        Radio,
        RadioGroup,
        RadioOption,
        Switch,
        Toggle;
export 'conversation_navigator.dart'
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
export 'context_panel.dart'
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
export 'code_view.dart'
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
export 'date_picker.dart' show DatePicker;
export 'data_table.dart'
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
export 'dialog.dart' show Dialog;
export 'diff_view.dart'
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
export 'file_browser.dart'
    show
        FileBrowser,
        FileBrowserController,
        FileBrowserCopyOptions,
        FileBrowserCopyResult,
        FileBrowserFilterDescriptor,
        buildFileBrowserEntryOrder,
        exportFileBrowserEntry;
export 'file_mention_picker.dart'
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
export 'file_picker.dart' show FilePicker;
export 'file_source.dart'
    show
        FileEntry,
        FileEntryFilter,
        FileEntryType,
        FileSource,
        FileSourceException,
        MemoryFileSource;
export 'form.dart' show FormController, Form, FormField, FormFieldState;
export 'digits.dart' show Digits;
export 'gauge.dart' show Gauge;
export 'heatmap.dart' show Heatmap;
export 'histogram.dart' show Histogram;
export 'image.dart' show Image, ImageFit, ImageGlyph, ImageSource;
export 'area_chart.dart' show AreaChart, AreaSeries;
export 'line_chart.dart'
    show
        LineChart,
        LineSeries,
        LineType,
        Palettes,
        ReferenceLine,
        ReferenceStyle,
        TickFormat,
        TickFormatter;
export 'log_region.dart'
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
export 'message_list.dart'
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
export 'model_status_bar.dart'
    show
        ModelRuntimeStatus,
        ModelStatusBar,
        ModelStatusInfo,
        TokenMeter,
        TokenUsage;
export 'json_view.dart'
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
export 'key_hint_bar.dart' show KeyHintBar;
export 'semantic_roles.dart' show WidgetRoles;
export 'which_key.dart' show WhichKey;
export 'markdown_text.dart'
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
export 'menu.dart' show Menu, MenuEntry, MenuItem, MenuSeparator, SubMenu;
export 'number_input.dart' show NumberInput;
export 'patch_review.dart'
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
export 'panel.dart' show Panel;
export 'password_input.dart' show PasswordInput;
export 'progress_bar.dart' show ProgressBar;
export 'range_slider.dart' show RangeSlider;
export 'search_panel.dart'
    show
        SearchPanel,
        SearchPanelCopyOptions,
        SearchPanelCopyResult,
        SearchResult,
        SearchResultIndex,
        SearchResultMatcher,
        buildSearchResultOrder,
        exportSearchResult;
export 'select.dart' show MultiSelect, Select, SelectOption;
export 'sparkline.dart' show Sparkline;
export 'stepper.dart' show Stepper;
export 'table.dart'
    show
        FixedColumnWidth,
        FlexColumnWidth,
        IntrinsicColumnWidth,
        Table,
        TableColumnWidth,
        TableController,
        TableCopyOptions,
        TableCopyResult,
        TableExportFormat,
        TableExportOptions,
        TableExportResult,
        exportTableRows,
        tableCellText;
export 'terminal_output_region.dart'
    show TerminalOutputRegion, buildTerminalOutputLogEntries;
export 'task_graph.dart'
    show
        TaskGraph,
        TaskGraphController,
        TaskGraphCopyOptions,
        TaskGraphCopyResult,
        TaskGraphNode,
        TaskGraphStatus,
        exportTaskGraphNode;
export 'trace_timeline.dart'
    show
        TraceTimeline,
        TraceTimelineController,
        TraceTimelineCopyOptions,
        TraceTimelineCopyResult,
        TraceTimelineEntry,
        TraceTimelineKind,
        TraceTimelineSelectResult,
        TraceTimelineStatus,
        exportTraceTimelineEntry;
export 'tool_call_card.dart'
    show
        ToolCallCard,
        ToolCallCopyOptions,
        ToolCallCopyResult,
        ToolCallRecord,
        ToolCallStatus,
        exportToolCallSummary;
export 'workflow_snapshot.dart'
    show WorkflowHealth, WorkflowSnapshot, WorkflowSummary;
export 'tabs.dart' show TabController, TabItem, Tabs;
export 'toaster.dart' show Toaster, ToastAction, ToastHandle, ToastSeverity;
export 'tooltip.dart' show Tooltip;
export 'tree.dart' show Tree, TreeNode;
export 'tree_table.dart'
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
