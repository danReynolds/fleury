// Web-safe widget examples for the docs site. These run client-side via
// dart2js (mountApp), so everything imports the dart:io-free host SPI
// (fleury_host) and the web-safe widget barrel (fleury_widgets_web) — never the
// full `fleury.dart` / `fleury_widgets.dart` umbrellas, which pull in native
// drivers and the dart:io-backed widgets.
import 'dart:math';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_themes/fleury_themes.dart';
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
  // ── Tutorial (not catalogued — embedded at the top of the tutorial page so
  //    readers interact with the finished app before building it) ────────────
  ExampleInfo(
    id: 'tutorial.filter',
    widget: 'Filterable list',
    category: 'Home',
    blurb: 'The tutorial’s finished app: a list that narrows as you type.',
    cols: 40,
    // TextInput + count + blank + 10 languages = 14 content rows, +2 frame.
    rows: 16,
    interactive: true,
    builder: () => const _TutorialFilterExample(),
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
    // A 1-row widget inside `_framed` (Padding.all(1)) needs 3 rows: pad +
    // content + pad. At rows: 2 the padding consumed both rows, squeezing the
    // sparkline to zero height (a blank inline demo that only appeared once
    // Expand grew the host to 3 rows).
    rows: 3,
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
        'A multi-series line (or scatter) chart with sub-cell braille '
        'rendering, axes, legend, and references. For a filled look, see '
        'AreaChart.',
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
  // --- LineChart rendering-option lab: compare line weights + markers ------
  ExampleInfo(
    id: 'linechart.lab.braille1',
    widget: 'LineChart',
    category: 'Charts & meters',
    blurb: 'Braille line, 1px hairline (thin).',
    cols: 58,
    rows: 15,
    code: 'LineChart(marker: CanvasMarker.braille, strokeWidth: 1, ...)',
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
          strokeWidth: 1,
          showAxes: true,
          showLegend: true,
          yRange: const (0, 100),
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'linechart.lab.braille2',
    widget: 'LineChart',
    category: 'Charts & meters',
    blurb: 'Braille line, 2px band (current default).',
    cols: 58,
    rows: 15,
    code: 'LineChart(marker: CanvasMarker.braille, strokeWidth: 2, ...)',
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
          strokeWidth: 2,
          showAxes: true,
          showLegend: true,
          yRange: const (0, 100),
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'linechart.lab.octant',
    widget: 'LineChart',
    category: 'Charts & meters',
    blurb: 'Octant line — solid, crispest (Unicode 16).',
    cols: 58,
    rows: 15,
    code: 'LineChart(marker: CanvasMarker.octant, ...)',
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
          marker: CanvasMarker.octant,
          showAxes: true,
          showLegend: true,
          yRange: const (0, 100),
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'areachart.basic',
    widget: 'AreaChart',
    category: 'Charts & meters',
    blurb: 'A gradient-filled area chart — the filled sibling of LineChart.',
    cols: 58,
    rows: 15,
    code: '''AreaChart(
  series: <AreaSeries>[
    AreaSeries(
      points,
      label: 'load',
      gradient: [cs.success, cs.warning, cs.error],
    ),
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
        builder: (data) => AreaChart(
          series: <AreaSeries>[
            AreaSeries(
              <(num, num)>[for (var i = 0; i < data.length; i++) (i, data[i])],
              label: 'load',
              gradient: <Color>[
                _theme.colorScheme.success,
                _theme.colorScheme.warning,
                _theme.colorScheme.error,
              ],
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
    blurb: 'A frequency-distribution chart that bins raw samples for you.',
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
    // 1-row widget + `_framed` padding needs 3 rows; rows: 2 rendered blank.
    rows: 3,
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
        // Show the hierarchy expanded instead of a lone collapsed "▸ lib/".
        initialExpandedDepth: 1,
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
        'A scrollable, keyboard-navigable viewer for full Markdown documents.',
    cols: 60,
    rows: 13,
    interactive: true,
    builder: () => _framed(MarkdownView(markdown: _markdownSample)),
  ),
  ExampleInfo(
    id: 'markdowntext.basic',
    widget: 'MarkdownText',
    category: 'Documents',
    blurb:
        'Lightweight inline Markdown for short strings — help text, labels, '
        'captions.',
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
    blurb:
        'A panel of context items with per-item share bars and a token-usage '
        'meter.',
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
        'A multiline editor with selection, clipboard, paste, and '
        'agent-editable semantics.',
    cols: 44,
    rows: 7,
    interactive: true,
    code: '''final controller = TextEditingController(text: releaseNotes);

TextArea(
  controller: controller,
  minLines: 4,
  maxLines: 4,
  semanticLabel: 'Release notes',
  keymap: TextEditingKeymap.chat,
  onChanged: (text) => updateReleaseNotes(text),
  onSubmit: (text) => saveReleaseNotes(text),
)''',
    // Seeded with a few lines so the demo reads as a filled multi-line editor
    // instead of an empty field floating in the frame.
    builder: () => const _TextAreaExample(),
  ),
  ExampleInfo(
    id: 'form.basic',
    widget: 'FormPanel',
    category: 'Inputs & controls',
    blurb:
        'A declarative, validated form that runs in terminal and browser apps '
        'alike.',
    cols: 54,
    rows: 14,
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
    // The example stacks "Pressed N×" + a spacer + the Button (3 rows); with
    // `_framed` padding that needs 5. At rows: 4 the Padding clipped the Button
    // itself — the demo showed the counter but not the button.
    rows: 5,
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
    blurb:
        'An arrow-key-navigable group of radio choices on a single tab stop.',
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
    blurb: 'A compact number spinner; ↑/↓ adjust the value (×10 with Shift).',
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
    blurb: 'An obscured text field with a reveal shortcut (Ctrl-R).',
    cols: 40,
    rows: 3,
    interactive: true,
    code: '''PasswordInput(
  controller: controller,
  semanticLabel: 'Password',
  // Ctrl-R briefly reveals the obscured value.
)''',
    // Seeded with a value so the demo shows the obscuring dots (the widget's
    // point) rather than a bare "Password" placeholder.
    builder: () => const _PasswordInputExample(),
  ),
  ExampleInfo(
    id: 'autocomplete.basic',
    widget: 'Autocomplete',
    category: 'Inputs & controls',
    blurb: 'A text field that filters a list of options as you type.',
    cols: 44,
    rows: 7,
    interactive: true,
    code: '''Autocomplete<String>(
  placeholder: 'Type a fruit…',
  options: const ['Apple', 'Apricot', 'Banana', 'Cherry', 'Grape'],
  onSelect: (fruit) => choose(fruit),
)''',
    // Seeded with a query + autofocus so the demo opens on the filtered matches
    // (the point of the widget) instead of a bare prompt. Clear it to type your
    // own.
    builder: () => const _AutocompleteExample(),
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
    blurb: 'A dropdown menu: a trigger that opens a floating list of actions.',
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
    id: 'anchored.basic',
    widget: 'Anchored',
    category: 'Navigation & overlays',
    blurb:
        'Floating content pinned to a trigger, placed by Alignment — the '
        'declarative way to build dropdowns, flyouts, and hover cards.',
    cols: 40,
    rows: 9,
    interactive: true,
    builder: () => _framed(
      Align(
        alignment: Alignment.center,
        child: Anchored(
          visible: true,
          alignment: Alignment.bottomLeft,
          overlay: Container.framed(
            border: BoxBorder(style: _theme.borderStyle),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: const Text('float'),
          ),
          child: const Text('[ trigger ]'),
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'tooltip.basic',
    widget: 'Tooltip',
    category: 'Navigation & overlays',
    blurb: 'A hover/focus hint attached to any child.',
    cols: 40,
    // A TUI tooltip triggers on focus (no hover), so the child is an autofocused
    // Button — the hint renders beneath it on mount instead of an inert label.
    rows: 5,
    interactive: true,
    builder: () => _framed(
      Tooltip(
        message: 'Saves the current file',
        child: Button(label: 'Save', autofocus: true, onPressed: () {}),
      ),
    ),
  ),
  ExampleInfo(
    id: 'container.filled',
    widget: 'Container',
    category: 'Layout',
    blurb:
        'Container is transparent by default; .filled paints the theme '
        'surface and .framed adds the theme border. Enter and Esc toggle a '
        'framed layer over live content.',
    cols: 44,
    rows: 11,
    interactive: true,
    // Toggling is the demo: while the framed layer is open the wall behind
    // is covered (it owns every cell it draws over), and closing restores
    // that content untouched — it layers, it doesn't overwrite.
    builder: () => const _ContainerFillExample(),
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
    blurb: 'A bar listing the keyboard shortcuts active for the current focus.',
    cols: 52,
    rows: 6,
    code: '''KeyBindings(
  bindings: <KeyBinding>[
    KeyBinding(KeyCode.char('s'), label: 'Save', onTrigger: save),
    KeyBinding(KeyCode.char('q'), label: 'Quit', onTrigger: quit),
  ],
  child: const KeyHintBar(),
)''',
    builder: () => _framed(
      KeyBindings(
        bindings: <KeyBinding>[
          KeyBinding(KeyCode.char('s'), label: 'Save', onTrigger: (_) {}),
          KeyBinding(KeyCode.char('r'), label: 'Run', onTrigger: (_) {}),
          KeyBinding(KeyCode.char('q'), label: 'Quit', onTrigger: (_) {}),
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
    id: 'whichkey.basic',
    widget: 'WhichKey',
    category: 'Navigation & overlays',
    blurb:
        'A which-key popup: press the leader (Space) and the shortcuts that '
        'continue the sequence appear.',
    cols: 44,
    rows: 8,
    interactive: true,
    code: '''KeyBindings(
  bindings: <KeyBinding>[
    KeyBinding(KeySequence.space.f, label: 'Find file', onTrigger: (_) => findFile()),
    KeyBinding(KeySequence.space.b, label: 'Buffers', onTrigger: (_) => buffers()),
    KeyBinding(KeySequence.space.g, label: 'Git', onTrigger: (_) => git()),
  ],
  child: WhichKey(
    child: Focus(autofocus: true, child: editor),
  ),
)''',
    builder: () => _framed(
      KeyBindings(
        bindings: <KeyBinding>[
          KeyBinding(
            KeySequence.space.f,
            label: 'Find file',
            onTrigger: (_) {},
          ),
          KeyBinding(KeySequence.space.b, label: 'Buffers', onTrigger: (_) {}),
          KeyBinding(KeySequence.space.g, label: 'Git', onTrigger: (_) {}),
        ],
        // Zero delay so the popup appears the instant Space is pressed in the
        // demo; real apps keep the default (a short delay hides it for fast
        // completions).
        child: const WhichKey(
          showDelay: Duration.zero,
          child: Focus(autofocus: true, child: Text('Press Space, then a key')),
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'commandpalette.basic',
    widget: 'CommandPalette',
    category: 'Navigation & overlays',
    blurb: 'A fuzzy command launcher; type to filter, Enter to invoke.',
    // Wide enough to show the trailing shortcut column (Ctrl-P / Ctrl-T); at
    // cols: 52 the shortcuts were clipped to "Ctr".
    cols: 66,
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
    blurb: 'A search box over a grouped, copyable result list.',
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
    blurb:
        'A column-aligned grid of widget cells, with optional row selection.',
    cols: 44,
    // Header + 3 data rows, framed, need 7; at rows: 6 the last row (lin) was
    // clipped.
    rows: 7,
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
        // Expand the top branch so the demo shows the hierarchy, not a collapsed
        // "▸ lib" the reader has to imagine.
        controller: TreeTableController(expandedKeys: const <Object>{'lib'}),
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
    // Title + message + subject + the [Approve]/[Deny] actions need 11 rows
    // once framed; at rows: 8 the subject and the decision buttons — the whole
    // point of an approval card — were clipped off the bottom.
    rows: 11,
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
          // A third event so the connector rail reads as a sequence
          // (╭ first → ├ middle → ╰ last), not a lone pair.
          TraceTimelineEntry(
            id: 't3',
            label: 'Publish report',
            kind: TraceTimelineKind.command,
            status: TraceTimelineStatus.queued,
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
    // Each entry is a single line (title · status · unread · latest); the list
    // window is only as tall as the entry count, so extra rows don't reveal a
    // hidden entry — the messages just have to fit one line. Sized so both rows
    // render un-wrapped: at cols 60 the first entry's long message wrapped and
    // pushed the second ("Docs site") out of the 2-row window.
    cols: 64,
    rows: 6,
    interactive: true,
    builder: () => _framed(
      const ConversationNavigator(
        conversations: <ConversationEntry>[
          ConversationEntry(
            id: 'c1',
            title: 'Benchmark scoreboard',
            subtitle: 'Perf follow-up',
            status: ConversationStatus.active,
            latestMessage: 'All peers green',
            unreadCount: 2,
          ),
          ConversationEntry(
            id: 'c2',
            title: 'Docs site',
            status: ConversationStatus.idle,
            latestMessage: 'Examples shipped',
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
        'A status line for the active model: name, state, latency, and '
        'token/context usage.',
    // A full-width status bar: model + live status + latency + a context meter.
    // The full widget (provider + mode + …) is ~90 cols — wider than the docs
    // column — so the demo drops the provider (the model id implies it) and the
    // mode (status already reads as "streaming") to show the whole bar, meter
    // and percentage included, without clipping or a horizontal scrollbar.
    cols: 80,
    rows: 3,
    builder: () => _framed(
      const ModelStatusBar(
        info: ModelStatusInfo(
          model: 'claude-opus-4-8',
          status: ModelRuntimeStatus.streaming,
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
    // Fits the full-bleed showcase column at a ~1280px laptop viewport (which
    // holds ~110 cells beside the sidebar); at 116 the right edge — the
    // load-average/uptime clock — was clipped with a horizontal scrollbar. The
    // app is responsive, so 108 renders every panel without crowding, and the
    // meta rail still sits beside it on wide viewports. (files/agent already fit.)
    cols: 108,
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
  ExampleInfo(
    id: 'showcase.editor',
    widget: 'Text editor',
    category: 'Showcases',
    blurb:
        'One buffer, two editors: a nano-style modeless keymap and a modal vim '
        'one, swapped live with Ctrl+B — the two ways a TUI teaches its own '
        'keys.',
    // The sample sizes itself to the viewport; 80×24 is the classic terminal
    // and leaves the shortcut bar and status line unclipped in the doc column.
    cols: 80,
    rows: 24,
    interactive: true,
    builder: () => const EditorApp(),
  ),
  ExampleInfo(
    id: 'showcase.finance',
    widget: 'Personal finance',
    category: 'Showcases',
    blurb:
        'A realistic local finance workspace with cash-flow and category '
        'charts, account balances, and a searchable, sortable transaction '
        'ledger—including an opt-in 2,500-row stress mode.',
    cols: 108,
    rows: 46,
    interactive: true,
    builder: () => const FinanceApp(),
  ),
  ExampleInfo(
    id: 'showcase.asteroids',
    widget: 'Neon Asteroids',
    category: 'Showcases',
    blurb:
        'A deterministic real-time arcade game with braille vector rendering, '
        'fixed-step physics, particles, collisions, screen wrapping, and '
        'keyboard or pointer flight controls.',
    cols: 100,
    rows: 32,
    interactive: true,
    builder: () => const NeonAsteroidsApp(),
  ),
  ExampleInfo(
    id: 'forms.project',
    widget: 'FormPanel',
    category: 'Guide examples',
    blurb:
        'A project form that validates on submit, keeps errors next to their '
        'fields, and returns typed values when complete.',
    cols: 68,
    rows: 15,
    interactive: true,
    builder: () => const _ProjectFormTour(),
  ),
  ExampleInfo(
    id: 'lists.tasks',
    widget: 'ListView',
    category: 'Guide examples',
    blurb:
        'A thousand-row lazy task list with keyboard selection, activation, '
        'paging, and a viewport scrollbar.',
    cols: 56,
    rows: 17,
    interactive: true,
    builder: () => const _TaskListTour(),
  ),
  ExampleInfo(
    id: 'layout.responsive',
    widget: 'LayoutBuilder',
    category: 'Guide examples',
    blurb:
        'A workspace that switches between two panes and a stacked layout '
        'from the local width its parent provides.',
    cols: 74,
    rows: 18,
    interactive: true,
    builder: () => const _ResponsiveWorkspaceTour(),
  ),
  ExampleInfo(
    id: 'navigation.basics',
    widget: 'Navigator',
    category: 'Navigation & overlays',
    blurb:
        'Push a screen, present a dialog, and pop with or without a typed '
        'result in one deliberately small flow.',
    cols: 58,
    rows: 14,
    interactive: true,
    builder: () => Navigator(
      transition: RouteTransition.none,
      home: const _NavigationBasicsTour(),
    ),
  ),
  ExampleInfo(
    id: 'navigation.placement',
    widget: 'Navigator',
    category: 'Guide examples',
    blurb:
        'Choose a dialog alignment, then see the same presented route move '
        'to that position.',
    cols: 66,
    rows: 16,
    interactive: true,
    builder: () => Navigator(
      transition: RouteTransition.none,
      home: const _DialogPlacementTour(),
    ),
  ),
  ExampleInfo(
    id: 'navigation.guard',
    widget: 'PopScope',
    category: 'Guide examples',
    blurb:
        'An unsaved editor visibly blocks back navigation until the draft is '
        'saved or deliberately discarded.',
    cols: 54,
    rows: 14,
    interactive: true,
    builder: () => Navigator(
      transition: RouteTransition.none,
      home: const _BackGuardHomeTour(),
    ),
  ),
  ExampleInfo(
    id: 'navigation.transitions',
    widget: 'RouteTransition',
    category: 'Guide examples',
    blurb:
        'Compare fade, slide, and instant route changes using the built-in '
        'production transitions.',
    cols: 58,
    rows: 12,
    interactive: true,
    builder: () => Navigator(
      transition: RouteTransition.none,
      home: const _TransitionTour(),
    ),
  ),
  ExampleInfo(
    id: 'navigation.nested-flow',
    widget: 'Navigator',
    category: 'Guide examples',
    blurb:
        'An outer app route contains a three-step inner flow, then replaces '
        'the whole flow with one completed screen.',
    cols: 64,
    rows: 17,
    interactive: true,
    builder: () => Navigator(
      transition: RouteTransition.none,
      home: const _NestedProjectsTour(),
    ),
  ),
  ExampleInfo(
    id: 'focus.explorer',
    widget: 'Focus',
    category: 'Inputs & controls',
    blurb:
        'A visible focus path across two panes, with Tab and directional '
        'traversal plus a dialog that traps and restores focus automatically.',
    cols: 70,
    rows: 18,
    interactive: true,
    builder: () => const Navigator(home: _FocusExplorerTour()),
  ),
  ExampleInfo(
    id: 'focusnode.programmatic',
    widget: 'FocusNode',
    category: 'Inputs & controls',
    blurb:
        'An action moves focus directly to a search field while the visible '
        'cursor and status line confirm the handoff.',
    cols: 60,
    rows: 10,
    interactive: true,
    builder: () => const _ProgrammaticFocusTour(),
  ),
  ExampleInfo(
    id: 'focusdetector.basic',
    widget: 'FocusDetector',
    category: 'Inputs & controls',
    blurb:
        'A visible boundary counter shows that moving between children stays '
        'inside one focused region.',
    cols: 62,
    rows: 14,
    interactive: true,
    builder: () => const _FocusDetectorTour(),
  ),
  ExampleInfo(
    id: 'keybindings.basic',
    widget: 'KeyBindings',
    category: 'Inputs & controls',
    blurb:
        'The key-binding surface in one screen: dot-shorthand gestures, an '
        'alias, a repeat-reliant mover, a two-key sequence, a Space leader — '
        'and the hint bar teaching all of it, for free.',
    cols: 64,
    rows: 14,
    interactive: true,
    builder: () => const _KeyBindingsTour(),
  ),
  ExampleInfo(
    id: 'keydetector.basic',
    widget: 'KeyDetector',
    category: 'Inputs & controls',
    blurb:
        'A visible event trace shows the pane consuming arrows while it can '
        'move, then passing the same key to its ancestor at the edge.',
    cols: 64,
    rows: 12,
    interactive: true,
    builder: () => const _KeyDetectorTour(),
  ),
  ExampleInfo(
    id: 'showcase.sprite',
    widget: 'ANSI Sprite Studio',
    category: 'Showcases',
    blurb:
        'A complete cell-art workflow: paint, erase, fill, onion-skin and time '
        'keyed frames, preview the animation, undo edits, and round-trip a '
        'portable JSON asset.',
    cols: 108,
    rows: 40,
    interactive: true,
    builder: () => const AnsiSpriteStudioApp(),
  ),
  ExampleInfo(
    id: 'themes.custom',
    widget: 'Themes',
    category: 'Theming',
    blurb:
        'One hand-written ThemeData, applied to the same preview the community '
        'themes use.',
    cols: 38,
    rows: 14,
    code: _customThemeSource,
    builder: () => const Theme(data: _customTheme, child: _ThemePreview()),
  ),
  ExampleInfo(
    id: 'themes.gallery',
    widget: 'Themes',
    category: 'Theming',
    blurb:
        'Every theme in fleury_themes, on a slice of real UI. Arrow through '
        'the picker to switch.',
    cols: 62,
    rows: 18,
    interactive: true,
    code: '''import 'package:fleury_themes/fleury_themes.dart';

runApp(const MyApp(), theme: tokyoNight);''',
    builder: () => const _ThemePickerExample(),
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
/// Typed printables arrive as TextInputEvents, so the quit key is a
/// widget-level KeyBinding (requestExit), never an onEvent char match.
void main() => runApp(
      KeyBindings(
        bindings: [
          KeyBinding(KeySequence.q, onTrigger: (_) => requestExit(), label: 'Quit'),
        ],
        child: const CounterApp(),
      ),
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

class _ContainerFillExample extends StatefulWidget {
  const _ContainerFillExample();

  @override
  State<_ContainerFillExample> createState() => _ContainerFillExampleState();
}

class _ContainerFillExampleState extends State<_ContainerFillExample> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    // The trigger and the wall stay at a fixed position in the tree so the
    // button keeps focus across a toggle; only the framed layer comes and
    // goes.
    final Widget behind = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Button(
          label: _open ? 'Hide layer' : 'Show layer',
          autofocus: true,
          onPressed: _toggle,
        ),
        for (var i = 0; i < 6; i++) const Text('live content behind the layer'),
      ],
    );
    return _framed(
      KeyBindings(
        bindings: <KeyBinding>[
          if (_open)
            KeyBinding(
              KeySequence.escape,
              label: 'Close',
              onTrigger: (_) => _toggle(),
            ),
        ],
        child: Stack(
          children: <Widget>[
            behind,
            if (_open)
              Align(
                alignment: Alignment.center,
                child: Container.framed(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  // Deliberately ragged: the shorter line leaves interior
                  // cells the content never writes — exactly the cells that
                  // would show the wall through an unfilled Container.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      Text('Container.framed'),
                      Text(
                        'opaque fill + theme border',
                        style: CellStyle(dim: true),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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

class _PasswordInputExample extends StatefulWidget {
  const _PasswordInputExample();

  @override
  State<_PasswordInputExample> createState() => _PasswordInputExampleState();
}

class _PasswordInputExampleState extends State<_PasswordInputExample> {
  final TextEditingController _controller = TextEditingController(
    text: 'correct-horse',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _framed(
    PasswordInput(
      controller: _controller,
      autofocus: true,
      semanticLabel: 'Password',
    ),
  );
}

// The tutorial's finished FilterApp, mirrored from
// doc_snippets/filterable_list.dart (the compile-checked source the prose walks
// through) — keep the three in sync. `_framed` supplies the app's Padding.
class _TutorialFilterExample extends StatefulWidget {
  const _TutorialFilterExample();

  @override
  State<_TutorialFilterExample> createState() => _TutorialFilterExampleState();
}

class _TutorialFilterExampleState extends State<_TutorialFilterExample> {
  static const _languages = <String>[
    'Dart',
    'Rust',
    'Go',
    'Python',
    'TypeScript',
    'Elixir',
    'Zig',
    'Swift',
    'Kotlin',
    'Haskell',
  ];

  String _query = '';

  List<String> get _matches => _languages
      .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return _framed(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextInput(
            autofocus: true,
            placeholder: 'Filter languages…',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 1),
          Text(
            '${matches.length} of ${_languages.length}',
            style: const CellStyle(dim: true),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: matches.isEmpty
                ? const Text('No matches', style: CellStyle(dim: true))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[for (final name in matches) Text(name)],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AutocompleteExample extends StatefulWidget {
  const _AutocompleteExample();

  @override
  State<_AutocompleteExample> createState() => _AutocompleteExampleState();
}

class _AutocompleteExampleState extends State<_AutocompleteExample> {
  // Seed a partial query so the suggestion list is already open on mount.
  final TextEditingController _controller = TextEditingController(text: 'Ap');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _framed(
    Autocomplete<String>(
      controller: _controller,
      autofocus: true,
      placeholder: 'Type a fruit…',
      options: const <String>['Apple', 'Apricot', 'Banana', 'Cherry', 'Grape'],
    ),
  );
}

class _TextAreaExample extends StatefulWidget {
  const _TextAreaExample();

  @override
  State<_TextAreaExample> createState() => _TextAreaExampleState();
}

class _TextAreaExampleState extends State<_TextAreaExample> {
  final TextEditingController _controller = TextEditingController(
    text:
        'Ship v1.4.0\n\n- Add a --version flag\n- Fix the Windows resize crash',
  );

  @override
  void initState() {
    super.initState();
    // Park the caret at the end of the seeded notes so typing appends where a
    // user would resume — and so keystrokes land deterministically in tests.
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _framed(
    TextArea(
      controller: _controller,
      autofocus: true,
      minLines: 4,
      maxLines: 4,
      semanticLabel: 'Release notes',
      onChanged: (_) {},
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
Alignment _knobAlignment(Object? raw) => switch (raw) {
  'topLeft' => Alignment.topLeft,
  'topCenter' => Alignment.topCenter,
  'topRight' => Alignment.topRight,
  'centerLeft' => Alignment.centerLeft,
  'center' => Alignment.center,
  'centerRight' => Alignment.centerRight,
  'bottomCenter' => Alignment.bottomCenter,
  'bottomRight' => Alignment.bottomRight,
  _ => Alignment.bottomLeft,
};

final Map<String, Widget Function(Map<String, Object?>)> knobExamples =
    <String, Widget Function(Map<String, Object?>)>{
      // Anchored: the float's placement is the whole story, so `alignment` is
      // the headline knob — all nine values, live. The trigger sits centred so
      // every direction has room to show.
      'anchored': (p) => _framed(
        Align(
          alignment: Alignment.center,
          child: Anchored(
            visible: _knobBool(p['visible'], true),
            alignment: _knobAlignment(p['alignment']),
            gap: _knobDouble(p['gap'], 0).round(),
            overlay: Container.framed(
              border: BoxBorder(style: _theme.borderStyle),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: const Text('float'),
            ),
            child: const Text('[ trigger ]'),
          ),
        ),
      ),
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

/// Live theme picker for the docs site: pick a theme on the left, see it
/// applied to a small slice of UI on the right.
class _ThemePickerExample extends StatefulWidget {
  const _ThemePickerExample();

  @override
  State<_ThemePickerExample> createState() => _ThemePickerExampleState();
}

class _ThemePickerExampleState extends State<_ThemePickerExample> {
  final ListController _list = ListController(selectedIndex: 0);

  @override
  void initState() {
    super.initState();
    // The preview follows the highlight, so arrowing the list re-themes
    // immediately — no separate "apply" step in a docs embed.
    _list.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = (_list.selectedIndex ?? 0).clamp(0, fleuryThemes.length - 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 20,
          child: ListView.builder(
            controller: _list,
            itemCount: fleuryThemes.length,
            autofocus: true,
            itemBuilder: (context, i, activeSelected) {
              final selected = i == index;
              return Text(
                selected
                    ? '> ${fleuryThemes[i].name}'
                    : '  ${fleuryThemes[i].name}',
                style: selected
                    ? Theme.of(context).selectionStyle
                    : CellStyle.empty,
              );
            },
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Theme(
            data: fleuryThemes[index].data,
            child: const _ThemePreview(),
          ),
        ),
      ],
    );
  }
}

/// A hand-written theme for the "creating a theme" guide section.
///
/// Deliberately small: the nine roles it actually needs, the three text styles,
/// and a border style — enough to be a real theme, short enough to read beside
/// its own render. Kept in sync with [_customThemeSource] by a test.
const ThemeData _customTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x1C, 0x18, 0x14),
    foreground: RgbColor(0xEB, 0xDB, 0xB2),
    surface: RgbColor(0x2A, 0x24, 0x1E),
    primary: RgbColor(0xE8, 0xA3, 0x3D),
    focus: RgbColor(0xF2, 0xC5, 0x5C),
    success: RgbColor(0x8E, 0xC0, 0x7C),
    warning: RgbColor(0xE8, 0xA3, 0x3D),
    error: RgbColor(0xE5, 0x6B, 0x5B),
    info: RgbColor(0x83, 0xA5, 0x98),
  ),
  mutedStyle: CellStyle(dim: true),
  selectionStyle: CellStyle(inverse: true),
  focusedStyle: CellStyle(bold: true),
  borderStyle: BorderStyle.rounded,
);

/// The literal source of [_customTheme], shown beside its render on the
/// theming guide. A test asserts the two agree, so the page cannot drift into
/// showing code that is not what produced the picture.
const String _customThemeSource = '''
const amber = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x1C, 0x18, 0x14),
    foreground: RgbColor(0xEB, 0xDB, 0xB2),
    surface: RgbColor(0x2A, 0x24, 0x1E),
    primary: RgbColor(0xE8, 0xA3, 0x3D),
    focus: RgbColor(0xF2, 0xC5, 0x5C),
    success: RgbColor(0x8E, 0xC0, 0x7C),
    warning: RgbColor(0xE8, 0xA3, 0x3D),
    error: RgbColor(0xE5, 0x6B, 0x5B),
    info: RgbColor(0x83, 0xA5, 0x98),
  ),
  mutedStyle: CellStyle(dim: true),
  selectionStyle: CellStyle(inverse: true),
  focusedStyle: CellStyle(bold: true),
  borderStyle: BorderStyle.rounded,
);

