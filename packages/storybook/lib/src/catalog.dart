import 'dart:io' as io;
import 'dart:math' as math;

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:image/image.dart' as img;

import 'story.dart';

final List<Story> storybookStories = _perWidgetStories(<Story>[
  Story(
    id: 'core.layout-text',
    title: 'Core Layout and Text',
    category: 'Core',
    description:
        'Framework primitives for composing terminal UI: styled text, rich text, rows, columns, padding, sizing, and borders.',
    widgets: const <String>[
      'Text',
      'RichText',
      'TextSpan',
      'Column',
      'Row',
      'Container',
      'Padding',
      'SizedBox',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'border',
        label: 'Border',
        options: <String>['Rounded', 'None'],
      ),
      StoryControl.text(
        id: 'label',
        label: 'Label',
        initialText: 'Centered in fixed cells',
        placeholder: 'Preview label',
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'plain',
        label: 'Plain cells',
        description: 'Layout primitives without a border frame.',
        controlValues: <String, Object?>{'border': 1},
      ),
      StoryVariant(
        id: 'long-label',
        label: 'Long label',
        description: 'Wrapping and clipping around longer text.',
        controlValues: <String, Object?>{
          'label': 'A longer storybook label constrained by fixed cells',
        },
      ),
    ],
    builder: (context) => _CoreLayoutStory(
      showBorder: context.option('border') == 'Rounded',
      label: context.text('label'),
      selectedWidgetName: context.selectedWidgetName,
    ),
  ),
  Story(
    id: 'core.selection-scroll',
    title: 'Selection, Lists, and Scroll',
    category: 'Core',
    description:
        'Selectable text, scroll containers, and lazy list navigation for longer terminal surfaces.',
    widgets: const <String>[
      'SelectionArea',
      'ScrollView',
      'ListView',
      'ListController',
    ],
    initialHeight: 16,
    builder: (context) =>
        _SelectionScrollStory(selectedWidgetName: context.selectedWidgetName),
  ),
  Story(
    id: 'controls.boolean-buttons',
    title: 'Buttons and Boolean Controls',
    category: 'Input',
    description:
        'Focusable activation controls for actions, binary settings, and single-choice options.',
    widgets: const <String>['Button', 'Checkbox', 'Toggle', 'Switch', 'Radio'],
    controls: const <StoryControl>[
      StoryControl.toggle(id: 'disabled', label: 'Disabled controls'),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'disabled',
        label: 'Disabled',
        description: 'All controls render in disabled state.',
        controlValues: <String, Object?>{'disabled': 1},
      ),
    ],
    builder: (context) => _ControlsStory(
      disabled: context.enabled('disabled'),
      onAction: context.action,
    ),
  ),
  Story(
    id: 'controls.select',
    title: 'Select and Multi-Select',
    category: 'Input',
    description:
        'Single-value dropdown selection and keyboard-navigable multi-select lists.',
    widgets: const <String>['Select', 'SelectOption', 'MultiSelect'],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'size',
        label: 'Option set',
        options: <String>['Small', 'With disabled'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'disabled-options',
        label: 'Disabled options',
        description: 'Includes disabled select and multi-select options.',
        controlValues: <String, Object?>{'size': 1},
      ),
    ],
    builder: (context) => _SelectionInputsStory(
      withDisabled: context.option('size') == 'With disabled',
      onAction: context.action,
    ),
  ),
  Story(
    id: 'controls.text-entry',
    title: 'Text Entry and Completion',
    category: 'Input',
    description:
        'Single-line, multi-line, numeric, secret, autocomplete, and completion-backed text input.',
    widgets: const <String>[
      'TextInput',
      'TextArea',
      'NumberInput',
      'PasswordInput',
      'Autocomplete',
      'CompletionTextInput',
    ],
    initialHeight: 17,
    builder: (context) => _TextEntryStory(onAction: context.action),
  ),
  // Each picker is its own 1:1 story — selecting it previews just that widget,
  // with controls scoped to it (the calendar-week option only on DatePicker).
  Story(
    id: 'input.date-picker',
    title: 'DatePicker',
    category: 'Input',
    description: 'Keyboard calendar with a configurable week start.',
    widgets: const <String>['DatePicker'],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'calendar',
        label: 'Calendar week',
        options: <String>['Sunday', 'Monday'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'monday-week',
        label: 'Monday week',
        description: 'Calendar starts on Monday for locale-sensitive layouts.',
        controlValues: <String, Object?>{'calendar': 1},
      ),
    ],
    initialHeight: 16,
    builder: (context) => _PickerStory(
      only: 'DatePicker',
      weekStartsOn: context.option('calendar') == 'Monday'
          ? CalendarWeekStart.monday
          : CalendarWeekStart.sunday,
      onAction: context.action,
    ),
  ),
  Story(
    id: 'input.color-picker',
    title: 'ColorPicker',
    category: 'Input',
    description: 'Swatch grid with keyboard selection.',
    widgets: const <String>['ColorPicker'],
    initialHeight: 8,
    builder: (context) =>
        _PickerStory(only: 'ColorPicker', onAction: context.action),
  ),
  Story(
    id: 'input.range-slider',
    title: 'RangeSlider',
    category: 'Input',
    description: 'Dual-handle numeric range with keyboard control.',
    widgets: const <String>['RangeSlider'],
    initialHeight: 6,
    builder: (context) =>
        _PickerStory(only: 'RangeSlider', onAction: context.action),
  ),
  Story(
    id: 'input.stepper',
    title: 'Stepper',
    category: 'Input',
    description: 'Numeric stepper with min/max and large steps.',
    widgets: const <String>['Stepper'],
    initialHeight: 5,
    builder: (context) =>
        _PickerStory(only: 'Stepper', onAction: context.action),
  ),
  Story(
    id: 'visualization.progress-bar',
    title: 'ProgressBar',
    category: 'Visualization',
    description: 'Determinate task progress bar.',
    widgets: const <String>['ProgressBar'],
    initialHeight: 5,
    builder: (context) =>
        _PickerStory(only: 'ProgressBar', onAction: context.action),
  ),
  Story(
    id: 'visualization.gauge',
    title: 'Gauge',
    category: 'Visualization',
    description: 'Labelled status gauge.',
    widgets: const <String>['Gauge'],
    initialHeight: 5,
    builder: (context) =>
        _PickerStory(only: 'Gauge', onAction: context.action),
  ),
  Story(
    id: 'overlays.commands',
    title: 'Menus, Palette, and Overlays',
    category: 'Navigation',
    description:
        'Anchored and modal overlay patterns for command surfaces, menus, toasts, dialogs, and tooltips.',
    widgets: const <String>[
      'CommandPalette',
      'Menu',
      'MenuItem',
      'SubMenu',
      'Dialog',
      'Toaster',
      'Tooltip',
    ],
    initialHeight: 13,
    builder: (_) => const _OverlayStory(),
  ),
  Story(
    id: 'navigation.tabs',
    title: 'Tabs',
    category: 'Navigation',
    description:
        'Mounted tab panels with keyboard tab-strip navigation and stateful content.',
    widgets: const <String>['Tabs', 'TabItem', 'TabController'],
    initialHeight: 14,
    builder: (_) => const _TabsStory(),
  ),
  Story(
    id: 'data.tables',
    title: 'Tables',
    category: 'Data',
    description:
        'Small widget-composed tables and larger virtualized text tables with row or cell selection.',
    widgets: const <String>[
      'Table',
      'TableController',
      'DataTable',
      'DataTableColumn',
      'DataTableController',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'selection',
        label: 'Data selection',
        options: <String>['Rows', 'Cells'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'cell-selection',
        label: 'Cell selection',
        description: 'Exercises cell-focused table navigation.',
        controlValues: <String, Object?>{'selection': 1},
      ),
    ],
    initialHeight: 18,
    builder: (context) =>
        _TablesStory(cellMode: context.option('selection') == 'Cells'),
  ),
  Story(
    id: 'data.trees',
    title: 'Trees and Tree Tables',
    category: 'Data',
    description:
        'Hierarchical navigation for nested data and expandable table rows.',
    widgets: const <String>[
      'Tree',
      'TreeNode',
      'TreeTable',
      'TreeTableNode',
      'TreeTableController',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'filter',
        label: 'Tree-table filter',
        options: <String>['All', 'Runtime only'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'runtime-filter',
        label: 'Runtime filter',
        description: 'Filtered tree-table view with ancestors preserved.',
        controlValues: <String, Object?>{'filter': 1},
      ),
    ],
    initialHeight: 18,
    builder: (context) =>
        _TreesStory(runtimeOnly: context.option('filter') == 'Runtime only'),
  ),
  Story(
    id: 'forms.panels',
    title: 'Forms and Wizards',
    category: 'Forms',
    description:
        'Declarative field specs, inline forms, and multi-step form flows.',
    widgets: const <String>[
      'FormDefinition',
      'FormFieldSpec',
      'FormPanel',
      'FormWizard',
      'FormWizardStep',
      'FormController',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'layout',
        label: 'View',
        options: <String>['Panel', 'Wizard'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'wizard',
        label: 'Wizard',
        description: 'Multi-step form layout instead of inline panel.',
        controlValues: <String, Object?>{'layout': 1},
      ),
    ],
    initialHeight: 20,
    builder: (context) =>
        _FormsStory(wizard: context.option('layout') == 'Wizard'),
  ),
  Story(
    id: 'visualization.charts',
    title: 'Charts and Status Visualizations',
    category: 'Visualization',
    description:
        'Terminal-native charts for distributions, time series, heatmaps, gauges, sparklines, and large digits.',
    widgets: const <String>[
      'BarChart',
      'LineChart',
      'Sparkline',
      'Histogram',
      'Heatmap',
      'CalendarHeatmap',
      'Gauge',
      'Digits',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'mode',
        label: 'Chart mode',
        options: <String>['Dashboard', 'Distribution'],
      ),
      StoryControl.toggle(id: 'interactive', label: 'Interactive line'),
      StoryControl.number(
        id: 'samples',
        label: 'Samples',
        initialNumber: 8,
        min: 4,
        max: 16,
        step: 1,
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'distribution',
        label: 'Distribution',
        description: 'Histogram-first chart layout.',
        controlValues: <String, Object?>{'mode': 1},
      ),
      StoryVariant(
        id: 'dense-interactive',
        label: 'Dense interactive',
        description: 'More samples with line-chart cursor interaction enabled.',
        controlValues: <String, Object?>{'interactive': 1, 'samples': 16},
      ),
    ],
    initialHeight: 20,
    builder: (context) => _ChartsStory(
      distribution: context.option('mode') == 'Distribution',
      interactiveLine: context.enabled('interactive'),
      selectedWidgetName: context.selectedWidgetName ?? context.story.title,
      samples: context.number('samples').round(),
    ),
  ),
  Story(
    id: 'visualization.canvas-image',
    title: 'Canvas and Image',
    category: 'Visualization',
    description:
        'Lower-level render surfaces for custom braille/quadrant drawing and ANSI image previews.',
    widgets: const <String>[
      'Canvas',
      'CanvasPainter',
      'CanvasBounds',
      'Image',
      'ImageSource',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'marker',
        label: 'Canvas marker',
        options: <String>['Braille', 'Quadrant', 'Half block'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'quadrant',
        label: 'Quadrant marker',
        description: 'Uses quadrant block plotting.',
        controlValues: <String, Object?>{'marker': 1},
      ),
      StoryVariant(
        id: 'half-block',
        label: 'Half block marker',
        description: 'Uses half-block plotting.',
        controlValues: <String, Object?>{'marker': 2},
      ),
    ],
    initialHeight: 16,
    builder: (context) =>
        _CanvasImageStory(marker: _canvasMarker(context.option('marker'))),
  ),
  Story(
    id: 'files.pickers',
    title: 'File Surfaces',
    category: 'Files',
    description:
        'Filesystem browsing, file picking, and @mention-style file target selection.',
    widgets: const <String>[
      'FileBrowser',
      'FilePicker',
      'FileMentionPicker',
      'FileMentionEntry',
    ],
    controls: const <StoryControl>[
      StoryControl.toggle(id: 'hidden', label: 'Show hidden'),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'hidden',
        label: 'Hidden files',
        description: 'Includes hidden entries in file surfaces.',
        controlValues: <String, Object?>{'hidden': 1},
      ),
    ],
    initialHeight: 18,
    builder: (context) => _FilesStory(showHidden: context.enabled('hidden')),
  ),
  Story(
    id: 'content.source-documents',
    title: 'Source, Diffs, JSON, and Markdown',
    category: 'Content',
    description:
        'Inspectable document views for code, diffs, patch reviews, JSON, and lightweight Markdown.',
    widgets: const <String>[
      'CodeView',
      'DiffView',
      'PatchReview',
      'JsonView',
      'MarkdownText',
      'MarkdownView',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'document',
        label: 'Document',
        options: <String>['Code', 'Diff', 'Patch', 'JSON', 'Markdown'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'diff',
        label: 'Diff',
        description: 'Unified diff rendering and semantics.',
        controlValues: <String, Object?>{'document': 1},
      ),
      StoryVariant(
        id: 'markdown',
        label: 'Markdown',
        description: 'Markdown document view.',
        controlValues: <String, Object?>{'document': 4},
      ),
    ],
    initialHeight: 20,
    builder: (context) => _DocumentStory(document: context.option('document')),
  ),
  Story(
    id: 'logs.search',
    title: 'Search, Logs, and Terminal Output',
    category: 'Output',
    description:
        'Keyboard-searchable results, structured logs, and captured terminal output regions.',
    widgets: const <String>[
      'SearchPanel',
      'SearchResult',
      'LogRegion',
      'LogEntry',
      'TerminalOutputRegion',
      'LogBuffer',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'view',
        label: 'View',
        options: <String>['Search', 'Logs', 'Terminal'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'logs',
        label: 'Logs',
        description: 'Structured log-region view.',
        controlValues: <String, Object?>{'view': 1},
      ),
      StoryVariant(
        id: 'terminal',
        label: 'Terminal',
        description: 'Captured terminal-output view.',
        controlValues: <String, Object?>{'view': 2},
      ),
    ],
    initialHeight: 18,
    builder: (context) => _SearchLogStory(view: context.option('view')),
  ),
  Story(
    id: 'agent.context-messages',
    title: 'Agent Context and Messages',
    category: 'Agent',
    description:
        'Protocol-neutral context, message, and conversation surfaces for agent/developer tools.',
    widgets: const <String>[
      'ContextPanel',
      'ContextItem',
      'MessageList',
      'MessageEntry',
      'ConversationNavigator',
      'ConversationEntry',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'view',
        label: 'View',
        options: <String>['Context', 'Messages', 'Conversations'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'messages',
        label: 'Messages',
        description: 'Agent message list surface.',
        controlValues: <String, Object?>{'view': 1},
      ),
      StoryVariant(
        id: 'conversations',
        label: 'Conversations',
        description: 'Conversation navigator surface.',
        controlValues: <String, Object?>{'view': 2},
      ),
    ],
    initialHeight: 18,
    builder: (context) => _AgentStory(view: context.option('view')),
  ),
  Story(
    id: 'agent.model-tools-approval',
    title: 'Model Status, Tools, and Approvals',
    category: 'Agent',
    description:
        'Model runtime status, token use, tool-call cards, and approval prompts.',
    widgets: const <String>[
      'ModelStatusBar',
      'ModelStatusInfo',
      'TokenMeter',
      'TokenUsage',
      'ToolCallCard',
      'ToolCallRecord',
      'ApprovalPrompt',
      'ApprovalRequest',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'status',
        label: 'Tool status',
        options: <String>['Running', 'Succeeded', 'Failed'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'failed',
        label: 'Failed tool',
        description: 'Tool-call and approval surfaces in failure state.',
        controlValues: <String, Object?>{'status': 2},
      ),
    ],
    initialHeight: 19,
    builder: (context) => _ModelToolsStory(status: context.option('status')),
  ),
  Story(
    id: 'workflow.process-trace',
    title: 'Workflow, Process, and Trace',
    category: 'Workflow',
    description:
        'Task graphs, process chrome, timeline inspection, and aggregate workflow summaries.',
    widgets: const <String>[
      'TaskGraph',
      'TaskGraphNode',
      'ProcessPanel',
      'ProcessTaskController',
      'TraceTimeline',
      'TraceTimelineEntry',
      'WorkflowSnapshot',
      'WorkflowSummary',
    ],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'view',
        label: 'View',
        options: <String>['Task graph', 'Trace', 'Process', 'Summary'],
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'trace',
        label: 'Trace',
        description: 'Timeline inspection view.',
        controlValues: <String, Object?>{'view': 1},
      ),
      StoryVariant(
        id: 'process',
        label: 'Process',
        description: 'Process panel view.',
        controlValues: <String, Object?>{'view': 2},
      ),
      StoryVariant(
        id: 'summary',
        label: 'Summary',
        description: 'Workflow summary view.',
        controlValues: <String, Object?>{'view': 3},
      ),
    ],
    initialHeight: 19,
    builder: (context) => _WorkflowStory(view: context.option('view')),
  ),
]);

