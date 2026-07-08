import 'dart:math' as math;

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'scaffold.dart';

/// A hands-on tour of Fleury's built-in debug shell. Each scenario button
/// *simulates* a situation the shell was built to diagnose — a janky frame, an
/// uncaught error, a burst of logs, a continuously-repainting region — so you
/// can trigger one and watch the matching tab light up. Press **Ctrl+G** to
/// open the shell (docked debug panel), then activate a scenario. (F12 is a
/// Logs-tab shortcut, but macOS reserves the function keys, so Ctrl+G is the
/// reliable toggle.)
///
/// Every trigger is a plain [Button], so its role/label reach the semantic tree
/// — which makes this app the agent-devtools dogfood too. Point `fleury mcp` at
/// it and an agent can `invoke_action` a scenario, then `read_errors` /
/// `read_frames` / `read_logs` to see what it just caused: your AI reading your
/// debugger while it drives the app.
///
/// Browser-safe (no `dart:io`), so it runs in a terminal or over `fleury serve`
/// — though the in-terminal shell (Ctrl+G) is where the payoff shows today.
class DebugPlaygroundApp extends StatelessWidget {
  const DebugPlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _DebugPlaygroundBody());
}

class _DebugPlaygroundBody extends StatefulWidget {
  const _DebugPlaygroundBody();

  @override
  State<_DebugPlaygroundBody> createState() => _DebugPlaygroundBodyState();
}

