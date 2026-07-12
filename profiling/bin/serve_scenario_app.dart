// Animated runApp scenarios for the live serve-wire profiler
// (serve_wire_live_profile.dart). `fleury serve --spawn` launches this as a
// per-session subprocess; runApp auto-wires the remote driver from
// $FLEURY_HANDLE, so every frame it produces streams over the real serve wire
// (app → serve → WebSocket → the profiler's headless client).
//
// The app ticks `--steps` times at `--interval-ms`, then stops (idles) — the
// profiler controls the session lifetime and tears serve down when it has
// captured the run.
//
// `input-latency` is the exception: it never ticks on its own. It idles until
// a key arrives over the wire, and every keystroke deterministically changes
// visible content (a fixed-width fill line plus a zero-padded key counter),
// so one INPUT_EVENT produces exactly one PLAN frame — the closed-loop
// input→paint latency probe (G4) depends on that 1:1 mapping.
//
//   serve_scenario_app.dart <scenario> [--steps=N] [--interval-ms=M]
//     scenario: dashboard | log | counter | input-latency

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main(List<String> args) async {
  final scenario = args.isNotEmpty && !args.first.startsWith('--')
      ? args.first
      : 'dashboard';
  var steps = 120;
  var intervalMs = 16;
  for (final arg in args) {
    if (arg.startsWith('--steps=')) {
      steps = int.parse(arg.substring('--steps='.length));
    } else if (arg.startsWith('--interval-ms=')) {
      intervalMs = int.parse(arg.substring('--interval-ms='.length));
    }
  }
  await runApp(
    _ScenarioApp(
      scenario: scenario,
      steps: steps,
      interval: Duration(milliseconds: intervalMs),
    ),
  );
}

final class _ScenarioApp extends StatefulWidget {
  const _ScenarioApp({
    required this.scenario,
    required this.steps,
    required this.interval,
  });

  final String scenario;
  final int steps;
  final Duration interval;

  @override
  State<_ScenarioApp> createState() => _ScenarioAppState();
}

class _ScenarioAppState extends State<_ScenarioApp> {
  Timer? _timer;
  var _tick = 0;
  var _keys = 0;
  late List<num> _history;

  @override
  void initState() {
    super.initState();
    _history = List<num>.generate(48, (i) => 40 + i % 17);
    // input-latency is input-driven, never time-driven: any self-ticking
    // would produce PLAN frames a keystroke didn't cause and break the
    // probe's one-key ⟹ one-plan accounting.
    if (widget.scenario == 'input-latency') return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (_tick >= widget.steps) {
        _timer?.cancel();
        return;
      }
      setState(() {
        _tick++;
        final next = 20 + ((_tick * 13) % 80);
        _history = <num>[..._history.skip(1), next];
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (widget.scenario) {
    'log' => _buildLog(),
    'counter' => _buildCounter(),
    'input-latency' => _buildInputLatency(),
    _ => _buildDashboard(),
  };

  // A dashboard mirroring SB.6's widget vocabulary: gauges, a sparkline, a bar
  // chart, and variable-width status lines — a realistic served workload.
  Widget _buildDashboard() {
    final cpu = ((_tick * 17) % 100) / 100;
    final mem = ((_tick * 29 + 15) % 100) / 100;
    final disk = ((_tick * 7 + 30) % 100) / 100;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('serve dashboard tick=$_tick active=${20 + (_tick * 7) % 900}',
              softWrap: false),
          const SizedBox(height: 1),
          Row(
            children: [
              SizedBox(width: 36, child: Gauge(value: cpu, label: 'CPU')),
              const SizedBox(width: 2),
              SizedBox(width: 36, child: Gauge(value: mem, label: 'MEM')),
              const SizedBox(width: 2),
              SizedBox(width: 36, child: Gauge(value: disk, label: 'IO')),
            ],
          ),
          const SizedBox(height: 1),
          SizedBox(width: 76, child: Sparkline(data: _history, max: 100)),
          const SizedBox(height: 1),
          SizedBox(
            height: 8,
            child: BarChart(
              bars: [
                Bar('api', (_tick * 3) % 100),
                Bar('cli', (_tick * 5 + 10) % 100),
                Bar('ui', (_tick * 7 + 20) % 100),
                Bar('io', (_tick * 11 + 30) % 100),
                Bar('net', (_tick * 13 + 40) % 100),
              ],
              showValues: false,
            ),
          ),
          const SizedBox(height: 1),
          for (final line in _statusLines())
            Text(line, softWrap: false, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Iterable<String> _statusLines() sync* {
    for (var i = 0; i < 10; i++) {
      final id = (_tick * 10 + i) % 100000;
      final status = switch ((id + _tick) % 5) {
        0 => 'queued',
        1 => 'running',
        2 => 'passed',
        3 => 'failed',
        _ => 'blocked',
      };
      yield 'RUN-${id.toString().padLeft(6, '0')} $status shard=${id % 31} '
          'owner=worker-${id % 17} latency=${20 + id % 900}ms';
    }
  }

  // A scrolling log tail: distinct content per line each frame.
  Widget _buildLog() {
    const words = [
      'connect', 'GET /api/v2/users', 'cache miss', 'retry backoff',
      'flush wal', 'commit txn', 'timeout', 'parse json', 'spawn worker',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < 24; r++)
          Text(
            () {
              final n = _tick + r;
              return '${n.toString().padLeft(6)} ${(n * 31) % 99999} '
                  '${words[(n * 7) % words.length]} shard=${n % 64} '
                  'lat=${(n * 13) % 900}ms';
            }(),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  // Idle until a key arrives; each keystroke changes exactly one frame's
  // worth of content, deterministically. The fill line is FIXED-WIDTH (64
  // cells, one glyph appended per key, wrapping) and the counter is
  // zero-padded, so layout never shifts and the frame a key produces is a
  // pure function of how many keys came before it — the byte axes stay
  // comparable run to run. Every key is handled (and repaints), so a missing
  // PLAN response means the input path itself broke, not the scenario.
  Widget _buildInputLatency() {
    const width = 64;
    final filled = _keys % width;
    return Focus(
      autofocus: true,
      onKey: (event) {
        setState(() => _keys++);
        return KeyEventResult.handled;
      },
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('input-latency probe'),
            const SizedBox(height: 1),
            Text('keys=${_keys.toString().padLeft(6, '0')}'),
            Text(('#' * filled).padRight(width, '.'), softWrap: false),
          ],
        ),
      ),
    );
  }

  // A single changing field — the sparse-update lower bound.
  Widget _buildCounter() => Padding(
    padding: const EdgeInsets.all(2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('counter'),
        const SizedBox(height: 1),
        Text('Count: ${_tick % 1000}'),
      ],
    ),
  );
}