List<Story> _perWidgetStories(List<Story> groupedStories) {
  final stories = <Story>[];
  for (final source in groupedStories) {
    for (final widgetName in source.widgets) {
      stories.add(
        Story(
          id: '${source.id}.${_storySlug(widgetName)}',
          title: widgetName,
          category: source.category,
          description: _widgetDescription(widgetName, source),
          widgets: <String>[widgetName],
          builder: source.builder,
          controls: source.controls,
          defaultControlValues: _widgetDefaultControlValues(widgetName, source),
          variants: source.variants,
          notes: <String>[
            'Focused ${source.title} story for $widgetName.',
            ...source.notes,
          ],
          initialHeight: source.initialHeight,
        ),
      );
    }
  }
  return List<Story>.unmodifiable(stories);
}

String _storySlug(String value) {
  final withWordBreaks = value.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}-${match.group(2)}',
  );
  final slug = withWordBreaks
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  return slug.replaceAll(RegExp(r'^-|-$'), '');
}

String _widgetDescription(String widgetName, Story source) {
  final specific = _widgetDescriptions[widgetName];
  if (specific != null) return specific;
  return '$widgetName focused story. ${source.description}';
}

Map<String, Object?> _widgetDefaultControlValues(
  String widgetName,
  Story source,
) {
  final defaults = _widgetDefaultControls[widgetName];
  if (defaults == null || defaults.isEmpty) return const <String, Object?>{};
  final controlIds = {for (final control in source.controls) control.id};
  final filtered = <String, Object?>{
    for (final entry in defaults.entries)
      if (controlIds.contains(entry.key)) entry.key: entry.value,
  };
  return Map<String, Object?>.unmodifiable(filtered);
}

