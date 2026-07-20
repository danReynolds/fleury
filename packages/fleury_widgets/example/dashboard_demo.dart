// A live-updating dashboard demo that composes the fleury_widgets viz
// catalog under one layout — the "do they actually compose?" smoke test
// for everything we've shipped.
//
// Run (from packages/fleury_widgets):
//
//   dart pub get
//   dart run example/dashboard_demo.dart
//
// Keys:
//   Tab           focus the line chart (then arrows drive the crosshair)
//   Space         pause / resume the live simulation
//   Ctrl+C        quit
//
// What's exercised:
//   - LineChart with two series, gridlines, palette, threshold coloring,
//     interactive crosshair (when focused), follow-cursor tooltip
//   - Gauge (×2)
//   - Stacked BarChart with segment legend
//   - CalendarHeatmap (Sun-first, 5-step ladder)
//   - Sparkline
//   - Theme — every widget pulls its colors from one ColorScheme
//   - Layout — Column / Row / Padding / SizedBox / Expanded
//   - Focus / keyboard — Tab targets the chart, arrows scrub the cursor

import 'dart:async';
import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main() async {
  await runApp(
    const FleuryApp(title: 'Widget dashboard', home: DashboardApp()),
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.code.character == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}

/// The dashboard root. Exposed for the smoke test in
/// `test/dashboard_demo_test.dart`.
class DashboardApp extends StatefulWidget {
  const DashboardApp({super.key});
  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  static const _windowSize = 40; // samples kept on screen
  static const _tick = Duration(milliseconds: 500);

  final _rng = Random(42);
  final _chartFocus = FocusNode(debugLabel: 'line chart');

  Timer? _timer;
  bool _paused = false;

  // Rolling windows of (x, y) pairs for the LineChart.
  final List<(num, num)> _cpu = [];
  final List<(num, num)> _mem = [];

  // Current values for gauges / sparkline.
  double _diskPct = 0.62;
  double _netPct = 0.34;
  final List<num> _rps = List.filled(24, 0);

  // 8 weeks of synthetic incident counts for the calendar heatmap.
  late final Map<DateTime, num> _incidents;
  late final DateTime _calStart;
  late final DateTime _calEnd;

  // Services by status counts — for the stacked bar chart.
  final List<(String, List<num>)> _services = [
    ('web', [12, 3, 1]),
    ('api', [8, 5, 2]),
    ('db', [4, 2, 0]),
    ('queue', [6, 1, 1]),
    ('cache', [9, 1, 0]),
  ];

  int _t = 0;

  @override
  void initState() {
    super.initState();
    _seedSeries();
    _seedCalendar();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted || _paused) return;
      setState(_advance);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chartFocus.dispose();
    super.dispose();
  }

  void _seedSeries() {
    // Pre-fill so the chart starts with a populated window rather than
    // growing in from the left.
    for (var i = 0; i < _windowSize; i++) {
      _cpu.add((i, 40 + _rng.nextDouble() * 30));
      _mem.add((i, 55 + _rng.nextDouble() * 15));
    }
    _t = _windowSize;
  }

  void _seedCalendar() {
    // 8 weeks ending today.
    final today = DateTime.now();
    _calEnd = DateTime(today.year, today.month, today.day);
    _calStart = _calEnd.subtract(const Duration(days: 8 * 7 - 1));
    _incidents = {};
    var d = _calStart;
    while (!d.isAfter(_calEnd)) {
      // Sparse — mostly empty, occasional bursts.
      final r = _rng.nextDouble();
      if (r > 0.7) {
        _incidents[d] = (r * 4).round();
      } else if (r > 0.5) {
        _incidents[d] = 0; // recorded zero (renders as `·`)
      }
      d = d.add(const Duration(days: 1));
    }
  }

  void _advance() {
    _t += 1;
    // CPU oscillates with occasional spikes; memory drifts.
    final cpuNext =
        50 +
        30 * sin(_t / 6) +
        (_rng.nextDouble() - 0.5) * 10 +
        (_rng.nextDouble() > 0.95 ? 25 : 0); // occasional spike
    final memNext = (_mem.last.$2.toDouble() + (_rng.nextDouble() - 0.5) * 4)
        .clamp(20, 95);
    _cpu.add((_t, cpuNext.clamp(0, 100)));
    _mem.add((_t, memNext));
    if (_cpu.length > _windowSize) _cpu.removeAt(0);
    if (_mem.length > _windowSize) _mem.removeAt(0);

    _diskPct = (_diskPct + (_rng.nextDouble() - 0.5) * 0.02).clamp(0, 1);
    _netPct = (_netPct + (_rng.nextDouble() - 0.5) * 0.08).clamp(0, 1);

    _rps.removeAt(0);
    _rps.add(20 + _rng.nextDouble() * 60);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.space,
          label: _paused ? 'Resume' : 'Pause',
          onEvent: (_) => setState(() => _paused = !_paused),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(paused: _paused, time: DateTime.now()),
            const SizedBox(height: 1),
            // Top row: LineChart on the left, Gauges + Sparkline on the right.
            SizedBox(
              height: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _CpuMemPanel(
                      cpu: _cpu,
                      mem: _mem,
                      focusNode: _chartFocus,
                    ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 28,
                    child: _StatsPanel(
                      diskPct: _diskPct,
                      netPct: _netPct,
                      rps: _rps,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            // Middle row: stacked bar chart on the left, calendar on right.
            SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _ServicesPanel(services: _services)),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _CalendarPanel(
                      values: _incidents,
                      start: _calStart,
                      end: _calEnd,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: SizedBox()),
            _Footer(theme: theme),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.paused, required this.time});
  final bool paused;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    return Row(
      children: [
        Text(
          ' fleury dashboard ',
          style: CellStyle(
            bold: true,
            foreground: const AnsiColor(15),
            background: theme.colorScheme.primary,
          ),
        ),
        const Expanded(child: SizedBox()),
        if (paused)
          const Text(
            ' paused ',
            style: CellStyle(
              bold: true,
              foreground: AnsiColor(0),
              background: AnsiColor(3),
            ),
          ),
        const Text('  '),
        Text(
          '$hh:$mm:$ss',
          style: CellStyle(foreground: theme.colorScheme.info),
        ),
      ],
    );
  }
}

