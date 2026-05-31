// The actual UI of the debug panel. Subscribes to DebugEvents,
// keeps a small rolling buffer of recent frames, renders the Live
// metrics tab. Tab strip is there but the other tabs are placeholders
// in P0 — they slot in cleanly in P1 without changing this file's
// shape.

import 'dart:async';

import '../rendering/border.dart';
import '../rendering/cell.dart';
import '../rendering/edge_insets.dart';
import '../rendering/render_flex.dart' show CrossAxisAlignment, MainAxisSize;
import '../widgets/basic.dart';
import '../widgets/framework.dart';
import '../widgets/log_view.dart';
import 'debug_events.dart';
import 'debug_monitors.dart';
import 'debug_state.dart';

/// The debug panel content. Caller wraps in SizedBox / docking layout.
class DebugPanel extends StatefulWidget {
  const DebugPanel({super.key, required this.controller});
  final DebugController controller;

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  static const _historySize = 60;
  // Throttle panel rebuilds to ~10 fps regardless of how fast the
  // framework emits frames. Without this we'd loop: every FrameEvent
  // triggers setState → schedules a frame → emits another FrameEvent
  // → another setState. The framework happily runs that at full speed,
  // burning CPU in production and locking the test suite (the runTui
  // future can't drain because the event loop is saturated with
  // panel-triggered frames). 100ms is fast enough that humans can't
  // perceive the lag in the live counters; the underlying history
  // still captures every frame.
  static const _rebuildIntervalMs = 100;
  final List<FrameEvent> _history = <FrameEvent>[];
  StreamSubscription<DebugEvent>? _sub;
  int _lastRebuildMs = 0;

  @override
  void initState() {
    super.initState();
    _sub = DebugEvents.stream.listen((event) {
      if (event is! FrameDebugEvent) return;
      _history.add(event.frame);
      if (_history.length > _historySize) _history.removeAt(0);
      _maybeThrottledRebuild();
    });
    widget.controller.addListener(_rebuild);
    FleuryDebug.instance.addListener(_rebuild);
  }