runApp(const MyApp(), theme: amber);''';

/// Exposed for the drift test in test/theme_source_parity_test.dart.
ThemeData get customThemeForTest => _customTheme;
String get customThemeSourceForTest => _customThemeSource;

/// A compact slice of UI: enough surfaces that a theme's character shows.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final theme = context.theme;
    return Container(
      color: cs.background,
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Deploy Console',
            style: CellStyle(foreground: cs.foreground, bold: true),
          ),
          Text('one app, two surfaces', style: theme.mutedStyle),
          const SizedBox(height: 1),
          Text('  api-gateway  running  42%', style: theme.selectionStyle),
          Text(
            '  worker-01    running  18%',
            style: CellStyle(foreground: cs.foreground),
          ),
          const SizedBox(height: 1),
          ProgressBar(value: 0.62),
          const SizedBox(height: 1),
          Wrap(
            children: <Widget>[
              Text('success  ', style: CellStyle(foreground: cs.success)),
              Text('warning  ', style: CellStyle(foreground: cs.warning)),
              Text('error  ', style: CellStyle(foreground: cs.error)),
              Text('info', style: CellStyle(foreground: cs.info)),
            ],
          ),
          const SizedBox(height: 1),
          Wrap(
            children: <Widget>[
              Text(
                '\u2589 primary  ',
                style: CellStyle(foreground: cs.primary),
              ),
              Text('\u2589 focus', style: CellStyle(foreground: cs.focus)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A guide-level FormPanel example with visible invalid and successful submit
/// states instead of the reference gallery's pre-filled happy path.
class _ProjectFormTour extends StatefulWidget {
  const _ProjectFormTour();

  @override
  State<_ProjectFormTour> createState() => _ProjectFormTourState();
}

class _ProjectFormTourState extends State<_ProjectFormTour> {
  late final FormDefinition _definition = FormDefinition(
    title: 'Create project',
    submitLabel: 'Create',
    showCancel: false,
    fields: [
      FormFieldSpec.text(id: 'name', label: 'Name', required: true),
      FormFieldSpec.text(
        id: 'slug',
        label: 'Slug',
        required: true,
        validator: (value, _) {
          final slug = (value ?? '').toString();
          return RegExp(r'^[a-z0-9-]+$').hasMatch(slug)
              ? null
              : 'Use lowercase letters, numbers, and hyphens';
        },
      ),
      FormFieldSpec.checkbox(id: 'private', label: 'Private project'),
    ],
  );

  String _status = 'Fill in the project details';

  void _submit(FormSubmitResult result) => setState(() {
    _status = result.valid
        ? 'Created ${result.values.text('name')}'
        : 'Fix ${result.errors.length} field(s)';
  });

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormPanel(
          definition: _definition,
          layout: FormPanelLayout.inline,
          fieldWidth: 26,
          onSubmit: _submit,
        ),
        const Spacer(),
        Text('status: $_status'),
      ],
    ),
  );
}

/// A primary list where containment is deliberate: the demo is entirely about
/// list navigation, so edge arrows should stay in the list instead of moving
/// to unrelated guide chrome.
class _TaskListTour extends StatefulWidget {
  const _TaskListTour();

  @override
  State<_TaskListTour> createState() => _TaskListTourState();
}

class _TaskListTourState extends State<_TaskListTour> {
  static const _count = 1000;
  var _selected = 0;
  String _lastAction = 'Choose a task';

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('TASKS', style: CellStyle(bold: true)),
        Text('selected: ${_selected + 1} / $_count'),
        const SizedBox(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _count,
            autofocus: true,
            edgeBehavior: EdgeBehavior.contain,
            scrollbar: true,
            onSelectionChanged: (index) => setState(() => _selected = index),
            onActivate: (index) => setState(() {
              _lastAction = 'Opened task ${index + 1}';
            }),
            itemBuilder: (context, index, selected) => Text(
              '${selected ? '›' : ' '} Task ${(index + 1).toString().padLeft(4, '0')}',
              style: selected
                  ? Theme.of(context).selectionStyle
                  : CellStyle.empty,
            ),
          ),
        ),
        const SizedBox(height: 1),
        Text('last: $_lastAction'),
      ],
    ),
  );
}

/// A local-breakpoint demo: its buttons change only the child envelope, so the
/// LayoutBuilder proves that panes adapt to parent constraints rather than the
/// global browser or terminal size.
class _ResponsiveWorkspaceTour extends StatefulWidget {
  const _ResponsiveWorkspaceTour();

  @override
  State<_ResponsiveWorkspaceTour> createState() =>
      _ResponsiveWorkspaceTourState();
}

class _ResponsiveWorkspaceTourState extends State<_ResponsiveWorkspaceTour> {
  var _width = 68;

  Widget _files() => const Panel(
    title: 'Files',
    child: Padding(
      padding: EdgeInsets.all(1),
      child: Text('README.md\nlib/\ntest/'),
    ),
  );

  Widget _preview() => const Panel(
    title: 'Preview',
    child: Padding(
      padding: EdgeInsets.all(1),
      child: Text('# Fleury\n\nA framework for terminal apps.'),
    ),
  );

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Button(
              label: 'Narrow',
              autofocus: true,
              onPressed: () => setState(() => _width = 42),
            ),
            const SizedBox(width: 1),
            Button(label: 'Wide', onPressed: () => setState(() => _width = 68)),
          ],
        ),
        const SizedBox(height: 1),
        Expanded(
          child: SizedBox(
            width: _width,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = (constraints.maxCols ?? 0) >= 60;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      wide ? 'WIDE · TWO PANES' : 'NARROW · STACKED',
                      style: const CellStyle(bold: true),
                    ),
                    const SizedBox(height: 1),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 2, child: _files()),
                                const SizedBox(width: 1),
                                Expanded(flex: 3, child: _preview()),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _files()),
                                const SizedBox(height: 1),
                                Expanded(child: _preview()),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

enum _NavigationResult { done }

/// The first navigation example intentionally teaches only the three stack
/// operations. Each screen labels its depth so the behavior is readable
/// without reverse-engineering project-specific state.
class _NavigationBasicsTour extends StatefulWidget {
  const _NavigationBasicsTour();

  @override
  State<_NavigationBasicsTour> createState() => _NavigationBasicsTourState();
}

class _NavigationBasicsTourState extends State<_NavigationBasicsTour> {
  String _result = 'none';

  Future<void> _openDetails() async {
    final result = await context.push<_NavigationResult>(
      const _NavigationDetailsTour(),
    );
    if (!mounted || result == null) return;
    setState(() => _result = result.name);
  }

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('HOME · STACK DEPTH 1', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        Button(label: 'Push details', autofocus: true, onPressed: _openDetails),
        const Spacer(),
        Text('result: $_result'),
      ],
    ),
  );
}

class _NavigationDetailsTour extends StatefulWidget {
  const _NavigationDetailsTour();

  @override
  State<_NavigationDetailsTour> createState() => _NavigationDetailsTourState();
}

class _NavigationDetailsTourState extends State<_NavigationDetailsTour> {
  String _dialogResult = 'not shown';

  Future<void> _presentDialog() async {
    final confirmed = await context.present<bool>(
      const _NavigationConfirmationDialog(),
    );
    if (!mounted) return;
    setState(() => _dialogResult = confirmed == true ? 'confirmed' : 'closed');
  }

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DETAILS · STACK DEPTH 2', style: CellStyle(bold: true)),
        Text('dialog: $_dialogResult'),
        const SizedBox(height: 1),
        Button(
          label: 'Present dialog',
          autofocus: true,
          onPressed: _presentDialog,
        ),
        Button(
          label: 'Pop with result',
          onPressed: () => context.pop(_NavigationResult.done),
        ),
        Button(label: 'Pop without result', onPressed: context.pop),
      ],
    ),
  );
}

class _NavigationConfirmationDialog extends StatelessWidget {
  const _NavigationConfirmationDialog();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 7,
    child: Panel(
      title: 'PRESENTED DIALOG',
      focused: true,
      child: Center(
        child: Button(
          label: 'Confirm and pop',
          autofocus: true,
          onPressed: () => context.pop(true),
        ),
      ),
    ),
  );
}

class _DialogPlacementTour extends StatefulWidget {
  const _DialogPlacementTour();

  @override
  State<_DialogPlacementTour> createState() => _DialogPlacementTourState();
}

class _DialogPlacementTourState extends State<_DialogPlacementTour> {
  Alignment _alignment = Alignment.center;

  Future<void> _show(Alignment alignment) async {
    setState(() => _alignment = alignment);
    await context.present<void>(
      const _PlacedDialogTour(),
      alignment: alignment,
      transition: RouteTransition.none,
    );
  }

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CHOOSE WHERE TO PRESENT', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        Select<Alignment>(
          semanticLabel: 'Dialog placement',
          autofocus: true,
          value: _alignment,
          options: const [
            SelectOption(value: Alignment.topLeft, label: 'Top left'),
            SelectOption(value: Alignment.center, label: 'Center'),
            SelectOption(value: Alignment.bottomRight, label: 'Bottom right'),
          ],
          onChanged: _show,
        ),
        const Spacer(),
        const Text('Choosing an option presents the dialog.'),
      ],
    ),
  );
}

class _PlacedDialogTour extends StatelessWidget {
  const _PlacedDialogTour();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 6,
    child: Panel(
      title: 'PLACED DIALOG',
      focused: true,
      child: Center(
        child: Button(label: 'Close', autofocus: true, onPressed: context.pop),
      ),
    ),
  );
}

class _BackGuardHomeTour extends StatefulWidget {
  const _BackGuardHomeTour();

  @override
  State<_BackGuardHomeTour> createState() => _BackGuardHomeTourState();
}

class _BackGuardHomeTourState extends State<_BackGuardHomeTour> {
  String _savedText = 'Release notes';

  void _saveDraft(String value) => setState(() => _savedText = value);

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DRAFTS', style: CellStyle(bold: true)),
        Text('saved: $_savedText'),
        const SizedBox(height: 1),
        Button(
          label: 'Edit draft',
          autofocus: true,
          onPressed: () => context.push<void>(
            _GuardedEditorTour(initialText: _savedText, onSave: _saveDraft),
          ),
        ),
      ],
    ),
  );
}

class _GuardedEditorTour extends StatefulWidget {
  const _GuardedEditorTour({required this.initialText, required this.onSave});

  final String initialText;
  final void Function(String) onSave;

  @override
  State<_GuardedEditorTour> createState() => _GuardedEditorTourState();
}

class _GuardedEditorTourState extends State<_GuardedEditorTour> {
  late final TextEditingController _controller;
  late String _savedText;
  bool _dirty = false;
  String _status = 'No unsaved changes';

  @override
  void initState() {
    super.initState();
    _savedText = widget.initialText;
    _controller = TextEditingController(text: _savedText);
  }

  void _handleChanged(String value) {
    final dirty = value != _savedText;
    setState(() {
      _dirty = dirty;
      _status = dirty ? 'Unsaved changes' : 'No unsaved changes';
    });
  }

  void _save() {
    final value = _controller.text;
    widget.onSave(value);
    setState(() {
      _savedText = value;
      _dirty = false;
      _status = 'Saved — back is allowed';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onBlocked: () => setState(() => _status = 'Back blocked — save first'),
    child: _framed(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EDITOR', style: CellStyle(bold: true)),
          Text('status: $_status'),
          const SizedBox(height: 1),
          TextInput(
            autofocus: true,
            semanticLabel: 'Draft text',
            controller: _controller,
            onChanged: _handleChanged,
          ),
          const SizedBox(height: 1),
          Button(
            label: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Button(label: 'Save', onPressed: _save),
          Button(label: 'Discard', onPressed: context.pop),
        ],
      ),
    ),
  );
}

enum _TransitionKind { fade, slide, none }

class _TransitionTour extends StatefulWidget {
  const _TransitionTour();

  @override
  State<_TransitionTour> createState() => _TransitionTourState();
}

class _TransitionTourState extends State<_TransitionTour> {
  _TransitionKind _kind = _TransitionKind.slide;

  RouteTransition get _previewTransition => switch (_kind) {
    _TransitionKind.fade => RouteTransition.fade,
    _TransitionKind.slide => RouteTransition.slide,
    _TransitionKind.none => RouteTransition.none,
  };

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ROUTE TRANSITIONS', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        Select<_TransitionKind>(
          semanticLabel: 'Transition',
          autofocus: true,
          value: _kind,
          options: const [
            SelectOption(value: _TransitionKind.fade, label: 'Fade'),
            SelectOption(value: _TransitionKind.slide, label: 'Slide'),
            SelectOption(value: _TransitionKind.none, label: 'None'),
          ],
          onChanged: (value) => setState(() => _kind = value),
        ),
        Button(
          label: 'Preview push',
          onPressed: () => context.push<void>(
            _TransitionScreenTour(kind: _kind),
            transition: _previewTransition,
          ),
        ),
        const Spacer(),
        const Text('Using Fleury\'s production transition presets.'),
      ],
    ),
  );
}

class _TransitionScreenTour extends StatelessWidget {
  const _TransitionScreenTour({required this.kind});

  final _TransitionKind kind;

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${kind.name.toUpperCase()} · PUSHED SCREEN'),
        const Spacer(),
        Button(label: 'Preview pop', autofocus: true, onPressed: context.pop),
      ],
    ),
  );
}

class _NestedProjectsTour extends StatelessWidget {
  const _NestedProjectsTour();

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PROJECTS · OUTER STACK 1', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        Button(
          label: 'Start setup',
          autofocus: true,
          onPressed: () => context.push<void>(const _NestedSetupTour()),
        ),
      ],
    ),
  );
}

class _NestedSetupTour extends StatelessWidget {
  const _NestedSetupTour();

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('SETUP · OUTER STACK 2', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        Expanded(
          child: Panel(
            title: 'INNER FLOW',
            child: Navigator(
              transition: RouteTransition.none,
              home: const _NestedFlowStepTour(step: 1),
            ),
          ),
        ),
        const SizedBox(height: 1),
        const Text('The inner stack advances inside one outer route.'),
      ],
    ),
  );
}

class _NestedFlowStepTour extends StatelessWidget {
  const _NestedFlowStepTour({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('INNER STEP $step OF 3'),
        Text(switch (step) {
          1 => 'Choose a project',
          2 => 'Configure access',
          _ => 'Review and finish',
        }),
        const Spacer(),
        if (step < 3)
          Button(
            label: 'Next step',
            autofocus: true,
            onPressed: () =>
                context.push<void>(_NestedFlowStepTour(step: step + 1)),
          )
        else
          Button(
            label: 'Finish setup',
            autofocus: true,
            onPressed: () => context.rootNavigator.pushReplacement<void>(
              const _NestedProjectReadyTour(),
            ),
          ),
        if (step > 1) Button(label: 'Previous', onPressed: context.pop),
        Button(label: 'Cancel setup', onPressed: context.rootNavigator.pop),
      ],
    ),
  );
}

class _NestedProjectReadyTour extends StatelessWidget {
  const _NestedProjectReadyTour();

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PROJECT READY · OUTER STACK 2'),
        const Text('The entire inner history was removed together.'),
        const Spacer(),
        Button(
          label: 'Back to projects',
          autofocus: true,
          onPressed: context.pop,
        ),
      ],
    ),
  );
}

/// The guide's focus explorer. The docs host supplies the same automatic
/// traversal that FleuryApp supplies to an application screen.
class _FocusExplorerTour extends StatefulWidget {
  const _FocusExplorerTour();

  @override
  State<_FocusExplorerTour> createState() => _FocusExplorerTourState();
}

class _FocusExplorerTourState extends State<_FocusExplorerTour> {
  String _activeRegion = 'Files';
  String _lastAction = 'New file is focused';

  void _markRegion(String name, bool focused) {
    if (!focused || _activeRegion == name) return;
    setState(() => _activeRegion = name);
  }

  void _act(String action) => setState(() => _lastAction = action);

  Future<void> _openDialog() async {
    setState(() {
      _activeRegion = 'Dialog';
      _lastAction = 'Dialog focus is trapped';
    });
    final published = await Navigator.of(context).present<bool>(
      const _FocusExplorerPublishDialog(),
      transition: RouteTransition.none,
    );
    if (!mounted) return;
    setState(() {
      _activeRegion = 'Preview';
      _lastAction = published == true ? 'Published' : 'Publish canceled';
    });
  }

  Widget _actionButton({
    required String label,
    required void Function() onPressed,
    bool autofocus = false,
  }) => SizedBox(
    width: 14,
    child: Button(label: label, autofocus: autofocus, onPressed: onPressed),
  );

  Widget _region({required String name, required List<Widget> controls}) =>
      Panel(
        title: name,
        focused: _activeRegion == name,
        child: FocusDetector(
          onFocusChange: (focused) => _markRegion(name, focused),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: controls,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'AUTOMATIC · TAB READS · ARROWS MOVE',
          style: CellStyle(bold: true),
        ),
        Text('active: $_activeRegion', style: const CellStyle(dim: true)),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _region(
                  name: 'Files',
                  controls: [
                    _actionButton(
                      label: 'New file',
                      autofocus: true,
                      onPressed: () => _act('Created a file'),
                    ),
                    _actionButton(
                      label: 'Open file',
                      onPressed: () => _act('Opened a file'),
                    ),
                    _actionButton(
                      label: 'Settings',
                      onPressed: () => _act('Opened settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _region(
                  name: 'Preview',
                  controls: [
                    _actionButton(
                      label: 'Refresh',
                      onPressed: () => _act('Refreshed preview'),
                    ),
                    _actionButton(
                      label: 'Inspect',
                      onPressed: () => _act('Opened inspector'),
                    ),
                    _actionButton(label: 'Publish…', onPressed: _openDialog),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Text('last: $_lastAction'),
      ],
    ),
  );
}

class _FocusExplorerPublishDialog extends StatelessWidget {
  const _FocusExplorerPublishDialog();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    height: 8,
    child: Panel(
      title: 'Publish?',
      focused: true,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          children: [
            const Text('Tab stays inside this dialog.'),
            const SizedBox(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Button(
                  label: 'Cancel',
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 1),
                Button(
                  label: 'Publish',
                  variant: ButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows the common programmatic-focus handoff: an action owns the decision,
/// while the destination owns the FocusNode that identifies it.
class _ProgrammaticFocusTour extends StatefulWidget {
  const _ProgrammaticFocusTour();

  @override
  State<_ProgrammaticFocusTour> createState() => _ProgrammaticFocusTourState();
}

class _ProgrammaticFocusTourState extends State<_ProgrammaticFocusTour> {
  final _searchFocus = FocusNode(debugLabel: 'search');
  String _lastAction = 'Focus search is focused';

  void _focusSearch() {
    _searchFocus.requestFocus();
    setState(() => _lastAction = 'Focus moved to Search files');
  }

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PROGRAMMATIC FOCUS', style: CellStyle(bold: true)),
        const Text(
          'Press Enter on Focus search, then type.',
          style: CellStyle(dim: true),
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            Button(
              label: 'Focus search',
              autofocus: true,
              onPressed: _focusSearch,
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 24,
              child: TextInput(
                focusNode: _searchFocus,
                semanticLabel: 'Search files',
                placeholder: 'Search files',
                onChanged: (query) => setState(() {
                  _lastAction = 'Searching for "$query"';
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text('last: $_lastAction'),
      ],
    ),
  );

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }
}

/// Makes FocusDetector's subtree semantics visible: moving Title -> Body does
/// not emit another change, while moving to Preview crosses the boundary once.
class _FocusDetectorTour extends StatefulWidget {
  const _FocusDetectorTour();

  @override
  State<_FocusDetectorTour> createState() => _FocusDetectorTourState();
}

class _FocusDetectorTourState extends State<_FocusDetectorTour> {
  bool _inside = false;
  int _changes = 0;

  void _onFocusChange(bool inside) => setState(() {
    _inside = inside;
    _changes++;
  });

  @override
  Widget build(BuildContext context) => _framed(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'FOCUSDETECTOR · ONE SUBTREE BOUNDARY',
          style: CellStyle(bold: true),
        ),
        Text(
          'editor: ${_inside ? 'ACTIVE' : 'inactive'} · '
          'boundary changes: $_changes',
        ),
        const SizedBox(height: 1),
        Panel(
          title: 'Editor region',
          focused: _inside,
          expandChild: false,
          child: FocusDetector(
            onFocusChange: _onFocusChange,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Button(label: 'Title', autofocus: true, onPressed: () {}),
                  Button(label: 'Body', onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 1),
        Button(label: 'Preview (outside)', onPressed: () {}),
        const Text(
          'Tab Title → Body: same region · Preview: leaves once',
          style: CellStyle(dim: true),
        ),
      ],
    ),
  );
}

/// The guide's "Key bindings" demo: every authoring feature on one screen,
/// with the hint bar proving that bindings are data the app can render.
class _KeyBindingsTour extends StatefulWidget {
  const _KeyBindingsTour();
  @override
  State<_KeyBindingsTour> createState() => _KeyBindingsTourState();
}

class _KeyBindingsTourState extends State<_KeyBindingsTour> {
  static const _count = 7;
  String _last = 'move with j / k, bookmark with Ctrl+S, clear with Space c';
  int _row = 3;
  final Set<int> _saved = <int>{};

  void _move(int delta) =>
      setState(() => _row = (_row + delta).clamp(0, _count - 1));

  void _toggleSave() => setState(() {
    if (_saved.remove(_row)) {
      _last = 'Un-bookmarked item ${_row + 1}';
    } else {
      _saved.add(_row);
      _last = 'Bookmarked item ${_row + 1} ★';
    }
  });

  // The Space leader clears every bookmark in one stroke — a simple,
  // obviously-useful action tied to Save.
  void _clearSaved() => setState(() {
    if (_saved.isEmpty) {
      _last = 'No bookmarks to clear';
      return;
    }
    final n = _saved.length;
    _saved.clear();
    _last = 'Cleared $n bookmark${n == 1 ? '' : 's'}';
  });

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(.ctrl.s, label: 'Bookmark', onTrigger: (_) => _toggleSave()),
        KeyBinding(
          .j,
          aliases: [.down],
          label: 'Down',
          includeRepeats: true,
          onTrigger: (_) => _move(1),
        ),
        KeyBinding(
          .k,
          aliases: [.up],
          label: 'Up',
          includeRepeats: true,
          onTrigger: (_) => _move(-1),
        ),
        KeyBinding(
          .g.g,
          label: 'Top',
          onTrigger: (_) => setState(() {
            _row = 0;
            _last = 'Jumped to top';
          }),
        ),
        KeyBinding(.space.c, label: 'Clear ★', onTrigger: (_) => _clearSaved()),
      ],
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(1),
              child: Text(_last, style: const CellStyle(bold: true)),
            ),
            Expanded(
              child: ListViewSelectionDemoRows(row: _row, saved: _saved),
            ),
            const KeyHintBar(),
          ],
        ),
      ),
    );
  }
}

/// Seven rows: one highlighted (the j/k cursor), any bookmarked (★, Ctrl+S).
class ListViewSelectionDemoRows extends StatelessWidget {
  const ListViewSelectionDemoRows({
    super.key,
    required this.row,
    this.saved = const <int>{},
  });
  final int row;
  final Set<int> saved;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          Text(
            '${i == row ? '▸' : ' '} ${saved.contains(i) ? '★' : ' '} '
            'item ${i + 1}',
            style: i == row
                ? CellStyle(foreground: theme.colorScheme.primary, bold: true)
                : saved.contains(i)
                ? CellStyle(foreground: theme.colorScheme.primary)
                : const CellStyle(),
          ),
      ],
    );
  }
}

/// KeyDetector's defining trait: it PROPAGATES by default and consumes only
/// what it owns. The inner detector moves a cursor inside the pane and
/// consumes the arrow; at the pane's edge it does NOT consume, so the arrow
/// bubbles to the outer KeyBindings — the scroll-region-yields-at-its-boundary
/// pattern, live.
class _KeyDetectorTour extends StatefulWidget {
  const _KeyDetectorTour();
  @override
  State<_KeyDetectorTour> createState() => _KeyDetectorTourState();
}

class _KeyDetectorTourState extends State<_KeyDetectorTour> {
  static const _count = 3;
  int _cursor = 0;
  int _paneHandled = 0;
  int _appHandled = 0;
  String _lastKey = '—';
  String _paneResult = 'waiting';
  String _appResult = 'waiting';
  bool _lastBubbled = false;

  void _handleAtApp(String key) {
    setState(() {
      _lastKey = key;
      _paneResult = 'PASSED · at edge';
      _appResult = 'HANDLED';
      _appHandled++;
      _lastBubbled = true;
    });
  }

  void _handleInPane(KeyEvent event, String key, int nextCursor) {
    setState(() {
      _cursor = nextCursor;
      _lastKey = key;
      _paneResult = 'HANDLED · moved';
      _appResult = '— not reached';
      _paneHandled++;
      _lastBubbled = false;
    });
    event.consume();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      // The ancestor. It only ever hears an arrow the pane declined to
      // consume — i.e. one that fell off the pane's edge.
      bindings: [
        KeyBinding(
          KeyCode.arrowDown,
          label: 'App ↓',
          onTrigger: (_) => _handleAtApp('↓'),
        ),
        KeyBinding(
          KeyCode.arrowUp,
          label: 'App ↑',
          onTrigger: (_) => _handleAtApp('↑'),
        ),
      ],
      child: KeyDetector(
        onKey: (e) {
          if (e.code == KeyCode.arrowDown && _cursor < _count - 1) {
            _handleInPane(e, '↓', _cursor + 1);
          } else if (e.code == KeyCode.arrowUp && _cursor > 0) {
            _handleInPane(e, '↑', _cursor - 1);
          }
          // At an edge: do nothing → the arrow continues to the ancestor.
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: Text('CLICK · THEN ↓ ↓ ↓', style: CellStyle(bold: true)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  'first 2 move; #3 bubbles',
                  style: CellStyle(dim: true),
                ),
              ),
              const SizedBox(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text('last key  $_lastKey'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  'PANE  $_paneResult',
                  style: CellStyle(
                    bold: _paneResult != 'waiting',
                    foreground: _lastBubbled
                        ? theme.colorScheme.warning
                        : _paneResult == 'waiting'
                        ? null
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  'APP   $_appResult',
                  style: CellStyle(
                    bold: _lastBubbled,
                    dim: !_lastBubbled,
                    foreground: _lastBubbled ? theme.colorScheme.warning : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  'pane $_paneHandled · app $_appHandled',
                  style: const CellStyle(dim: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: Text('── inner pane ──'),
              ),
              for (var i = 0; i < _count; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Text(
                    '${i == _cursor ? '▸' : ' '} line ${i + 1}',
                    style: i == _cursor
                        ? CellStyle(
                            foreground: theme.colorScheme.primary,
                            bold: true,
                          )
                        : const CellStyle(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