class _DebugPlaygroundBodyState extends State<_DebugPlaygroundBody>
    with SingleTickerProviderStateMixin {
  // Tallies so the app gives immediate in-pane feedback — you see *something*
  // happened even before opening the shell (and it's what a browser session
  // sees until the DT4 browser panel lands).
  int _errors = 0;
  int _logBursts = 0;
  int _janks = 0;
  String _lastAction = 'nothing yet — pick a scenario';

  // One-shot flag: the next build burns ~120 ms so exactly one frame is slow.
  bool _jankNextFrame = false;

  // Continuous-repaint scenario + the forced-rebuild storm, both driven by the
  // ticker. The ticker only runs while one of them is active, so an idle
  // playground stays quiet and the scenarios you trigger stand out.
  bool _streaming = false;
  int _streamTick = 0;
  int _stormRemaining = 0;
  int _rebuildStorms = 0;
  Ticker? _ticker;
  int _lastStreamMs = 0;

  // Visible manifestations so a running scenario shows a CAUSE in the pane, not
  // just an effect in the shell's tabs: a scrolling signal for the stream, a
  // filling bar + spinner for the storm.
  static const _waveWidth = 18;
  static const _blocks = <String>[' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
  static const _spinner = <String>['◐', '◓', '◑', '◒'];
  final List<int> _wave = <int>[];
  double _wavePhase = 0;
  int _spin = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The ticker needs the TuiBinding runApp installs; a headless test tree has
    // none, so there the playground just renders its initial frame.
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var changed = false;
    if (_stormRemaining > 0) {
      _stormRemaining--; // one forced rebuild per frame → a visible burst
      _spin = (_spin + 1) % _spinner.length;
      changed = true;
    }
    if (_streaming) {
      // A new signal sample every tick (~30/s) → a smooth scrolling waveform.
      _wavePhase += 0.6;
      _wave.add((((math.sin(_wavePhase) + 1) / 2) * 8).round());
      while (_wave.length > _waveWidth) _wave.removeAt(0);
      final ms = elapsed.inMilliseconds;
      if (ms - _lastStreamMs >= 100) {
        _lastStreamMs = ms;
        _streamTick++; // the semantic "update" count (~10/s)
      }
      changed = true;
    }
    if (changed) setState(() {});
    if (!_streaming && _stormRemaining == 0) _ticker?.stop();
  }

  void _ensureTicking() {
    final t = _ticker;
    if (t != null && !t.isActive && (_streaming || _stormRemaining > 0)) {
      t.start();
    }
  }

  // --- scenarios ------------------------------------------------------------

  void _spikeSlowFrame() => setState(() {
    _janks++;
    _jankNextFrame = true;
    _lastAction = 'spiked a slow frame → see the Live tab (build µs)';
  });

  void _throwInHandler() {
    _errors++;
    _lastAction = 'threw in a handler → see the Errors tab (caught, not fatal)';
    // Uncaught on purpose: runApp's per-boundary error containment reports it
    // to the Errors tab and keeps rendering, rather than tearing down.
    throw StateError('debug playground: simulated handler failure #$_errors');
  }

  void _emitLogBurst() => setState(() {
    _logBursts++;
    for (var i = 1; i <= 40; i++) {
      print('[playground] log burst #$_logBursts line $i/40');
    }
    _lastAction =
        'emitted 40 log lines → see the Logs tab '
        '(fleury also fd-captures native/library output)';
  });

  void _toggleStream() => setState(() {
    _streaming = !_streaming;
    if (_streaming) {
      // Reset the cadence clock: Ticker.start() zeroes `elapsed`, so a stale
      // _lastStreamMs from a previous run would freeze the stream until elapsed
      // climbed back past it (seconds of dead air after a stop/restart).
      _lastStreamMs = 0;
    } else {
      _wave.clear();
    }
    _lastAction = _streaming
        ? 'streaming ~10 updates/s → watch Live: FPS climbs off 0, cadence holds'
        : 'streaming off';
    _ensureTicking();
  });

  void _rebuildStorm() => setState(() {
    _stormRemaining = 120;
    _rebuildStorms++;
    _lastAction = 'forced 120 rebuilds → see the Rebuilds tab';
    _ensureTicking();
  });

  // --- ui -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // One deliberately slow frame: burn CPU in the build phase so the shell's
    // Live tab records a spiked build time, then clear the one-shot flag (no
    // rebuild needed — the next frame is normal again).
    if (_jankNextFrame) {
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < 120) {
        // busy-wait — intentionally janky
      }
      _jankNextFrame = false;
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _topBar(theme),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(flex: 2, child: _scenarioPanel(theme)),
              const SizedBox(width: 1),
              Expanded(flex: 3, child: _readoutPanel(theme)),
            ],
          ),
        ),
        const SizedBox(height: 1),
        _footer(theme),
      ],
    );
  }

  Widget _topBar(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    return Row(
      children: <Widget>[
        Text('▌ ', style: CellStyle(foreground: accent)),
        Text(
          'Fleury Debug Playground',
          style: CellStyle(bold: true, foreground: accent),
        ),
        const Expanded(child: SizedBox.shrink()),
        Text(
          'press Ctrl+G to open the debug shell',
          style: CellStyle(foreground: theme.colorScheme.info),
        ),
        Text('   ', style: theme.mutedStyle),
      ],
    );
  }

  Widget _scenarioPanel(ThemeData theme) {
    // Arrows move focus between these buttons via the root FocusTraversalGroup
    // that runApp installs — no per-container group needed here. Tab/Shift+Tab
    // traverse too; a list or text field still owns its own arrows (they bubble
    // to traversal only when the focused widget doesn't consume them).
    return Panel(
      title: 'Scenarios',
      trailing: Text('↑↓ / Tab · Enter', style: theme.mutedStyle),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _scenario(
            theme,
            Button(
              label: 'Spike a slow frame',
              variant: ButtonVariant.warning,
              autofocus: true,
              onPressed: _spikeSlowFrame,
            ),
            'burns ~120ms in build → Live: build µs spikes',
          ),
          _scenario(
            theme,
            Button(
              label: 'Throw in a handler',
              variant: ButtonVariant.error,
              onPressed: _throwInHandler,
            ),
            'throws (caught) → Errors: logged, app keeps running',
          ),
          _scenario(
            theme,
            Button(label: 'Emit a log burst', onPressed: _emitLogBurst),
            'prints 40 lines → Logs: press / to search',
          ),
          _scenario(
            theme,
            Button(
              label: _streaming ? 'Stop live stream' : 'Toggle live stream',
              variant: ButtonVariant.success,
              onPressed: _toggleStream,
            ),
            '~10 updates/s → Live: FPS climbs off 0',
          ),
          _scenario(
            theme,
            Button(
              label: 'Rebuild storm',
              variant: ButtonVariant.primary,
              onPressed: _rebuildStorm,
            ),
            '120 forced rebuilds → Rebuilds: invalidation count',
          ),
        ],
      ),
    );
  }

  // Each scenario stacks its trigger over a one-line hint, so a narrow panel
  // never truncates the hint the way a side-by-side row would.
  Widget _scenario(ThemeData theme, Widget button, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        button,
        Text('   $hint', style: theme.mutedStyle),
        const SizedBox(height: 1),
      ],
    );
  }

  Widget _readoutPanel(ThemeData theme) {
    return Panel(
      title: 'What just happened',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Last action', style: theme.mutedStyle),
          Text(
            _lastAction,
            style: CellStyle(foreground: theme.colorScheme.info),
          ),
          const SizedBox(height: 1),
          Text(
            'Live activity  (the cause — watch the shell for the effect)',
            style: theme.mutedStyle,
          ),
          _activityStrip(theme),
          const SizedBox(height: 1),
          _stat(theme, 'errors thrown', _errors),
          _stat(theme, 'log bursts', _logBursts),
          _stat(theme, 'slow frames', _janks),
          _stat(theme, 'rebuild storms', _rebuildStorms),
          const SizedBox(height: 1),
          Text('Where to look', style: theme.mutedStyle),
          Text(
            'Ctrl+G opens the shell (F12 jumps to Logs, when macOS lets it '
            'through) — Tab cycles Live · Rebuilds · Logs · Errors · Tree. '
            'The Tree tab is the semantic view an agent reads over fleury '
            'mcp; it can invoke these same buttons, then read_errors / '
            'read_frames / read_logs to see what it caused.',
            style: theme.mutedStyle,
          ),
        ],
      ),
    );
  }

  // The continuous scenarios made visible: a scrolling signal while streaming,
  // a filling bar + spinner while the storm churns, quiet when idle. Pair this
  // (the cause) with the shell's Live / Rebuilds tabs (the effect).
  Widget _activityStrip(ThemeData theme) {
    if (_streaming) {
      final signal = [for (final h in _wave) _blocks[h.clamp(0, 8)]].join();
      return Row(
        children: <Widget>[
          Text(
            signal.padRight(_waveWidth),
            style: CellStyle(foreground: theme.colorScheme.success),
          ),
          Text('  ◐ streaming · tick $_streamTick', style: theme.mutedStyle),
        ],
      );
    }
    if (_stormRemaining > 0) {
      final done = 120 - _stormRemaining;
      final filled = (done / 120 * _waveWidth).round().clamp(0, _waveWidth);
      final bar = '█' * filled + '░' * (_waveWidth - filled);
      return Row(
        children: <Widget>[
          Text(bar, style: CellStyle(foreground: theme.colorScheme.primary)),
          Text(
            '  ${_spinner[_spin]} rebuilding · $done/120',
            style: theme.mutedStyle,
          ),
        ],
      );
    }
    return Text('· idle · trigger a scenario', style: theme.mutedStyle);
  }

  Widget _stat(ThemeData theme, String label, int value) =>
      _statText(theme, label, value.toString());

  Widget _statText(ThemeData theme, String label, String value) {
    return Row(
      children: <Widget>[
        Text(label.padRight(16), style: theme.mutedStyle),
        Text(value, style: CellStyle(foreground: theme.colorScheme.primary)),
      ],
    );
  }

  Widget _footer(ThemeData theme) {
    return Text(
      ' Ctrl+G debug shell · ↑↓/Tab move · Enter run · q quit · '
      'drive me: fleury mcp -> invoke_action',
      style: theme.mutedStyle,
    );
  }
}