class _CpuMemPanel extends StatelessWidget {
  const _CpuMemPanel({
    required this.cpu,
    required this.mem,
    required this.focusNode,
  });
  final List<(num, num)> cpu;
  final List<(num, num)> mem;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('cpu / mem (tab to focus, ←→ to scrub)', style: theme.mutedStyle),
        Expanded(
          child: LineChart(
            series: [
              LineSeries(
                cpu,
                label: 'cpu',
                color: theme.colorScheme.primary,
                belowColor: theme.colorScheme.success,
                thresholdY: 80, // above 80%: color flips to the primary
              ),
              LineSeries(mem, label: 'mem', color: theme.colorScheme.warning),
            ],
            yRange: const (0, 100),
            // Data is already in 0..100; format as a plain percent
            // suffix. (TickFormat.percent would multiply by 100.)
            yTickFormat: (v) => '${v.round()}%',
            xTickFormat: (v) => '${v.round()}s',
            references: [
              ReferenceLine.horizontal(
                80,
                color: theme.colorScheme.error,
                label: 'SLA',
              ),
            ],
            showGrid: true,
            showLegend: true,
            interactive: true,
            focusNode: focusNode,
          ),
        ),
      ],
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({
    required this.diskPct,
    required this.netPct,
    required this.rps,
  });
  final double diskPct;
  final double netPct;
  final List<num> rps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('disk', style: theme.mutedStyle),
        SizedBox(
          height: 1,
          child: Gauge(value: diskPct, label: 'used'),
        ),
        const SizedBox(height: 1),
        Text('net', style: theme.mutedStyle),
        SizedBox(
          height: 1,
          child: Gauge(value: netPct, label: 'bw'),
        ),
        const SizedBox(height: 1),
        Text('req/s (last 24)', style: theme.mutedStyle),
        SizedBox(height: 1, child: Sparkline(data: rps, max: 100)),
        const Expanded(child: SizedBox()),
        // Current readouts as big digits for the disk %.
        SizedBox(
          height: 5,
          child: Center(
            child: Digits(
              '${(diskPct * 100).round()}'.padLeft(2, ' '),
              color: theme.colorScheme.info,
            ),
          ),
        ),
      ],
    );
  }
}

class _ServicesPanel extends StatelessWidget {
  const _ServicesPanel({required this.services});
  final List<(String, List<num>)> services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('services / hosts by state', style: theme.mutedStyle),
        Expanded(
          child: BarChart(
            bars: [
              for (final (name, counts) in services) Bar.stacked(name, counts),
            ],
            palette: Palettes.categorical,
            segmentLabels: const ['ok', 'warn', 'down'],
            barWidth: 3,
            gap: 2,
            showValues: true,
            showLegend: true,
          ),
        ),
      ],
    );
  }
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.values,
    required this.start,
    required this.end,
  });
  final Map<DateTime, num> values;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('incidents (last 8 weeks)', style: theme.mutedStyle),
        Expanded(
          child: CalendarHeatmap(
            start: start,
            end: end,
            values: values,
            color: theme.colorScheme.warning,
            cellWidth: 2,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      ' tab focus chart   ←→ crosshair   space pause   ctrl+c quit',
      style: theme.mutedStyle,
    );
  }
}