const Map<String, String> _widgetDescriptions = <String, String>{
  'Text':
      'Plain text rendering with terminal cell styling and predictable clipping.',
  'RichText':
      'Inline mixed-style text for dense terminal labels and status lines.',
  'TextSpan':
      'Composable spans that build rich terminal text without extra layout.',
  'Column':
      'Vertical layout composition with fixed cells, gaps, and nested children.',
  'Row':
      'Horizontal layout composition with expansion and alignment under terminal constraints.',
  'Container':
      'Framed, padded, colored layout chrome for focused terminal regions.',
  'Padding': 'Cell-accurate spacing around content without manual spacer rows.',
  'SizedBox':
      'Fixed and flexible sizing primitives for stable terminal layouts.',
  'SelectionArea':
      'Selectable terminal-native text inside longer scrollable surfaces.',
  'ScrollView':
      'Keyboard-scrollable content for long panes and document-like regions.',
  'ListView': 'Lazy, focusable list navigation for large selectable item sets.',
  'ListController':
      'Programmatic list selection and scroll state for coordinated lists.',
  'Button':
      'Focusable command activation with action logging and keyboard support.',
  'Checkbox': 'Binary form state with clear selected and disabled rendering.',
  'Toggle': 'Compact on/off switching for terminal settings surfaces.',
  'Switch':
      'Labeled binary switching with stronger visual state than a checkbox.',
  'Radio': 'Single-choice state across related options.',
  'Select': 'Single-value dropdown selection for compact option sets.',
  'SelectOption':
      'Typed select option metadata including labels and disabled states.',
  'MultiSelect':
      'Keyboard-navigable multi-value selection with visible selected facets.',
  'TextInput':
      'Single-line editing with cursor movement, submission, and focus traversal.',
  'TextArea': 'Multi-line text editing for notes and longer form fields.',
  'NumberInput': 'Bounded numeric entry with validation-friendly semantics.',
  'PasswordInput':
      'Secret text entry with redacted rendering and editing behavior.',
  'Autocomplete': 'Inline suggestion picking for short known option lists.',
  'CompletionTextInput':
      'Provider-backed completions for command and search inputs.',
  'DatePicker': 'Keyboard calendar selection with configurable week starts.',
  'ColorPicker': 'Terminal color selection with live swatches.',
  'RangeSlider': 'Low/high numeric range picking for thresholds and filters.',
  'Stepper': 'Incremental numeric control for bounded counts and retries.',
  'ProgressBar': 'Compact progress display for task and pipeline completion.',
  'Gauge': 'At-a-glance scalar status display for utilization and health.',
  'CommandPalette':
      'Scoped command discovery and execution from the active widget tree.',
  'Menu': 'Anchored command menu with keyboard interaction.',
  'MenuItem': 'Single menu action row with selection behavior.',
  'SubMenu': 'Nested menu grouping for larger command sets.',
  'Dialog':
      'Modal-style framed content for confirmations and focused decisions.',
  'Toaster': 'Transient notification host for contextual app feedback.',
  'Tooltip': 'Anchored help text for compact controls.',
  'Tabs': 'Mounted tab panels with keyboard navigation and retained content.',
  'TabItem': 'Tab metadata and content pairing for tabbed surfaces.',
  'TabController': 'Programmatic tab state for command-driven navigation.',
  'Table': 'Widget-composed tabular layout for compact mixed-content rows.',
  'TableController': 'Selection and coordination state for composed tables.',
  'DataTable': 'Virtualized text table for larger row and cell datasets.',
  'DataTableColumn':
      'Column descriptors for width, labels, and data-table identity.',
  'DataTableController':
      'Programmatic data-table selection and scroll coordination.',
  'Tree': 'Expandable hierarchy navigation for nested data.',
  'TreeNode': 'Typed tree model entries with children and labels.',
  'TreeTable':
      'Hierarchical data table with expandable rows and aligned columns.',
  'TreeTableNode': 'Tree-table row model carrying labels, keys, and cells.',
  'TreeTableController':
      'Programmatic expansion, selection, and focus for tree tables.',
  'FormDefinition': 'Declarative form schema for repeatable terminal forms.',
  'FormFieldSpec':
      'Typed form field definitions for text, select, number, and checkbox rows.',
  'FormPanel': 'Inline form rendering for dense settings and task setup.',
  'FormWizard': 'Multi-step form flow for guided terminal workflows.',
  'FormWizardStep': 'Step grouping metadata for wizard-style forms.',
  'FormController': 'Form state coordination and validation entry point.',
  'BarChart': 'Stacked and labeled bars for categorical metrics.',
  'LineChart':
      'Series charting with axes, grids, legends, and optional cursor interaction.',
  'Sparkline': 'Tiny trend visualization for dense dashboard rows.',
  'Histogram': 'Distribution view for latency, size, or count samples.',
  'Heatmap': 'Matrix intensity visualization with row and column labels.',
  'CalendarHeatmap': 'Date-indexed activity visualization in terminal cells.',
  'Digits': 'Large terminal-native numeric display for timers and counters.',
  'Canvas':
      'Custom plotting surface for braille, quadrant, and half-block drawing.',
  'CanvasPainter': 'Imperative painter hook for custom terminal graphics.',
  'CanvasBounds': 'Coordinate bounds for mapping data space to terminal cells.',
  'Image': 'ANSI image preview rendering from decoded image data.',
  'ImageSource': 'Image input abstraction for decoded or file-backed previews.',
  'FileBrowser': 'Navigable filesystem browser for directories and files.',
  'FilePicker': 'Focusable file selection surface with filters and callbacks.',
  'FileMentionPicker':
      'Mention-style picker for quickly targeting repository files.',
  'FileMentionEntry': 'File mention metadata including path and language.',
  'CodeView': 'Syntax-aware source display for inspectable code snippets.',
  'DiffView': 'Unified diff rendering for review and change inspection.',
  'PatchReview': 'Patch-focused review surface for changed hunks.',
  'JsonView': 'Structured JSON inspection with terminal-friendly formatting.',
  'MarkdownText': 'Inline lightweight Markdown rendering.',
  'MarkdownView': 'Scrollable Markdown document rendering.',
  'SearchPanel': 'Keyboard-searchable result list with metadata-rich rows.',
  'SearchResult':
      'Search result data model for titles, categories, and details.',
  'LogRegion': 'Structured log display with stdout and stderr styling.',
  'LogEntry': 'Log entry model for timestamped or sourced log rows.',
  'TerminalOutputRegion':
      'Captured terminal output rendering backed by a buffer.',
  'LogBuffer': 'Appendable terminal output buffer for live process surfaces.',
  'ContextPanel': 'Agent context inventory with token usage and focused items.',
  'ContextItem':
      'Context record metadata for files, symbols, and prompt inputs.',
  'MessageList':
      'Conversation message rendering for agent and developer tools.',
  'MessageEntry': 'Message record data for roles, status, and content.',
  'ConversationNavigator':
      'Focusable conversation list for multi-thread tools.',
  'ConversationEntry': 'Conversation list metadata with recency and status.',
  'ModelStatusBar': 'Compact model runtime, latency, and token status display.',
  'ModelStatusInfo': 'Model status data used by runtime status bars.',
  'TokenMeter': 'Token budget visualization for context-window pressure.',
  'TokenUsage':
      'Token accounting model for input, output, cached, and limit values.',
  'ToolCallCard': 'Tool-call progress, output, and error rendering.',
  'ToolCallRecord':
      'Tool-call model carrying arguments, progress, status, and results.',
  'ApprovalPrompt':
      'Interactive approval request surface for sensitive actions.',
  'ApprovalRequest': 'Approval request data model with severity and details.',
  'TaskGraph': 'Task dependency graph visualization for workflow planning.',
  'TaskGraphNode': 'Task graph node metadata with state and dependencies.',
  'ProcessPanel': 'Live process task panel with command status and progress.',
  'ProcessTaskController':
      'Controller for process state and task lifecycle updates.',
  'TraceTimeline': 'Timeline view for trace events and execution steps.',
  'TraceTimelineEntry': 'Trace event data for timeline rendering.',
  'WorkflowSnapshot': 'Aggregated workflow state model for summaries.',
  'WorkflowSummary':
      'Derived workflow metrics for health and activity displays.',
};

