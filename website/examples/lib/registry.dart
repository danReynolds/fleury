// Web-safe widget examples for the docs site. These run client-side via
// dart2js (mountApp), so everything imports the dart:io-free host SPI
// (fleury_host) and the web-safe widget barrel (fleury_widgets_web) — never the
// full `fleury.dart` / `fleury_widgets.dart` umbrellas, which pull in native
// drivers and the dart:io-backed widgets.
import 'dart:math';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// Builds the root widget for one live example.
typedef ExampleBuilder = Widget Function();

/// Visual theme used by a docs embed.
enum DocsExampleStyle { dark, light }

/// Lets the host page retheme a live example after it has mounted.
final class DocsExampleThemeController extends ChangeNotifier {
  DocsExampleThemeController(this._style);

  DocsExampleStyle _style;

  DocsExampleStyle get style => _style;

  set style(DocsExampleStyle value) {
    if (value == _style) return;
    _style = value;
    notifyListeners();
  }
}

Widget themedExampleRoot(
  ExampleBuilder builder,
  DocsExampleThemeController controller,
) => ListenableBuilder(
  listenable: controller,
  child: builder(),
  builder: (context, child) {
    final theme = _themeFor(controller.style);
    return _DocsExampleTheme(
      data: theme,
      child: Theme(
        data: theme,
        // Docs embeds are intentionally not full applications, but interactive
        // examples still need a traversal policy now that browser hosts mount
        // their supplied root exactly.
        child: FocusTraversalGroup(child: child!),
      ),
    );
  },
);

/// One embeddable example, keyed by the `data-fleury-example` id used on the
/// docs page. This list is the single source of truth: it drives the live
/// mounts AND the generated widget-reference pages (via `bin/manifest.dart`).
class ExampleInfo {
  const ExampleInfo({
    required this.id,
    required this.widget,
    required this.category,
    required this.blurb,
    required this.builder,
    this.cols = 56,
    this.rows = 10,
    this.code,
    this.interactive = false,
  });

  /// Stable id, e.g. `gauge.basic`.
  final String id;

  /// Display name of the widget, e.g. `Gauge`.
  final String widget;

  /// Section the widget belongs to.
  final String category;

  /// One-line description for the reference page.
  final String blurb;

  /// Root-widget factory mounted via mountApp.
  final ExampleBuilder builder;

  /// Host grid size in cells — the example is framed to exactly this, not
  /// stretched to the page column.
  final int cols;
  final int rows;

  /// Optional override for the code shown on the page. Used by animated
  /// examples so the snippet stays the clean static widget usage while the live
  /// example streams. When null, the code is extracted from the builder source.
  final String? code;

  /// Whether the widget actually responds to keyboard/mouse input. Drives the
  /// "interactive" badge so it never over-promises on a view-only widget.
  /// (Knob-enabled widgets are interactive via their controls — see
  /// `knobExamples` — and are flagged in the page generator, not here.)
  final bool interactive;
}

