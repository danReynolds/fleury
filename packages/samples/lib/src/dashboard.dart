import 'dart:math';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'scaffold.dart';

/// An htop-style live system dashboard built entirely from Fleury widgets:
/// per-core CPU gauges, a streaming history chart, memory/swap/IO meters, and a
/// live, sortable process table. The data is synthetic (a bounded random walk)
/// so the demo runs identically in a terminal or in the browser over
/// `fleury serve` — no host system access required.
class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _DashboardBody());
}

class _DashboardBody extends StatefulWidget {
  const _DashboardBody();

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody>
    with SingleTickerProviderStateMixin {
  final _Metrics _metrics = _Metrics();
  final DataTableController _table = DataTableController();
  Ticker? _ticker;
  int _lastFastMs = 0;
  int _lastTableMs = 0;

  // Decoupled refresh cadences. Graphs and meters scroll smoothly at ~11 Hz;
  // the process table refreshes ~1 Hz so its rows stay readable instead of
  // jittering. (One frame renders in ~0.6 ms — ~50x under a 30 Hz budget — so
  // the cadence, not the renderer, is what governs how alive this feels.)
  static const int _fastMs = 90;
  static const int _tableMs = 1100;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The ticker needs the TuiBinding that runApp installs; a headless test
    // tree has none, so the dashboard simply renders its initial frame there.
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _table.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    var changed = false;
    if (ms - _lastFastMs >= _fastMs) {
      _lastFastMs = ms;
      _metrics.advanceFast();
      changed = true;
    }
    if (ms - _lastTableMs >= _tableMs) {
      _lastTableMs = ms;
      _metrics.advanceTable();
      changed = true;
    }
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _topBar(theme),
        const SizedBox(height: 1),
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _cpuPanel(theme)),
              const SizedBox(width: 1),
              Expanded(child: _memPanel(theme)),
              const SizedBox(width: 1),
              Expanded(flex: 2, child: _historyPanel(theme)),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Expanded(flex: 6, child: _processPanel(theme)),
        const SizedBox(height: 1),
        _footer(theme),
      ],
    );
  }

  Widget _topBar(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    final load = _metrics.loadAvg.map((v) => v.toStringAsFixed(2)).join(' ');
    return Row(
      children: <Widget>[
        Text('▌ ', style: CellStyle(foreground: accent)),
        Text(
          'Fleury System Monitor',
          style: CellStyle(bold: true, foreground: accent),
        ),
        const Expanded(child: SizedBox.shrink()),
        Text('load $load   ', style: theme.mutedStyle),
        Text('up ${_metrics.uptime}   ', style: theme.mutedStyle),
        Text(
          _metrics.clock,
          style: CellStyle(foreground: theme.colorScheme.info),
        ),
      ],
    );
  }

  Widget _cpuPanel(ThemeData theme) {
    return Panel(
      title: 'CPU',
      trailing: Text(
        '${(_metrics.cpuAvg * 100).round()}%',
        style: theme.mutedStyle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < _metrics.cores.length; i++)
            Gauge(
              value: _metrics.cores[i],
              label: i.toString().padLeft(2),
              thresholds: <(double, Color)>[
                (0.7, theme.colorScheme.warning),
                (0.9, theme.colorScheme.error),
              ],
            ),
        ],
      ),
    );
  }

  Widget _memPanel(ThemeData theme) {
    final m = _metrics;
    return Panel(
      title: 'Memory & I/O',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Gauge(
            value: m.mem,
            label: 'Mem',
            thresholds: <(double, Color)>[
              (0.8, theme.colorScheme.warning),
              (0.92, theme.colorScheme.error),
            ],
          ),
          Text(
            '  ${_gb(m.mem, m.memTotalGb)} / ${m.memTotalGb.toStringAsFixed(0)} GB',
            style: theme.mutedStyle,
          ),
          const SizedBox(height: 1),
          Gauge(value: m.swap, label: 'Swp', color: theme.colorScheme.info),
          Text(
            '  ${_gb(m.swap, m.swapTotalGb)} / ${m.swapTotalGb.toStringAsFixed(0)} GB',
            style: theme.mutedStyle,
          ),
          const SizedBox(height: 1),
          _ioRow(theme, 'Net ↓', m.netRx, theme.colorScheme.success),
          _ioRow(theme, 'Net ↑', m.netTx, theme.colorScheme.info),
          _ioRow(theme, 'Disk ', m.disk, theme.colorScheme.warning),
        ],
      ),
    );
  }

  Widget _ioRow(ThemeData theme, String label, List<num> series, Color color) {
    return Row(
      children: <Widget>[
        Text('$label ', style: theme.mutedStyle),
        Expanded(
          child: Sparkline(data: series, color: color, showValue: true),
        ),
      ],
    );
  }

  Widget _historyPanel(ThemeData theme) {
    return Panel(
      title: 'CPU / Mem history (%)',
      child: LineChart(
        series: <LineSeries>[
          LineSeries(
            _metrics.points(_metrics.cpuHist),
            label: 'cpu',
            color: theme.colorScheme.primary,
          ),
          LineSeries(
            _metrics.points(_metrics.memHist),
            label: 'mem',
            color: theme.colorScheme.info,
          ),
        ],
        yRange: const (0, 100),
        showAxes: true,
        showLegend: true,
        yTickCount: 5,
      ),
    );
  }

  Widget _processPanel(ThemeData theme) {
    return Panel(
      title: 'Processes',
      trailing: Text(
        '${_metrics.procs.length} tasks · sorted by CPU%',
        style: theme.mutedStyle,
      ),
      child: DataTable(
        rowCount: _metrics.procs.length,
        controller: _table,
        autofocus: true,
        selectionMode: DataTableSelectionMode.row,
        columns: const <DataTableColumn>[
          DataTableColumn(id: 'pid', title: 'PID', width: FixedColumnWidth(7)),
          DataTableColumn(
            id: 'user',
            title: 'USER',
            width: FixedColumnWidth(9),
          ),
          DataTableColumn(id: 'cpu', title: 'CPU%', width: FixedColumnWidth(6)),
          DataTableColumn(id: 'mem', title: 'MEM%', width: FixedColumnWidth(6)),
          DataTableColumn(
            id: 'time',
            title: 'TIME',
            width: FixedColumnWidth(8),
          ),
          DataTableColumn(id: 'cmd', title: 'COMMAND'),
        ],
        cellBuilder: (row, columnId) {
          final p = _metrics.procs[row];
          return switch (columnId) {
            'pid' => p.pid.toString(),
            'user' => p.user,
            'cpu' => p.cpu.toStringAsFixed(1),
            'mem' => p.mem.toStringAsFixed(1),
            'time' => _hms(p.timeSec),
            _ => p.command,
          };
        },
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Text(
      ' q quit   ↑/↓ select process   live · synthetic metrics',
      style: theme.mutedStyle,
    );
  }
}

String _gb(double fraction, double totalGb) =>
    (fraction * totalGb).toStringAsFixed(1).padLeft(4);

String _hms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

// ---------------------------------------------------------------------------
// Synthetic metric model — a bounded random walk that looks like a live host.
// ---------------------------------------------------------------------------

class _Proc {
  _Proc(this.pid, this.user, this.command, this.cpu, this.mem, this.timeSec);
  final int pid;
  final String user;
  final String command;
  double cpu;
  double mem;
  int timeSec;
}

class _Metrics {
  _Metrics() {
    cores = List<double>.generate(8, (i) => 0.15 + _r.nextDouble() * 0.4);
    procs = _seedProcesses();
    // Pre-fill the history windows so the graphs start populated, not empty.
    for (var i = 0; i < _window; i++) {
      _netRxV = _walk(_netRxV / 60, 0.08, 0, 1) * 60;
      _netTxV = _walk(_netTxV / 30, 0.08, 0, 1) * 30;
      _diskV = _walk(_diskV / 45, 0.08, 0, 1) * 45;
      cpuHist.add(cpuAvg * 100);
      memHist.add(mem * 100);
      netRx.add(_netRxV);
      netTx.add(_netTxV);
      disk.add(_diskV);
    }
  }

  static const int _window = 56;
  final Random _r = Random(7);
  late List<double> cores;
  double mem = 0.62;
  double swap = 0.08;
  double _netRxV = 18;
  double _netTxV = 9;
  double _diskV = 16;
  final double memTotalGb = 16;
  final double swapTotalGb = 4;
  final List<num> cpuHist = <num>[];
  final List<num> memHist = <num>[];
  final List<num> netRx = <num>[];
  final List<num> netTx = <num>[];
  final List<num> disk = <num>[];
  final List<double> loadAvg = <double>[1.24, 0.98, 0.71];
  late List<_Proc> procs;
  final DateTime _boot = DateTime.now().subtract(
    const Duration(days: 3, hours: 4, minutes: 12),
  );

  double get cpuAvg => cores.fold<double>(0, (a, b) => a + b) / cores.length;

  String get clock {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  String get uptime {
    final d = DateTime.now().difference(_boot);
    final days = d.inDays;
    final hours = d.inHours % 24;
    return days > 0 ? '${days}d ${hours}h' : '${hours}h ${d.inMinutes % 60}m';
  }

  /// Maps a value history into `(x, y)` points for [LineChart].
  List<(num, num)> points(List<num> history) => <(num, num)>[
    for (var i = 0; i < history.length; i++) (i, history[i]),
  ];

  // ~11 Hz: the smoothly-scrolling graphs and meters. Steps are small so the
  // walk stays organic at this rate rather than thrashing.
  void advanceFast() {
    for (var i = 0; i < cores.length; i++) {
      cores[i] = _walk(cores[i], 0.05, 0.02, 0.99);
    }
    mem = _walk(mem, 0.008, 0.25, 0.95);
    swap = _walk(swap, 0.005, 0, 0.6);
    _netRxV = _walk(_netRxV / 60, 0.07, 0, 1) * 60;
    _netTxV = _walk(_netTxV / 30, 0.07, 0, 1) * 30;
    _diskV = _walk(_diskV / 45, 0.07, 0, 1) * 45;
    _push(cpuHist, cpuAvg * 100);
    _push(memHist, mem * 100);
    _push(netRx, _netRxV);
    _push(netTx, _netTxV);
    _push(disk, _diskV);
    for (var i = 0; i < loadAvg.length; i++) {
      loadAvg[i] = _walk(loadAvg[i] / 4, 0.015, 0, 1) * 4;
    }
  }

  // ~1 Hz: process churn. Slower so rows don't jitter or re-sort every frame.
  void advanceTable() {
    for (final p in procs) {
      p.cpu = _walk(p.cpu / 100, 0.25, 0, 1) * 100;
      p.mem = _walk(p.mem / 100, 0.03, 0, 1) * 100;
      p.timeSec += 1;
    }
    procs.sort((a, b) => b.cpu.compareTo(a.cpu));
  }

  double _walk(double v, double step, double lo, double hi) =>
      (v + (_r.nextDouble() * 2 - 1) * step).clamp(lo, hi).toDouble();

  void _push(List<num> series, num value) {
    series.add(value);
    if (series.length > _window) series.removeAt(0);
  }

  List<_Proc> _seedProcesses() {
    const seeds = <(String, String)>[
      ('dan', 'fleury serve --port 4000'),
      ('dan', 'dart run packages/storybook/bin/storybook.dart'),
      ('dan', 'Code Helper (Renderer)'),
      ('dan', 'Chrome Helper (GPU)'),
      ('root', 'kernel_task'),
      ('_windowserver', 'WindowServer'),
      ('dan', 'node esbuild-service'),
      ('dan', 'zsh'),
      ('dan', 'ssh dan@build-01'),
      ('postgres', 'postgres: writer process'),
      ('dan', 'redis-server *:6379'),
      ('root', 'launchd'),
      ('dan', 'docker-proxy'),
      ('_spotlight', 'mds_stores'),
      ('dan', 'rg --json fleury'),
      ('dan', 'dart analyze packages/fleury'),
      ('root', 'syslogd'),
      ('dan', 'tmux: server'),
      ('dan', 'git status'),
      ('dan', 'htop'),
      ('dan', 'python3 -m http.server'),
      ('root', 'coreaudiod'),
      ('dan', 'fleury serve worker[2]'),
      ('dan', 'fleury serve worker[1]'),
    ];
    var pid = 412;
    return <_Proc>[
      for (final (user, cmd) in seeds)
        _Proc(
          pid += 137 + _r.nextInt(900),
          user,
          cmd,
          _r.nextDouble() * 35,
          _r.nextDouble() * 8,
          _r.nextInt(48 * 3600),
        ),
    ]..sort((a, b) => b.cpu.compareTo(a.cpu));
  }
}