const Map<String, Map<String, Object?>> _widgetDefaultControls =
    <String, Map<String, Object?>>{
      'ListView': <String, Object?>{},
      'ListController': <String, Object?>{},
      'SelectOption': <String, Object?>{'size': 1},
      'DataTableColumn': <String, Object?>{'selection': 1},
      'DataTableController': <String, Object?>{'selection': 1},
      'TreeTable': <String, Object?>{'filter': 0},
      'TreeTableNode': <String, Object?>{'filter': 0},
      'TreeTableController': <String, Object?>{'filter': 0},
      'FormWizard': <String, Object?>{'layout': 1},
      'FormWizardStep': <String, Object?>{'layout': 1},
      'BarChart': <String, Object?>{'mode': 0},
      'LineChart': <String, Object?>{'mode': 0, 'interactive': 1},
      'Sparkline': <String, Object?>{'mode': 0},
      'Histogram': <String, Object?>{'mode': 1},
      'Heatmap': <String, Object?>{'mode': 1},
      'CalendarHeatmap': <String, Object?>{'mode': 0},
      'Digits': <String, Object?>{'mode': 0},
      'Canvas': <String, Object?>{'marker': 0},
      'CanvasPainter': <String, Object?>{'marker': 1},
      'CanvasBounds': <String, Object?>{'marker': 2},
      'Image': <String, Object?>{'marker': 0},
      'ImageSource': <String, Object?>{'marker': 0},
      'FileMentionPicker': <String, Object?>{'hidden': 0},
      'FileMentionEntry': <String, Object?>{'hidden': 0},
      'DiffView': <String, Object?>{'document': 1},
      'PatchReview': <String, Object?>{'document': 2},
      'JsonView': <String, Object?>{'document': 3},
      'MarkdownText': <String, Object?>{'document': 4},
      'MarkdownView': <String, Object?>{'document': 4},
      'LogRegion': <String, Object?>{'view': 1},
      'LogEntry': <String, Object?>{'view': 1},
      'TerminalOutputRegion': <String, Object?>{'view': 2},
      'LogBuffer': <String, Object?>{'view': 2},
      'MessageList': <String, Object?>{'view': 1},
      'MessageEntry': <String, Object?>{'view': 1},
      'ConversationNavigator': <String, Object?>{'view': 2},
      'ConversationEntry': <String, Object?>{'view': 2},
      'ToolCallCard': <String, Object?>{'status': 0},
      'ToolCallRecord': <String, Object?>{'status': 1},
      'ApprovalPrompt': <String, Object?>{'status': 0},
      'ApprovalRequest': <String, Object?>{'status': 0},
      'TraceTimeline': <String, Object?>{'view': 1},
      'TraceTimelineEntry': <String, Object?>{'view': 1},
      'ProcessPanel': <String, Object?>{'view': 2},
      'ProcessTaskController': <String, Object?>{'view': 2},
      'WorkflowSnapshot': <String, Object?>{'view': 3},
      'WorkflowSummary': <String, Object?>{'view': 3},
    };

CanvasMarker _canvasMarker(String label) {
  return switch (label) {
    'Quadrant' => CanvasMarker.quadrant,
    'Half block' => CanvasMarker.halfBlock,
    _ => CanvasMarker.braille,
  };
}

class _CoreLayoutStory extends StatelessWidget {
  const _CoreLayoutStory({
    required this.showBorder,
    required this.label,
    required this.selectedWidgetName,
  });

  final bool showBorder;
  final String label;
  final String? selectedWidgetName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (selectedWidgetName) {
      'RichText' || 'TextSpan' => _RichTextSpotlight(theme: theme),
      'Column' => const _ColumnSpotlight(),
      'Row' => const _RowSpotlight(),
      'Container' => _ContainerSpotlight(showBorder: showBorder),
      'Padding' => _PaddingSpotlight(showBorder: showBorder),
      'SizedBox' => _SizedBoxSpotlight(label: label),
      _ => _TextSpotlight(label: label),
    };
  }
}

class _TextSpotlight extends StatelessWidget {
  const _TextSpotlight({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Text renders directly into stable terminal cells.'),
        Text('Muted, bold, and colored labels stay layout-predictable.'),
        const SizedBox(height: 1),
        Text(label, style: CellStyle(foreground: theme.colorScheme.primary)),
        Text('plain status line', style: theme.mutedStyle),
      ],
    );
  }
}

class _RichTextSpotlight extends StatelessWidget {
  const _RichTextSpotlight({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RichText(
          text: TextSpan(
            text: 'RichText ',
            style: const CellStyle(bold: true),
            children: <TextSpan>[
              TextSpan(text: 'can mix ', style: theme.mutedStyle),
              const TextSpan(
                text: 'styles',
                style: CellStyle(foreground: AnsiColor(10)),
              ),
              const TextSpan(text: ' inside one terminal row.'),
            ],
          ),
        ),
        const SizedBox(height: 1),
        RichText(
          text: const TextSpan(
            text: 'TextSpan',
            style: CellStyle(foreground: AnsiColor(14)),
            children: <TextSpan>[
              TextSpan(text: ' composes '),
              TextSpan(text: 'semantic', style: CellStyle(bold: true)),
              TextSpan(text: ' fragments.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColumnSpotlight extends StatelessWidget {
  const _ColumnSpotlight();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Column stacks children vertically.'),
        const SizedBox(height: 1),
        for (final phase in const <String>['Plan', 'Build', 'Verify'])
          Container(
            width: 28,
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(phase),
          ),
      ],
    );
  }
}

class _RowSpotlight extends StatelessWidget {
  const _RowSpotlight();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Text('left'),
        SizedBox(width: 2),
        Text('middle'),
        Expanded(child: Text('expands')),
        Text('right'),
      ],
    );
  }
}

class _ContainerSpotlight extends StatelessWidget {
  const _ContainerSpotlight({required this.showBorder});

  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 7,
      border: showBorder
          ? BoxBorder(style: Theme.of(context).borderStyle)
          : null,
      padding: const EdgeInsets.all(1),
      alignment: Alignment.center,
      color: const AnsiColor(8),
      child: const Text('Container frames, colors, aligns, and sizes.'),
    );
  }
}

class _PaddingSpotlight extends StatelessWidget {
  const _PaddingSpotlight({required this.showBorder});

  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      border: showBorder
          ? BoxBorder(style: Theme.of(context).borderStyle)
          : null,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text('Padding creates breathing room in terminal cells.'),
      ),
    );
  }
}

class _SizedBoxSpotlight extends StatelessWidget {
  const _SizedBoxSpotlight({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('SizedBox reserves exact terminal dimensions.'),
        const SizedBox(height: 1),
        Container(
          width: 34,
          height: 3,
          alignment: Alignment.center,
          color: const AnsiColor(8),
          child: Text(label),
        ),
      ],
    );
  }
}

class _SelectionScrollStory extends StatefulWidget {
  const _SelectionScrollStory({required this.selectedWidgetName});

  final String? selectedWidgetName;

  @override
  State<_SelectionScrollStory> createState() => _SelectionScrollStoryState();
}

class _SelectionScrollStoryState extends State<_SelectionScrollStory> {
  late final ListController _list = ListController(selectedIndex: 0);

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  KeyEventResult _handleListKey(KeyEvent event) {
    return switch (event.keyCode) {
      KeyCode.arrowUp => _moveList(-1),
      KeyCode.arrowDown => _moveList(1),
      _ => KeyEventResult.ignored,
    };
  }

  KeyEventResult _moveList(int delta) {
    final selected = _list.selectedIndex;
    if (selected == null) {
      return KeyEventResult.ignored;
    }
    final next = (selected + delta).clamp(0, 19);
    if (next == selected) {
      return KeyEventResult.ignored;
    }
    _list.selectedIndex = next;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final listPane = SizedBox(
      width: 36,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKey: _handleListKey,
        child: ListView.builder(
          controller: _list,
          itemCount: 20,
          autofocus: true,
          itemBuilder: (context, index, selected) => Text(
            '${selected ? '>' : ' '} Lazy row ${index + 1}',
            style: selected
                ? Theme.of(context).selectionStyle
                : CellStyle.empty,
          ),
        ),
      ),
    );
    final scrollPane = SelectionArea(
      child: ScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('SelectionArea + ScrollView'),
            const Text('Drag text to select it, or use Ctrl+A/C.'),
            const SizedBox(height: 1),
            for (var i = 1; i <= 10; i += 1)
              Text(
                'Selectable paragraph $i: Fleury text stays terminal-native.',
              ),
          ],
        ),
      ),
    );
    return switch (widget.selectedWidgetName) {
      'ListView' || 'ListController' => listPane,
      _ => scrollPane,
    };
  }
}

class _ControlsStory extends StatefulWidget {
  const _ControlsStory({required this.disabled, required this.onAction});

  final bool disabled;
  final StoryActionRecorder onAction;

  @override
  State<_ControlsStory> createState() => _ControlsStoryState();
}