  /// Rebuild only if [_rebuildIntervalMs] has passed since the last
  /// frame-event-driven rebuild. Controller / monitor changes still
  /// rebuild immediately via [_rebuild] — those are user-initiated
  /// and infrequent.
  void _maybeThrottledRebuild() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRebuildMs < _rebuildIntervalMs) return;
    _lastRebuildMs = now;
    _rebuild();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    FleuryDebug.instance.removeListener(_rebuild);
    _sub?.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      border: const BoxBorder(
        style: BorderStyle.single,
        cellStyle: CellStyle(foreground: RgbColor(120, 130, 150)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          _Header(controller: widget.controller),
          _TabStrip(controller: widget.controller),
          const Text(''),
          ..._tabBody(),
        ],
      ),
    );
  }

  List<Widget> _tabBody() {
    switch (widget.controller.tab) {
      case DebugTab.live:
        return _liveBody();
      case DebugTab.tree:
        return const [
          Text('Widget tree inspector — P1', style: CellStyle(dim: true)),
        ];
      case DebugTab.rebuilds:
        return const [Text('Rebuild stats — P1', style: CellStyle(dim: true))];
      case DebugTab.logs:
        // Captured stdout/stderr lives in the ambient LogBufferScope
        // installed by runTui; LogView wires itself to it.
        return const [Expanded(child: LogView())];
    }
  }

  List<Widget> _liveBody() {
    if (_history.isEmpty) {
      return const [
        Text('waiting for first frame…', style: CellStyle(dim: true)),
      ];
    }
    final latest = _history.last;
    // FPS = frames over last 1 second of wallclock-equivalent — but
    // since FrameEvent doesn't carry wallclock, approximate from
    // history length and total recent frame time.
    final fps = _approxFps();
    final avg = _avgTotal();
    final slow = _slowCount();

    return [
      _row('Frame', '#${latest.frameNumber}'),
      _row('Size', '${latest.bufferSize.cols}×${latest.bufferSize.rows}'),
      _row('FPS', fps.toStringAsFixed(0)),
      _row('Avg', _us(avg)),
      _row('Slow', '$slow/${_history.length} >16ms'),
      const Text(''),
      _phaseRow('Build ', latest.build, _history.map((f) => f.build)),
      _phaseRow('Layout', latest.layout, _history.map((f) => f.layout)),
      _phaseRow('Paint ', latest.paint, _history.map((f) => f.paint)),
      _phaseRow('Diff  ', latest.diff, _history.map((f) => f.diff)),
      const Text(''),
      _row('Dirty', '${latest.dirtyCells} cells'),
      const Text(''),
      Text(
        widget.controller.paintFlash
            ? '[p] paint-flash: ON'
            : '[p] paint-flash: off',
        style: const CellStyle(dim: true),
      ),
      ..._monitorRows(),
    ];
  }

  List<Widget> _monitorRows() {
    final monitors = FleuryDebug.instance.monitors;
    if (monitors.isEmpty) return const [];
    return [
      const Text(''),
      const Text('— monitors —', style: CellStyle(dim: true)),
      for (final m in monitors) _row(m.name, _safeEval(m.value)),
    ];
  }

  /// Calls a custom monitor's getter and stringifies it. Any throw is
  /// swallowed so a single buggy monitor can't crash the debug panel
  /// (it's the most-watched widget in the app — must stay rock-solid).
  String _safeEval(Object Function() get) {
    try {
      return get().toString();
    } on Object catch (e) {
      return '<error: $e>';
    }
  }

  double _approxFps() {
    if (_history.length < 2) return 0;
    final totalMicros = _history.fold<int>(
      0,
      (s, f) => s + f.total.inMicroseconds,
    );
    if (totalMicros == 0) return 0;
    final avgMicros = totalMicros / _history.length;
    return 1e6 / avgMicros;
  }

  Duration _avgTotal() {
    final totalMicros = _history.fold<int>(
      0,
      (s, f) => s + f.total.inMicroseconds,
    );
    return Duration(microseconds: totalMicros ~/ _history.length);
  }

  int _slowCount() =>
      _history.where((f) => f.total.inMicroseconds > 16000).length;

  Widget _row(String label, String value) {
    return Text('$label  $value');
  }

  /// One phase line: `Label  3.2ms ▁▂▃▄▅▆▇█` — color the value red
  /// when over budget (~4ms is a reasonable per-phase ceiling at 60fps
  /// since the four phases share a 16ms total).
  Widget _phaseRow(String label, Duration latest, Iterable<Duration> series) {
    final ms = latest.inMicroseconds / 1000;
    final overBudget = ms > 4.0;
    final spark = _sparkline(series.map((d) => d.inMicroseconds).toList());
    return Text(
      '$label ${_us(latest).padLeft(7)} $spark',
      style: overBudget
          ? const CellStyle(foreground: RgbColor(255, 120, 120))
          : CellStyle.empty,
    );
  }

  static String _us(Duration d) {
    final ms = d.inMicroseconds / 1000;
    return '${ms.toStringAsFixed(ms < 10 ? 1 : 0)}ms';
  }

  /// 8-level braille-style sparkline. Empty when series is empty.
  static String _sparkline(List<int> values) {
    if (values.isEmpty) return '';
    const blocks = ' ▁▂▃▄▅▆▇█';
    final maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV == 0) return blocks[0] * values.length;
    final buf = StringBuffer();
    for (final v in values) {
      final idx = ((v / maxV) * (blocks.length - 1)).round();
      buf.write(blocks[idx]);
    }
    return buf.toString();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final DebugController controller;

  @override
  Widget build(BuildContext context) {
    final hint = controller.mode == DebugMode.fullscreen
        ? 'Esc: dock | Ctrl+G: close'
        : 'F11: expand | Ctrl+G: close';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('FLEURY DEBUG', style: CellStyle(bold: true)),
        Text(hint, style: const CellStyle(dim: true)),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.controller});
  final DebugController controller;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (final tab in DebugTab.values) {
      final selected = tab == controller.tab;
      cells.add(
        Text(
          ' ${_label(tab)} ',
          style: selected
              ? const CellStyle(
                  foreground: RgbColor(0, 0, 0),
                  background: RgbColor(120, 200, 255),
                  bold: true,
                )
              : const CellStyle(dim: true),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: cells);
  }

  String _label(DebugTab tab) {
    switch (tab) {
      case DebugTab.live:
        return 'Live';
      case DebugTab.tree:
        return 'Tree';
      case DebugTab.rebuilds:
        return 'Rebuilds';
      case DebugTab.logs:
        return 'Logs';
    }
  }
}
