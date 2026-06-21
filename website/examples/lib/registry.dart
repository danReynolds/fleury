// Web-safe widget examples for the docs site. These run client-side via
// dart2js (runTuiWebDom), so everything imports the dart:io-free host SPI
// (fleury_host) and the web-safe widget barrel (fleury_widgets_web) — never the
// full `fleury.dart` / `fleury_widgets.dart` umbrellas, which pull in native
// drivers and the dart:io-backed widgets.
import 'dart:math';

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
    this.cols = 56,
    this.rows = 10,
    this.code,
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

  /// Host grid size in cells — the example is framed to exactly this, not
  /// stretched to the page column.
  final int cols;
  final int rows;

  /// Optional override for the code shown on the page. Used by animated
  /// examples so the snippet stays the clean static widget usage while the live
  /// example streams. When null, the code is extracted from the builder source.
  final String? code;
}

final List<ExampleInfo> exampleList = <ExampleInfo>[
  // ── Charts & meters ──────────────────────────────────────────────────────
  ExampleInfo(
    id: 'gauge.basic',
    widget: 'Gauge',
    category: 'Charts & meters',
    blurb: 'A labelled progress meter with colored warning/critical thresholds.',
    cols: 40,
    rows: 3,
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
    cols: 44,
    rows: 2,
    code: '''Sparkline(
  data: <num>[3, 5, 4, 7, 6, 9, 8, 11, 9, 12],
  color: theme.colorScheme.success,
  showValue: true,
)''',
    builder: () => _framed(_LiveSeries(
      length: 28,
      min: 0,
      max: 20,
      builder: (data) => Sparkline(
        data: data,
        color: _theme.colorScheme.success,
        showValue: true,
      ),
    )),
  ),
  ExampleInfo(
    id: 'linechart.basic',
    widget: 'LineChart',
    category: 'Charts & meters',
    blurb: 'A braille line/area/scatter chart with axes, legend, and references.',
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
    builder: () => _framed(_LiveSeries(
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
    )),
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
    builder: () => _framed(_LiveSeries(
      length: 5,
      min: 2,
      max: 24,
      builder: (data) => BarChart(
        bars: <Bar>[
          for (var i = 0; i < data.length; i++) Bar('q${i + 1}', data[i]),
        ],
        showYAxis: true,
      ),
    )),
  ),
  ExampleInfo(
    id: 'histogram.basic',
    widget: 'Histogram',
    category: 'Charts & meters',
    blurb: 'Bins a list of samples into a frequency distribution.',
    cols: 52,
    rows: 12,
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
    cols: 40,
    rows: 8,
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
    cols: 44,
    rows: 2,
    builder: () => _framed(const ProgressBar(value: 0.45)),
  ),
  ExampleInfo(
    id: 'digits.basic',
    widget: 'Digits',
    category: 'Charts & meters',
    blurb: 'Seven-segment-style large digits for clocks and counters.',
    cols: 44,
    rows: 7,
    builder: () => _framed(Digits('12:34:56', color: _theme.colorScheme.primary)),
  ),

  // ── Data & lists ─────────────────────────────────────────────────────────
  ExampleInfo(
    id: 'datatable.basic',
    widget: 'DataTable',
    category: 'Data & lists',
    blurb: 'A columnar table with flex/fixed widths and row/cell selection.',
    cols: 48,
    rows: 8,
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
    cols: 40,
    rows: 9,
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
    cols: 60,
    rows: 13,
    builder: () => _framed(MarkdownView(markdown: _markdownSample)),
  ),
  ExampleInfo(
    id: 'codeview.basic',
    widget: 'CodeView',
    category: 'Documents',
    blurb: 'Source with line numbers, comment dimming, and copy support.',
    cols: 58,
    rows: 8,
    builder: () => _framed(CodeView(source: _codeSample, language: 'dart')),
  ),
  ExampleInfo(
    id: 'jsonview.basic',
    widget: 'JsonView',
    category: 'Documents',
    blurb: 'A collapsible, type-colored tree view of a JSON value.',
    cols: 48,
    rows: 10,
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
    cols: 64,
    rows: 8,
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
    cols: 56,
    rows: 9,
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
    cols: 48,
    rows: 6,
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
    cols: 116,
    rows: 38,
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

  double _walk(double v) => (v + (_r.nextDouble() * 2 - 1) * (widget.max - widget.min) * 0.16)
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