class _ControlsStoryState extends State<_ControlsStory> {
  bool _checked = true;
  bool _toggle = false;
  bool _switch = true;
  String _radio = 'fast';
  int _pressed = 0;

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.disabled
        ? null
        : () {
            setState(() => _pressed += 1);
            widget.onAction('button.pressed', <String, Object?>{
              'count': _pressed,
            });
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Button(label: 'Normal', onPressed: onPressed),
            const Text(' '),
            Button(
              label: 'Primary',
              variant: ButtonVariant.primary,
              onPressed: onPressed,
            ),
            const Text(' '),
            Button(
              label: 'Warn',
              variant: ButtonVariant.warning,
              onPressed: onPressed,
            ),
            const Text(' '),
            Button(
              label: 'Error',
              variant: ButtonVariant.error,
              onPressed: onPressed,
            ),
          ],
        ),
        const SizedBox(height: 1),
        Checkbox(
          value: _checked,
          label: 'Enable semantic graph',
          onChanged: widget.disabled
              ? null
              : (value) {
                  setState(() => _checked = value);
                  widget.onAction('checkbox.changed', <String, Object?>{
                    'value': value,
                  });
                },
        ),
        Toggle(
          value: _toggle,
          label: 'Compact rows',
          onChanged: widget.disabled
              ? null
              : (value) {
                  setState(() => _toggle = value);
                  widget.onAction('toggle.changed', <String, Object?>{
                    'value': value,
                  });
                },
        ),
        Switch(
          value: _switch,
          label: 'Streaming updates',
          onChanged: widget.disabled
              ? null
              : (value) {
                  setState(() => _switch = value);
                  widget.onAction('switch.changed', <String, Object?>{
                    'value': value,
                  });
                },
        ),
        const SizedBox(height: 1),
        Row(
          children: <Widget>[
            Radio<String>(
              value: 'fast',
              groupValue: _radio,
              label: 'Fast',
              onChanged: widget.disabled
                  ? null
                  : (value) {
                      setState(() => _radio = value);
                      widget.onAction('radio.changed', <String, Object?>{
                        'value': value,
                      });
                    },
            ),
            const Text('  '),
            Radio<String>(
              value: 'safe',
              groupValue: _radio,
              label: 'Safe',
              onChanged: widget.disabled
                  ? null
                  : (value) {
                      setState(() => _radio = value);
                      widget.onAction('radio.changed', <String, Object?>{
                        'value': value,
                      });
                    },
            ),
          ],
        ),
        Text('Pressed: $_pressed, mode: $_radio'),
      ],
    );
  }
}

class _SelectionInputsStory extends StatefulWidget {
  const _SelectionInputsStory({
    required this.withDisabled,
    required this.onAction,
  });

  final bool withDisabled;
  final StoryActionRecorder onAction;

  @override
  State<_SelectionInputsStory> createState() => _SelectionInputsStoryState();
}

class _SelectionInputsStoryState extends State<_SelectionInputsStory> {
  String? _environment = 'prod';
  Set<String> _facets = <String>{'logs', 'traces'};

