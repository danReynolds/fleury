// Browser-safe examples use the same bundled widget API as terminal apps.
// Native hosting and filesystem APIs stay in fleury.dart.
import 'package:fleury/fleury_core.dart';
import 'dart:async';
import 'dart:math';

import 'package:fleury_samples/samples.dart';
import 'package:fleury/themes.dart';

import 'state_management_guide.dart' as state;
import 'loading_data_guide.dart' as loading;
import 'testing_guide.dart' as testing;
import 'input_guide.dart' as input;
import 'lists_guide.dart' as lists;
import 'datatable_rows.dart';
import 'datatable_cells.dart';
import 'forms/project_form.dart';
import 'forms/save_project.dart';
import 'forms/related_fields.dart';
import 'forms/custom_field.dart';
import 'concepts.dart' as concepts;
import 'flutter_map.dart' as flutter_map;
import 'live_previews.dart' as live;
import 'home_pad.dart' as home_pad;
import 'hot_reload_guide.dart';

/// Builds the root widget for one live example.
typedef ExampleBuilder = Widget Function();

/// Visual theme used by a docs embed.
enum DocsExampleStyle { dark, light }

/// Lets the host page retheme a live example after it has mounted.
final class DocsExampleThemeController extends Notifier {
  DocsExampleThemeController(this._style);

  DocsExampleStyle _style;

  DocsExampleStyle get style => _style;

  set style(DocsExampleStyle value) {
    if (value == _style) return;
    _style = value;
    notify();
  }
}

Widget themedExampleRoot(
  ExampleBuilder builder,
  DocsExampleThemeController controller,
) {
  final child = builder();
  return NotifierBuilder(
    notifier: controller,
    builder: (context, controller) {
      final theme = _themeFor(controller.style);
      return Scope<_DocsExampleTheme>(
        _DocsExampleTheme(theme),
        child: Theme(
          data: theme,
          // Docs embeds need a traversal policy even without a full app shell.
          child: FocusTraversalGroup(child: child),
        ),
      );
    },
  );
}

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
  ExampleInfo(
    id: 'guide.hot-reload',
    widget: 'Hot reload',
    category: 'Guide examples',
    blurb: 'Edit a running notes app and preserve its drafts.',
    cols: 64,
    rows: 15,
    interactive: true,
    builder: () => const HotReloadNotes(heading: 'Notes'),
  ),

  // ── Landing hero (not catalogued — mounted directly on the home page) ─────
  ExampleInfo(
    id: 'home.pad',
    widget: 'Fleury Pad',
    category: 'Home',
    blurb: 'A small app to edit and run on the home page.',
    cols: 34,
    rows: 11,
    interactive: true,
    builder: () => _framed(const home_pad.HelloFleury()),
  ),
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
        'A labelled status meter (CPU, memory, disk) that changes color at '
        'thresholds you set.',
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
    blurb: 'Braille line with a 2px band (the default strokeWidth is 1).',
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
    code: '''// Pass raw samples; the chart buckets them into equal-width bins.
Histogram(values: latenciesMs, bins: 7, showValues: true)''',
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
    code: '''// import 'dart:math' show sin;
class SineWavePainter extends CanvasPainter {
  @override
  void paint(CanvasContext ctx) {
    const segments = 96;
    for (var i = 0; i < segments; i++) {
      final x1 = 6.28 * i / segments;
      final x2 = 6.28 * (i + 1) / segments;
      ctx.drawLine(x1, sin(x1), x2, sin(x2));
    }
  }
}

// In build:
Canvas(
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
    blurb:
        'A task progress bar: a fraction fills it; null shows an indeterminate '
        'sweep.',
    cols: 44,
    // 1-row widget + `_framed` padding needs 3 rows; rows: 2 rendered blank.
    rows: 3,
    builder: () => _framed(const ProgressBar(value: 0.45)),
  ),
  ExampleInfo(
    id: 'digits.basic',
    widget: 'Digits',
    category: 'Charts & meters',
    blurb: 'Large block-character numerals for clocks, timers, and counters.',
    cols: 56,
    rows: 11,
    interactive: true,
    code: '''Digits('12:34', color: theme.colorScheme.primary)''',
    builder: () => _framed(const _WorldClock()),
  ),

  // ── Data & lists ─────────────────────────────────────────────────────────
  ExampleInfo(
    id: 'datatable.basic',
    widget: 'DataTable',
    category: 'Lists & data',
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
    id: 'datatable.rows',
    widget: 'Table row choice',
    category: 'Guide examples',
    blurb: 'Browse and choose rows, or select cell ranges for copying.',
    cols: 30,
    rows: 13,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: TableRows()),
  ),
  ExampleInfo(
    id: 'datatable.cells',
    widget: 'Table cell selection',
    category: 'Guide examples',
    blurb:
        'Cell ranges stay selected while the cursor moves; Enter opens a row.',
    cols: 30,
    rows: 13,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: TableCells()),
  ),
  ExampleInfo(
    id: 'tree.basic',
    widget: 'Tree',
    category: 'Lists & data',
    blurb: 'An expandable hierarchy with keyboard navigation and type-ahead.',
    cols: 40,
    rows: 9,
    interactive: true,
    builder: () => _framed(
      Tree<String>(
        semanticLabel: 'project',
        // Start with the top-level branches expanded.
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
    category: 'Text & content',
    blurb:
        'A scrollable, keyboard-navigable viewer for full Markdown documents.',
    cols: 60,
    rows: 12,
    interactive: true,
    code: """MarkdownView(
  markdown: '''
# Release notes

**Fleury 1.0** runs in the terminal and the browser.

- Arrow keys move between blocks
- Ctrl+C copies the selected block
''',
)""",
    builder: () => _framed(
      const MarkdownView(
        markdown: '''
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
''',
      ),
    ),
  ),
  ExampleInfo(
    id: 'markdowntext.basic',
    widget: 'MarkdownText',
    category: 'Text & content',
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
    category: 'Text & content',
    blurb: 'Source with line numbers, comment dimming, and copy support.',
    cols: 58,
    rows: 12,
    interactive: true,
    code: """CodeView(
  language: 'dart',
  source: '''
void main() {
  print('hello, terminal');
}
''',
)""",
    builder: () => _framed(
      CodeView(
        language: 'dart',
        source: r'''
import 'package:fleury/fleury.dart';

/// A tiny counter — the smallest interesting Fleury program.
void main() => runApp(
      KeyBindings(
        bindings: [
          KeyBinding(KeySequence.q, onTrigger: (_) => exitApp(), label: 'Quit'),
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
          Text('count: $_count'),
          const SizedBox(height: 1),
          Button(text: '+1', onPressed: _increment),
        ],
      ),
    );
  }
}
''',
      ),
    ),
  ),
  ExampleInfo(
    id: 'jsonview.basic',
    widget: 'JsonView',
    category: 'Text & content',
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
        defaultExpandedDepth: 2,
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
    code: '''TextInput(
  placeholder: 'Command',
  onChanged: (text) => updateDraft(text),
  onSubmit: (text) => runCommand(text),
)

// To read or set the text from code, pass a controller your State creates
// once and disposes:
TextInput(controller: controller, onSubmit: (text) => runCommand(text))''',
    builder: () => _framed(const _TextInputExample()),
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
    builder: () => _framed(const _TextAreaExample()),
  ),
  ExampleInfo(
    id: 'form.basic',
    widget: 'Form',
    category: 'Forms',
    blurb:
        'A composable validation and submission boundary that leaves values '
        'and layout in application code.',
    cols: 54,
    rows: 14,
    interactive: true,
    code: '''Form(
  controller: form,
  onSubmit: saveProject,
  child: Column(children: [
    FormField(
      validator: () => name.text.isEmpty ? 'Enter a name.' : null,
      child: TextInput(controller: name),
    ),
    Button(text: 'Save', onPressed: form.submit),
  ]),
)''',
    builder: () => const ProjectForm(),
  ),
  ExampleInfo(
    id: 'formfield.basic',
    widget: 'FormField',
    category: 'Forms',
    blurb:
        'One validated value with automatic control styling, semantics, and '
        'first-invalid focus.',
    // The ordinary constructor is on every other form demo; this one shows
    // FormField.builder joining two steppers into one validated value.
    cols: 40,
    rows: 12,
    interactive: true,
    builder: () => const CustomField(),
  ),
  ExampleInfo(
    id: 'formcontroller.basic',
    widget: 'FormController',
    category: 'Forms',
    blurb:
        'An optional command surface for validating, submitting, clearing '
        'errors, and observing submission progress.',
    cols: 40,
    rows: 16,
    interactive: true,
    code: '''// A State field; dispose it with the state.
final form = FormController();

