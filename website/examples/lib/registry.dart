// Web-safe widget examples for the docs site. These run client-side via
// dart2js (runTuiWebDom), so everything imports the dart:io-free host SPI
// (fleury_host) and the web-safe widget barrel (fleury_widgets_web) — never the
// full `fleury.dart` / `fleury_widgets.dart` umbrellas, which pull in native
// drivers and the 7 dart:io-backed widgets.
import 'package:fleury/fleury_host.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// Builds the root widget for one live example.
typedef ExampleBuilder = Widget Function();

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
    this.height = 12,
  });

  /// Stable id, e.g. `gauge.basic`.
  final String id;

  /// Display name of the widget, e.g. `Gauge`.
  final String widget;

  /// Section the widget belongs to.
  final String category;

  /// One-line description for the reference page.
  final String blurb;

  /// Root-widget factory mounted via runTuiWebDom.
  final ExampleBuilder builder;

  /// Host height in `em`.
  final int height;
}

final List<ExampleInfo> exampleList = <ExampleInfo>[
  // ── Charts & meters ──────────────────────────────────────────────────────
  ExampleInfo(
    id: 'gauge.basic',
    widget: 'Gauge',
    category: 'Charts & meters',
    blurb: 'A labelled progress meter with colored warning/critical thresholds.',
    height: 6,
    builder: () => _framed(Gauge(
      value: 0.62,
      label: 'CPU',
      thresholds: <(double, Color)>[
        (0.7, _theme.colorScheme.warning),
        (0.9, _theme.colorScheme.error),
      ],
    )),
  ),
  ExampleInfo(
    id: 'sparkline.basic',
    widget: 'Sparkline',
    category: 'Charts & meters',
    blurb: 'A compact inline trend line with an optional trailing value.',
    height: 5,
    builder: () => _framed(Sparkline(
      data: const <num>[3, 5, 4, 7, 6, 9, 8, 11, 9, 12, 10, 13, 12, 15],
      color: _theme.colorScheme.success,
      showValue: true,
    )),
  ),
  ExampleInfo(
    id: 'linechart.basic',
    widget: 'LineChart',
    category: 'Charts & meters',
    blurb: 'A braille line/area/scatter chart with axes, legend, and references.',
    builder: () => _framed(LineChart(
      series: <LineSeries>[
        LineSeries(
          const <(num, num)>[
            (0, 1), (1, 3), (2, 2), (3, 5), (4, 4), (5, 7), (6, 6), (7, 8),
          ],
          label: 'load',
          color: _theme.colorScheme.primary,
        ),
      ],
      showAxes: true,
      showLegend: true,
      yRange: const (0, 8),
    )),
  ),
  ExampleInfo(
    id: 'barchart.basic',
    widget: 'BarChart',
    category: 'Charts & meters',
    blurb: 'Vertical bars with a categorical palette and an optional y-axis.',
    builder: () => _framed(BarChart(
      bars: <Bar>[Bar('q1', 12), Bar('q2', 19), Bar('q3', 9), Bar('q4', 22)],
      showYAxis: true,
    )),
  ),
  ExampleInfo(
    id: 'histogram.basic',
    widget: 'Histogram',
    category: 'Charts & meters',
    blurb: 'Bins a list of samples into a frequency distribution.',
    builder: () => _framed(const Histogram(
      values: <num>[1, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 6, 6, 7, 2, 3, 4, 5],
      bins: 7,
      showValues: true,
    )),
  ),
  ExampleInfo(
    id: 'heatmap.basic',
    widget: 'Heatmap',
    category: 'Charts & meters',
    blurb: 'A 2-D grid of values shaded by magnitude, with an optional legend.',
    builder: () => _framed(const Heatmap(
      values: <List<num>>[
        <num>[0.1, 0.3, 0.6, 0.9],
        <num>[0.2, 0.5, 0.8, 0.4],
        <num>[0.7, 0.6, 0.3, 0.1],
      ],
      rowLabels: <String>['a', 'b', 'c'],
      colLabels: <String>['w', 'x', 'y', 'z'],
      showLegend: true,
    )),
  ),
  ExampleInfo(
    id: 'progressbar.basic',
    widget: 'ProgressBar',
    category: 'Charts & meters',
    blurb: 'A determinate or indeterminate progress indicator.',
    height: 4,
    builder: () => _framed(const ProgressBar(value: 0.45)),
  ),
  ExampleInfo(
    id: 'digits.basic',
    widget: 'Digits',
    category: 'Charts & meters',
    blurb: 'Seven-segment-style large digits for clocks and counters.',
    height: 6,
    builder: () => _framed(Digits('12:34:56', color: _theme.colorScheme.primary)),
  ),

  // ── Data & lists ─────────────────────────────────────────────────────────
  ExampleInfo(
    id: 'datatable.basic',
    widget: 'DataTable',
    category: 'Data & lists',
    blurb: 'A columnar table with flex/fixed widths and row/cell selection.',
    builder: () => _framed(DataTable(
      rowCount: _people.length,
      controller: DataTableController(),
      selectionMode: DataTableSelectionMode.row,
      columns: const <DataTableColumn>[
        DataTableColumn(id: 'name', title: 'NAME', width: FixedColumnWidth(10)),
        DataTableColumn(id: 'role', title: 'ROLE'),
        DataTableColumn(id: 'commits', title: 'COMMITS', width: FixedColumnWidth(9)),
      ],
      cellBuilder: (row, col) {
        final p = _people[row];
        return switch (col) {
          'name' => p.$1,
          'role' => p.$2,
          _ => p.$3.toString(),
        };
      },
    )),
  ),
  ExampleInfo(
    id: 'tree.basic',
    widget: 'Tree',
    category: 'Data & lists',
    blurb: 'An expandable hierarchy with keyboard navigation and type-ahead.',
    builder: () => _framed(Tree<String>(
      label: 'project',
      roots: <TreeNode<String>>[
        TreeNode<String>('lib/', children: <TreeNode<String>>[
          const TreeNode<String>('main.dart'),
          TreeNode<String>('src/', children: const <TreeNode<String>>[
            TreeNode<String>('app.dart'),
            TreeNode<String>('theme.dart'),
          ]),
        ]),
        const TreeNode<String>('README.md'),
      ],
    )),
  ),

  // ── Documents ────────────────────────────────────────────────────────────
  ExampleInfo(
    id: 'markdown.basic',
    widget: 'MarkdownView',
    category: 'Documents',
    blurb: 'Renders Markdown — headings, lists, code, quotes — to styled cells.',
    builder: () => _framed(MarkdownView(markdown: _markdownSample)),
  ),
  ExampleInfo(
    id: 'codeview.basic',
    widget: 'CodeView',
    category: 'Documents',
    blurb: 'Source with line numbers, comment dimming, and copy support.',
    builder: () => _framed(CodeView(source: _codeSample, language: 'dart')),
  ),
  ExampleInfo(
    id: 'jsonview.basic',
    widget: 'JsonView',
    category: 'Documents',
    blurb: 'A collapsible, type-colored tree view of a JSON value.',
    builder: () => _framed(JsonView(
      value: const <String, Object?>{
        'name': 'fleury',
        'version': '1.0.0',
        'web': true,
        'targets': <String>['terminal', 'dom', 'serve'],
      },
      initialExpandedDepth: 2,
    )),
  ),

  // ── Agent surfaces ───────────────────────────────────────────────────────
  ExampleInfo(
    id: 'messagelist.basic',
    widget: 'MessageList',
    category: 'Agent surfaces',
    blurb: 'A role-aware conversation transcript (user/assistant/tool/…).',
    builder: () => _framed(MessageList(
      showTimestamp: false,
      messages: const <MessageEntry>[
        MessageEntry(text: 'Add a --version flag.', role: MessageRole.user),
        MessageEntry(
            text: "I'll read the CLI and pubspec first.",
            role: MessageRole.assistant),
        MessageEntry(text: 'Read  lib/main.dart', role: MessageRole.tool),
        MessageEntry(text: 'Done — prints 1.4.0.', role: MessageRole.assistant),
      ],
    )),
  ),
  ExampleInfo(
    id: 'contextpanel.basic',
    widget: 'ContextPanel',
    category: 'Agent surfaces',
    blurb: 'Lists context items with a token-usage meter and share bars.',
    builder: () => _framed(ContextPanel(
      showTokenShare: true,
      usage: const TokenUsage(
          input: 9200, output: 3100, contextUsed: 12300, contextLimit: 200000),
      items: const <ContextItem>[
        ContextItem(
            id: 'a', label: 'lib/main.dart', kind: ContextItemKind.file, tokenCount: 410),
        ContextItem(
            id: 'b', label: 'pubspec.yaml', kind: ContextItemKind.file, tokenCount: 120),
        ContextItem(
            id: 'c',
            label: 'dart test',
            kind: ContextItemKind.command,
            tokenCount: 90),
      ],
    )),
  ),
  ExampleInfo(
    id: 'taskgraph.basic',
    widget: 'TaskGraph',
    category: 'Agent surfaces',
    blurb: 'A compact plan / dependency graph with per-node status.',
    builder: () => _framed(const TaskGraph(nodes: <TaskGraphNode>[
      TaskGraphNode(id: '1', title: 'Inspect CLI', status: TaskGraphStatus.succeeded),
      TaskGraphNode(id: '2', title: 'Handle --version', status: TaskGraphStatus.running),
      TaskGraphNode(id: '3', title: 'Add a test', status: TaskGraphStatus.pending),
    ])),
  ),

  // ── Showcases (full apps; rendered on the Showcases page, not as widgets) ──
  ExampleInfo(
    id: 'showcase.dashboard',
    widget: 'System monitor',
    category: 'Showcases',
    blurb:
        'An htop-style live dashboard: per-core CPU gauges, a streaming history '
        'chart, memory/IO meters, and a live process table.',
    height: 42,
    builder: () => const DashboardApp(),
  ),
  ExampleInfo(
    id: 'showcase.files',
    widget: 'File manager',
    category: 'Showcases',
    blurb:
        'A two-pane file explorer over an in-memory project, with a preview that '
        'adapts to each file type (code, Markdown, JSON).',
    height: 30,
    builder: () => const FileManagerApp(),
  ),
  ExampleInfo(
    id: 'showcase.agent',
    widget: 'Coding agent',
    category: 'Showcases',
    blurb:
        'A Claude-Code-style streaming session: prose, tool cards, a live todo '
        'list, a colored diff, and a prompt box.',
    height: 38,
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
A **retained-mode** UI framework.

- terminal target
- web target

> One app, two surfaces.
''';

const String _codeSample = '''
import 'package:fleury/fleury.dart';

Future<void> main() => runTui(const App());
''';

// A compact dark theme so embedded examples read well on the docs page.
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

Widget _framed(Widget child) => Theme(
      data: _theme,
      child: Padding(padding: const EdgeInsets.all(1), child: child),
    );