  List<SelectOption<String>> get _options => <SelectOption<String>>[
    const SelectOption<String>(value: 'dev', label: 'Development'),
    const SelectOption<String>(value: 'stage', label: 'Staging'),
    SelectOption<String>(
      value: 'prod',
      label: 'Production',
      enabled: !widget.withDisabled,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(width: 14, child: Text('Environment')),
            Select<String>(
              options: _options,
              value: _environment,
              semanticLabel: 'Environment',
              onChanged: (value) {
                setState(() => _environment = value);
                widget.onAction('select.changed', <String, Object?>{
                  'value': value,
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 1),
        const Text('Facets'),
        MultiSelect<String>(
          options: const <SelectOption<String>>[
            SelectOption<String>(value: 'logs', label: 'Logs'),
            SelectOption<String>(value: 'traces', label: 'Traces'),
            SelectOption<String>(value: 'metrics', label: 'Metrics'),
            SelectOption<String>(value: 'profile', label: 'Profile samples'),
          ],
          values: _facets,
          onChanged: (values) {
            setState(() => _facets = values);
            widget.onAction('multi_select.changed', <String, Object?>{
              'count': values.length,
            });
          },
          semanticLabel: 'Enabled facets',
        ),
        const SizedBox(height: 1),
        Text('Selected: ${_environment ?? 'none'} / ${_facets.join(', ')}'),
      ],
    );
  }
}

class _TextEntryStory extends StatefulWidget {
  const _TextEntryStory({required this.onAction});

  final StoryActionRecorder onAction;

  @override
  State<_TextEntryStory> createState() => _TextEntryStoryState();
}

class _TextEntryStoryState extends State<_TextEntryStory> {
  late final TextEditingController _single = TextEditingController(
    text: 'fleury',
  );
  late final TextEditingController _multi = TextEditingController(
    text: 'Line one\nLine two',
  );
  late final TextEditingController _secret = TextEditingController(
    text: 'sk-live-redacted',
  );
  String _selected = 'none';

  @override
  void dispose() {
    _single.dispose();
    _multi.dispose();
    _secret.dispose();
    super.dispose();
  }

  Iterable<TextCompletionOption> _complete(TextCompletionRequest request) {
    const options = <TextCompletionOption>[
      TextCompletionOption(label: 'benchmark'),
      TextCompletionOption(label: 'storybook'),
      TextCompletionOption(label: 'command-palette'),
      TextCompletionOption(label: 'semantic-tree'),
    ];
    final query = request.query.toLowerCase();
    return options.where((option) => option.label.contains(query));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextInput(
                controller: _single,
                placeholder: 'Project name',
                semanticLabel: 'Project name',
              ),
              const SizedBox(height: 1),
              NumberInput(
                initialValue: 42,
                min: 0,
                max: 100,
                placeholder: 'Budget',
                semanticLabel: 'Budget',
              ),
              const SizedBox(height: 1),
              PasswordInput(
                controller: _secret,
                placeholder: 'Token',
                semanticLabel: 'API token',
              ),
              const SizedBox(height: 1),
              Autocomplete<String>(
                options: const <String>[
                  'fleury',
                  'flutter',
                  'ratatui',
                  'bubble tea',
                ],
                placeholder: 'Type f...',
                onSelected: (value) {
                  setState(() => _selected = value);
                  widget.onAction('autocomplete.selected', <String, Object?>{
                    'value': value,
                  });
                },
              ),
              Text('Autocomplete selected: $_selected'),
            ],
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 5,
                child: TextArea(
                  controller: _multi,
                  placeholder: 'Multi-line note',
                ),
              ),
              const SizedBox(height: 1),
              CompletionTextInput(
                provider: _complete,
                placeholder: 'Completion query',
                showOnEmptyQuery: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerStory extends StatefulWidget {
  const _PickerStory({
    required this.only,
    required this.onAction,
    this.weekStartsOn = CalendarWeekStart.sunday,
  });

  /// The single widget this story previews — each picker has its own 1:1 story.
  final String only;
  final CalendarWeekStart weekStartsOn;
  final StoryActionRecorder onAction;

  @override
  State<_PickerStory> createState() => _PickerStoryState();
}

class _PickerStoryState extends State<_PickerStory> {
  DateTime _date = DateTime(2026, 6, 9);
  Color _color = const AnsiColor(10);
  (num low, num high) _range = (20, 72);
  num _stepper = 4;

  @override
  Widget build(BuildContext context) {
    switch (widget.only) {
      case 'DatePicker':
        return SizedBox(
          width: 24,
          child: DatePicker(
            value: _date,
            firstDate: DateTime(2026, 1, 1),
            lastDate: DateTime(2026, 12, 31),
            weekStartsOn: widget.weekStartsOn,
            onChanged: (value) {
              setState(() => _date = value);
              widget.onAction('date.changed', <String, Object?>{
                'date': '${value.year}-${value.month}-${value.day}',
              });
            },
          ),
        );
      case 'ColorPicker':
        return ColorPicker(
          value: _color,
          onChanged: (value) {
            setState(() => _color = value);
            widget.onAction('color.changed', <String, Object?>{
              'color': value.toString(),
            });
          },
        );
      case 'Stepper':
        return Stepper(
          value: _stepper,
          min: 0,
          max: 10,
          label: 'Retries',
          onChanged: (value) {
            setState(() => _stepper = value);
            widget.onAction('stepper.changed', <String, Object?>{
              'value': value,
            });
          },
        );
      case 'RangeSlider':
        return SizedBox(
          width: 36,
          child: RangeSlider(
            values: _range,
            min: 0,
            max: 100,
            label: 'Latency band',
            onChanged: (value) {
              setState(() => _range = value);
              widget.onAction('range.changed', <String, Object?>{
                'low': value.$1,
                'high': value.$2,
              });
            },
          ),
        );
      case 'ProgressBar':
        return const SizedBox(width: 36, child: ProgressBar(value: 0.64));
      case 'Gauge':
        return const SizedBox(width: 36, child: Gauge(value: 0.78, label: 'CPU'));
      default:
        return const SizedBox.shrink();
    }
  }
}

class _OverlayStory extends StatelessWidget {
  const _OverlayStory();

  @override
  Widget build(BuildContext context) {
    return Toaster(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Menu(
                semanticLabel: 'Demo menu',
                trigger: const Text('Open menu'),
                items: <MenuEntry>[
                  MenuItem(
                    label: 'Show toast',
                    onSelected: () => Toaster.show(
                      context,
                      'Saved story state',
                      severity: ToastSeverity.success,
                    ),
                  ),
                  const MenuSeparator(),
                  SubMenu(
                    label: 'Theme',
                    items: <MenuEntry>[
                      MenuItem(label: 'Dark', onSelected: () {}),
                      MenuItem(label: 'Light', onSelected: () {}),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 2),
              Button(
                label: 'Open palette',
                onPressed: () => CommandPalette.open(context),
              ),
              const SizedBox(width: 2),
              Button(
                label: 'Toast',
                onPressed: () => Toaster.show(
                  context,
                  'Storybook toast',
                  severity: ToastSeverity.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Tooltip(
            message: 'Focus the button to show this anchored tooltip.',
            child: Button(label: 'Tooltip target', onPressed: () {}),
          ),
          const SizedBox(height: 1),
          Dialog(
            title: 'Dialog chrome',
            width: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                Text('Dialogs provide frame and semantics.'),
                Text('Positioning is handled by Navigator.present.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabsStory extends StatelessWidget {
  const _TabsStory();

  @override
  Widget build(BuildContext context) {
    return Tabs(
      tabs: const <TabItem>[
        TabItem(
          label: 'Overview',
          content: Text('The overview tab remains mounted while hidden.'),
        ),
        TabItem(
          label: 'Metrics',
          content: SizedBox(
            width: 32,
            child: Sparkline(data: <num>[4, 6, 3, 8, 9, 6, 11, 12]),
          ),
        ),
        TabItem(
          label: 'Notes',
          content: Text('Use Left/Right in the tab strip or Alt+1..9.'),
        ),
      ],
    );
  }
}

class _TablesStory extends StatelessWidget {
  const _TablesStory({required this.cellMode});

  final bool cellMode;

  static const _columns = <DataTableColumn>[
    DataTableColumn(id: 'name', title: 'Name', width: FlexColumnWidth(2)),
    DataTableColumn(id: 'state', title: 'State'),
    DataTableColumn(id: 'latency', title: 'P95'),
  ];

  static const _rows = <Map<String, String>>[
    <String, String>{
      'name': 'Frame scheduler',
      'state': 'leading',
      'latency': '4.8ms',
    },
    <String, String>{
      'name': 'Tree table',
      'state': 'parity',
      'latency': '12ms',
    },
    <String, String>{
      'name': 'Search panel',
      'state': 'leading',
      'latency': '6ms',
    },
    <String, String>{
      'name': 'Message list',
      'state': 'parity',
      'latency': '8ms',
    },
    <String, String>{
      'name': 'Patch review',
      'state': 'watch',
      'latency': '18ms',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 34,
          child: Table(
            selectable: true,
            header: const <Widget>[
              Text('Widget', style: CellStyle(bold: true)),
              Text('Owner', style: CellStyle(bold: true)),
            ],
            rows: const <List<Widget>>[
              <Widget>[Text('Button'), Text('Core')],
              <Widget>[Text('DataTable'), Text('Widgets')],
              <Widget>[Text('TraceTimeline'), Text('Widgets')],
            ],
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: DataTable(
            rowCount: _rows.length,
            columns: _columns,
            selectionMode: cellMode
                ? DataTableSelectionMode.cell
                : DataTableSelectionMode.row,
            cellBuilder: (rowIndex, columnId) =>
                _rows[rowIndex][columnId] ?? '',
            rowKeyBuilder: (rowIndex) => _rows[rowIndex]['name']!,
            sortColumnId: 'latency',
            sortDirection: DataTableSortDirection.ascending,
          ),
        ),
      ],
    );
  }
}

class _TreesStory extends StatelessWidget {
  const _TreesStory({required this.runtimeOnly});

  final bool runtimeOnly;

  static const _treeRoots = <TreeNode<String>>[
    TreeNode<String>(
      'packages',
      children: <TreeNode<String>>[
        TreeNode<String>(
          'fleury',
          children: <TreeNode<String>>[
            TreeNode<String>('runtime'),
            TreeNode<String>('widgets'),
          ],
        ),
        TreeNode<String>(
          'fleury_widgets',
          children: <TreeNode<String>>[
            TreeNode<String>('forms'),
            TreeNode<String>('tables'),
          ],
        ),
      ],
    ),
  ];

  static const _columns = <DataTableColumn>[
    DataTableColumn(id: 'name', title: 'Component', width: FlexColumnWidth(2)),
    DataTableColumn(id: 'owner', title: 'Owner'),
    DataTableColumn(id: 'status', title: 'Status'),
  ];

  static const _roots = <TreeTableNode<String>>[
    TreeTableNode<String>(
      key: 'runtime',
      label: 'Runtime',
      cells: <String, String>{'owner': 'Core', 'status': 'stable'},
      children: <TreeTableNode<String>>[
        TreeTableNode<String>(
          key: 'runtime.scheduler',
          label: 'FrameScheduler',
          cells: <String, String>{'owner': 'Core', 'status': 'hot path'},
        ),
        TreeTableNode<String>(
          key: 'runtime.focus',
          label: 'FocusManager',
          cells: <String, String>{'owner': 'Core', 'status': 'stable'},
        ),
      ],
    ),
    TreeTableNode<String>(
      key: 'widgets',
      label: 'Widgets',
      cells: <String, String>{'owner': 'Widgets', 'status': 'growing'},
      children: <TreeTableNode<String>>[
        TreeTableNode<String>(
          key: 'widgets.table',
          label: 'TreeTable',
          cells: <String, String>{'owner': 'Widgets', 'status': 'watch'},
        ),
        TreeTableNode<String>(
          key: 'widgets.search',
          label: 'SearchPanel',
          cells: <String, String>{'owner': 'Widgets', 'status': 'stable'},
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 28,
          child: Tree<String>(roots: _treeRoots, label: 'Package tree'),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: TreeTable<String>(
            roots: _roots,
            columns: _columns,
            treeColumnId: 'name',
            maxVisible: 10,
            filter: runtimeOnly
                ? const TreeTableFilterDescriptor(query: 'runtime')
                : null,
          ),
        ),
      ],
    );
  }
}

class _FormsStory extends StatelessWidget {
  _FormsStory({required this.wizard});

  final bool wizard;

  final FormDefinition _definition = FormDefinition(
    title: 'Run benchmark',
    submitLabel: 'Run',
    fields: <FormFieldSpec>[
      FormFieldSpec.text(
        id: 'scenario',
        label: 'Scenario',
        initialValue: 'sb6_data_table',
      ),
      FormFieldSpec.select(
        id: 'peer',
        label: 'Peer',
        initialValue: 'ratatui',
        options: const <FormOption>[
          FormOption(value: 'ratatui', label: 'Ratatui'),
          FormOption(value: 'bubbletea', label: 'Bubble Tea'),
          FormOption(value: 'ink', label: 'Ink'),
        ],
      ),
      FormFieldSpec.number(
        id: 'replicates',
        label: 'Replicates',
        initialValue: 3,
        min: 1,
        max: 20,
      ),
      FormFieldSpec.checkbox(
        id: 'bare_metal',
        label: 'Bare metal run',
        initialValue: true,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (wizard) {
      return FormWizard(
        definition: _definition,
        layout: FormPanelLayout.inline,
        steps: const <FormWizardStep>[
          FormWizardStep(
            id: 'scenario',
            title: 'Scenario',
            fieldIds: <String>['scenario', 'peer'],
          ),
          FormWizardStep(
            id: 'run',
            title: 'Run',
            fieldIds: <String>['replicates', 'bare_metal'],
          ),
        ],
      );
    }
    return FormPanel(
      definition: _definition,
      layout: FormPanelLayout.inline,
      fieldWidth: 24,
    );
  }
}

class _ChartsStory extends StatelessWidget {
  const _ChartsStory({
    required this.distribution,
    required this.interactiveLine,
    required this.selectedWidgetName,
    required this.samples,
  });

  final bool distribution;
  final bool interactiveLine;
  final String selectedWidgetName;
  final int samples;

  @override
  Widget build(BuildContext context) {
    final values = _distributionValues(samples);
    final framePoints = _framePoints(samples);
    final wirePoints = _wirePoints(samples);
    final sparkline = _sparkline(samples);
    final heatmap = _heatmap();
    final calendarValues = _calendarValues();

    if (distribution) {
      switch (selectedWidgetName) {
        case 'Histogram':
          return Histogram(values: values, bins: 8, showValues: true);
        case 'Heatmap':
          return Heatmap(
            values: heatmap,
            rowLabels: const <String>['CPU', 'IO', 'UI'],
            colLabels: const <String>['A', 'B', 'C', 'D', 'E'],
          );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: Histogram(values: values, bins: 8, showValues: true)),
          const SizedBox(width: 2),
          Expanded(
            child: Heatmap(
              values: const <List<num>>[
                <num>[1, 4, 6, 8, 4],
                <num>[2, 5, 7, 9, 5],
                <num>[1, 3, 4, 6, 3],
              ],
              rowLabels: const <String>['CPU', 'IO', 'UI'],
              colLabels: const <String>['A', 'B', 'C', 'D', 'E'],
            ),
          ),
        ],
      );
    }

    switch (selectedWidgetName) {
      case 'BarChart':
        return BarChart(
          bars: _statusBars,
          barWidth: 3,
          gap: 2,
          segmentLabels: const <String>['app', 'framework', 'driver'],
          showLegend: true,
          showValues: true,
          palette: Palettes.categorical,
        );
      case 'LineChart':
        return LineChart(
          interactive: interactiveLine,
          series: <LineSeries>[
            LineSeries(framePoints, label: 'frame'),
            LineSeries(wirePoints, label: 'wire'),
          ],
          showAxes: true,
          showLegend: true,
          showGrid: true,
        );
      case 'Sparkline':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Frame time'),
            Sparkline(data: sparkline),
            const SizedBox(height: 1),
            const Text('Wire latency'),
            Sparkline(data: wirePoints.map((point) => point.$2).toList()),
            const SizedBox(height: 1),
            const Text('Queue depth'),
            Sparkline(
              data: <num>[for (var i = 0; i < samples; i += 1) (i * 2) % 9],
            ),
          ],
        );
      case 'Histogram':
        return Histogram(values: values, bins: 8, showValues: true);
      case 'Heatmap':
        return Heatmap(
          values: heatmap,
          rowLabels: const <String>['CPU', 'IO', 'UI'],
          colLabels: const <String>['A', 'B', 'C', 'D', 'E'],
        );
      case 'CalendarHeatmap':
        return CalendarHeatmap(
          start: _chartToday.subtract(const Duration(days: 56)),
          end: _chartToday,
          values: calendarValues,
          cellWidth: 2,
          showMonthLabels: true,
        );
      case 'Gauge':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const <Widget>[
            Gauge(value: 0.82, label: 'RSS'),
            SizedBox(height: 1),
            Gauge(value: 0.64, label: 'CPU'),
            SizedBox(height: 1),
            Gauge(value: 0.38, label: 'IO'),
          ],
        );
      case 'Digits':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Digits('12:34', color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 1),
            const Text('elapsed runtime'),
          ],
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 7,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: BarChart(
                  bars: _statusBars,
                  barWidth: 3,
                  gap: 2,
                  segmentLabels: const <String>['app', 'framework', 'driver'],
                  showLegend: true,
                  showValues: true,
                  palette: Palettes.categorical,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: LineChart(
                  interactive: interactiveLine,
                  series: <LineSeries>[
                    LineSeries(framePoints, label: 'frame'),
                    LineSeries(wirePoints, label: 'wire'),
                  ],
                  showAxes: true,
                  showLegend: true,
                  showGrid: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Row(
          children: <Widget>[
            SizedBox(width: 22, child: Sparkline(data: sparkline)),
            const SizedBox(width: 2),
            const Gauge(value: 0.82, label: 'RSS'),
            const SizedBox(width: 2),
            Digits('12:34', color: Theme.of(context).colorScheme.primary),
          ],
        ),
        const SizedBox(height: 1),
        CalendarHeatmap(
          start: _chartToday.subtract(const Duration(days: 28)),
          end: _chartToday,
          values: calendarValues,
          cellWidth: 1,
          showMonthLabels: false,
        ),
      ],
    );
  }
}

const List<Bar> _statusBars = <Bar>[
  Bar.stacked('CPU', <num>[34, 12, 8]),
  Bar.stacked('Mem', <num>[26, 18, 5]),
  Bar.stacked('IO', <num>[18, 9, 3]),
];

final DateTime _chartToday = DateTime(2026, 6, 9);

List<num> _distributionValues(int samples) => <num>[
  for (var i = 0; i < samples * 2; i += 1)
    4 + ((i * 7) % 15) + (i.isEven ? 0 : 0.5),
];

List<(num, num)> _framePoints(int samples) => <(num, num)>[
  for (var i = 0; i < samples; i += 1) (i, 2 + ((i * 5) % 7)),
];

List<(num, num)> _wirePoints(int samples) => <(num, num)>[
  for (var i = 0; i < samples; i += 1) (i, 1 + ((i * 3) % 5)),
];

List<num> _sparkline(int samples) => <num>[
  for (var i = 0; i < samples; i += 1) 1 + ((i * 4) % 11),
];

List<List<num>> _heatmap() => const <List<num>>[
  <num>[1, 4, 6, 8, 4],
  <num>[2, 5, 7, 9, 5],
  <num>[1, 3, 4, 6, 3],
];

Map<DateTime, num> _calendarValues() => <DateTime, num>{
  for (var i = 0; i < 56; i += 1)
    _chartToday.subtract(Duration(days: i)): (i * 7) % 6,
};

class _CanvasImageStory extends StatelessWidget {
  _CanvasImageStory({required this.marker});

  final CanvasMarker marker;
  final img.Image _image = _buildPreviewImage();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Canvas(
            marker: marker,
            bounds: const CanvasBounds(
              minX: 0,
              maxX: math.pi * 2,
              minY: -1,
              maxY: 1,
            ),
            painter: _WavePainter(),
            semanticRole: SemanticRole.chart,
            semanticLabel: 'Sine wave canvas',
          ),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 28,
          child: Image.decoded(
            _image,
            semanticLabel: 'Generated color preview',
          ),
        ),
      ],
    );
  }
}

class _WavePainter extends CanvasPainter {
  _WavePainter();

  @override
  void paint(CanvasContext ctx) {
    var previousX = 0.0;
    var previousY = math.sin(previousX);
    for (var i = 1; i <= 96; i += 1) {
      final x = math.pi * 2 * i / 96;
      final y = math.sin(x);
      ctx.drawLine(previousX, previousY, x, y, color: const AnsiColor(10));
      previousX = x;
      previousY = y;
    }
  }
}

img.Image _buildPreviewImage() {
  final image = img.Image(width: 18, height: 10);
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      final r = (255 * x / (image.width - 1)).round();
      final g = (255 * y / (image.height - 1)).round();
      final b = 180;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

class _FilesStory extends StatelessWidget {
  const _FilesStory({required this.showHidden});

  final bool showHidden;

  @override
  Widget build(BuildContext context) {
    final cwd = io.Directory.current.path;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: FileBrowser(
            initialDirectory: cwd,
            filter: FileBrowserFilterDescriptor(showHidden: showHidden),
            maxVisible: 10,
            label: 'Repository files',
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: FilePicker(
                  initialDirectory: cwd,
                  showHidden: showHidden,
                  onSelected: (_) {},
                  filter: (entity) =>
                      entity is io.Directory || entity.path.endsWith('.dart'),
                ),
              ),
              const SizedBox(height: 1),
              FileMentionPicker(
                width: 42,
                maxVisible: 4,
                entries: const <FileMentionEntry>[
                  FileMentionEntry(
                    path: 'packages/fleury/lib/fleury.dart',
                    language: 'dart',
                  ),
                  FileMentionEntry(
                    path: 'packages/fleury_widgets/lib/fleury_widgets.dart',
                    language: 'dart',
                  ),
                  FileMentionEntry(
                    path: 'packages/storybook/lib/storybook.dart',
                    language: 'dart',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DocumentStory extends StatelessWidget {
  const _DocumentStory({required this.document});

  final String document;

  @override
  Widget build(BuildContext context) {
    return switch (document) {
      'Diff' => DiffView(diff: _sampleDiff, label: 'Diff sample'),
      'Patch' => PatchReview(diff: _sampleDiff, label: 'Patch review'),
      'JSON' => JsonView.string(_sampleJson, label: 'Story metadata'),
      'Markdown' => MarkdownView(
        markdown: _sampleMarkdown,
        label: 'Markdown sample',
      ),
      _ => CodeView(
        source: _sampleCode,
        language: 'dart',
        filePath: 'storybook.dart',
      ),
    };
  }
}

class _SearchLogStory extends StatefulWidget {
  const _SearchLogStory({required this.view});

  final String view;

  @override
  State<_SearchLogStory> createState() => _SearchLogStoryState();
}

class _SearchLogStoryState extends State<_SearchLogStory> {
  late final LogBuffer _buffer = LogBuffer(capacity: 16)
    ..add(const LogLine('boot storybook', LogSource.stdout))
    ..add(const LogLine('warning: fixture uses local cwd', LogSource.stderr))
    ..add(const LogLine('ready', LogSource.stdout));

  @override
  void dispose() {
    _buffer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.view) {
      'Logs' => LogRegion(entries: _sampleLogs, label: 'Scenario logs'),
      'Terminal' => TerminalOutputRegion(
        buffer: _buffer,
        label: 'Captured output',
      ),
      _ => SearchPanel(
        width: 56,
        results: const <SearchResult>[
          SearchResult(
            id: 'buttons',
            title: 'Buttons and Boolean Controls',
            category: 'Input',
            subtitle: 'Button, Checkbox, Toggle, Switch, Radio',
          ),
          SearchResult(
            id: 'charts',
            title: 'Charts and Status Visualizations',
            category: 'Visualization',
            subtitle: 'BarChart, LineChart, Sparkline, Histogram',
          ),
          SearchResult(
            id: 'agent',
            title: 'Agent Context and Messages',
            category: 'Agent',
            subtitle: 'ContextPanel, MessageList, ConversationNavigator',
          ),
        ],
      ),
    };
  }
}

class _AgentStory extends StatelessWidget {
  const _AgentStory({required this.view});

  final String view;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      'Messages' => MessageList(
        messages: _sampleMessages,
        label: 'Conversation',
      ),
      'Conversations' => ConversationNavigator(
        width: 56,
        conversations: _sampleConversations,
      ),
      _ => ContextPanel(
        items: _sampleContext,
        usage: const TokenUsage(
          input: 1800,
          output: 420,
          cached: 300,
          contextLimit: 8000,
        ),
        maxVisible: 8,
      ),
    };
  }
}

class _ModelToolsStory extends StatelessWidget {
  const _ModelToolsStory({required this.status});

  final String status;

  ToolCallStatus get _toolStatus {
    return switch (status) {
      'Succeeded' => ToolCallStatus.succeeded,
      'Failed' => ToolCallStatus.failed,
      _ => ToolCallStatus.running,
    };
  }

  @override
  Widget build(BuildContext context) {
    final toolStatus = _toolStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const ModelStatusBar(
          info: ModelStatusInfo(
            model: 'gpt-5-codex',
            provider: 'OpenAI',
            status: ModelRuntimeStatus.streaming,
            mode: 'edit',
            latency: Duration(milliseconds: 180),
            tokenUsage: TokenUsage(
              input: 2400,
              output: 680,
              cached: 1200,
              contextLimit: 16000,
            ),
          ),
        ),
        const SizedBox(height: 1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ToolCallCard(
                record: ToolCallRecord(
                  id: 'tool-1',
                  name: 'benchmark.run',
                  title: 'Run benchmark',
                  status: toolStatus,
                  description: 'Capture peer comparison output.',
                  arguments: const <String, Object?>{
                    'scenario': 'sb6_data_table',
                    'peers': <String>['ratatui', 'bubbletea'],
                  },
                  output: toolStatus == ToolCallStatus.succeeded
                      ? 'median p95=4.8ms'
                      : null,
                  error: toolStatus == ToolCallStatus.failed
                      ? 'peer fixture timed out'
                      : null,
                  progressCurrent: toolStatus == ToolCallStatus.running
                      ? 2
                      : null,
                  progressTotal: toolStatus == ToolCallStatus.running
                      ? 3
                      : null,
                ),
                onCancel: toolStatus == ToolCallStatus.running ? () {} : null,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: ApprovalPrompt(
                width: 44,
                request: const ApprovalRequest(
                  id: 'approval-1',
                  title: 'Run on bare metal?',
                  message:
                      'This run will reserve the terminal and write benchmark artifacts.',
                  subject: 'Tier-C benchmark',
                  details: <String>[
                    '3 replicates',
                    'CPU/RSS/FPS capture enabled',
                  ],
                  severity: ApprovalSeverity.warning,
                ),
                onDecision: (_) {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkflowStory extends StatefulWidget {
  const _WorkflowStory({required this.view});

  final String view;

  @override
  State<_WorkflowStory> createState() => _WorkflowStoryState();
}

class _WorkflowStoryState extends State<_WorkflowStory> {
  late final ProcessTaskController _process = ProcessTaskController(
    id: 'storybook.process',
    label: 'storybook smoke',
  );

  @override
  void dispose() {
    _process.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.view) {
      'Trace' => TraceTimeline(events: _sampleTrace, label: 'Scenario trace'),
      'Process' => ProcessPanel(
        controller: _process,
        label: 'dart test packages/storybook',
      ),
      'Summary' => _WorkflowSummaryStory(snapshot: _sampleSnapshot),
      _ => TaskGraph(nodes: _sampleTasks, label: 'DX plan'),
    };
  }
}

class _WorkflowSummaryStory extends StatelessWidget {
  const _WorkflowSummaryStory({required this.snapshot});

  final WorkflowSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final summary = snapshot.summary;
    return Table(
      header: const <Widget>[
        Text('Metric', style: CellStyle(bold: true)),
        Text('Value', style: CellStyle(bold: true)),
      ],
      rows: <List<Widget>>[
        <Widget>[const Text('Health'), Text(summary.health.name)],
        <Widget>[const Text('Messages'), Text('${summary.messageCount}')],
        <Widget>[const Text('Tool calls'), Text('${summary.toolCallCount}')],
        <Widget>[const Text('Tasks'), Text('${summary.taskCount}')],
        <Widget>[
          const Text('Trace events'),
          Text('${summary.traceEventCount}'),
        ],
        <Widget>[const Text('Logs'), Text('${summary.logEntryCount}')],
      ],
    );
  }
}

const _sampleCode = '''
class StorybookApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CommandScope(
      commands: commands,
      child: const WidgetCatalog(),
    );
  }
}
''';

const _sampleDiff = '''
diff --git a/lib/widget.dart b/lib/widget.dart
index 1111111..2222222 100644
--- a/lib/widget.dart
+++ b/lib/widget.dart
@@ -1,5 +1,6 @@
 class WidgetCatalog {
+  final List<Story> stories;
   void build() {
-    renderOld();
+    renderStories(stories);
   }
 }
''';

const _sampleJson = '''
{
  "storybook": true,
  "stories": 19,
  "commands": ["palette", "theme", "reset"]
}
''';

const _sampleMarkdown = '''
# Storybook

- Browse widget stories
- Change controls in the inspector
- Open the command palette with `Ctrl+K`

```dart
dart tool/fleury_dev.dart storybook
```
''';

const _sampleLogs = <LogEntry>[
  LogEntry(
    id: 1,
    source: 'harness',
    severity: LogSeverity.info,
    message: 'starting scenario',
  ),
  LogEntry(
    id: 2,
    source: 'runner',
    severity: LogSeverity.success,
    message: 'compiled storybook',
  ),
  LogEntry(
    id: 3,
    source: 'runner',
    severity: LogSeverity.warning,
    message: 'using local terminal palette',
  ),
  LogEntry(
    id: 4,
    source: 'harness',
    severity: LogSeverity.info,
    message: 'frame capture complete',
  ),
];

const _sampleMessages = <MessageEntry>[
  MessageEntry(
    id: 'm1',
    role: MessageRole.user,
    author: 'User',
    text: 'Can you show the widget API in a live browser?',
  ),
  MessageEntry(
    id: 'm2',
    role: MessageRole.assistant,
    status: MessageStatus.streaming,
    author: 'Assistant',
    text: 'Opening the storybook and rendering the selected widget story.',
  ),
  MessageEntry(
    id: 'm3',
    role: MessageRole.tool,
    author: 'benchmark',
    text: 'median frame time: 4.8ms',
  ),
];

const _sampleConversations = <ConversationEntry>[
  ConversationEntry(
    id: 'c1',
    title: 'Benchmark scoreboard',
    subtitle: 'Perf follow-up',
    status: ConversationStatus.active,
    latestMessage: 'Run all peers before deciding.',
    unreadCount: 2,
    messageCount: 48,
    pinned: true,
  ),
  ConversationEntry(
    id: 'c2',
    title: 'Command palette DX',
    subtitle: 'API cleanup',
    status: ConversationStatus.complete,
    latestMessage: 'Scoped commands now surface by source context.',
    messageCount: 31,
  ),
  ConversationEntry(
    id: 'c3',
    title: 'Widget storybook',
    subtitle: 'Current task',
    status: ConversationStatus.streaming,
    latestMessage: 'Catalog implementation in progress.',
    unreadCount: 1,
    messageCount: 12,
  ),
];

const _sampleContext = <ContextItem>[
  ContextItem(
    id: 'ctx1',
    label: 'packages/fleury_widgets/lib/fleury_widgets.dart',
    kind: ContextItemKind.file,
    priority: ContextItemPriority.high,
    tokenCount: 1200,
    source: 'workspace',
    pinned: true,
  ),
  ContextItem(
    id: 'ctx2',
    label: 'benchmark scoreboard',
    kind: ContextItemKind.note,
    tokenCount: 700,
    source: 'docs',
  ),
  ContextItem(
    id: 'ctx3',
    label: 'CommandPalette.open(context)',
    kind: ContextItemKind.symbol,
    priority: ContextItemPriority.normal,
    tokenCount: 180,
    source: 'command_palette.dart',
  ),
];

const _sampleTasks = <TaskGraphNode>[
  TaskGraphNode(
    id: 'catalog',
    title: 'Build catalog',
    status: TaskGraphStatus.succeeded,
    description: 'Group widgets into interactive stories.',
  ),
  TaskGraphNode(
    id: 'launcher',
    title: 'Wire launcher',
    status: TaskGraphStatus.running,
    dependsOn: <String>['catalog'],
    progressCurrent: 1,
    progressTotal: 2,
  ),
  TaskGraphNode(
    id: 'verify',
    title: 'Run checks',
    status: TaskGraphStatus.pending,
    dependsOn: <String>['launcher'],
  ),
];

final _sampleTrace = <TraceTimelineEntry>[
  TraceTimelineEntry(
    id: 't1',
    label: 'Resolve story',
    kind: TraceTimelineKind.command,
    status: TraceTimelineStatus.succeeded,
    timestamp: DateTime(2026, 6, 9, 10),
    duration: const Duration(milliseconds: 12),
  ),
  TraceTimelineEntry(
    id: 't2',
    label: 'Build preview',
    kind: TraceTimelineKind.render,
    status: TraceTimelineStatus.running,
    timestamp: DateTime(2026, 6, 9, 10, 0, 1),
  ),
  TraceTimelineEntry(
    id: 't3',
    label: 'Collect semantics',
    kind: TraceTimelineKind.debug,
    status: TraceTimelineStatus.info,
    timestamp: DateTime(2026, 6, 9, 10, 0, 2),
  ),
];

final _sampleSnapshot = WorkflowSnapshot(
  id: 'storybook-build',
  title: 'Storybook build',
  messages: _sampleMessages,
  toolCalls: const <ToolCallRecord>[
    ToolCallRecord(
      id: 'tool-1',
      name: 'dart.analyze',
      status: ToolCallStatus.succeeded,
    ),
  ],
  approvals: const <ApprovalRequest>[
    ApprovalRequest(
      id: 'approval-1',
      title: 'Run smoke test',
      message: 'Run storybook smoke test.',
    ),
  ],
  tasks: _sampleTasks,
  contextItems: _sampleContext,
  conversations: _sampleConversations,
  traceEvents: _sampleTrace,
  logEntries: _sampleLogs,
);