// In build: rebuild on submission progress and submit from the button.
NotifierBuilder(
  notifier: form,
  builder: (context, form) => Form(
    controller: form,
    onSubmit: save, // async: the form stays busy until it completes
    child: Column(
      children: [
        FormField(
          validator: () => name.text.trim().isEmpty ? 'Enter a name.' : null,
          child: TextInput(controller: name),
        ),
        Button(
          text: form.isBusy ? 'Saving…' : 'Save',
          onPressed: form.isBusy ? null : form.submit,
        ),
      ],
    ),
  ),
)''',
    builder: () => const SaveProject(),
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
  text: 'Save',
  variant: ButtonVariant.primary,
  onPressed: () => save(),
)''',
    builder: () => _framed(const _ButtonExample()),
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
    builder: () => _framed(const _CheckboxExample()),
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
    builder: () => _framed(const _ToggleExample()),
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
    builder: () => _framed(const _SwitchExample()),
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
    builder: () => _framed(const _RadioExample()),
  ),
  ExampleInfo(
    id: 'radiogroup.basic',
    widget: 'RadioGroup',
    category: 'Inputs & controls',
    blurb:
        'A group of radio choices: the arrow keys move the selection, and each '
        'option is its own Tab stop.',
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
    builder: () => _framed(const _RadioGroupExample()),
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
    builder: () => _framed(const _SelectExample()),
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
    builder: () => _framed(const _MultiSelectExample()),
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
    builder: () => _framed(const _RangeSliderExample()),
  ),
  ExampleInfo(
    id: 'stepper.basic',
    widget: 'Stepper',
    category: 'Inputs & controls',
    blurb:
        'A compact number spinner: ↑/↓ or +/− step the value, PageUp/PageDown '
        'take large steps, and typed digits set it directly.',
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
    builder: () => _framed(const _StepperExample()),
  ),
  ExampleInfo(
    id: 'numberinput.basic',
    widget: 'NumberInput',
    category: 'Inputs & controls',
    blurb:
        'A numeric text field that rejects non-numeric keys and clamps to '
        'min/max when you press Enter.',
    cols: 36,
    rows: 3,
    interactive: true,
    code: '''NumberInput(
  initialValue: 42,
  min: 0,
  max: 100,
  // null while the field is empty or mid-edit ("-", "1.").
  onChanged: (value) => setState(() => count = value),
)''',
    builder: () =>
        _framed(const NumberInput(initialValue: 42, min: 0, max: 100)),
  ),
  ExampleInfo(
    id: 'passwordinput.basic',
    widget: 'PasswordInput',
    category: 'Inputs & controls',
    blurb: 'A masked text field for secrets; Ctrl+R shows or hides the text.',
    cols: 40,
    rows: 3,
    interactive: true,
    code: '''PasswordInput(
  controller: controller,
  semanticLabel: 'Password',
  // Ctrl+R shows or hides the value while the field has focus.
)''',
    // Seeded with a value so the demo shows the obscuring dots (the widget's
    // point) rather than a bare "Password" placeholder.
    builder: () => _framed(const _PasswordInputExample()),
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
    builder: () => _framed(const _AutocompleteExample()),
  ),
  ExampleInfo(
    id: 'filebrowser.basic',
    widget: 'FileBrowser',
    category: 'Inputs & controls',
    blurb:
        'A keyboard-driven directory browser with filtering, copy, and '
        'semantic rows; reads the local disk or any FileSource.',
    cols: 48,
    rows: 13,
    interactive: true,
    code: '''// In a terminal, FileBrowser reads the local disk:
FileBrowser(
  initialDirectory: Directory.current.path,
  onActivate: (entry) => openFile(entry.path),
)

// In the browser there is no disk to list, so pass a source, as this demo
// does. MemoryFileSource holds a fixed tree; implement FileSource to list
// data your app already has.
FileBrowser(
  source: MemoryFileSource([
    '/my_app/lib/app.dart',
    '/my_app/pubspec.yaml',
    '/my_app/README.md',
  ]),
  initialDirectory: '/my_app',
  onActivate: (entry) => openFile(entry.path),
)''',
    builder: () => _framed(const live.FileBrowserPreview()),
  ),
  ExampleInfo(
    id: 'filepicker.basic',
    widget: 'FilePicker',
    category: 'Inputs & controls',
    blurb:
        'A one-directory-at-a-time picker: arrows move, Enter opens a folder '
        'or picks a file.',
    cols: 48,
    rows: 13,
    interactive: true,
    code: '''FilePicker(
  initialDirectory: Directory.current.path,
  filter: (entry) => entry.isDirectory || entry.name.endsWith('.dart'),
  onSelect: (file) => openFile(file.path),
)

// In the browser, pass a source, such as the MemoryFileSource this demo uses:
// FilePicker(source: projectFiles, initialDirectory: '/my_app', ...)''',
    builder: () => _framed(const live.FilePickerPreview()),
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
    builder: () => _framed(const _ColorPickerExample()),
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
    builder: () => _framed(const _DatePickerExample()),
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
    code: '''Tabs(
  tabs: const <TabItem>[
    TabItem(label: 'Overview', content: Text('Project at a glance.')),
    TabItem(label: 'Logs', content: Text('› build finished in 1.8s')),
    TabItem(label: 'Settings', content: Text('Theme · keybindings · …')),
  ],
)''',
    builder: () => _framed(
      Tabs(
        tabs: <TabItem>[
          TabItem(
            label: 'Overview',
            content: const Padding(
              padding: EdgeInsets.all(1),
              child: Text('Project at a glance.'),
            ),
          ),
          TabItem(
            label: 'Logs',
            content: const Padding(
              padding: EdgeInsets.all(1),
              child: Text('› build finished in 1.8s'),
            ),
          ),
          TabItem(
            label: 'Settings',
            content: const Padding(
              padding: EdgeInsets.all(1),
              child: Text('Theme · keybindings · …'),
            ),
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
    blurb: 'A hint that appears below a widget while focus is inside it.',
    cols: 40,
    // A TUI tooltip triggers on focus (no hover), so the child is an autofocused
    // Button — the hint renders beneath it on mount instead of an inert label.
    rows: 5,
    interactive: true,
    builder: () => _framed(
      Tooltip(
        message: 'Saves the current file',
        child: Button(text: 'Save', autofocus: true, onPressed: () {}),
      ),
    ),
  ),
  ExampleInfo(
    id: 'toaster.basic',
    widget: 'Toaster',
    category: 'Navigation & overlays',
    blurb:
        'Transient notifications in a screen corner, raised from anywhere '
        'below the host.',
    cols: 48,
    rows: 10,
    interactive: true,
    code: '''// Wrap your app once:
Toaster(child: app)

// …then from anywhere below it:
Toaster.show(context, 'Saved', severity: ToastSeverity.success);''',
    builder: () => _framed(const live.ToasterPreview()),
  ),
  ExampleInfo(
    id: 'container.filled',
    widget: 'Container',
    category: 'Layout',
    blurb:
        'One visual region: size, padding, margin, background, border, and '
        'alignment. Container.filled and Container.framed apply the theme\'s '
        'surface and border.',
    cols: 44,
    rows: 11,
    interactive: true,
    // Toggling is the demo: while the framed layer is open the wall behind
    // is covered (it owns every cell it draws over), and closing restores
    // that content untouched — it layers, it doesn't overwrite.
    builder: () => _framed(const _ContainerFillExample()),
  ),
  ExampleInfo(
    id: 'dialog.basic',
    widget: 'Dialog',
    category: 'Navigation & overlays',
    blurb: 'A bordered, titled modal surface.',
    cols: 44,
    rows: 10,
    code: '''// Present it over the current screen and await the result:
final confirmed = await context.present<bool>(const DeleteDialog());

// DeleteDialog's build returns the frame and pops with a result:
Dialog(
  title: 'Confirm',
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Delete 3 files? This cannot be undone.'),
      Row(
        children: [
          Button(text: 'Cancel', onPressed: () => context.pop(false)),
          const SizedBox(width: 1),
          Button(text: 'Delete', onPressed: () => context.pop(true)),
        ],
      ),
    ],
  ),
)''',
    builder: () => _framed(
      Dialog(
        title: 'Confirm',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Delete 3 files? This cannot be undone.'),
            Row(
              children: <Widget>[
                Button(text: 'Cancel', autofocus: true, onPressed: () {}),
                const SizedBox(width: 1),
                Button(text: 'Delete', onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
  ExampleInfo(
    id: 'keyhintbar.basic',
    widget: 'KeyHintBar',
    category: 'Input handling & focus',
    blurb: 'A bar listing the keyboard shortcuts active for the current focus.',
    cols: 52,
    rows: 6,
    code: '''KeyBindings(
  bindings: <KeyBinding>[
    KeyBinding(KeyCode.char('s'), label: 'Save', onTrigger: (_) => save()),
    KeyBinding(KeyCode.char('q'), label: 'Quit', onTrigger: (_) => quit()),
  ],
  child: Column(
    children: [
      // The bar lists the bindings above whatever holds focus.
      Expanded(child: Focus(autofocus: true, child: editor)),
      const KeyHintBar(),
    ],
  ),
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
    category: 'Input handling & focus',
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
    id: 'commandbutton.basic',
    widget: 'CommandButton',
    category: 'Inputs & controls',
    blurb:
        'A button that resolves its label, availability, and action from an '
        'application command.',
    cols: 42,
    rows: 5,
    interactive: true,
    code: '''CommandScope(
  commands: [
    AppCommand(
      id: const CommandId('project.runTests'),
      title: 'Run tests',
      run: (_) => runTests(),
    ),
  ],
  child: const CommandButton(
    command: CommandId('project.runTests'),
    variant: ButtonVariant.primary,
  ),
)''',
    builder: () => _framed(
      CommandScope(
        commands: <AppCommand>[
          AppCommand(
            id: const CommandId('project.runTests'),
            title: 'Run tests',
            run: (_) {},
          ),
        ],
        child: const CommandButton(
          command: CommandId('project.runTests'),
          variant: ButtonVariant.primary,
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
    code:
        '''// Present it over the app; choosing a command closes it and runs it.
context.present<void>(
  CommandPalette(
    commands: [
      CommandPaletteItem(
        label: 'Open file…',
        shortcut: 'Ctrl-P',
        onInvoke: openFile,
      ),
      CommandPaletteItem(
        label: 'Toggle theme',
        category: 'View',
        onInvoke: toggleTheme,
      ),
      CommandPaletteItem(
        label: 'Run tests',
        shortcut: 'Ctrl-T',
        onInvoke: runTests,
      ),
    ],
  ),
);

// Or list the commands the app registered as AppCommands:
CommandPalette.open(context);''',
    builder: () => _framed(
      CommandPalette(
        commands: <CommandPaletteItem>[
          CommandPaletteItem(
            label: 'Open file…',
            shortcut: 'Ctrl-P',
            onInvoke: () {},
          ),
          CommandPaletteItem(
            label: 'Toggle theme',
            category: 'View',
            onInvoke: () {},
          ),
          CommandPaletteItem(
            label: 'Run tests',
            shortcut: 'Ctrl-T',
            onInvoke: () {},
          ),
          CommandPaletteItem(
            label: 'Git: commit',
            category: 'Git',
            onInvoke: () {},
          ),
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
    category: 'Lists & data',
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
    category: 'Lists & data',
    blurb: 'A hierarchical, expandable table; ←/→ collapse and expand rows.',
    cols: 48,
    rows: 9,
    interactive: true,
    builder: () => _framed(
      TreeTable<String>(
        treeColumnId: 'name',
        // Start with the lib branch expanded.
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
    category: 'Charts & meters',
    blurb: 'A GitHub-style contribution grid keyed by date.',
    cols: 56,
    rows: 9,
    builder: () => _framed(
      CalendarHeatmap(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 3, 31),
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
    blurb:
        'A unified diff with styled additions and deletions, hunk headers, and '
        'an old/new line-number gutter.',
    cols: 56,
    rows: 9,
    interactive: true,
    code: """DiffView(
  diff: '''
@@ -1,3 +1,3 @@
 void main() {
-  print('hi');
+  print('hello');
 }
''',
)""",
    builder: () => _framed(
      DiffView(
        diff: '''
@@ -1,4 +1,4 @@
 void main() {
-  final greeting = 'hi';
-  print(greeting);
+  final greeting = 'hello';
+  print(greeting.toUpperCase());
 }
''',
      ),
    ),
  ),
  ExampleInfo(
    id: 'patchreview.basic',
    widget: 'PatchReview',
    category: 'Agent surfaces',
    blurb: 'A file-by-file patch review surface over a diff.',
    cols: 60,
    rows: 14,
    interactive: true,
    code: """PatchReview(
  diff: '''
diff --git a/bin/app.dart b/bin/app.dart
--- a/bin/app.dart
+++ b/bin/app.dart
@@ -1,3 +1,3 @@
 void main() {
-  print('hi');
+  print('hello');
 }
''',
  onSelectFile: (result) => openFile(result.file.path),
)""",
    builder: () => _framed(
      PatchReview(
        autofocus: true,
        diffHeight: 8,
        diff: '''
diff --git a/bin/app.dart b/bin/app.dart
--- a/bin/app.dart
+++ b/bin/app.dart
@@ -1,4 +1,4 @@
 void main() {
-  final greeting = 'hi';
-  print(greeting);
+  final greeting = 'hello';
+  print(greeting.toUpperCase());
 }
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1 +1,3 @@
 # app
+
+Prints a greeting.
''',
      ),
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
  ExampleInfo(
    id: 'logregion.basic',
    widget: 'LogRegion',
    category: 'Agent surfaces',
    blurb:
        'A tail-following log view with severity styling, filtering, and '
        'copy.',
    cols: 58,
    rows: 12,
    interactive: true,
    code: '''LogRegion(
  entries: const [
    LogEntry(id: 1, message: 'Starting deploy', source: 'deploy'),
    LogEntry(
      id: 2,
      message: 'Health check failed: 503 on /ready',
      severity: LogSeverity.error,
      source: 'probe',
    ),
  ],
  // Narrow what's shown without changing the entries:
  filter: const LogRegionFilterDescriptor(severities: {LogSeverity.error}),
)''',
    builder: () => _framed(const _LogRegionExample()),
  ),
  ExampleInfo(
    id: 'terminaloutputregion.basic',
    widget: 'TerminalOutputRegion',
    category: 'Agent surfaces',
    blurb:
        'Captured stdout and stderr as a structured, filterable log; stderr '
        'lines read as errors.',
    cols: 64,
    rows: 12,
    interactive: true,
    code:
        '''// In a terminal app, runApp captures stdout and stderr into the LogBuffer
// this widget reads by default. Anywhere else, including the browser, feed
// one yourself:
final buffer = LogBuffer(capacity: 500)
  ..add(const LogLine(r'\$ dart test', LogSource.stdout))
  ..add(const LogLine('warning: unused import', LogSource.stderr));

TerminalOutputRegion(buffer: buffer)''',
    builder: () => _framed(const _TerminalOutputExample()),
  ),
  ExampleInfo(
    id: 'workflowsnapshot.basic',
    widget: 'WorkflowSnapshot',
    category: 'Agent surfaces',
    blurb:
        'A data model that bundles a workflow\'s tasks, tool calls, and logs, '
        'and derives its health.',
    cols: 48,
    rows: 10,
    interactive: true,
    code: '''final snapshot = WorkflowSnapshot(
  title: 'Release',
  tasks: const [
    TaskGraphNode(id: 'tests', title: 'Run tests', status: TaskGraphStatus.succeeded),
    TaskGraphNode(id: 'build', title: 'Build image', status: TaskGraphStatus.running),
  ],
);

// Derived, safe aggregate state: health, counts, semantic state.
final summary = snapshot.summary;
Text('\${summary.health.name}: \${summary.activeTaskCount} of \${summary.taskCount} tasks remaining')''',
    builder: () => _framed(const _WorkflowSnapshotExample()),
  ),

  ExampleInfo(
    id: 'terminal-modes.fullscreen',
    widget: 'TerminalMode',
    category: 'Guide examples',
    blurb:
        'The setup form fills a simulated alternate screen, then restores the '
        'shell context on completion. Browser illustration of native behavior.',
    cols: 84,
    rows: 29,
    interactive: true,
    builder: () => const InlineSetupPreview(fullScreen: true),
  ),

  // ── Showcases (full apps; rendered on the Showcases page, not as widgets) ──
  ExampleInfo(
    id: 'showcase.inline',
    widget: 'Interactive CLI commands',
    category: 'Showcases',
    blurb:
        'A project setup command: choose a template, review the configuration, '
        'and finish back at the prompt. The same form runs inline in a native terminal.',
    cols: 84,
    rows: 29,
    interactive: true,
    builder: () => const InlineSetupPreview(),
  ),
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
        'A coding-agent streaming session: prose, tool cards, a live todo '
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
    id: 'showcase.commands',
    widget: 'Command editor',
    category: 'Showcases',
    blurb:
        'Open a live command palette over an editor whose actions stay in sync '
        'with its toolbar, shortcuts, semantics, and tests.',
    cols: 82,
    rows: 28,
    interactive: true,
    builder: () => const CommandWorkbenchApp(openPaletteInitially: true),
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
    id: 'showcase.forms',
    widget: 'Deployment form',
    category: 'Showcases',
    blurb:
        'A multi-screen service deployment flow with app-owned values, '
        'automatic validation, server errors, retained state, and async '
        'submission.',
    cols: 84,
    rows: 30,
    interactive: true,
    builder: () => const FormsShowcaseApp(),
  ),
  ExampleInfo(
    id: 'showcase.state',
    widget: 'Shared state',
    category: 'Showcases',
    blurb:
        'Local fields, a shared project scope, and an application-owned cart, '
        'with builder widgets and context readers updating together.',
    cols: 80,
    rows: 28,
    interactive: true,
    builder: () => const StateManagementShowcaseApp(),
  ),
  ExampleInfo(
    id: 'agents.release-checklist',
    widget: 'Agent-driving release checklist',
    category: 'Guide examples',
    blurb:
        'Ordinary text, checkbox, and button semantics drive one complete '
        'release workflow by hand, in tests, or through MCP.',
    cols: 46,
    rows: 15,
    interactive: true,
    builder: () => const AgentGuideApp(),
  ),
  ExampleInfo(
    id: 'showcase.themes',
    widget: 'Theme studio',
    category: 'Showcases',
    blurb:
        'A live gallery for every bundled community theme, plus a custom '
        'editor that selects one semantic role at a time, then changes its '
        'color, brightness, or borders with live widget-state feedback.',
    cols: 108,
    rows: 34,
    interactive: true,
    builder: () => const ThemingShowcaseApp(),
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
    widget: 'Form',
    category: 'Guide examples',
    blurb:
        'A project form that validates on submit, keeps errors next to their '
        'fields, and confirms a successful submission.',
    cols: 40,
    rows: 18,
    interactive: true,
    builder: () => const ProjectForm(),
  ),
  ExampleInfo(
    id: 'forms.save',
    widget: 'Form',
    category: 'Guide examples',
    blurb: 'Save asynchronously, recover from service errors, and retry.',
    cols: 40,
    rows: 16,
    interactive: true,
    builder: () => const SaveProject(),
  ),
  ExampleInfo(
    id: 'forms.related',
    widget: 'Form',
    category: 'Guide examples',
    blurb: 'Validate related values without moving keyboard focus.',
    cols: 40,
    rows: 18,
    interactive: true,
    builder: () => const RelatedFields(),
  ),
  ExampleInfo(
    id: 'forms.custom',
    widget: 'FormField',
    category: 'Guide examples',
    blurb: 'Integrate two controls as one validated range.',
    cols: 40,
    rows: 12,
    interactive: true,
    builder: () => const CustomField(),
  ),
  ExampleInfo(
    id: 'loading.snapshot',
    widget: 'FutureBuilder',
    category: 'Guide examples',
    blurb: 'Switch among the user-visible states of one asynchronous result.',
    cols: 48,
    rows: 12,
    interactive: true,
    builder: () => const _SnapshotLoadingTour(),
  ),
  ExampleInfo(
    id: 'loading.image',
    widget: 'Image',
    category: 'Guide examples',
    blurb:
        'Fetch, decode, and render a real photo with a reloadable '
        'FutureBuilder.',
    cols: 54,
    rows: 16,
    interactive: true,
    builder: () => _framed(const _NetworkImageLoadingTour()),
  ),
  ExampleInfo(
    id: 'loading.stream',
    widget: 'StreamBuilder',
    category: 'Guide examples',
    blurb: 'Receive a star map one packet at a time from a controlled stream.',
    cols: 48,
    rows: 14,
    interactive: true,
    builder: () => const _StreamLoadingTour(),
  ),
  ExampleInfo(
    id: 'commands.overview',
    widget: 'AppCommand',
    category: 'Guide examples',
    blurb:
        'Use one save command through a button, Ctrl+S, the command palette, '
        'semantics, and a stable programmatic ID.',
    cols: 60,
    rows: 13,
    interactive: true,
    builder: () => const CommandIntroApp(),
  ),
  ExampleInfo(
    id: 'animation.state',
    widget: 'Animation',
    category: 'Guide examples',
    blurb:
        'Launch an orbital courier whose route, color, progress, and status '
        'all follow one animated value.',
    cols: 60,
    rows: 15,
    interactive: true,
    builder: () => const _OrbitalCourier(),
  ),
  ExampleInfo(
    id: 'animation.manual',
    widget: 'Animation',
    category: 'Guide examples',
    blurb:
        'Own, chain, await, and interrupt one animated value while building '
        'a route.',
    cols: 48,
    rows: 11,
    interactive: true,
    builder: () => _framed(const _ManualRoute()),
  ),
  ExampleInfo(
    id: 'animation.progress',
    widget: 'AnimationBuilder',
    category: 'Guide examples',
    blurb:
        'Move a package between two destinations and inspect the double value '
        'that AnimationBuilder supplies.',
    cols: 48,
    rows: 12,
    interactive: true,
    builder: () => _framed(const _PackageRoute()),
  ),
  ExampleInfo(
    id: 'animation.timing',
    widget: 'AnimationBuilder',
    category: 'Guide examples',
    blurb:
        'Compare a status panel whose width and accent share timing with one '
        'whose properties settle independently.',
    cols: 54,
    rows: 15,
    interactive: true,
    builder: () => _framed(const _TimingComparison()),
  ),
  ExampleInfo(
    id: 'animation.effects',
    widget: 'Animate',
    category: 'Guide examples',
    blurb: 'Mount a connection status with a chained fade-and-slide entrance.',
    cols: 48,
    rows: 10,
    interactive: true,
    builder: () => _framed(const _ConnectionStatus()),
  ),
  ExampleInfo(
    id: 'animation.trigger',
    widget: 'Animate',
    category: 'Guide examples',
    blurb: 'Animate a real form submission for both error and success.',
    cols: 48,
    rows: 14,
    interactive: true,
    builder: () => _framed(const _PilotValidation()),
  ),
  ExampleInfo(
    id: 'animation.presence',
    widget: 'AnimatedVisibility',
    category: 'Guide examples',
    blurb: 'Choose and compare Fleury entrance and exit effects.',
    cols: 58,
    rows: 19,
    interactive: true,
    builder: () => _framed(const _EffectPicker()),
  ),
  ExampleInfo(
    id: 'animation.frames',
    widget: 'FrameBuilder',
    category: 'Guide examples',
    blurb: 'Cycle through the authored frames of a packet transfer.',
    cols: 48,
    rows: 12,
    interactive: true,
    builder: () => _framed(const _PacketTransfer()),
  ),
  ExampleInfo(
    id: 'animation.ticker',
    widget: 'Ticker',
    category: 'Guide examples',
    blurb: 'Advance a small simulation from elapsed time on each tick.',
    cols: 48,
    rows: 11,
    interactive: true,
    builder: () => _framed(const _TickerSimulation()),
  ),
  ExampleInfo(
    id: 'flutter.counter',
    widget: 'Counter',
    category: 'Guide examples',
    blurb: 'The Flutter counter, ported: same widgets and setState, in cells.',
    cols: 34,
    rows: 7,
    interactive: true,
    builder: () => _framed(const flutter_map.Counter()),
  ),
  ExampleInfo(
    id: 'flutter.cells',
    widget: 'AspectRatio',
    category: 'Guide examples',
    blurb: 'Cells are taller than wide, so a square-looking box is 2:1.',
    cols: 28,
    rows: 14,
    builder: () => _framed(const flutter_map.CellBoxes()),
  ),
  ExampleInfo(
    id: 'flutter.keys',
    widget: 'KeyBindings',
    category: 'Guide examples',
    blurb:
        'Ctrl+S and Esc bindings around a focused field, listed by a hint bar.',
    cols: 44,
    rows: 8,
    interactive: true,
    builder: () => _framed(const flutter_map.EditorShortcuts()),
  ),
  ExampleInfo(
    id: 'flutter.animation',
    widget: 'AnimationBuilder',
    category: 'Guide examples',
    blurb: 'AnimationBuilder eases toward a new target when state changes.',
    cols: 36,
    rows: 7,
    interactive: true,
    builder: () => _framed(const flutter_map.SelectionMeter()),
  ),
  ExampleInfo(
    id: 'flutter.routes',
    widget: 'Navigator',
    category: 'Guide examples',
    blurb: 'Push a screen widget, pop it, or pop back to a screen type.',
    cols: 38,
    rows: 8,
    interactive: true,
    builder: () => _framed(
      Navigator(
        transition: RouteTransition.none,
        home: const flutter_map.HomeScreen(),
      ),
    ),
  ),
  ExampleInfo(
    id: 'concepts.clock',
    widget: 'State',
    category: 'Guide examples',
    blurb:
        'A clock that starts its timer in initState and cancels it in dispose.',
    cols: 25,
    rows: 3,
    builder: () => _framed(const concepts.Clock()),
  ),
  ExampleInfo(
    id: 'state.local-counter',
    widget: 'State',
    category: 'Guide examples',
    blurb: 'A counter updates its own widget subtree with setState.',
    cols: 34,
    rows: 9,
    interactive: true,
    builder: () => _framed(const state.LocalCounter()),
  ),
  ExampleInfo(
    id: 'state.project-scope',
    widget: 'Scope',
    category: 'Guide examples',
    blurb:
        'Two const descendants read one shared project, one with ScopeBuilder '
        'and one with context.scope.',
    cols: 38,
    rows: 9,
    interactive: true,
    builder: () => _framed(const state.ProjectScreen()),
  ),
  ExampleInfo(
    id: 'state.shop',
    widget: 'Scope.create',
    category: 'Guide examples',
    blurb:
        'A scope creates and owns a cart; a badge and two buttons elsewhere '
        'in the subtree share it.',
    cols: 38,
    rows: 9,
    interactive: true,
    builder: () => _framed(const state.Shop()),
  ),
  ExampleInfo(
    id: 'state.cart-notifier',
    widget: 'NotifierBuilder',
    category: 'Guide examples',
    blurb: 'Two readers listen to the same cart and update together.',
    cols: 38,
    rows: 9,
    interactive: true,
    builder: () => _framed(const state.CartDemo()),
  ),
  ExampleInfo(
    id: 'input.editing',
    widget: 'Pointer editing',
    category: 'Guide examples',
    blurb: 'Click, drag-select, and move between ordinary text fields.',
    cols: 38,
    rows: 10,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: input.ContactFields()),
  ),
  ExampleInfo(
    id: 'input.actions',
    widget: 'Button feedback',
    category: 'Guide examples',
    blurb: 'One button opens and closes a note by mouse or keyboard.',
    cols: 38,
    rows: 11,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: input.FileActions()),
  ),
  ExampleInfo(
    id: 'input.press',
    widget: 'Press and cancel',
    category: 'Guide examples',
    blurb:
        'Observe a press, move to another cell to cancel, or right-click for details.',
    cols: 38,
    rows: 19,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: input.PressTile()),
  ),
  ExampleInfo(
    id: 'input.selection',
    widget: 'Select a note',
    category: 'Guide examples',
    blurb: 'Select across text widgets and copy the note.',
    cols: 38,
    rows: 12,
    interactive: true,
    builder: () => const Padding(
      padding: EdgeInsets.all(1),
      child: input.SelectableNote(),
    ),
  ),
  ExampleInfo(
    id: 'input.splitter',
    widget: 'Pointer splitter',
    category: 'Guide examples',
    blurb: 'Drag a captured handle or resize it with the arrow keys.',
    cols: 38,
    rows: 10,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: input.SplitPane()),
  ),
  ExampleInfo(
    id: 'input.nesting',
    widget: 'Nested input',
    category: 'Guide examples',
    blurb: 'A child button acts while its surrounding row stays hovered.',
    cols: 38,
    rows: 9,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: input.NestedRow()),
  ),
  ExampleInfo(
    id: 'input.scrolling',
    widget: 'Nested scroll panes',
    category: 'Guide examples',
    blurb: 'Wheel input moves to an ancestor at the edge, unless contained.',
    cols: 38,
    rows: 14,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: input.ScrollPanes()),
  ),
  ExampleInfo(
    id: 'testing.counter',
    widget: 'Testing counter',
    category: 'Guide examples',
    blurb: 'The counter exercised by the first widget test.',
    cols: 32,
    rows: 5,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: testing.Counter()),
  ),
  ExampleInfo(
    id: 'testing.preferences',
    widget: 'Testing preferences',
    category: 'Guide examples',
    blurb: 'Find one of two forms, fill a named field, and check an option.',
    cols: 32,
    rows: 11,
    interactive: true,
    builder: () => Padding(
      padding: const EdgeInsets.all(1),
      child: testing.preferencesPair(),
    ),
  ),
  ExampleInfo(
    id: 'testing.save',
    widget: 'Testing an async save',
    category: 'Guide examples',
    blurb: 'A small save button shows pending and completed work.',
    cols: 32,
    rows: 5,
    interactive: true,
    builder: () => const Padding(
      padding: EdgeInsets.all(1),
      child: testing.TestingSaveDemo(),
    ),
  ),
  ExampleInfo(
    id: 'testing.animation',
    widget: 'Testing animation time',
    category: 'Guide examples',
    blurb: 'An upload meter animates between zero and one hundred percent.',
    cols: 32,
    rows: 6,
    interactive: true,
    builder: () => const Padding(
      padding: EdgeInsets.all(1),
      child: testing.AnimatedUpload(),
    ),
  ),
  ExampleInfo(
    id: 'testing.editor',
    widget: 'Testing editor',
    category: 'Guide examples',
    blurb: 'Edit, save, recover from an offline save, and confirm a discard.',
    cols: 58,
    rows: 16,
    interactive: true,
    builder: () => const Navigator(home: testing.TestingEditorDemo()),
  ),
  ExampleInfo(
    id: 'testing.publish',
    widget: 'Testing async control',
    category: 'Guide examples',
    blurb: 'A custom semantic handler returns its publishing future.',
    cols: 32,
    rows: 6,
    interactive: true,
    builder: () => const testing.TestingPublishDemo(),
  ),
  ExampleInfo(
    id: 'lists.files',
    widget: 'File list',
    category: 'Guide examples',
    blurb: 'Focus with arrows; select with click or Enter.',
    cols: 34,
    rows: 9,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: lists.FileList()),
  ),
  ExampleInfo(
    id: 'lists.tasks',
    widget: 'Task browser',
    category: 'Guide examples',
    blurb: 'Browse, select, or scroll a thousand tasks with separate outcomes.',
    cols: 40,
    rows: 22,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: lists.TaskBrowser()),
  ),
  ExampleInfo(
    id: 'lists.reorder',
    widget: 'Reorder tasks',
    category: 'Guide examples',
    blurb: 'Reverse a collection while keeping the current task highlighted.',
    cols: 38,
    rows: 11,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: lists.ReorderTasks()),
  ),
  ExampleInfo(
    id: 'lists.document',
    widget: 'Scroll edges',
    category: 'Guide examples',
    blurb:
        'See the top and bottom, then let an arrow leave or stay in the pane.',
    cols: 40,
    rows: 18,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: lists.ScrollEdges()),
  ),
  ExampleInfo(
    id: 'lists.horizontal',
    widget: 'Horizontal list',
    category: 'Guide examples',
    blurb: 'Browse with left/right and select with Enter or a click.',
    cols: 40,
    rows: 8,
    interactive: true,
    builder: () => const Padding(
      padding: EdgeInsets.all(1),
      child: lists.HorizontalList(),
    ),
  ),
  ExampleInfo(
    id: 'lists.wide-content',
    widget: 'Horizontal content',
    category: 'Guide examples',
    blurb: 'Scroll a wide report without wrapping its lines.',
    cols: 40,
    rows: 10,
    interactive: true,
    builder: () => const Padding(
      padding: EdgeInsets.all(1),
      child: lists.HorizontalContent(),
    ),
  ),
  ExampleInfo(
    id: 'lists.log',
    widget: 'Build log',
    category: 'Guide examples',
    blurb: 'Follow output, pause to read older entries, then catch up.',
    cols: 46,
    rows: 14,
    interactive: true,
    builder: () =>
        const Padding(padding: EdgeInsets.all(1), child: lists.BuildLog()),
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
        'A stack of screens: push screens, present dialogs, and pop them with '
        'typed results.',
    cols: 58,
    rows: 14,
    interactive: true,
    code:
        '''// FleuryApp(home: ...) creates the root navigator. Nest another Navigator
// to keep a flow inside one pane:
Navigator(home: const SetupStep())

// From any screen below a navigator:
final result = await context.push<String>(const DetailsScreen());
final confirmed = await context.present<bool>(const ConfirmDialog());
context.pop('done'); // completes the push that opened this screen''',
    builder: () => _framed(
      Navigator(transition: RouteTransition.none, home: const _HomeScreen()),
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
    builder: () => _framed(
      Navigator(
        transition: RouteTransition.none,
        home: const _DialogPlacement(),
      ),
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
    builder: () => _framed(
      Navigator(transition: RouteTransition.none, home: const _DraftsScreen()),
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
    builder: () => _framed(
      Navigator(
        transition: RouteTransition.none,
        home: const _ProjectsScreen(),
      ),
    ),
  ),
  ExampleInfo(
    id: 'focus.explorer',
    widget: 'Focus',
    category: 'Input handling & focus',
    blurb:
        'Makes a custom widget focusable, so it receives keys and joins Tab '
        'and arrow traversal.',
    cols: 70,
    rows: 18,
    interactive: true,
    code:
        '''// A custom control becomes one focus stop. Handle its keys outside the
// Focus: keys travel from the focused node up through its ancestors.
KeyBindings(
  bindings: [
    KeyBinding(KeySequence.enter, label: 'Play', onTrigger: (_) => play()),
  ],
  child: const Focus(child: TrackRow()),
)

// In TrackRow's build, reading Focus.of rebuilds it when focus changes:
final focused = Focus.of(context).hasFocus;
return Text(focused ? '▸ Track 1' : '  Track 1');''',
    builder: () => const Navigator(home: _FocusExplorerTour()),
  ),
  ExampleInfo(
    id: 'focusnode.programmatic',
    widget: 'FocusNode',
    category: 'Input handling & focus',
    blurb:
        'A focus target you own: move focus to it from code, check whether it '
        'has focus, and dispose it with its state.',
    cols: 60,
    rows: 10,
    interactive: true,
    code: '''class _WorkspaceState extends State<Workspace> {
  final _searchFocus = FocusNode(debugLabel: 'search');

  void focusSearch() => _searchFocus.requestFocus();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Button(text: 'Focus search', onPressed: focusSearch),
      SizedBox(
        width: 24,
        child: TextInput(focusNode: _searchFocus, onChanged: search),
      ),
    ],
  );

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }
}''',
    builder: () => _framed(const _ProgrammaticFocusTour()),
  ),
  ExampleInfo(
    id: 'fleuryapp.basic',
    widget: 'FleuryApp',
    category: 'App & theming',
    blurb:
        'The app shell: app-wide commands with shortcuts, status items, and '
        'a root navigator for its screens.',
    cols: 44,
    rows: 8,
    interactive: true,
    code: '''FleuryApp(
  title: 'Inbox',
  commands: [
    AppCommand(
      id: const CommandId('inbox.archive'),
      title: 'Archive message',
      shortcuts: [KeySequence.a],
      enabled: (_) => unread > 0,
      run: (_) => setState(() => unread -= 1),
    ),
  ],
  status: (app) => [StatusItem.text('Unread', value: '\$unread')],
  home: const InboxScreen(),
)''',
    builder: () => _framed(const _FleuryAppExample()),
  ),
  ExampleInfo(
    id: 'focusscope.basic',
    widget: 'FocusScope',
    category: 'Input handling & focus',
    blurb:
        'A focus boundary that remembers its last focused control and can '
        'trap focus inside it.',
    cols: 44,
    rows: 8,
    interactive: true,
    code:
        '''// Keep focus inside a custom overlay: Tab, clicks, and focus requests
// can't move it out.
FocusScope(
  trapFocus: true,
  // Stop unmatched keys from reaching the app behind it too.
  child: KeyBindings(modal: true, bindings: const [], child: child),
)''',
    builder: () => _framed(const _FocusScopeExample()),
  ),
  ExampleInfo(
    id: 'focusdetector.basic',
    widget: 'FocusDetector',
    category: 'Input handling & focus',
    blurb:
        'Reports when keyboard focus enters or leaves a subtree, the signal '
        'for styling the active pane.',
    cols: 62,
    rows: 14,
    interactive: true,
    code:
        '''// Panel already accents itself while focus is inside it. Use a detector
// when your own chrome or state should follow the active pane.
FocusDetector(
  onFocusChange: (hasFocus) => setState(() => editorActive = hasFocus),
  child: Container(
    border: BoxBorder(
      style: theme.borderStyle,
      cellStyle: editorActive
          ? CellStyle(foreground: theme.colorScheme.primary)
          : theme.mutedStyle,
    ),
    child: editor,
  ),
)''',
    builder: () => _framed(const _FocusDetectorTour()),
  ),
  ExampleInfo(
    id: 'keybindings.basic',
    widget: 'KeyBindings',
    category: 'Input handling & focus',
    blurb:
        'Declares keyboard shortcuts and multi-key sequences for a subtree; '
        'the nearest match wins and its label feeds shortcut hints.',
    cols: 64,
    rows: 14,
    interactive: true,
    code: '''KeyBindings(
  bindings: [
    KeyBinding(.ctrl.s, label: 'Bookmark', onTrigger: (_) => toggleBookmark()),
    // Movement keys opt in to key repeat, so holding j keeps moving.
    KeyBinding(
      .j,
      aliases: [.down],
      label: 'Down',
      includeRepeats: true,
      onTrigger: (_) => move(1),
    ),
    KeyBinding(
      .k,
      aliases: [.up],
      label: 'Up',
      includeRepeats: true,
      onTrigger: (_) => move(-1),
    ),
    KeyBinding(.g.g, label: 'Top', onTrigger: (_) => jumpToTop()),
    KeyBinding(.space.c, label: 'Clear ★', onTrigger: (_) => clearBookmarks()),
  ],
  child: Focus(
    autofocus: true,
    child: Column(
      children: [
        Expanded(child: list),
        const KeyHintBar(), // lists the labelled bindings above
      ],
    ),
  ),
)''',
    builder: () => const _KeyBindingsTour(),
  ),
  ExampleInfo(
    id: 'keydetector.basic',
    widget: 'KeyDetector',
    category: 'Input handling & focus',
    blurb:
        'Low-level key handling inside a custom control: inspect each key and '
        'consume only the ones the control handles.',
    cols: 64,
    rows: 12,
    interactive: true,
    code: '''KeyDetector(
  onKey: (event) {
    if (event.code == KeyCode.arrowDown && cursor < rows.length - 1) {
      setState(() => cursor++);
      event.consume(); // handled inside the pane
    }
    // At the last row the arrow is not consumed, so it reaches the
    // ancestors' key bindings.
  },
  child: Focus(child: pane),
)''',
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
    builder: () => Theme(data: _customTheme, child: const _ThemePreview()),
  ),
  ExampleInfo(
    id: 'themes.gallery',
    widget: 'Themes',
    category: 'Theming',
    blurb:
        'Every bundled community theme, on a slice of real UI. Arrow through '
        'the picker to switch.',
    cols: 62,
    rows: 18,
    interactive: true,
    code: '''import 'package:fleury/fleury.dart';
import 'package:fleury/themes.dart';

void main() =>
    runApp(const FleuryApp(title: 'My app', theme: tokyoNight, home: MyApp()));''',
    builder: () => const _ThemePickerExample(),
  ),
  ExampleInfo(
    id: 'themes.local_style',
    widget: 'Themes',
    category: 'Theming',
    blurb: 'Apply one local CellStyle override to a text input.',
    cols: 34,
    rows: 4,
    interactive: true,
    code: _localStyleSource,
    builder: () => const _LocalStyleTour(),
  ),
  ExampleInfo(
    id: 'themes.cell_style',
    widget: 'Themes',
    category: 'Theming',
    blurb: 'Compare default text with one styled line.',
    cols: 34,
    rows: 5,
    code: _cellStyleSource,
    builder: () => const _CellStyleTour(),
  ),
  ExampleInfo(
    id: 'themes.local_interactive',
    widget: 'Themes',
    category: 'Theming',
    blurb: 'Compare an inherited focus cue with a local interactive override.',
    cols: 46,
    rows: 8,
    interactive: true,
    code: _localInteractiveSource,
    builder: () => const _LocalStateTour(),
  ),
  ExampleInfo(
    id: 'themes.invalid_none',
    widget: 'Themes',
    category: 'Theming',
    blurb:
        'Suppress invalid chrome locally while retaining the visible and '
        'semantic validation error.',
    cols: 48,
    rows: 9,
    interactive: true,
    code: _invalidNoneSource,
    builder: () => const _InvalidNoneTour(),
  ),
  ExampleInfo(
    id: 'themes.interactive_styles',
    widget: 'Themes',
    category: 'Theming',
    blurb:
        'One interactive style adapts to focus, hover, selection, validation, and '
        'disabled state without changing each widget separately.',
    cols: 52,
    rows: 13,
    code: _interactiveStylesSource,
    builder: () => const _InteractiveStyleTour(),
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

/// The docs shell's theme override, shared through its own scope type so a
/// `Theme` inside an example never shadows it.
final class _DocsExampleTheme {
  const _DocsExampleTheme(this.data);

  final ThemeData data;

  static ThemeData? maybeOf(BuildContext context) =>
      context.scope<_DocsExampleTheme?>()?.data;

  @override
  bool operator ==(Object other) =>
      other is _DocsExampleTheme && other.data == data;

  @override
  int get hashCode => data.hashCode;
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
          text: _open ? 'Hide layer' : 'Show layer',
          autofocus: true,
          onPressed: _toggle,
        ),
        for (var i = 0; i < 6; i++) const Text('live content behind the layer'),
      ],
    );
    return KeyBindings(
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
  Widget build(BuildContext context) => Checkbox(
    value: _accepted,
    label: 'Accept terms',
    autofocus: true,
    onChanged: (value) => setState(() => _accepted = value),
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
  Widget build(BuildContext context) => Toggle(
    value: _compact,
    label: 'Compact rows',
    autofocus: true,
    onChanged: (value) => setState(() => _compact = value),
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
  Widget build(BuildContext context) => Switch(
    value: _streaming,
    label: 'Streaming updates',
    autofocus: true,
    onChanged: (value) => setState(() => _streaming = value),
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
  Widget build(BuildContext context) => Column(
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
  Widget build(BuildContext context) => RadioGroup<String>(
    value: _mode,
    autofocus: true,
    options: const <RadioOption<String>>[
      RadioOption(value: 'fast', label: 'Fast'),
      RadioOption(value: 'safe', label: 'Safe'),
      RadioOption(value: 'thorough', label: 'Thorough'),
    ],
    onChanged: (value) => setState(() => _mode = value),
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
  Widget build(BuildContext context) => MultiSelect<String>(
    autofocus: true,
    semanticLabel: 'Enabled telemetry',
    options: const <SelectOption<String>>[
      SelectOption(value: 'logs', label: 'Logs'),
      SelectOption(value: 'traces', label: 'Traces'),
      SelectOption(value: 'metrics', label: 'Metrics'),
    ],
    values: _selected,
    onChanged: (values) => setState(() => _selected = values),
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
  Widget build(BuildContext context) => TextInput(
    controller: _controller,
    autofocus: true,
    semanticLabel: 'Command',
    onChanged: (_) {},
    onSubmit: (_) {},
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
  Widget build(BuildContext context) => PasswordInput(
    controller: _controller,
    autofocus: true,
    semanticLabel: 'Password',
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
  Widget build(BuildContext context) => Autocomplete<String>(
    controller: _controller,
    autofocus: true,
    placeholder: 'Type a fruit…',
    options: const <String>['Apple', 'Apricot', 'Banana', 'Cherry', 'Grape'],
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
  Widget build(BuildContext context) => TextArea(
    controller: _controller,
    autofocus: true,
    minLines: 4,
    maxLines: 4,
    semanticLabel: 'Release notes',
    onChanged: (_) {},
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
  Widget build(BuildContext context) => Select<String>(
    value: _v,
    onChanged: (v) => setState(() => _v = v),
    options: const <SelectOption<String>>[
      SelectOption(value: 'low', label: 'Low'),
      SelectOption(value: 'medium', label: 'Medium'),
      SelectOption(value: 'high', label: 'High'),
    ],
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
  Widget build(BuildContext context) => RangeSlider(
    values: _v,
    min: 0,
    max: 100,
    label: 'Range',
    showValues: true,
    autofocus: true,
    onChanged: (v) => setState(() => _v = v),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Pressed $_count×'),
      const SizedBox(height: 1),
      Button(
        text: 'Press me',
        variant: ButtonVariant.primary,
        autofocus: true,
        onPressed: () => setState(() => _count++),
      ),
    ],
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
  Widget build(BuildContext context) => Stepper(
    value: _v,
    min: 0,
    max: 10,
    label: 'Quantity',
    onChanged: (v) => setState(() => _v = v),
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
  Widget build(BuildContext context) => ColorPicker(
    value: _c,
    onChanged: (c) => setState(() => _c = c),
    colors: const <Color>[
      RgbColor(0xFF, 0x5C, 0x57),
      RgbColor(0xF5, 0xC2, 0x11),
      RgbColor(0x3D, 0xDC, 0x97),
      RgbColor(0x56, 0xC2, 0xFF),
      RgbColor(0xBD, 0x93, 0xF9),
    ],
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
  Widget build(BuildContext context) => DatePicker(
    value: _d,
    label: 'Date',
    onChanged: (d) => setState(() => _d = d),
  );
}

class _FleuryAppExample extends StatefulWidget {
  const _FleuryAppExample();

  @override
  State<_FleuryAppExample> createState() => _FleuryAppExampleState();
}

class _FleuryAppExampleState extends State<_FleuryAppExample> {
  static const _archive = CommandId('inbox.archive');
  var _unread = 3;

  @override
  Widget build(BuildContext context) => FleuryApp(
    title: 'Inbox',
    commands: [
      AppCommand(
        id: _archive,
        title: 'Archive message',
        shortcuts: [KeySequence.a],
        enabled: (_) => _unread > 0,
        run: (_) => setState(() => _unread -= 1),
      ),
    ],
    status: (app) => [StatusItem.text('Unread', value: '$_unread')],
    home: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Press A, or the button, to archive.'),
        SizedBox(height: 1),
        CommandButton(command: _archive, autofocus: true),
        SizedBox(height: 1),
        AppStatusBar(),
      ],
    ),
  );
}

class _FocusScopeExample extends StatefulWidget {
  const _FocusScopeExample();
  @override
  State<_FocusScopeExample> createState() => _FocusScopeExampleState();
}

class _FocusScopeExampleState extends State<_FocusScopeExample> {
  bool _trap = true;
  String _pressed = 'nothing yet';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FocusScope(
        trapFocus: _trap,
        child: Container.framed(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _trap,
                label: 'Trap focus in this pane',
                autofocus: true,
                onChanged: (value) => setState(() => _trap = value),
              ),
              Row(
                children: [
                  Button(
                    text: 'Run',
                    onPressed: () => setState(() => _pressed = 'Run'),
                  ),
                  const SizedBox(width: 1),
                  Button(
                    text: 'Stop',
                    onPressed: () => setState(() => _pressed = 'Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      Button(
        text: 'Outside',
        onPressed: () => setState(() => _pressed = 'Outside'),
      ),
      Text('pressed: $_pressed', style: const CellStyle(dim: true)),
    ],
  );
}

// Log surfaces read as a running process: each demo appends its next scripted
// line every 0.7 seconds, looping at the end.

class _LogRegionExample extends StatefulWidget {
  const _LogRegionExample();
  @override
  State<_LogRegionExample> createState() => _LogRegionExampleState();
}

class _LogRegionExampleState extends State<_LogRegionExample>
    with SingleTickerProviderStateMixin {
  static const _deploy = <(LogSeverity, String, String)>[
    (LogSeverity.info, 'deploy', 'Starting deploy of api@4.2.0'),
    (LogSeverity.info, 'build', 'Compiling 214 files'),
    (LogSeverity.success, 'build', 'Built in 3.8s'),
    (LogSeverity.info, 'deploy', 'Uploading image (48 MB)'),
    (LogSeverity.warning, 'probe', 'Health check slow: 1.9s'),
    (LogSeverity.info, 'deploy', 'Routing 10% of traffic'),
    (LogSeverity.error, 'probe', 'Health check failed: 503 on /ready'),
    (LogSeverity.info, 'deploy', 'Rolling back to api@4.1.3'),
    (LogSeverity.success, 'deploy', 'Rollback complete'),
  ];

  final List<LogEntry> _entries = [];
  int _next = 0;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 4; i++) {
      _append();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Frames only tick inside a running app.
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _last < const Duration(milliseconds: 700)) return;
    _last = elapsed;
    setState(_append);
  }

  void _append() {
    final (severity, source, message) = _deploy[_next % _deploy.length];
    _entries.add(
      LogEntry(id: _next, severity: severity, source: source, message: message),
    );
    _next++;
    if (_entries.length > 200) _entries.removeAt(0);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LogRegion(entries: List.of(_entries), autofocus: true);
}

class _TerminalOutputExample extends StatefulWidget {
  const _TerminalOutputExample();
  @override
  State<_TerminalOutputExample> createState() => _TerminalOutputExampleState();
}

class _TerminalOutputExampleState extends State<_TerminalOutputExample>
    with SingleTickerProviderStateMixin {
  static const _session = <(LogSource, String)>[
    (LogSource.stdout, r'$ dart compile exe bin/server.dart'),
    (LogSource.stdout, 'Generated: bin/server.exe'),
    (LogSource.stdout, r'$ dart test'),
    (LogSource.stdout, '00:01 +12: All tests passed!'),
    (LogSource.stdout, r'$ dart analyze'),
    (
      LogSource.stderr,
      "warning - lib/cache.dart:14:7 - Unused import: 'dart:io'.",
    ),
    (LogSource.stdout, '1 issue found.'),
  ];

  final LogBuffer _buffer = LogBuffer(capacity: 200);
  int _next = 0;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      _append();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Frames only tick inside a running app.
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _last < const Duration(milliseconds: 700)) return;
    _last = elapsed;
    _append();
  }

  // The region listens to the buffer, so appending needs no setState.
  void _append() {
    final (source, text) = _session[_next++ % _session.length];
    _buffer.add(LogLine(text, source));
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
    _buffer.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TerminalOutputRegion(buffer: _buffer, autofocus: true);
}

class _WorkflowSnapshotExample extends StatefulWidget {
  const _WorkflowSnapshotExample();
  @override
  State<_WorkflowSnapshotExample> createState() =>
      _WorkflowSnapshotExampleState();
}

class _WorkflowSnapshotExampleState extends State<_WorkflowSnapshotExample> {
  static const _plan = <String>['Run tests', 'Build image', 'Deploy'];

  List<TaskGraphStatus> _statuses = [
    TaskGraphStatus.succeeded,
    TaskGraphStatus.running,
    TaskGraphStatus.pending,
  ];

  WorkflowSnapshot get _snapshot => WorkflowSnapshot(
    title: 'Release',
    tasks: [
      for (var i = 0; i < _plan.length; i++)
        TaskGraphNode(id: 'task-$i', title: _plan[i], status: _statuses[i]),
    ],
  );

  void _advance() => setState(() {
    final running = _statuses.indexOf(TaskGraphStatus.running);
    final pending = _statuses.indexOf(TaskGraphStatus.pending);
    _statuses = [..._statuses];
    if (running >= 0) _statuses[running] = TaskGraphStatus.succeeded;
    if (pending >= 0) _statuses[pending] = TaskGraphStatus.running;
  });

  void _fail() => setState(() {
    final running = _statuses.indexOf(TaskGraphStatus.running);
    if (running < 0) return;
    _statuses = [..._statuses]..[running] = TaskGraphStatus.failed;
  });

  void _reset() => setState(() {
    _statuses = [
      TaskGraphStatus.running,
      TaskGraphStatus.pending,
      TaskGraphStatus.pending,
    ];
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final summary = snapshot.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 4, child: TaskGraph(nodes: snapshot.tasks)),
        Text(
          'health: ${summary.health.name} · '
          '${summary.activeTaskCount} of ${summary.taskCount} remaining · '
          '${summary.failedTaskCount} failed',
          style: const CellStyle(bold: true),
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            Button(text: 'Advance', autofocus: true, onPressed: _advance),
            const SizedBox(width: 1),
            Button(text: 'Fail', onPressed: _fail),
            const SizedBox(width: 1),
            Button(text: 'Reset', onPressed: _reset),
          ],
        ),
      ],
    );
  }
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
/// [NotifierBuilder] can rebuild the widget in place (no remount/recompile).
class KnobParams with Notifier {
  KnobParams(this._value);

  Map<String, Object?> _value;
  Map<String, Object?> get value => _value;
  set value(Map<String, Object?> next) {
    _value = next;
    notify();
  }
}

/// Root widget for a knob playground: rebuilds [id]'s widget whenever [params]
/// changes.
Widget knobRoot(String id, KnobParams params) {
  final builder = knobExamples[id];
  if (builder == null) return const Center(child: Text('Unknown knob example'));
  return FocusTraversalGroup(
    child: NotifierBuilder(
      notifier: params,
      builder: (context, params) => builder(params.value),
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
      _ticker!.start();
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
  final ListController _list = ListController(initialIndex: 0);

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = (context.listen(_list).currentIndex ?? 0).clamp(
      0,
      fleuryThemes.length - 1,
    );
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
                    : CellStyle.none,
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

const String _localStyleSource = '''
TextInput(
  controller: query,
  style: const CellStyle(foreground: Colors.cyan),
)''';

class _LocalStyleTour extends StatefulWidget {
  const _LocalStyleTour();

  @override
  State<_LocalStyleTour> createState() => _LocalStyleTourState();
}

class _LocalStyleTourState extends State<_LocalStyleTour> {
  final _query = TextEditingController(text: 'api-gateway');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    child: TextInput(
      controller: _query,
      style: const CellStyle(foreground: Colors.cyan),
    ),
  );
}

const String _cellStyleSource = '''
Column(children: [
  Text('Default text'),
  Text(
    'Styled text',
    style: CellStyle(
      foreground: RgbColor(0x3D, 0xDC, 0x97),
      bold: true,
      underline: true,
    ),
  ),
]);''';

class _CellStyleTour extends StatelessWidget {
  const _CellStyleTour();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('Default text'),
      Text(
        'Styled text',
        style: CellStyle(
          foreground: RgbColor(0x3D, 0xDC, 0x97),
          bold: true,
          underline: true,
        ),
      ),
    ],
  );
}

const String _localInteractiveSource = '''
Row(
  children: [
    Button(text: 'Theme focus', onPressed: deploy),
    SizedBox(width: 2),
    Button(
      text: 'Local focus',
      style: CellStyle.interactive(
        focused: CellStyle(
          foreground: Colors.cyan,
          underline: true,
        ),
      ),
      onPressed: deploy,
    ),
  ],
)''';

class _LocalStateTour extends StatelessWidget {
  const _LocalStateTour();

  @override
  Widget build(BuildContext context) => Theme(
    // Overrides the app theme below this point: every control's inherited
    // focus cue becomes inverse and bold.
    data: Theme.of(context).copyWith(
      interactiveStyle: const CellStyle.interactive(
        focused: CellStyle(inverse: true, bold: true),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('LOCAL INTERACTION STYLE', style: CellStyle(bold: true)),
          const Text('Tab or click to compare focus cues'),
          Row(
            children: <Widget>[
              Button(text: 'Theme focus', autofocus: true, onPressed: () {}),
              const SizedBox(width: 2),
              Button(
                text: 'Local focus',
                style: const CellStyle.interactive(
                  focused: CellStyle(foreground: Colors.cyan, underline: true),
                ),
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

const String _invalidNoneSource = '''
FormField(
  validator: () => query.text.isEmpty ? 'Enter a query.' : null,
  child: TextInput(
    controller: query,
    style: const CellStyle.interactive(
      invalid: CellStyle.none,
    ),
  ),
)''';

class _InvalidNoneTour extends StatefulWidget {
  const _InvalidNoneTour();

  @override
  State<_InvalidNoneTour> createState() => _InvalidNoneTourState();
}

class _InvalidNoneTourState extends State<_InvalidNoneTour> {
  final _form = FormController();
  final _query = TextEditingController();

  @override
  void dispose() {
    _form.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Form(
      controller: _form,
      onSubmit: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('NEUTRAL INVALID CHROME', style: CellStyle(bold: true)),
          const Text('Submit empty: the message stays visible'),
          FormField(
            validator: () => _query.text.isEmpty ? 'Enter a query.' : null,
            child: SizedBox(
              width: 30,
              child: TextInput(
                controller: _query,
                autofocus: true,
                semanticLabel: 'Query',
                placeholder: 'Query',
                style: const CellStyle.interactive(invalid: CellStyle.none),
              ),
            ),
          ),
          Button(text: 'Submit', onPressed: _form.submit),
        ],
      ),
    ),
  );
}

/// A small customization of Fleury's dark starting theme.
///
/// Kept in sync with [_customThemeSource] by a test so the code beside the
/// preview remains the code that produced it.
ThemeData get _customTheme => _buildCustomTheme();

ThemeData _buildCustomTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: const RgbColor(0xE8, 0xA3, 0x3D),
      focus: const RgbColor(0xF2, 0xC5, 0x5C),
      warning: const RgbColor(0xE8, 0xA3, 0x3D),
    ),
    borderStyle: BorderStyle.double,
  );
}

/// The literal source of [_customTheme], shown beside its render on the
/// theming guide. A test asserts the two agree, so the page cannot drift into
/// showing code that is not what produced the picture.
const String _customThemeSource = '''
final base = ThemeData.dark();
final amber = base.copyWith(
  colorScheme: base.colorScheme.copyWith(
    primary: RgbColor(0xE8, 0xA3, 0x3D),
    focus: RgbColor(0xF2, 0xC5, 0x5C),
    warning: RgbColor(0xE8, 0xA3, 0x3D),
  ),
  borderStyle: BorderStyle.double,
);

FleuryApp(title: 'Dashboard', theme: amber, home: const Dashboard());''';

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
    // The border shows the theme's borderStyle; it replaces vertical padding
    // so the preview keeps its height in both embeds.
    return Container(
      color: cs.background,
      border: BoxBorder(
        style: theme.borderStyle,
        cellStyle: CellStyle(foreground: cs.primary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
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

const CellStyle _interactiveStyle = CellStyle.interactive(
  focused: CellStyle(inverse: true, bold: true),
  hovered: CellStyle(underline: true),
  selected: CellStyle(foreground: Colors.green, bold: true),
  invalid: CellStyle(foreground: Colors.red, underline: true),
  disabled: CellStyle(dim: true),
);

const String _interactiveStylesSource = '''
const interactions = CellStyle.interactive(
  focused: CellStyle(inverse: true, bold: true),
  hovered: CellStyle(underline: true),
  selected: CellStyle(foreground: Colors.green, bold: true),
  invalid: CellStyle(foreground: Colors.red, underline: true),
  disabled: CellStyle(dim: true),
);''';

/// Exposed for the guide/source/live parity test.
CellStyle get interactiveStyleForTest => _interactiveStyle;
String get interactiveStyleSourceForTest => _interactiveStylesSource;

/// Visual legend for the styles carried by one interaction-aware value.
class _InteractiveStyleTour extends StatelessWidget {
  const _InteractiveStyleTour();

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context);
    return Theme(
      data: outer.copyWith(interactiveStyle: _interactiveStyle),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('INTERACTION STYLES', style: CellStyle(bold: true)),
            SizedBox(height: 1),
            Text('base      ordinary control paint'),
            Text(
              'focused   inverse + bold',
              style: CellStyle.resolve(
                cascade: [_interactiveStyle],
                focused: true,
              ),
            ),
            Text(
              'hovered   underline',
              style: CellStyle.resolve(
                cascade: [_interactiveStyle],
                hovered: true,
              ),
            ),
            Text(
              'selected  green + bold',
              style: CellStyle.resolve(
                cascade: [_interactiveStyle],
                selected: true,
              ),
            ),
            Text(
              'invalid   red + underline',
              style: CellStyle.resolve(
                cascade: [_interactiveStyle],
                invalid: true,
              ),
            ),
            Text(
              'disabled  dim',
              style: CellStyle.resolve(
                cascade: [_interactiveStyle],
                disabled: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotLoadingTour extends StatelessWidget {
  const _SnapshotLoadingTour();

  @override
  Widget build(BuildContext context) => _framed(
    const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('PREVIEW ASYNC UI', style: CellStyle(bold: true)),
        loading.SnapshotExplorer(),
      ],
    ),
  );
}

class _NetworkImageLoadingTour extends StatefulWidget {
  const _NetworkImageLoadingTour();

  @override
  State<_NetworkImageLoadingTour> createState() =>
      _NetworkImageLoadingTourState();
}

/// Mounts the photo viewer only after the reader asks for it, so opening a
/// page that embeds this demo sends no request to the photo service.
class _NetworkImageLoadingTourState extends State<_NetworkImageLoadingTour> {
  var _seed = 0;
  var _started = false;

  @override
  Widget build(BuildContext context) => _started
      ? loading.PhotoViewer(loadPhoto: () => loading.fetchPhoto(++_seed))
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Photos come from picsum.photos.'),
            Button(
              text: 'Load a photo',
              onPressed: () => setState(() => _started = true),
            ),
          ],
        );
}

class _StreamLoadingTour extends StatelessWidget {
  const _StreamLoadingTour();

  @override
  Widget build(BuildContext context) => _framed(
    const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('STAR MAP TRANSMISSION', style: CellStyle(bold: true)),
        loading.TransmissionView(),
      ],
    ),
  );
}

class _OrbitalCourier extends StatefulWidget {
  const _OrbitalCourier();

  @override
  State<_OrbitalCourier> createState() => _OrbitalCourierState();
}

class _OrbitalCourierState extends State<_OrbitalCourier> {
  static const _idle = RgbColor(115, 125, 140);
  static const _arrived = RgbColor(70, 220, 145);

  late final Animation<double> _progress = Animation<double>(
    0.0,
    debugLabel: 'orbital courier progress',
  );
  var _launched = false;

  void _toggleMission() {
    if (_launched) {
      setState(() => _launched = false);
      _progress.to(
        0.0,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }

    setState(() => _launched = true);
    _launch();
  }

  Future<void> _launch() async {
    try {
      await _progress
          .to(
            0.12,
            curve: Curves.easeOut,
            duration: const Duration(milliseconds: 700),
          )
          .delay(const Duration(milliseconds: 450))
          .to(
            0.58,
            curve: Curves.easeInOut,
            duration: const Duration(milliseconds: 1600),
          )
          .delay(const Duration(milliseconds: 400))
          .to(
            1.0,
            curve: Curves.easeOut,
            duration: const Duration(milliseconds: 1800),
          )
          .orCancel;
    } on TickerCanceled {
      // Reset or a newer launch replaced this flight.
    }
  }

  String _statusFor(double progress) {
    if (!_launched && progress > 0.02) return 'RETURN · Recalling courier';
    if (progress > 0.98) return '4/4 DELIVERY · Payload secured';
    if (progress > 0.60) return '3/4 TRANSFER · Matching orbital speed';
    if (progress > 0.13) return '2/4 ASCENT · Clearing the atmosphere';
    if (progress > 0.01) return '1/4 IGNITION · Engines nominal';
    return 'READY · Awaiting flight plan';
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = _progress.value.clamp(0.0, 1.0);
    final position = (visual * 30).round();
    final filled = (visual * 30).round();
    final accent = rgbColorLerp(_idle, _arrived, visual);
    final route =
        '${List<String>.filled(position, '·').join()}◆'
        '${List<String>.filled(30 - position, '·').join()}';
    final gauge =
        '${List<String>.filled(filled, '█').join()}'
        '${List<String>.filled(30 - filled, '░').join()}';

    return _framed(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('ORBITAL COURIER', style: CellStyle(bold: true)),
          const Text('A tiny package. One very large delivery.'),
          const SizedBox(height: 1),
          Button(
            text: _launched ? 'Reset mission' : 'Launch',
            onPressed: _toggleMission,
          ),
          const SizedBox(height: 1),
          Container(
            width: 52,
            height: 7,
            border: BoxBorder(
              style: Theme.of(context).borderStyle,
              cellStyle: CellStyle(foreground: accent),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'EARTH $route ORBIT',
                  style: CellStyle(foreground: accent),
                ),
                Text('$gauge ${(visual * 100).round()}%'),
                Text(_statusFor(visual), style: CellStyle(foreground: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualRoute extends StatefulWidget {
  const _ManualRoute();

  @override
  State<_ManualRoute> createState() => _ManualRouteState();
}

class _ManualRouteState extends State<_ManualRoute> {
  final _progress = Animation<double>(0.0, debugLabel: 'manual package route');
  var _running = false;

  Future<void> _runRoute() async {
    setState(() => _running = true);
    try {
      await _progress
          .to(
            1.0,
            curve: Curves.easeInOut,
            duration: const Duration(milliseconds: 700),
          )
          .delay(const Duration(milliseconds: 600))
          .to(
            0.0,
            curve: Curves.easeInOut,
            duration: const Duration(milliseconds: 700),
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted) setState(() => _running = false);
  }

  void _returnNow() {
    setState(() => _running = false);
    _progress.to(
      0.0,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress.value;
    final position = (progress * 24).round();
    final route =
        '${List<String>.filled(position, '─').join()}◆'
        '${List<String>.filled(24 - position, '·').join()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('RAW ANIMATION', style: CellStyle(bold: true)),
        const Text('Own it to chain, await, and interrupt motion.'),
        const SizedBox(height: 1),
        Button(
          text: _running ? 'Return now' : 'Run route',
          onPressed: _running ? _returnNow : _runRoute,
        ),
        const SizedBox(height: 1),
        Text('DEPOT $route STATION'),
        Text('progress.value: ${progress.toStringAsFixed(2)}'),
      ],
    );
  }
}

class _PackageRoute extends StatefulWidget {
  const _PackageRoute();

  @override
  State<_PackageRoute> createState() => _PackageRouteState();
}

class _PackageRouteState extends State<_PackageRoute> {
  var _delivered = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('PACKAGE ROUTE', style: CellStyle(bold: true)),
      const Text('Change the target; the builder interpolates the value.'),
      const SizedBox(height: 1),
      Button(
        text: _delivered ? 'Return to depot' : 'Send to station',
        onPressed: () => setState(() => _delivered = !_delivered),
      ),
      const SizedBox(height: 1),
      AnimationBuilder<double>(
        _delivered ? 1.0 : 0.0,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 1100),
        builder: (context, double progress, _) {
          final position = (progress * 24).round();
          final route =
              '${List<String>.filled(position, '─').join()}◆'
              '${List<String>.filled(24 - position, '·').join()}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('DEPOT $route STATION'),
              Text('progress: ${progress.toStringAsFixed(2)} · double'),
              Container(
                height: 1,
                child: progress > 0.995
                    ? const Text(
                            '✦ PACKAGE DELIVERED ✦',
                            style: CellStyle(
                              foreground: RgbColor(70, 220, 145),
                              bold: true,
                            ),
                          )
                          .animate(duration: const Duration(milliseconds: 650))
                          .flash(color: const RgbColor(120, 255, 190))
                          .slideIn(from: Edge.bottom)
                    : const Text(''),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _TimingComparison extends StatefulWidget {
  const _TimingComparison();

  @override
  State<_TimingComparison> createState() => _TimingComparisonState();
}

Widget _sharedTimingStatus(bool active) {
  const inactive = RgbColor(110, 120, 135);
  const activeColor = RgbColor(70, 220, 145);

  return AnimationBuilder<double>(
    active ? 1.0 : 0.0,
    curve: Curves.easeOut,
    duration: const Duration(milliseconds: 800),
    builder: (context, double progress, _) {
      final width = 22 + (20 * progress).round();
      final accent = rgbColorLerp(inactive, activeColor, progress);
      return Container(
        width: width,
        height: 3,
        border: BoxBorder(
          style: Theme.of(context).borderStyle,
          cellStyle: CellStyle(foreground: accent),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text('TOGETHER ${(progress * 100).round()}%'),
      );
    },
  );
}

Widget _independentTimingStatus(bool active) {
  const inactive = RgbColor(110, 120, 135);
  const activeColor = RgbColor(70, 220, 145);

  return AnimationBuilder<int>(
    active ? 42 : 22,
    curve: Curves.easeOut,
    duration: const Duration(milliseconds: 180),
    builder: (context, width, _) => AnimationBuilder<double>(
      active ? 1.0 : 0.0,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 800),
      builder: (context, double colorProgress, _) => Container(
        width: width,
        height: 3,
        border: BoxBorder(
          style: Theme.of(context).borderStyle,
          cellStyle: CellStyle(
            foreground: rgbColorLerp(inactive, activeColor, colorProgress),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text('ACCENT ${(colorProgress * 100).round()}%'),
      ),
    ),
  );
}

class _TimingComparisonState extends State<_TimingComparison> {
  var _enabled = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('TIMING COMPARISON', style: CellStyle(bold: true)),
      const SizedBox(height: 1),
      Button(
        text: _enabled ? 'Reset' : 'Animate',
        onPressed: () => setState(() => _enabled = !_enabled),
      ),
      const Text('Shared timing: width + color together'),
      _sharedTimingStatus(_enabled),
      const SizedBox(height: 1),
      const Text('Independent timing: width 180 ms · accent 800 ms'),
      _independentTimingStatus(_enabled),
    ],
  );
}

class _ConnectionStatus extends StatefulWidget {
  const _ConnectionStatus();

  @override
  State<_ConnectionStatus> createState() => _ConnectionStatusState();
}

class _ConnectionStatusState extends State<_ConnectionStatus> {
  var _connected = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('RELAY CONNECTION', style: CellStyle(bold: true)),
      const Text('The effect runs when the status enters the tree.'),
      const SizedBox(height: 1),
      Button(
        text: _connected ? 'Disconnect' : 'Connect',
        onPressed: () => setState(() => _connected = !_connected),
      ),
      const SizedBox(height: 1),
      if (_connected)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child:
              const Text(
                    '● Connected to relay',
                    style: CellStyle(foreground: RgbColor(70, 220, 145)),
                  )
                  .animate(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.linear,
                  )
                  .fadeIn()
                  .slideIn(from: Edge.left),
        )
      else
        const Text(
          '○ Offline',
          style: CellStyle(foreground: RgbColor(115, 125, 140)),
        ),
    ],
  );
}

enum _EntryEffectChoice { fade, slide, wipe, expand }

enum _ExitEffectChoice { fade, slide, wipe, shrink }

class _EffectPicker extends StatefulWidget {
  const _EffectPicker();

  @override
  State<_EffectPicker> createState() => _EffectPickerState();
}

class _EffectPickerState extends State<_EffectPicker> {
  var _entry = _EntryEffectChoice.fade;
  var _exit = _ExitEffectChoice.fade;
  var _visible = true;

  Effect get _entryEffect => switch (_entry) {
    _EntryEffectChoice.fade => Effects.fadeIn(),
    _EntryEffectChoice.slide => Effects.slideIn(from: Edge.left),
    _EntryEffectChoice.wipe => Effects.wipeIn(from: Edge.left),
    _EntryEffectChoice.expand => Effects.expand(),
  };

  Effect get _exitEffect => switch (_exit) {
    _ExitEffectChoice.fade => Effects.fadeOut(),
    _ExitEffectChoice.slide => Effects.slideOut(to: Edge.right),
    _ExitEffectChoice.wipe => Effects.wipeOut(to: Edge.right),
    _ExitEffectChoice.shrink => Effects.shrink(),
  };

  Duration get _transitionDuration {
    if (_visible) {
      return switch (_entry) {
        _EntryEffectChoice.fade => const Duration(milliseconds: 400),
        _EntryEffectChoice.slide ||
        _EntryEffectChoice.wipe => const Duration(milliseconds: 800),
        _EntryEffectChoice.expand => const Duration(milliseconds: 300),
      };
    }
    return switch (_exit) {
      _ExitEffectChoice.fade => const Duration(milliseconds: 400),
      _ExitEffectChoice.slide ||
      _ExitEffectChoice.wipe => const Duration(milliseconds: 800),
      _ExitEffectChoice.shrink => const Duration(milliseconds: 300),
    };
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('ENTRANCE + EXIT LAB', style: CellStyle(bold: true)),
      const Text('Choose a pair, then toggle the sample.'),
      const SizedBox(height: 1),
      Row(
        children: <Widget>[
          SizedBox(
            width: 25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('ENTER'),
                Select<_EntryEffectChoice>(
                  semanticLabel: 'Entrance effect',
                  autofocus: true,
                  value: _entry,
                  options: const <SelectOption<_EntryEffectChoice>>[
                    SelectOption(
                      value: _EntryEffectChoice.fade,
                      label: 'Fade in',
                    ),
                    SelectOption(
                      value: _EntryEffectChoice.slide,
                      label: 'Slide in',
                    ),
                    SelectOption(
                      value: _EntryEffectChoice.wipe,
                      label: 'Wipe in',
                    ),
                    SelectOption(
                      value: _EntryEffectChoice.expand,
                      label: 'Expand',
                    ),
                  ],
                  onChanged: (value) => setState(() => _entry = value),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('EXIT'),
                Select<_ExitEffectChoice>(
                  semanticLabel: 'Exit effect',
                  value: _exit,
                  options: const <SelectOption<_ExitEffectChoice>>[
                    SelectOption(
                      value: _ExitEffectChoice.fade,
                      label: 'Fade out',
                    ),
                    SelectOption(
                      value: _ExitEffectChoice.slide,
                      label: 'Slide out',
                    ),
                    SelectOption(
                      value: _ExitEffectChoice.wipe,
                      label: 'Wipe out',
                    ),
                    SelectOption(
                      value: _ExitEffectChoice.shrink,
                      label: 'Shrink',
                    ),
                  ],
                  onChanged: (value) => setState(() => _exit = value),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 1),
      Button(
        text: _visible ? 'Hide sample' : 'Show sample',
        onPressed: () => setState(() => _visible = !_visible),
      ),
      const SizedBox(height: 1),
      AnimatedVisibility(
        visible: _visible,
        enter: _entryEffect,
        exit: _exitEffect,
        duration: _transitionDuration,
        curve: Curves.linear,
        child: Container(
          width: 24,
          border: BoxBorder(style: Theme.of(context).borderStyle),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('DEPLOY PREVIEW', style: CellStyle(bold: true)),
              Text('✓ Resolve'),
              Text('✓ Analyze'),
              Text('✓ Test'),
              Text('✓ Package'),
              Text('✓ Sign'),
              Text('✓ Publish'),
            ],
          ),
        ),
      ),
    ],
  );
}

class _PilotValidation extends StatefulWidget {
  const _PilotValidation();

  @override
  State<_PilotValidation> createState() => _PilotValidationState();
}

class _PilotValidationState extends State<_PilotValidation> {
  final _form = FormController();
  final _name = TextEditingController();
  var _submitCount = 0;
  String? _clearedName;

  Future<void> _submit() async {
    final valid = await _form.submit();
    if (!mounted) return;
    setState(() {
      _submitCount++;
      _clearedName = valid ? _name.text.trim() : null;
    });
  }

  Widget _feedback() {
    final cleared = _clearedName;
    final message = _submitCount == 0
        ? 'Enter a pilot name, then validate it.'
        : cleared == null
        ? '✕ Enter any non-empty name'
        : '✓ $cleared is cleared for launch';
    final color = cleared == null
        ? const RgbColor(255, 90, 90)
        : const RgbColor(70, 220, 145);
    final feedback =
        Text(
          message,
          style: CellStyle(foreground: _submitCount == 0 ? null : color),
        ).animate(
          trigger: _submitCount,
          curve: Curves.easeOut,
          duration: const Duration(milliseconds: 650),
        );
    return feedback.wipeIn(from: Edge.left);
  }

  @override
  void dispose() {
    _form.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    controller: _form,
    onSubmit: () {},
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('FORM VALIDATION', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        const Text('Pilot name'),
        FormField(
          validator: () =>
              _name.text.trim().isEmpty ? 'Enter any non-empty name' : null,
          // The animated line below shows the outcome instead.
          showErrorMessage: false,
          child: Container(
            width: 32,
            border: BoxBorder(style: Theme.of(context).borderStyle),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: SizedBox(
              width: 28,
              child: TextInput(
                controller: _name,
                autofocus: true,
                semanticLabel: 'Pilot name',
                placeholder: 'Type any name',
                onSubmit: (_) => _submit(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 1),
        _feedback(),
        const SizedBox(height: 1),
        Button(text: 'Validate pilot', onPressed: _submit),
      ],
    ),
  );
}

class _PacketTransfer extends StatefulWidget {
  const _PacketTransfer();

  @override
  State<_PacketTransfer> createState() => _PacketTransferState();
}

class _PacketTransferState extends State<_PacketTransfer> {
  static const _frames = <String>[
    '●··········◇',
    '──●········◇',
    '────●······◇',
    '──────●····◇',
    '────────●··◇',
    '──────────◆',
  ];

  var _fast = true;
  var _running = true;

  Duration get _interval => Duration(milliseconds: _fast ? 180 : 650);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('PACKET TRANSFER', style: CellStyle(bold: true)),
      const Text('Each step is an authored frame, not an interpolated value.'),
      const SizedBox(height: 1),
      Row(
        children: <Widget>[
          Button(
            text: _fast ? 'Slow down' : 'Speed up',
            onPressed: () => setState(() => _fast = !_fast),
          ),
          const SizedBox(width: 1),
          Button(
            text: _running ? 'Pause' : 'Resume',
            onPressed: () => setState(() => _running = !_running),
          ),
        ],
      ),
      const SizedBox(height: 1),
      FrameBuilder(
        interval: _interval,
        enabled: _running,
        builder: (context, frame, _, delta) {
          final index = frame % _frames.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('UPLINK ${_frames[index]} ARCHIVE'),
              Text(
                'authored frame ${index + 1}/${_frames.length} · '
                '${delta.inMilliseconds} ms',
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _TickerSimulation extends StatefulWidget {
  const _TickerSimulation();

  @override
  State<_TickerSimulation> createState() => _TickerSimulationState();
}

class _TickerSimulationState extends State<_TickerSimulation>
    with SingleTickerProviderStateMixin {
  static const _trackWidth = 28.0;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  var _position = 0.0;
  var _velocity = 12.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final seconds = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    var next = _position + (_velocity * seconds);
    if (next >= _trackWidth) {
      next = _trackWidth - (next - _trackWidth);
      _velocity = -_velocity.abs();
    } else if (next <= 0) {
      next = -next;
      _velocity = _velocity.abs();
    }
    setState(() => _position = next.clamp(0.0, _trackWidth));
  }

  void _toggle() => setState(() {
    if (_ticker.isActive) {
      _ticker.stop();
    } else {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  });

  @override
  Widget build(BuildContext context) {
    final position = _position.round();
    final track =
        '${List<String>.filled(position, '─').join()}●'
        '${List<String>.filled(_trackWidth.round() - position, '·').join()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('SIMULATION CLOCK', style: CellStyle(bold: true)),
        const Text('Position advances from elapsed time on every tick.'),
        const SizedBox(height: 1),
        Text('|$track|'),
        Text('position ${_position.toStringAsFixed(1)} cells'),
        const SizedBox(height: 1),
        Button(
          text: _ticker.isActive ? 'Pause simulation' : 'Resume simulation',
          onPressed: _toggle,
        ),
      ],
    );
  }
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
              text: 'Narrow',
              autofocus: true,
              onPressed: () => setState(() => _width = 42),
            ),
            const SizedBox(width: 1),
            Button(text: 'Wide', onPressed: () => setState(() => _width = 68)),
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

/// The first navigation example intentionally teaches only the three stack
/// operations. Each screen labels its depth so the behavior is readable
/// without reverse-engineering project-specific state.
class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  String _result = 'none';

  Future<void> _openDetails() async {
    final result = await context.push<String>(const _DetailsScreen());
    if (!mounted || result == null) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('HOME · STACK DEPTH 1', style: CellStyle(bold: true)),
      const SizedBox(height: 1),
      Button(text: 'Push details', autofocus: true, onPressed: _openDetails),
      const Spacer(),
      Text('result: $_result'),
    ],
  );
}

class _DetailsScreen extends StatefulWidget {
  const _DetailsScreen();

  @override
  State<_DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<_DetailsScreen> {
  String _dialogResult = 'not shown';

  Future<void> _presentDialog() async {
    final confirmed = await context.present<bool>(const _ConfirmDialog());
    if (!mounted) return;
    setState(() => _dialogResult = confirmed == true ? 'confirmed' : 'closed');
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('DETAILS · STACK DEPTH 2', style: CellStyle(bold: true)),
      Text('dialog: $_dialogResult'),
      const SizedBox(height: 1),
      Button(
        text: 'Present dialog',
        autofocus: true,
        onPressed: _presentDialog,
      ),
      Button(text: 'Pop with result', onPressed: () => context.pop('done')),
      Button(text: 'Pop without result', onPressed: context.pop),
    ],
  );
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 7,
    child: Panel(
      title: 'PRESENTED DIALOG',
      focused: true,
      child: Center(
        child: Button(
          text: 'Confirm and pop',
          autofocus: true,
          onPressed: () => context.pop(true),
        ),
      ),
    ),
  );
}

class _DialogPlacement extends StatefulWidget {
  const _DialogPlacement();

  @override
  State<_DialogPlacement> createState() => _DialogPlacementState();
}

class _DialogPlacementState extends State<_DialogPlacement> {
  Alignment _alignment = Alignment.center;

  Future<void> _show(Alignment alignment) async {
    setState(() => _alignment = alignment);
    await context.present<void>(
      const _PlacedDialog(),
      alignment: alignment,
      transition: RouteTransition.none,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
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
  );
}

class _PlacedDialog extends StatelessWidget {
  const _PlacedDialog();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 6,
    child: Panel(
      title: 'PLACED DIALOG',
      focused: true,
      child: Center(
        child: Button(text: 'Close', autofocus: true, onPressed: context.pop),
      ),
    ),
  );
}

class _DraftsScreen extends StatefulWidget {
  const _DraftsScreen();

  @override
  State<_DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<_DraftsScreen> {
  String _savedText = 'Release notes';

  void _saveDraft(String value) => setState(() => _savedText = value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('DRAFTS', style: CellStyle(bold: true)),
      Text('saved: $_savedText'),
      const SizedBox(height: 1),
      Button(
        text: 'Edit draft',
        autofocus: true,
        onPressed: () => context.push<void>(
          _GuardedEditor(initialText: _savedText, onSave: _saveDraft),
        ),
      ),
    ],
  );
}

class _GuardedEditor extends StatefulWidget {
  const _GuardedEditor({required this.initialText, required this.onSave});

  final String initialText;
  final void Function(String) onSave;

  @override
  State<_GuardedEditor> createState() => _GuardedEditorState();
}

class _GuardedEditorState extends State<_GuardedEditor> {
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
    child: Column(
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
        Button(text: 'Back', onPressed: () => Navigator.of(context).maybePop()),
        Button(text: 'Save', onPressed: _save),
        Button(text: 'Discard', onPressed: context.pop),
      ],
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
          text: 'Preview push',
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
        Button(text: 'Preview pop', autofocus: true, onPressed: context.pop),
      ],
    ),
  );
}

class _ProjectsScreen extends StatelessWidget {
  const _ProjectsScreen();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('PROJECTS · OUTER STACK 1', style: CellStyle(bold: true)),
      const SizedBox(height: 1),
      Button(
        text: 'Start setup',
        autofocus: true,
        onPressed: () => context.push<void>(const _SetupFlow()),
      ),
    ],
  );
}

class _SetupFlow extends StatelessWidget {
  const _SetupFlow();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('SETUP · OUTER STACK 2', style: CellStyle(bold: true)),
      const SizedBox(height: 1),
      Expanded(
        child: Panel(
          title: 'INNER FLOW',
          child: Navigator(
            transition: RouteTransition.none,
            home: const _SetupStep(step: 1),
          ),
        ),
      ),
      const SizedBox(height: 1),
      const Text('The inner stack advances inside one outer route.'),
    ],
  );
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({required this.step});

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
            text: 'Next step',
            autofocus: true,
            onPressed: () => context.push<void>(_SetupStep(step: step + 1)),
          )
        else
          Button(
            text: 'Finish setup',
            autofocus: true,
            onPressed: () => context.rootNavigator.pushReplacement<void>(
              const _ProjectReady(),
            ),
          ),
        if (step > 1) Button(text: 'Previous', onPressed: context.pop),
        Button(text: 'Cancel setup', onPressed: context.rootNavigator.pop),
      ],
    ),
  );
}

class _ProjectReady extends StatelessWidget {
  const _ProjectReady();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('PROJECT READY · OUTER STACK 2'),
      const Text('The entire inner history was removed together.'),
      const Spacer(),
      Button(text: 'Back to projects', autofocus: true, onPressed: context.pop),
    ],
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
    child: Button(text: label, autofocus: autofocus, onPressed: onPressed),
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
                  text: 'Cancel',
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 1),
                Button(
                  text: 'Publish',
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
  Widget build(BuildContext context) => Column(
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
            text: 'Focus search',
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
        FocusDetector(
          onFocusChange: _onFocusChange,
          // The border follows the detector: accented while focus is inside.
          child: Container(
            border: BoxBorder(
              style: theme.borderStyle,
              cellStyle: _inside
                  ? CellStyle(foreground: theme.colorScheme.primary)
                  : theme.mutedStyle,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Editor region', allowSelect: false),
                Button(text: 'Title', autofocus: true, onPressed: () {}),
                Button(text: 'Body', onPressed: () {}),
              ],
            ),
          ),
        ),
        const SizedBox(height: 1),
        Button(text: 'Preview (outside)', onPressed: () {}),
        const Text(
          'Tab Title → Body: same region · Preview: leaves once',
          style: CellStyle(dim: true),
        ),
      ],
    );
  }
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