final List<ExampleInfo> exampleList = <ExampleInfo>[
  // ── Landing hero (not catalogued — mounted directly on the home page) ─────
  ExampleInfo(
    id: 'home.monitor',
    widget: 'System monitor',
    category: 'Home',
    blurb: 'A compact system monitor built from a few Fleury widgets.',
    cols: 34,
    rows: 9,
    builder: () => _framed(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Gauge(value: 0.62, label: 'CPU'),
          const Gauge(value: 0.81, label: 'MEM'),
          const Gauge(value: 0.34, label: 'DISK'),
          const SizedBox(height: 1),
          Sparkline(
            data: const <num>[3, 5, 4, 8, 6, 9, 7, 5, 8, 6],
            color: _theme.colorScheme.primary,
          ),
        ],
      ),
    ),
  ),
  // ── Charts & meters ──────────────────────────────────────────────────────
  ExampleInfo(
    id: 'gauge.basic',
    widget: 'Gauge',
    category: 'Charts & meters',
    blurb:
        'A labelled progress meter with colored warning/critical thresholds.',
    cols: 40,
    rows: 3,
    builder: () => _framed(
      Gauge(
        value: 0.62,
        label: 'CPU',
        thresholds: <(double, Color)>[
          (0.7, _theme.colorScheme.warning),
          (0.9, _theme.colorScheme.error),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'sparkline.basic',
    widget: 'Sparkline',
    category: 'Charts & meters',
    blurb: 'A compact inline trend line with an optional trailing value.',
    cols: 44,
    rows: 2,
    code: '''Sparkline(
  data: <num>[3, 5, 4, 7, 6, 9, 8, 11, 9, 12],
  color: theme.colorScheme.success,
  showValue: true,
)''',
    builder: () => _framed(
      _LiveSeries(
        length: 28,
        min: 0,
        max: 20,
        builder: (data) => Sparkline(
          data: data,
          color: _theme.colorScheme.success,
          showValue: true,
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'linechart.basic',
    widget: 'LineChart',
    category: 'Charts & meters',
    blurb:
        'A braille line/area/scatter chart with axes, legend, and references.',
    cols: 60,
    rows: 16,
    code: '''LineChart(
  series: <LineSeries>[
    LineSeries(points, label: 'load', color: theme.colorScheme.primary),
  ],
  showAxes: true,
  showLegend: true,
  yRange: const (0, 100),
)''',
    builder: () => _framed(
      _LiveSeries(
        length: 40,
        min: 0,
        max: 100,
        builder: (data) => LineChart(
          series: <LineSeries>[
            LineSeries(
              <(num, num)>[for (var i = 0; i < data.length; i++) (i, data[i])],
              label: 'load',
              color: _theme.colorScheme.primary,
            ),
          ],
          showAxes: true,
          showLegend: true,
          yRange: const (0, 100),
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'barchart.basic',
    widget: 'BarChart',
    category: 'Charts & meters',
    blurb: 'Vertical bars with a categorical palette and an optional y-axis.',
    cols: 52,
    rows: 14,
    code: '''BarChart(
  bars: <Bar>[Bar('q1', 12), Bar('q2', 19), Bar('q3', 9), Bar('q4', 22)],
  showYAxis: true,
)''',
    builder: () => _framed(
      _LiveSeries(
        length: 5,
        min: 2,
        max: 24,
        builder: (data) => BarChart(
          bars: <Bar>[
            for (var i = 0; i < data.length; i++) Bar('q${i + 1}', data[i]),
          ],
          showYAxis: true,
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'histogram.basic',
    widget: 'Histogram',
    category: 'Charts & meters',
    blurb: 'Bins a list of samples into a frequency distribution.',
    cols: 52,
    rows: 12,
    builder: () => _framed(
      const Histogram(
        values: <num>[
          1,
          2,
          2,
          3,
          3,
          3,
          4,
          4,
          4,
          4,
          5,
          5,
          5,
          6,
          6,
          7,
          2,
          3,
          4,
          5,
        ],
        bins: 7,
        showValues: true,
      ),
    ),
  ),
  ExampleInfo(
    id: 'heatmap.basic',
    widget: 'Heatmap',
    category: 'Charts & meters',
    blurb: 'A 2-D grid of values shaded by magnitude, with an optional legend.',
    cols: 40,
    rows: 8,
    builder: () => _framed(
      const Heatmap(
        values: <List<num>>[
          <num>[0.1, 0.3, 0.6, 0.9],
          <num>[0.2, 0.5, 0.8, 0.4],
          <num>[0.7, 0.6, 0.3, 0.1],
        ],
        rowLabels: <String>['a', 'b', 'c'],
        colLabels: <String>['w', 'x', 'y', 'z'],
        showLegend: true,
      ),
    ),
  ),
  ExampleInfo(
    id: 'canvas.basic',
    widget: 'Canvas',
    category: 'Charts & meters',
    blurb: 'A sub-cell drawing surface for custom plots and diagrams.',
    cols: 52,
    rows: 11,
    code: '''Canvas(
  painter: SineWavePainter(),
  bounds: const CanvasBounds(minX: 0, maxX: 6.28, minY: -1, maxY: 1),
  semanticRole: SemanticRole.chart,
  semanticLabel: 'Sine wave',
)''',
    builder: () => _framed(
      SizedBox(
        width: 48,
        height: 9,
        child: Canvas(
          painter: _DocsCanvasPainter(),
          bounds: const CanvasBounds(minX: 0, maxX: 6.28, minY: -1, maxY: 1),
          semanticRole: SemanticRole.chart,
          semanticLabel: 'Sine wave',
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'panel.basic',
    widget: 'Panel',
    category: 'Layout',
    blurb:
        'A bordered, titled pane — the standard framing for dashboards and '
        'multi-pane screens; the accent border marks the focused pane.',
    cols: 44,
    rows: 8,
    builder: () => _framed(
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Panel(
              title: 'CPU',
              trailing: Text('42%'),
              focused: true,
              child: Sparkline(data: <num>[3, 5, 4, 8, 6, 9, 7, 5, 8, 6]),
            ),
          ),
          Expanded(
            child: Panel(
              title: 'MEM',
              trailing: Text('61%'),
              child: Sparkline(data: <num>[6, 6, 5, 7, 7, 8, 6, 7, 8, 8]),
            ),
          ),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'progressbar.basic',
    widget: 'ProgressBar',
    category: 'Charts & meters',
    blurb: 'A determinate or indeterminate progress indicator.',
    cols: 44,
    rows: 2,
    builder: () => _framed(const ProgressBar(value: 0.45)),
  ),
  ExampleInfo(
    id: 'digits.basic',
    widget: 'Digits',
    category: 'Charts & meters',
    blurb: 'Seven-segment-style large digits for clocks and counters.',
    cols: 56,
    rows: 11,
    interactive: true,
    code:
        '''// A live world clock: Tabs pick the zone, Digits show the ticking time.
// Switch zones with ← / → (or click a tab); the clock ticks every second.
Tabs(
  tabs: <TabItem>[
    TabItem(label: 'UTC', content: Digits(utcTime)),
    TabItem(label: 'EST', content: Digits(estTime)),
    // …one tab per zone — the selected tab's clock updates each second.
  ],
)''',
    builder: () => _framed(const _WorldClock()),
  ),

  // ── Data & lists ─────────────────────────────────────────────────────────
  ExampleInfo(
    id: 'datatable.basic',
    widget: 'DataTable',
    category: 'Data & lists',
    blurb: 'A columnar table with flex/fixed widths and row/cell selection.',
    cols: 48,
    rows: 8,
    interactive: true,
    builder: () => _framed(
      DataTable(
        rowCount: _people.length,
        controller: DataTableController(),
        selectionMode: DataTableSelectionMode.row,
        columns: const <DataTableColumn>[
          DataTableColumn(
            id: 'name',
            title: 'NAME',
            width: FixedColumnWidth(10),
          ),
          DataTableColumn(id: 'role', title: 'ROLE'),
          DataTableColumn(
            id: 'commits',
            title: 'COMMITS',
            width: FixedColumnWidth(9),
          ),
        ],
        cellBuilder: (row, col) {
          final p = _people[row];
          return switch (col) {
            'name' => p.$1,
            'role' => p.$2,
            _ => p.$3.toString(),
          };
        },
      ),
    ),
  ),
  ExampleInfo(
    id: 'tree.basic',
    widget: 'Tree',
    category: 'Data & lists',
    blurb: 'An expandable hierarchy with keyboard navigation and type-ahead.',
    cols: 40,
    rows: 9,
    interactive: true,
    builder: () => _framed(
      Tree<String>(
        semanticLabel: 'project',
        roots: <TreeNode<String>>[
          TreeNode<String>(
            'lib/',
            children: <TreeNode<String>>[
              const TreeNode<String>('main.dart'),
              TreeNode<String>(
                'src/',
                children: const <TreeNode<String>>[
                  TreeNode<String>('app.dart'),
                  TreeNode<String>('theme.dart'),
                ],
              ),
            ],
          ),
          const TreeNode<String>('README.md'),
        ],
      ),
    ),
  ),

  // ── Documents ────────────────────────────────────────────────────────────
  ExampleInfo(
    id: 'markdown.basic',
    widget: 'MarkdownView',
    category: 'Documents',
    blurb:
        'Renders Markdown — headings, lists, code, quotes — to styled cells.',
    cols: 60,
    rows: 13,
    interactive: true,
    builder: () => _framed(MarkdownView(markdown: _markdownSample)),
  ),
  ExampleInfo(
    id: 'markdowntext.basic',
    widget: 'MarkdownText',
    category: 'Documents',
    blurb: 'Lightweight Markdown for headings, emphasis, lists, and links.',
    cols: 56,
    rows: 9,
    code: """MarkdownText('''
## Release

- **Checks:** passing
- [Open the docs](https://example.com)
''')""",
    builder: () => _framed(
      const MarkdownText('''
## Release

- **Checks:** passing
- **Target:** terminal + browser
- [Open the docs](https://example.com)
'''),
    ),
  ),
  ExampleInfo(
    id: 'codeview.basic',
    widget: 'CodeView',
    category: 'Documents',
    blurb: 'Source with line numbers, comment dimming, and copy support.',
    cols: 58,
    rows: 12,
    interactive: true,
    builder: () => _framed(CodeView(source: _codeSample, language: 'dart')),
  ),
  ExampleInfo(
    id: 'jsonview.basic',
    widget: 'JsonView',
    category: 'Documents',
    blurb: 'A collapsible, type-colored tree view of a JSON value.',
    cols: 48,
    rows: 10,
    interactive: true,
    builder: () => _framed(
      JsonView(
        value: const <String, Object?>{
          'name': 'fleury',
          'version': '1.0.0',
          'web': true,
          'targets': <String>['terminal', 'dom', 'serve'],
        },
        initialExpandedDepth: 2,
      ),
    ),
  ),

  // ── Agent surfaces ───────────────────────────────────────────────────────
  ExampleInfo(
    id: 'messagelist.basic',
    widget: 'MessageList',
    category: 'Agent surfaces',
    blurb: 'A role-aware conversation transcript (user/assistant/tool/…).',
    cols: 64,
    rows: 11,
    interactive: true,
    builder: () => _framed(
      MessageList(
        showTimestamp: false,
        messages: const <MessageEntry>[
          MessageEntry(text: 'Add a --version flag.', role: MessageRole.user),
          MessageEntry(
            text: "I'll read the CLI and pubspec first.",
            role: MessageRole.assistant,
          ),
          MessageEntry(text: 'Read  lib/main.dart', role: MessageRole.tool),
          MessageEntry(text: 'Read  pubspec.yaml', role: MessageRole.tool),
          MessageEntry(
            text:
                'Found version 1.4.0 in pubspec. Adding a --version flag '
                'that prints it and exits.',
            role: MessageRole.assistant,
          ),
          MessageEntry(
            text: 'Edit  lib/main.dart (+8 −0)',
            role: MessageRole.tool,
          ),
          MessageEntry(text: 'dart test', role: MessageRole.tool),
          MessageEntry(
            text: 'All 12 tests pass. `myapp --version` prints 1.4.0.',
            role: MessageRole.assistant,
          ),
          MessageEntry(text: 'Ship it 🚀', role: MessageRole.user),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'contextpanel.basic',
    widget: 'ContextPanel',
    category: 'Agent surfaces',
    blurb: 'Lists context items with a token-usage meter and share bars.',
    cols: 56,
    rows: 9,
    builder: () => _framed(
      ContextPanel(
        showTokenShare: true,
        usage: const TokenUsage(
          input: 9200,
          output: 3100,
          contextUsed: 12300,
          contextLimit: 200000,
        ),
        items: const <ContextItem>[
          ContextItem(
            id: 'a',
            label: 'lib/main.dart',
            kind: ContextItemKind.file,
            tokenCount: 410,
          ),
          ContextItem(
            id: 'b',
            label: 'pubspec.yaml',
            kind: ContextItemKind.file,
            tokenCount: 120,
          ),
          ContextItem(
            id: 'c',
            label: 'dart test',
            kind: ContextItemKind.command,
            tokenCount: 90,
          ),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'taskgraph.basic',
    widget: 'TaskGraph',
    category: 'Agent surfaces',
    blurb: 'A compact plan / dependency graph with per-node status.',
    cols: 48,
    rows: 6,
    builder: () => _framed(
      const TaskGraph(
        nodes: <TaskGraphNode>[
          TaskGraphNode(
            id: '1',
            title: 'Inspect CLI',
            status: TaskGraphStatus.succeeded,
          ),
          TaskGraphNode(
            id: '2',
            title: 'Handle --version',
            status: TaskGraphStatus.running,
          ),
          TaskGraphNode(
            id: '3',
            title: 'Add a test',
            status: TaskGraphStatus.pending,
          ),
        ],
      ),
    ),
  ),

  // ── Inputs & controls ────────────────────────────────────────────────────
  ExampleInfo(
    id: 'textinput.basic',
    widget: 'TextInput',
    category: 'Inputs & controls',
    blurb:
        'A single-line editor with selection, clipboard, history, and completion support.',
    cols: 44,
    rows: 4,
    interactive: true,
    code: '''final controller = TextEditingController(text: 'deploy staging')
  ..selection = const TextSelection(baseOffset: 7, extentOffset: 14);

TextInput(
  controller: controller,
  semanticLabel: 'Command',
  onChanged: (text) => updateDraft(text),
  onSubmit: (text) => runCommand(text),
)''',
    builder: () => const _TextInputExample(),
  ),
  ExampleInfo(
    id: 'textarea.basic',
    widget: 'TextArea',
    category: 'Inputs & controls',
    blurb:
        'A multiline editor with shared selection, clipboard, paste, and semantic editing.',
    cols: 44,
    rows: 7,
    interactive: true,
    code: '''TextArea(
  minLines: 4,
  maxLines: 8,
  placeholder: 'Write release notes…',
  semanticLabel: 'Release notes',
  keymap: TextEditingKeymap.chat,
  onChanged: (text) => updateReleaseNotes(text),
  onSubmit: (text) => saveReleaseNotes(text),
)''',
    builder: () => _framed(
      TextArea(
        autofocus: true,
        minLines: 4,
        maxLines: 4,
        placeholder: 'Write release notes…',
        semanticLabel: 'Release notes',
        onChanged: (_) {},
      ),
    ),
  ),
  ExampleInfo(
    id: 'form.basic',
    widget: 'FormPanel',
    category: 'Inputs & controls',
    blurb:
        'A declarative, validated form that runs in terminal, served, and embedded apps.',
    cols: 54,
    rows: 12,
    interactive: true,
    code: '''FormPanel(
  definition: FormDefinition(
    title: 'Project settings',
    fields: <FormFieldSpec>[
      FormFieldSpec.text(id: 'name', label: 'Name', required: true),
      FormFieldSpec.checkbox(id: 'private', label: 'Private project'),
    ],
  ),
  onSubmit: (result) => saveSettings(result.values),
)''',
    builder: () => _framed(
      FormPanel(
        definition: FormDefinition(
          title: 'Project settings',
          fields: <FormFieldSpec>[
            FormFieldSpec.text(
              id: 'name',
              label: 'Name',
              initialValue: 'fleury',
              required: true,
            ),
            FormFieldSpec.checkbox(id: 'private', label: 'Private project'),
          ],
        ),
        layout: FormPanelLayout.inline,
        onSubmit: (_) {},
      ),
    ),
  ),
  ExampleInfo(
    id: 'formwizard.basic',
    widget: 'FormWizard',
    category: 'Inputs & controls',
    blurb: 'A validated form split into an ordered sequence of steps.',
    cols: 54,
    rows: 13,
    interactive: true,
    code: '''FormWizard(
  definition: definition,
  steps: const <FormWizardStep>[
    FormWizardStep(id: 'project', title: 'Project', fieldIds: ['name']),
    FormWizardStep(id: 'access', title: 'Access', fieldIds: ['private']),
  ],
  onSubmit: handleSubmit,
)''',
    builder: () => _framed(
      FormWizard(
        definition: FormDefinition(
          title: 'Create project',
          fields: <FormFieldSpec>[
            FormFieldSpec.text(
              id: 'name',
              label: 'Name',
              initialValue: 'fleury-app',
              required: true,
            ),
            FormFieldSpec.checkbox(id: 'private', label: 'Private project'),
          ],
        ),
        steps: const <FormWizardStep>[
          FormWizardStep(
            id: 'project',
            title: 'Project',
            fieldIds: <String>['name'],
          ),
          FormWizardStep(
            id: 'access',
            title: 'Access',
            fieldIds: <String>['private'],
          ),
        ],
        layout: FormPanelLayout.inline,
        fieldWidth: 24,
        onSubmit: (_) {},
      ),
    ),
  ),
  ExampleInfo(
    id: 'button.basic',
    widget: 'Button',
    category: 'Inputs & controls',
    blurb: 'A focusable action button; activate with Enter/Space.',
    cols: 24,
    rows: 4,
    interactive: true,
    code: '''Button(
  label: 'Save',
  variant: ButtonVariant.primary,
  onPressed: () => save(),
)''',
    builder: () => const _ButtonExample(),
  ),
  ExampleInfo(
    id: 'checkbox.basic',
    widget: 'Checkbox',
    category: 'Inputs & controls',
    blurb: 'A controlled boolean input; toggle it with Enter or Space.',
    cols: 36,
    rows: 4,
    interactive: true,
    code: '''Checkbox(
  value: _accepted,
  label: 'Accept terms',
  onChanged: (value) => setState(() => _accepted = value),
)''',
    builder: () => const _CheckboxExample(),
  ),
  ExampleInfo(
    id: 'toggle.basic',
    widget: 'Toggle',
    category: 'Inputs & controls',
    blurb: 'A compact controlled on/off toggle.',
    cols: 34,
    rows: 4,
    interactive: true,
    code: '''Toggle(
  value: _compact,
  label: 'Compact rows',
  onChanged: (value) => setState(() => _compact = value),
)''',
    builder: () => const _ToggleExample(),
  ),
  ExampleInfo(
    id: 'switch.basic',
    widget: 'Switch',
    category: 'Inputs & controls',
    blurb: 'An accent-tinted controlled switch for prominent settings.',
    cols: 40,
    rows: 4,
    interactive: true,
    code: '''Switch(
  value: _streaming,
  label: 'Streaming updates',
  onChanged: (value) => setState(() => _streaming = value),
)''',
    builder: () => const _SwitchExample(),
  ),
  ExampleInfo(
    id: 'radio.basic',
    widget: 'Radio',
    category: 'Inputs & controls',
    blurb: 'A controlled single choice within a group of radio inputs.',
    cols: 34,
    rows: 6,
    interactive: true,
    code: '''Radio<String>(
  value: 'fast',
  groupValue: _mode,
  label: 'Fast',
  onChanged: (value) => setState(() => _mode = value),
)''',
    builder: () => const _RadioExample(),
  ),
  ExampleInfo(
    id: 'radiogroup.basic',
    widget: 'RadioGroup',
    category: 'Inputs & controls',
    blurb: 'A roving, arrow-key-navigable group of radio choices.',
    cols: 40,
    rows: 6,
    interactive: true,
    code: '''RadioGroup<String>(
  value: _mode,
  options: const <RadioOption<String>>[
    RadioOption(value: 'fast', label: 'Fast'),
    RadioOption(value: 'safe', label: 'Safe'),
  ],
  onChanged: (value) => setState(() => _mode = value),
)''',
    builder: () => const _RadioGroupExample(),
  ),
  ExampleInfo(
    id: 'select.basic',
    widget: 'Select',
    category: 'Inputs & controls',
    blurb: 'A single-choice dropdown; open it with Enter and pick with ↑/↓.',
    cols: 40,
    rows: 6,
    interactive: true,
    code: '''Select<String>(
  value: _size,
  options: const [
    SelectOption(value: 'low', label: 'Low'),
    SelectOption(value: 'medium', label: 'Medium'),
    SelectOption(value: 'high', label: 'High'),
  ],
  onChanged: (value) => setState(() => _size = value),
)''',
    builder: () => const _SelectExample(),
  ),
  ExampleInfo(
    id: 'multiselect.basic',
    widget: 'MultiSelect',
    category: 'Inputs & controls',
    blurb: 'A keyboard-navigable list of independently checkable options.',
    cols: 42,
    rows: 8,
    interactive: true,
    code: '''MultiSelect<String>(
  options: options,
  values: _selected,
  onChanged: (values) => setState(() => _selected = values),
)''',
    builder: () => const _MultiSelectExample(),
  ),
  ExampleInfo(
    id: 'rangeslider.basic',
    widget: 'RangeSlider',
    category: 'Inputs & controls',
    blurb: 'A two-handle slider for picking a low/high range.',
    cols: 44,
    rows: 5,
    interactive: true,
    code: '''RangeSlider(
  values: _range,
  min: 0,
  max: 100,
  label: 'Range',
  showValues: true,
  onChanged: (values) => setState(() => _range = values),
)''',
    builder: () => const _RangeSliderExample(),
  ),
  ExampleInfo(
    id: 'stepper.basic',
    widget: 'Stepper',
    category: 'Inputs & controls',
    blurb: 'Increment/decrement a number with ↑/↓ (×10 with Shift).',
    cols: 40,
    rows: 3,
    interactive: true,
    code: '''Stepper(
  value: _quantity,
  min: 0,
  max: 10,
  label: 'Quantity',
  onChanged: (value) => setState(() => _quantity = value),
)''',
    builder: () => const _StepperExample(),
  ),
  ExampleInfo(
    id: 'numberinput.basic',
    widget: 'NumberInput',
    category: 'Inputs & controls',
    blurb:
        'A numeric text field with min/max clamping; type or wheel to change.',
    cols: 36,
    rows: 3,
    interactive: true,
    builder: () =>
        _framed(const NumberInput(initialValue: 42, min: 0, max: 100)),
  ),
  ExampleInfo(
    id: 'passwordinput.basic',
    widget: 'PasswordInput',
    category: 'Inputs & controls',
    blurb: 'An obscured text field with a reveal chord (Ctrl-R).',
    cols: 40,
    rows: 3,
    interactive: true,
    builder: () => _framed(const PasswordInput(placeholder: 'Password')),
  ),
  ExampleInfo(
    id: 'autocomplete.basic',
    widget: 'Autocomplete',
    category: 'Inputs & controls',
    blurb: 'A text field that filters a list of options as you type.',
    cols: 44,
    rows: 7,
    interactive: true,
    builder: () => _framed(
      Autocomplete<String>(
        placeholder: 'Type a fruit…',
        options: const <String>[
          'Apple',
          'Apricot',
          'Banana',
          'Cherry',
          'Grape',
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'colorpicker.basic',
    widget: 'ColorPicker',
    category: 'Inputs & controls',
    blurb: 'A swatch grid; move with the arrow keys, choose with Enter.',
    cols: 36,
    rows: 4,
    interactive: true,
    code: '''ColorPicker(
  value: _color,
  colors: const [
    RgbColor(0xFF, 0x5C, 0x57),
    RgbColor(0xF5, 0xC2, 0x11),
    RgbColor(0x3D, 0xDC, 0x97),
    RgbColor(0x56, 0xC2, 0xFF),
    RgbColor(0xBD, 0x93, 0xF9),
  ],
  onChanged: (color) => setState(() => _color = color),
)''',
    builder: () => const _ColorPickerExample(),
  ),
  ExampleInfo(
    id: 'datepicker.basic',
    widget: 'DatePicker',
    category: 'Inputs & controls',
    blurb: 'A month calendar; arrow keys move days, PageUp/Down change month.',
    cols: 30,
    rows: 12,
    interactive: true,
    code: '''DatePicker(
  value: _date,
  label: 'Date',
  onChanged: (date) => setState(() => _date = date),
)''',
    builder: () => const _DatePickerExample(),
  ),

  // ── Navigation & overlays ────────────────────────────────────────────────
  ExampleInfo(
    id: 'tabs.basic',
    widget: 'Tabs',
    category: 'Navigation & overlays',
    blurb: 'A tab strip over swappable panels; ←/→ switch tabs.',
    cols: 48,
    rows: 6,
    interactive: true,
    builder: () => _framed(
      Tabs(
        tabs: <TabItem>[
          TabItem(
            label: 'Overview',
            content: _framed(const Text('Project at a glance.')),
          ),
          TabItem(
            label: 'Logs',
            content: _framed(const Text('› build finished in 1.8s')),
          ),
          TabItem(
            label: 'Settings',
            content: _framed(const Text('Theme · keybindings · …')),
          ),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'menu.basic',
    widget: 'Menu',
    category: 'Navigation & overlays',
    blurb: 'A trigger that opens a list of actions.',
    cols: 40,
    rows: 7,
    interactive: true,
    builder: () => _framed(
      Menu(
        trigger: const Text('Actions ▾'),
        items: <MenuEntry>[
          MenuItem(label: 'Rename', onSelect: () {}),
          MenuItem(label: 'Duplicate', onSelect: () {}),
          MenuItem(label: 'Delete', onSelect: () {}),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'tooltip.basic',
    widget: 'Tooltip',
    category: 'Navigation & overlays',
    blurb: 'A hover/focus hint attached to any child.',
    cols: 40,
    rows: 4,
    interactive: true,
    builder: () => _framed(
      const Tooltip(message: 'Saves the current file', child: Text('[ Save ]')),
    ),
  ),
  ExampleInfo(
    id: 'dialog.basic',
    widget: 'Dialog',
    category: 'Navigation & overlays',
    blurb: 'A bordered, titled modal surface.',
    cols: 44,
    rows: 6,
    builder: () => _framed(
      const Dialog(
        title: 'Confirm',
        child: Text('Delete 3 files? This cannot be undone.'),
      ),
    ),
  ),
  ExampleInfo(
    id: 'keyhintbar.basic',
    widget: 'KeyHintBar',
    category: 'Navigation & overlays',
    blurb: 'Shows the active focus chain’s visible keyboard bindings.',
    cols: 52,
    rows: 6,
    code: '''KeyBindings(
  bindings: <KeyBinding>[
    KeyBinding(KeyChord.char('s'), label: 'Save', onEvent: save),
    KeyBinding(KeyChord.char('q'), label: 'Quit', onEvent: quit),
  ],
  child: const KeyHintBar(),
)''',
    builder: () => _framed(
      KeyBindings(
        bindings: <KeyBinding>[
          KeyBinding(KeyChord.char('s'), label: 'Save', onEvent: (_) {}),
          KeyBinding(KeyChord.char('r'), label: 'Run', onEvent: (_) {}),
          KeyBinding(KeyChord.char('q'), label: 'Quit', onEvent: (_) {}),
        ],
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Focus(autofocus: true, child: Text('Focused editor')),
            SizedBox(height: 1),
            KeyHintBar(),
          ],
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'commandpalette.basic',
    widget: 'CommandPalette',
    category: 'Navigation & overlays',
    blurb: 'A fuzzy command launcher; type to filter, Enter to invoke.',
    cols: 52,
    rows: 10,
    interactive: true,
    builder: () => _framed(
      CommandPalette(
        commands: <Command>[
          Command(label: 'Open file…', shortcut: 'Ctrl-P', onInvoke: () {}),
          Command(label: 'Toggle theme', category: 'View', onInvoke: () {}),
          Command(label: 'Run tests', shortcut: 'Ctrl-T', onInvoke: () {}),
          Command(label: 'Git: commit', category: 'Git', onInvoke: () {}),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'searchpanel.basic',
    widget: 'SearchPanel',
    category: 'Navigation & overlays',
    blurb: 'A query box over a result list, grouped and copyable.',
    cols: 60,
    rows: 11,
    interactive: true,
    builder: () => _framed(
      const SearchPanel(
        groupByCategory: true,
        results: <SearchResult>[
          SearchResult(title: 'main.dart', subtitle: 'lib/', category: 'Files'),
          SearchResult(
            title: 'pubspec.yaml',
            subtitle: './',
            category: 'Files',
          ),
          SearchResult(
            title: 'runApp',
            subtitle: 'lib/src/app.dart',
            category: 'Symbols',
          ),
          SearchResult(
            title: 'Gauge',
            subtitle: 'widgets/gauge.dart',
            category: 'Symbols',
          ),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'filementionpicker.basic',
    widget: 'FileMentionPicker',
    category: 'Navigation & overlays',
    blurb: 'An @-mention picker for files; type to filter the project.',
    cols: 56,
    rows: 8,
    interactive: true,
    builder: () => _framed(
      const FileMentionPicker(
        entries: <FileMentionEntry>[
          FileMentionEntry(path: 'lib/main.dart', label: 'main.dart'),
          FileMentionEntry(path: 'lib/src/app.dart', label: 'app.dart'),
          FileMentionEntry(path: 'pubspec.yaml', label: 'pubspec.yaml'),
          FileMentionEntry(path: 'README.md', label: 'README.md'),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'completiontextinput.basic',
    widget: 'CompletionTextInput',
    category: 'Inputs & controls',
    blurb: 'A text field with inline completion suggestions as you type.',
    cols: 44,
    rows: 7,
    interactive: true,
    builder: () => _framed(
      CompletionTextInput(
        placeholder: 'Type a command…',
        showOnEmptyQuery: true,
        provider: (request) {
          const options = <TextCompletionOption>[
            TextCompletionOption(label: 'benchmark'),
            TextCompletionOption(label: 'storybook'),
            TextCompletionOption(label: 'command-palette'),
            TextCompletionOption(label: 'semantic-tree'),
          ];
          final q = request.query.toLowerCase();
          return options.where((o) => o.label.toLowerCase().contains(q));
        },
      ),
    ),
  ),

  // ── Data & lists ─────────────────────────────────────────────────────────
  ExampleInfo(
    id: 'table.basic',
    widget: 'Table',
    category: 'Data & lists',
    blurb: 'A text table of widget cells, with optional row selection.',
    cols: 44,
    rows: 6,
    interactive: true,
    builder: () => _framed(
      Table(
        selectable: true,
        header: const <Widget>[Text('Name'), Text('Role'), Text('Commits')],
        rows: const <List<Widget>>[
          <Widget>[Text('dan'), Text('author'), Text('1284')],
          <Widget>[Text('ada'), Text('reviewer'), Text('642')],
          <Widget>[Text('lin'), Text('docs'), Text('219')],
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'treetable.basic',
    widget: 'TreeTable',
    category: 'Data & lists',
    blurb: 'A hierarchical, expandable table; ←/→ collapse and expand rows.',
    cols: 48,
    rows: 9,
    interactive: true,
    builder: () => _framed(
      TreeTable<String>(
        treeColumnId: 'name',
        columns: const <DataTableColumn>[
          DataTableColumn(id: 'name', title: 'Name'),
          DataTableColumn(id: 'size', title: 'Size'),
        ],
        roots: const <TreeTableNode<String>>[
          TreeTableNode(
            key: 'lib',
            label: 'lib',
            cells: <String, String>{'size': '—'},
            children: <TreeTableNode<String>>[
              TreeTableNode(
                key: 'main',
                label: 'main.dart',
                cells: <String, String>{'size': '1.2k'},
              ),
              TreeTableNode(
                key: 'app',
                label: 'app.dart',
                cells: <String, String>{'size': '8.4k'},
              ),
            ],
          ),
          TreeTableNode(
            key: 'pub',
            label: 'pubspec.yaml',
            cells: <String, String>{'size': '512'},
          ),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'calendarheatmap.basic',
    widget: 'CalendarHeatmap',
    category: 'Data & lists',
    blurb: 'A GitHub-style contribution grid keyed by date.',
    cols: 56,
    rows: 9,
    builder: () => _framed(
      CalendarHeatmap(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 3, 31),
        color: _theme.colorScheme.primary,
        values: <DateTime, num>{
          DateTime(2026, 1, 6): 2,
          DateTime(2026, 1, 14): 5,
          DateTime(2026, 1, 21): 8,
          DateTime(2026, 2, 3): 3,
          DateTime(2026, 2, 10): 6,
          DateTime(2026, 2, 18): 9,
          DateTime(2026, 3, 2): 4,
          DateTime(2026, 3, 11): 7,
          DateTime(2026, 3, 20): 1,
        },
      ),
    ),
  ),

  // ── Agent surfaces (more) ────────────────────────────────────────────────
  ExampleInfo(
    id: 'approvalprompt.basic',
    widget: 'ApprovalPrompt',
    category: 'Agent surfaces',
    blurb: 'A yes/no approval card for gating risky agent actions.',
    cols: 56,
    rows: 8,
    interactive: true,
    builder: () => _framed(
      ApprovalPrompt(
        onDecision: (d) {},
        request: const ApprovalRequest(
          id: 'a1',
          title: 'Run on bare metal?',
          message:
              'This will reserve the terminal and write benchmark artifacts.',
          subject: 'Tier-C benchmark',
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'diffview.basic',
    widget: 'DiffView',
    category: 'Agent surfaces',
    blurb: 'A unified diff with line numbers and word-level highlighting.',
    cols: 56,
    rows: 9,
    interactive: true,
    builder: () => _framed(DiffView(diff: _diffSample)),
  ),
  ExampleInfo(
    id: 'patchreview.basic',
    widget: 'PatchReview',
    category: 'Agent surfaces',
    blurb: 'A file-by-file patch review surface over a diff.',
    cols: 60,
    rows: 12,
    interactive: true,
    builder: () => _framed(
      PatchReview(diff: _diffSample, status: PatchReviewStatus.pending),
    ),
  ),
  ExampleInfo(
    id: 'toolcallcard.basic',
    widget: 'ToolCallCard',
    category: 'Agent surfaces',
    blurb: 'A card summarizing one tool/function call and its result.',
    cols: 56,
    rows: 8,
    builder: () => _framed(
      ToolCallCard(
        record: ToolCallRecord(
          id: 't1',
          name: 'benchmark.run',
          title: 'Run benchmark',
          status: ToolCallStatus.succeeded,
          description: 'Capture peer comparison output.',
          arguments: const <String, Object?>{
            'scenario': 'sb6_data_table',
            'peers': <String>['ratatui', 'bubbletea'],
          },
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'tracetimeline.basic',
    widget: 'TraceTimeline',
    category: 'Agent surfaces',
    blurb: 'A vertical timeline of trace events with status and timing.',
    cols: 56,
    rows: 8,
    interactive: true,
    builder: () => _framed(
      TraceTimeline(
        events: <TraceTimelineEntry>[
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
            label: 'Run tests',
            kind: TraceTimelineKind.command,
            status: TraceTimelineStatus.running,
            timestamp: DateTime(2026, 6, 9, 10, 0, 1),
          ),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'conversationnavigator.basic',
    widget: 'ConversationNavigator',
    category: 'Agent surfaces',
    blurb: 'A searchable list of conversations with status and unread counts.',
    cols: 60,
    rows: 8,
    interactive: true,
    builder: () => _framed(
      const ConversationNavigator(
        conversations: <ConversationEntry>[
          ConversationEntry(
            id: 'c1',
            title: 'Benchmark scoreboard',
            subtitle: 'Perf follow-up',
            status: ConversationStatus.active,
            latestMessage: 'Run all peers before deciding.',
            unreadCount: 2,
          ),
          ConversationEntry(
            id: 'c2',
            title: 'Docs site',
            status: ConversationStatus.idle,
            latestMessage: 'Tabbed examples shipped.',
          ),
        ],
      ),
    ),
  ),
  ExampleInfo(
    id: 'modelstatusbar.basic',
    widget: 'ModelStatusBar',
    category: 'Agent surfaces',
    blurb:
        'A status line for the active model: provider, mode, latency, tokens.',
    cols: 60,
    rows: 3,
    builder: () => _framed(
      const ModelStatusBar(
        info: ModelStatusInfo(
          model: 'claude-opus-4-8',
          provider: 'Anthropic',
          status: ModelRuntimeStatus.streaming,
          mode: 'edit',
          latency: Duration(milliseconds: 180),
          tokenUsage: TokenUsage(
            input: 8200,
            output: 1400,
            contextUsed: 64000,
            contextLimit: 200000,
          ),
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'tokenmeter.basic',
    widget: 'TokenMeter',
    category: 'Agent surfaces',
    blurb: 'A compact context-window and token-usage indicator.',
    cols: 52,
    rows: 3,
    code: '''TokenMeter(
  usage: const TokenUsage(contextUsed: 128000, contextLimit: 200000),
  label: 'Context',
  width: 20,
)''',
    builder: () => _framed(
      const TokenMeter(
        usage: TokenUsage(
          input: 8200,
          output: 1400,
          contextUsed: 128000,
          contextLimit: 200000,
        ),
        label: 'Context',
        width: 20,
      ),
    ),
  ),

  // ── Showcases (full apps; rendered on the Showcases page, not as widgets) ──
  ExampleInfo(
    id: 'showcase.dashboard',
    widget: 'System monitor',
    category: 'Showcases',
    blurb:
        'An htop-style live dashboard: per-core CPU gauges, a streaming history '
        'chart, memory/IO meters, and a live process table.',
    cols: 116,
    rows: 38,
    interactive: true,
    builder: () => const DashboardApp(),
  ),
  ExampleInfo(
    id: 'showcase.files',
    widget: 'File manager',
    category: 'Showcases',
    blurb:
        'A two-pane file explorer over an in-memory project, with a preview that '
        'adapts to each file type (code, Markdown, JSON).',
    cols: 104,
    rows: 26,
    interactive: true,
    builder: () => const FileManagerApp(),
  ),
  ExampleInfo(
    id: 'showcase.agent',
    widget: 'Coding agent',
    category: 'Showcases',
    blurb:
        'A Claude-Code-style streaming session: prose, tool cards, a live todo '
        'list, a colored diff, and a prompt box.',
    cols: 92,
    rows: 34,
    interactive: true,
    builder: () => const AgentApp(),
  ),
];

/// id → builder, derived from [exampleList].
final Map<String, ExampleBuilder> examples = <String, ExampleBuilder>{
  for (final e in exampleList) e.id: e.builder,
};

const List<(String, String, int)> _people = <(String, String, int)>[
  ('dan', 'author', 1284),
  ('ada', 'reviewer', 642),
  ('lin', 'docs', 219),
  ('rey', 'infra', 877),
];

const String _markdownSample = '''
# Fleury

A **retained-mode** UI framework for the terminal — and the browser.

## Targets

- **terminal** — POSIX & Windows drivers
- **web (serve)** — stream frames to a browser over a socket
- **web (embed)** — compile the widget tree to JS with dart2js

## Why

> One widget tree. Two surfaces. No rewrite.

Build with the same `Widget` / `State` / `build` model you know from
Flutter, then run it wherever your users are — a terminal, or a
`<div>` on a page.

```dart
runApp(const App());
```

See the **Guides** for theming, animation, focus, and testing.
''';

const String _diffSample = '''@@ -1,5 +1,5 @@
 void main() {
-  final greeting = 'hi';
-  print(greeting);
+  final greeting = 'hello';
+  print(greeting.toUpperCase());
 }
''';

const String _codeSample = '''
import 'package:fleury/fleury.dart';

/// A tiny counter — the smallest interesting Fleury program.
void main() => runApp(
      const CounterApp(),
      onEvent: (event) => event is KeyEvent && event.char == 'q'
          ? const ExitRequested()
          : null,
    );

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  void _increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('count: \$_count'),
          const SizedBox(height: 1),
          Button(label: '+1', onPressed: _increment),
        ],
      ),
    );
  }
}
''';

// Compact docs themes so embedded examples read well against the site chrome.
final ThemeData _theme = const ThemeData(
  brightness: Brightness.dark,
  textStyle: CellStyle(foreground: RgbColor(0xC8, 0xD3, 0xE0)),
  mutedStyle: CellStyle(foreground: RgbColor(0x6B, 0x7A, 0x8C)),
  borderStyle: BorderStyle.rounded,
  colorScheme: ColorScheme(
    foreground: RgbColor(0xC8, 0xD3, 0xE0),
    primary: RgbColor(0x3D, 0xDC, 0x97),
    success: RgbColor(0x3D, 0xDC, 0x97),
    warning: RgbColor(0xF5, 0xC2, 0x11),
    error: RgbColor(0xFF, 0x5C, 0x57),
    info: RgbColor(0x56, 0xC2, 0xFF),
  ),
);

final ThemeData _lightTheme = const ThemeData(
  brightness: Brightness.light,
  textStyle: CellStyle(foreground: RgbColor(0x20, 0x2A, 0x25)),
  mutedStyle: CellStyle(foreground: RgbColor(0x72, 0x7F, 0x78)),
  selectionStyle: CellStyle(
    foreground: RgbColor(0xF7, 0xFF, 0xFB),
    background: RgbColor(0x13, 0x8A, 0x5C),
  ),
  focusedStyle: CellStyle(bold: true, foreground: RgbColor(0x0A, 0x36, 0x25)),
  borderStyle: BorderStyle.rounded,
  colorScheme: ColorScheme(
    foreground: RgbColor(0x20, 0x2A, 0x25),
    primary: RgbColor(0x13, 0x8A, 0x5C),
    success: RgbColor(0x13, 0x8A, 0x5C),
    warning: RgbColor(0x9A, 0x6B, 0x00),
    error: RgbColor(0xB4, 0x23, 0x18),
    info: RgbColor(0x0A, 0x66, 0xA0),
  ),
);

ThemeData _themeFor(DocsExampleStyle style) => switch (style) {
  DocsExampleStyle.dark => _theme,
  DocsExampleStyle.light => _lightTheme,
};

Widget _framed(Widget child) => _Framed(child: child);

class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: _DocsExampleTheme.maybeOf(context) ?? _theme,
    child: Padding(padding: const EdgeInsets.all(1), child: child),
  );
}

class _DocsExampleTheme extends InheritedWidget {
  const _DocsExampleTheme({required this.data, required super.child});

  final ThemeData data;

  static ThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DocsExampleTheme>()?.data;

  @override
  bool updateShouldNotify(_DocsExampleTheme oldWidget) =>
      oldWidget.data != data;
}

// ── Stateful wrappers ───────────────────────────────────────────────────────
// Controlled widgets (value + onChanged) need a holder so interacting with the
// live example actually moves them; self-managing widgets are used directly.
final class _DocsCanvasPainter extends CanvasPainter {
  @override
  void paint(CanvasContext ctx) {
    const segments = 96;
    var previousX = 0.0;
    var previousY = 0.0;
    for (var i = 1; i <= segments; i++) {
      final x = 6.28 * i / segments;
      final y = sin(x);
      ctx.drawLine(previousX, previousY, x, y);
      previousX = x;
      previousY = y;
    }
  }
}

class _CheckboxExample extends StatefulWidget {
  const _CheckboxExample();

  @override
  State<_CheckboxExample> createState() => _CheckboxExampleState();
}

class _CheckboxExampleState extends State<_CheckboxExample> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => _framed(
    Checkbox(
      value: _accepted,
      label: 'Accept terms',
      autofocus: true,
      onChanged: (value) => setState(() => _accepted = value),
    ),
  );
}

class _ToggleExample extends StatefulWidget {
  const _ToggleExample();

  @override
  State<_ToggleExample> createState() => _ToggleExampleState();
}

class _ToggleExampleState extends State<_ToggleExample> {
  bool _compact = true;

  @override
  Widget build(BuildContext context) => _framed(
    Toggle(
      value: _compact,
      label: 'Compact rows',
      autofocus: true,
      onChanged: (value) => setState(() => _compact = value),
    ),
  );
}

class _SwitchExample extends StatefulWidget {
  const _SwitchExample();

  @override
  State<_SwitchExample> createState() => _SwitchExampleState();
}

class _SwitchExampleState extends State<_SwitchExample> {
  bool _streaming = false;

  @override
  Widget build(BuildContext context) => _framed(
    Switch(
      value: _streaming,
      label: 'Streaming updates',
      autofocus: true,
      onChanged: (value) => setState(() => _streaming = value),
    ),
  );
}

class _RadioExample extends StatefulWidget {
  const _RadioExample();

  @override
  State<_RadioExample> createState() => _RadioExampleState();
}

class _RadioExampleState extends State<_RadioExample> {
  String _mode = 'fast';

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Radio<String>(
          value: 'fast',
          groupValue: _mode,
          label: 'Fast',
          autofocus: true,
          onChanged: (value) => setState(() => _mode = value),
        ),
        Radio<String>(
          value: 'safe',
          groupValue: _mode,
          label: 'Safe',
          onChanged: (value) => setState(() => _mode = value),
        ),
      ],
    ),
  );
}

class _RadioGroupExample extends StatefulWidget {
  const _RadioGroupExample();

  @override
  State<_RadioGroupExample> createState() => _RadioGroupExampleState();
}

class _RadioGroupExampleState extends State<_RadioGroupExample> {
  String _mode = 'fast';

  @override
  Widget build(BuildContext context) => _framed(
    RadioGroup<String>(
      value: _mode,
      autofocus: true,
      options: const <RadioOption<String>>[
        RadioOption(value: 'fast', label: 'Fast'),
        RadioOption(value: 'safe', label: 'Safe'),
        RadioOption(value: 'thorough', label: 'Thorough'),
      ],
      onChanged: (value) => setState(() => _mode = value),
    ),
  );
}

class _MultiSelectExample extends StatefulWidget {
  const _MultiSelectExample();

  @override
  State<_MultiSelectExample> createState() => _MultiSelectExampleState();
}

class _MultiSelectExampleState extends State<_MultiSelectExample> {
  Set<String> _selected = <String>{'logs'};

  @override
  Widget build(BuildContext context) => _framed(
    MultiSelect<String>(
      autofocus: true,
      semanticLabel: 'Enabled telemetry',
      options: const <SelectOption<String>>[
        SelectOption(value: 'logs', label: 'Logs'),
        SelectOption(value: 'traces', label: 'Traces'),
        SelectOption(value: 'metrics', label: 'Metrics'),
      ],
      values: _selected,
      onChanged: (values) => setState(() => _selected = values),
    ),
  );
}

class _TextInputExample extends StatefulWidget {
  const _TextInputExample();

  @override
  State<_TextInputExample> createState() => _TextInputExampleState();
}

class _TextInputExampleState extends State<_TextInputExample> {
  final TextEditingController _controller = TextEditingController(
    text: 'deploy staging',
  )..selection = const TextSelection(baseOffset: 7, extentOffset: 14);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _framed(
    TextInput(
      controller: _controller,
      autofocus: true,
      semanticLabel: 'Command',
      onChanged: (_) {},
      onSubmit: (_) {},
    ),
  );
}

class _SelectExample extends StatefulWidget {
  const _SelectExample();
  @override
  State<_SelectExample> createState() => _SelectExampleState();
}

class _SelectExampleState extends State<_SelectExample> {
  String _v = 'medium';
  @override
  Widget build(BuildContext context) => _framed(
    Select<String>(
      value: _v,
      onChanged: (v) => setState(() => _v = v),
      options: const <SelectOption<String>>[
        SelectOption(value: 'low', label: 'Low'),
        SelectOption(value: 'medium', label: 'Medium'),
        SelectOption(value: 'high', label: 'High'),
      ],
    ),
  );
}

class _RangeSliderExample extends StatefulWidget {
  const _RangeSliderExample();
  @override
  State<_RangeSliderExample> createState() => _RangeSliderExampleState();
}

class _RangeSliderExampleState extends State<_RangeSliderExample> {
  (num, num) _v = (20, 70);
  @override
  Widget build(BuildContext context) => _framed(
    RangeSlider(
      values: _v,
      min: 0,
      max: 100,
      label: 'Range',
      showValues: true,
      autofocus: true,
      onChanged: (v) => setState(() => _v = v),
    ),
  );
}

class _ButtonExample extends StatefulWidget {
  const _ButtonExample();
  @override
  State<_ButtonExample> createState() => _ButtonExampleState();
}

class _ButtonExampleState extends State<_ButtonExample> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Pressed $_count×'),
        const SizedBox(height: 1),
        Button(
          label: 'Press me',
          variant: ButtonVariant.primary,
          autofocus: true,
          onPressed: () => setState(() => _count++),
        ),
      ],
    ),
  );
}

class _StepperExample extends StatefulWidget {
  const _StepperExample();
  @override
  State<_StepperExample> createState() => _StepperExampleState();
}

class _StepperExampleState extends State<_StepperExample> {
  num _v = 3;
  @override
  Widget build(BuildContext context) => _framed(
    Stepper(
      value: _v,
      min: 0,
      max: 10,
      label: 'Quantity',
      onChanged: (v) => setState(() => _v = v),
    ),
  );
}

class _ColorPickerExample extends StatefulWidget {
  const _ColorPickerExample();
  @override
  State<_ColorPickerExample> createState() => _ColorPickerExampleState();
}

class _ColorPickerExampleState extends State<_ColorPickerExample> {
  Color _c = const RgbColor(0x3D, 0xDC, 0x97);
  @override
  Widget build(BuildContext context) => _framed(
    ColorPicker(
      value: _c,
      onChanged: (c) => setState(() => _c = c),
      colors: const <Color>[
        RgbColor(0xFF, 0x5C, 0x57),
        RgbColor(0xF5, 0xC2, 0x11),
        RgbColor(0x3D, 0xDC, 0x97),
        RgbColor(0x56, 0xC2, 0xFF),
        RgbColor(0xBD, 0x93, 0xF9),
      ],
    ),
  );
}

class _DatePickerExample extends StatefulWidget {
  const _DatePickerExample();
  @override
  State<_DatePickerExample> createState() => _DatePickerExampleState();
}

class _DatePickerExampleState extends State<_DatePickerExample> {
  DateTime _d = DateTime(2026, 6, 22);
  @override
  Widget build(BuildContext context) => _framed(
    DatePicker(
      value: _d,
      label: 'Date',
      onChanged: (d) => setState(() => _d = d),
    ),
  );
}

// ── Knobs (interactive props) ───────────────────────────────────────────────
//
// A small set of widgets gets a live "playground": the docs UI renders form
// controls and pushes a params map in here, which builds the widget. Re-running
// with new params re-renders without a recompile — the realistic browser-side
// answer to "edit and re-run" (true Dart editing would need a compile server).

/// Builds a knob-enabled widget from a params map supplied by the docs UI.
/// Missing or ill-typed keys fall back to the defaults below.
final Map<String, Widget Function(Map<String, Object?>)> knobExamples =
    <String, Widget Function(Map<String, Object?>)>{
      'gauge': (p) => _framed(
        Gauge(
          value: _knobDouble(p['value'], 0.62),
          label: _knobString(p['label'], 'CPU'),
          showPercentage: _knobBool(p['showPercentage'], true),
          thresholds: <(double, Color)>[
            (0.7, _theme.colorScheme.warning),
            (0.9, _theme.colorScheme.error),
          ],
        ),
      ),
      'progressbar': (p) {
        final indeterminate = _knobBool(p['indeterminate'], false);
        return _framed(
          ProgressBar(
            value: indeterminate ? null : _knobDouble(p['value'], 0.45),
          ),
        );
      },
      'histogram': (p) => _framed(
        Histogram(
          values: const <num>[
            1,
            2,
            2,
            3,
            3,
            3,
            4,
            4,
            4,
            4,
            5,
            5,
            5,
            6,
            6,
            7,
            2,
            3,
            4,
            5,
          ],
          bins: _knobInt(p['bins'], 7),
          showValues: _knobBool(p['showValues'], true),
          color: _theme.colorScheme.primary,
        ),
      ),
      'heatmap': (p) => _framed(
        Heatmap(
          values: const <List<num>>[
            <num>[0.1, 0.3, 0.6, 0.9],
            <num>[0.2, 0.5, 0.8, 0.4],
            <num>[0.7, 0.6, 0.3, 0.1],
          ],
          rowLabels: const <String>['a', 'b', 'c'],
          colLabels: const <String>['w', 'x', 'y', 'z'],
          cellWidth: _knobInt(p['cellWidth'], 3),
          showLegend: _knobBool(p['showLegend'], true),
        ),
      ),
    };

double _knobDouble(Object? v, double fallback) =>
    v is num ? v.toDouble() : fallback;
int _knobInt(Object? v, int fallback) => v is num ? v.round() : fallback;
String _knobString(Object? v, String fallback) =>
    v is String && v.isNotEmpty ? v : fallback;
bool _knobBool(Object? v, bool fallback) => v is bool ? v : fallback;

/// A mutable params holder the docs knob UI pushes updates into. Notifies so a
/// [ListenableBuilder] can rebuild the widget in place (no remount/recompile).
class KnobParams with ChangeNotifier {
  KnobParams(this._value);

  Map<String, Object?> _value;
  Map<String, Object?> get value => _value;
  set value(Map<String, Object?> next) {
    _value = next;
    notifyListeners();
  }
}

/// Root widget for a knob playground: rebuilds [id]'s widget whenever [params]
/// changes.
Widget knobRoot(String id, KnobParams params) {
  final builder = knobExamples[id];
  if (builder == null) return const Center(child: Text('Unknown knob example'));
  return FocusTraversalGroup(
    child: ListenableBuilder(
      listenable: params,
      builder: (context, _) => builder(params.value),
    ),
  );
}

/// An interactive world clock: a [Tabs] strip selects a timezone and a [Digits]
/// shows that zone's wall-clock time, ticking once a second. Demonstrates making
/// a display widget interactive — pick a zone with ← / → (or click a tab).
class _WorldClock extends StatefulWidget {
  const _WorldClock();

  @override
  State<_WorldClock> createState() => _WorldClockState();
}

class _WorldClockState extends State<_WorldClock>
    with SingleTickerProviderStateMixin {
  // (label, UTC offset in hours). Fixed offsets — a demo, not a DST authority.
  static const List<(String, int)> _zones = <(String, int)>[
    ('UTC', 0),
    ('EST', -5),
    ('PST', -8),
    ('CET', 1),
    ('JST', 9),
  ];

  Ticker? _ticker;
  int _lastSecond = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  void _onTick(Duration _) {
    final second = DateTime.now().second;
    if (second == _lastSecond)
      return; // rebuild ~once a second, not every frame
    _lastSecond = second;
    setState(() {});
  }

  String _timeFor(int offsetHours) {
    final t = DateTime.now().toUtc().add(Duration(hours: offsetHours));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tabs(
      tabs: <TabItem>[
        for (final zone in _zones)
          TabItem(
            label: zone.$1,
            content: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Digits(
                _timeFor(zone.$2),
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// Streams a bounded random-walk series into [builder] on a ticker, so chart
/// examples animate in the docs. The shown code stays the plain static widget
/// (see each example's `code` override).
class _LiveSeries extends StatefulWidget {
  const _LiveSeries({
    required this.length,
    required this.min,
    required this.max,
    required this.builder,
  });

  final int length;
  final double min;
  final double max;
  final Widget Function(List<num> data) builder;

  @override
  State<_LiveSeries> createState() => _LiveSeriesState();
}

class _LiveSeriesState extends State<_LiveSeries>
    with SingleTickerProviderStateMixin {
  final Random _r = Random(5);
  late List<double> _data;
  Ticker? _ticker;
  int _lastMs = 0;

  @override
  void initState() {
    super.initState();
    var v = (widget.min + widget.max) / 2;
    _data = List<double>.generate(widget.length, (_) => v = _walk(v));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick);
      // Let the initial chart paint before the stream starts — otherwise the
      // browser DOM host can keep re-scheduling and never complete the first
      // paint of a constantly-rebuilding leaf.
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted && _ticker != null && !_ticker!.isActive) _ticker!.start();
      });
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed.inMilliseconds - _lastMs < 160) return;
    _lastMs = elapsed.inMilliseconds;
    setState(() {
      _data = <double>[..._data.skip(1), _walk(_data.last)];
    });
  }

  double _walk(double v) =>
      (v + (_r.nextDouble() * 2 - 1) * (widget.max - widget.min) * 0.16)
          .clamp(widget.min, widget.max)
          .toDouble();

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_data);
}
