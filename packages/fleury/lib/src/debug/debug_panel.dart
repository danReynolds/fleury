// The actual UI of the debug panel. Subscribes to DebugEvents,
// keeps a small rolling buffer of recent frames, renders the Live
// metrics tab. Tab strip is there but the other tabs are placeholders
// in P0 — they slot in cleanly in P1 without changing this file's
// shape.

import 'dart:async';

import '../animation/clock.dart';
import '../foundation/geometry.dart';
import '../rendering/border.dart';
import '../rendering/cell.dart';
import '../rendering/edge_insets.dart';
import '../rendering/render_flex.dart' show CrossAxisAlignment, MainAxisSize;
import '../rendering/render_layout_stats.dart';
import '../rendering/render_objects.dart' show TextOverflow;
import '../rendering/render_repaint_boundary.dart';
import '../rendering/text_sanitizer.dart';
import '../runtime/output_capture.dart';
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import '../terminal/diagnostics.dart';
import '../widgets/basic.dart';
import '../widgets/framework.dart';
import '../widgets/layout_builder.dart';
import '../widgets/output_capture_view.dart';
import '../widgets/pointer.dart';
import '../widgets/rich_text.dart';
import '../widgets/theme.dart';
import 'debug_events.dart';
import 'debug_monitors.dart';
import 'debug_state.dart';

/// The debug panel content. Caller wraps in SizedBox / docking layout.
class DebugPanel extends StatefulWidget {
  const DebugPanel({
    super.key,
    required this.controller,
    this.clock = const SystemClock(),
  });

  final DebugController controller;

  /// Time source for the FPS window, rebuild throttle, and frame stamps.
  /// Injectable so the wallclock-derived metrics are deterministically
  /// testable (a FakeClock pins "frames in the last second" exactly);
  /// production uses the monotonic [SystemClock].
  final Clock clock;

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  static const _historySize = 60;
  // Throttle panel rebuilds to ~10 fps regardless of how fast the
  // framework emits frames. Without this we'd loop: every FrameEvent
  // triggers setState → schedules a frame → emits another FrameEvent
  // → another setState. The framework happily runs that at full speed,
  // burning CPU in production and locking the test suite (the runApp
  // future can't drain because the event loop is saturated with
  // panel-triggered frames). 100ms is fast enough that humans can't
  // perceive the lag in the live counters; the underlying history
  // still captures every frame.
  static const _rebuildIntervalMs = 100;
  final List<FrameEvent> _history = <FrameEvent>[];
  // Wallclock receipt times (ms) of frames in the last second — the basis for a
  // REAL fps (frames actually rendered per second). Distinct from 1/avg-frame-
  // time, which is per-frame headroom and reads ~200 even on an idle app.
  final List<int> _frameStamps = <int>[];
  // Trailing decay: the panel only rebuilds on frame events, so after the app
  // goes idle the FPS row would freeze at its last value. One trailing rebuild
  // ~1.2s after the last frame repaints it at 0. The flag marks that decay
  // rebuild's OWN frame so its event doesn't re-arm the timer — the panel
  // quiesces instead of heartbeating forever (and the event lands inside the
  // 100ms rebuild throttle, so the momentary count of 1 is never displayed).
  Timer? _fpsDecayTimer;
  bool _decayRebuild = false;
  StreamSubscription<DebugEvent>? _sub;
  // Null = never rebuilt: the first frame event must always repaint (the
  // monotonic SystemClock can read ~0 early in a process, so a zero sentinel
  // would wrongly throttle it).
  int? _lastRebuildMs;
  // The panel's content width (box minus border + padding), captured from the
  // real layout constraints each build so sparklines size to what actually
  // fits — see [_sparkWidth]. Overwritten before any row reads it.
  int _contentWidth = 28;

  @override
  void initState() {
    super.initState();
    _sub = DebugEvents.stream.listen((event) {
      if (event is! FrameDebugEvent) return;
      _history.add(event.frame);
      if (_history.length > _historySize) _history.removeAt(0);
      final now = widget.clock.now.inMilliseconds;
      _frameStamps.add(now);
      while (_frameStamps.isNotEmpty && _frameStamps.first < now - 1000) {
        _frameStamps.removeAt(0);
      }
      if (_decayRebuild) {
        // This frame is the decay rebuild's own render — don't re-arm, or
        // the panel would heartbeat forever while idle.
        _decayRebuild = false;
      } else {
        _fpsDecayTimer?.cancel();
        _fpsDecayTimer = Timer(const Duration(milliseconds: 1200), () {
          _decayRebuild = true;
          _rebuild();
        });
      }
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
    final now = widget.clock.now.inMilliseconds;
    final last = _lastRebuildMs;
    if (last != null && now - last < _rebuildIntervalMs) return;
    _lastRebuildMs = now;
    _rebuild();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    FleuryDebug.instance.removeListener(_rebuild);
    _fpsDecayTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // maxCols is the REAL panel width — the docking SizedBox sizes this box,
        // clamped to the terminal — unlike config.panelWidth, which can exceed a
        // narrow terminal. Content width = box minus border (2) and horizontal
        // padding (2); sparklines size off it so they can't overflow and wrap.
        _contentWidth =
            (constraints.maxCols ?? widget.controller.config.panelWidth) - 4;
        // Opaque surface: the panel now Positioned-floats over the app, so
        // every cell it covers must be painted or the app bleeds through the
        // gaps (border ring + unfilled interior). Surface fills the whole slot;
        // the border and content paint on top.
        //
        // AbsorbPointer is the INPUT counterpart of that opacity: pointer
        // regions resolve topmost-by-paint-order *per handler kind*, so a
        // panel with no regions would let taps, scrolls, hover, and
        // click-to-focus fall through to whatever app widget sits invisibly
        // underneath. The boundary absorbs all of them; the tab chips'
        // detectors paint later (deeper), so they stay on top and keep
        // working.
        return AbsorbPointer(
          child: Surface(
            color: const RgbColor(20, 22, 28),
            child: Container(
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
            ),
          ),
        );
      },
    );
  }

  List<Widget> _tabBody() {
    switch (widget.controller.tab) {
      case DebugTab.live:
        return _liveBody();
      case DebugTab.tree:
        return _treeBody();
      case DebugTab.rebuilds:
        return _rebuildsBody();
      case DebugTab.logs:
        // Captured stdout/stderr lives in the ambient LogBufferScope installed
        // by runApp; _LogsView adds search (`/`) and a source filter (`s`) on
        // top, driven by the controller.
        return [Expanded(child: _LogsView(controller: widget.controller))];
      case DebugTab.errors:
        return _errorsBody();
    }
  }

  List<Widget> _errorsBody() {
    final errors = widget.controller.errorHistory();
    if (errors.isEmpty) {
      return const [
        Text('no runtime errors', style: CellStyle(dim: true)),
        Text(''),
        Text(
          'Uncaught errors from event handlers and async',
          style: CellStyle(dim: true),
        ),
        Text(
          'callbacks collect here (newest last).',
          style: CellStyle(dim: true),
        ),
      ];
    }
    final rows = <Widget>[
      _row('Errors', '${errors.length} (last 50 kept)'),
      const Text(''),
    ];
    // Newest first; one summary line + timestamp each. The Text widget
    // sanitizes terminal-bound content, so hostile error strings are inert.
    for (final record in errors.reversed.take(12)) {
      final at = record.when.toIso8601String().substring(11, 19);
      final summary = record.error.toString().split('\n').first;
      rows
        ..add(Text('$at  $summary'))
        ..add(
          Text(
            '        ${record.stackTrace.toString().split('\n').first}',
            style: const CellStyle(dim: true),
          ),
        );
    }
    return rows;
  }

  List<Widget> _liveBody() {
    if (_history.isEmpty) {
      return const [
        Text('waiting for first frame…', style: CellStyle(dim: true)),
      ];
    }
    final latest = _history.last;
    // FPS = frames over last 1 second of wallclock-equivalent — but
    // FPS is the real wallclock render rate (frames in the last second); `Avg`
    // is the per-frame cost. Idle reads FPS 0 — an event-driven app renders
    // nothing at rest.
    final fps = _fps();
    final avg = _avgTotal();
    final slow = _slowCount();

    return [
      _row('Frame', '#${latest.frameNumber}'),
      _row('Reason', latest.reason),
      _row('Size', '${latest.bufferSize.cols}×${latest.bufferSize.rows}'),
      _row('FPS', '$fps'),
      _row('Avg', _us(avg)),
      _row('Slow', '$slow/${_history.length} >16ms'),
      const Text(''),
      _phaseRow('Build ', latest.build, _history.map((f) => f.build)),
      _phaseRow('Layout', latest.layout, _history.map((f) => f.layout)),
      _phaseRow('Paint ', latest.paint, _history.map((f) => f.paint)),
      _phaseRow('Diff  ', latest.diff, _history.map((f) => f.diff)),
      const Text(''),
      _row('Dirty', _dirtySummary(latest)),
      _row('Spans', _dirtySpanSummary(latest.dirtySpans)),
      _row('Layouts', _layoutSummary(latest.layoutStats)),
      _row('Boundaries', _repaintBoundarySummary(latest.repaintBoundaries)),
      _row('Sources', _sourceSummary(latest.dirtySources)),
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

  List<Widget> _rebuildsBody() {
    if (_history.isEmpty) {
      return const [
        Text('waiting for frame diagnostics…', style: CellStyle(dim: true)),
      ];
    }

    final latest = _history.last;
    final worst = _history.reduce((a, b) => a.total >= b.total ? a : b);
    final maxDirty = _history.reduce(
      (a, b) => a.dirtyCells >= b.dirtyCells ? a : b,
    );
    final cells = latest.bufferSize.cols * latest.bufferSize.rows;
    final recent = _history.length <= 5
        ? _history
        : _history.sublist(_history.length - 5);

    return [
      _row('Last frame', '#${latest.frameNumber} ${latest.reason}'),
      _row('Total', _us(latest.total)),
      _row('Dirty cells', '${latest.dirtyCells}/$cells'),
      _row('Dirty bounds', _dirtyBoundsSummary(latest.dirtyBounds)),
      _row('Dirty spans', _dirtySpanSummary(latest.dirtySpans)),
      _row('Layouts', _layoutSummary(latest.layoutStats)),
      _row('Boundaries', _repaintBoundarySummary(latest.repaintBoundaries)),
      _row('Sources', _sourceSummary(latest.dirtySources)),
      _row('Slow frames', '${_slowCount()}/${_history.length} >16ms'),
      _row('Worst frame', '#${worst.frameNumber} ${_us(worst.total)}'),
      _row('Max dirty', '#${maxDirty.frameNumber} ${maxDirty.dirtyCells}'),
      ..._dirtySourceRows(latest.dirtySources),
      const Text(''),
      const Text('— last phase costs —', style: CellStyle(dim: true)),
      _phaseRow('Build ', latest.build, _history.map((f) => f.build)),
      _phaseRow('Layout', latest.layout, _history.map((f) => f.layout)),
      _phaseRow('Paint ', latest.paint, _history.map((f) => f.paint)),
      _phaseRow('Diff  ', latest.diff, _history.map((f) => f.diff)),
      const Text(''),
      const Text('— recent frames —', style: CellStyle(dim: true)),
      for (final frame in recent)
        _row(
          '#${frame.frameNumber}',
          '${frame.reason} ${_us(frame.total)} '
              '${frame.dirtyCells} dirty ${_dirtyBoundsSummary(frame.dirtyBounds)}',
        ),
    ];
  }

  List<Widget> _treeBody() {
    final diagnosis = widget.controller.terminalDiagnosisSnapshot();
    final tree = widget.controller.semanticSnapshot();
    if (tree == null) {
      return [
        ..._terminalDiagnosisRows(diagnosis),
        if (diagnosis != null) const Text(''),
        const Text('Semantic tree unavailable', style: CellStyle(dim: true)),
      ];
    }

    final inspection = tree.toInspectionSnapshot();
    final nodes = tree.nodes.toList(growable: false);
    final focused = nodes.where((node) => node.focused).toList(growable: false);
    final appNode = _appNode(nodes);
    final commands = nodes
        .where((node) => node.role == SemanticRole.command)
        .toList(growable: false);
    final tasks = nodes
        .where((node) => node.role == SemanticRole.task)
        .toList(growable: false);
    final capabilityNodes = nodes
        .where(_hasCapabilityState)
        .toList(growable: false);
    final counts = <SemanticRole, int>{};
    for (final node in nodes) {
      counts[node.role] = (counts[node.role] ?? 0) + 1;
    }
    final roles = counts.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return [
      ..._terminalDiagnosisRows(diagnosis),
      if (diagnosis != null) const Text(''),
      _row('Semantic nodes', '${inspection.nodeCount}'),
      _row('Inspection', 'v${inspection.schemaVersion}'),
      _row('Actions', '${inspection.actionCount}'),
      _row('Focus id', inspection.focusedNodeId ?? '-'),
      _row('Focused', focused.isEmpty ? '-' : _nodeSummary(focused.first)),
      ..._appRows(appNode, commands),
      ..._commandRows(commands),
      ..._taskRows(tasks),
      ..._capabilityRows(capabilityNodes),
      ..._safetyRows(nodes),
      const Text(''),
      const Text('— semantic roles —', style: CellStyle(dim: true)),
      for (final entry in roles.take(12))
        _row(_roleLabel(entry.key), '${entry.value}'),
      if (roles.length > 12)
        Text(
          '+${roles.length - 12} more roles',
          style: const CellStyle(dim: true),
        ),
      ..._semanticOutlineRows(tree.root, inspection: inspection),
    ];
  }

  List<Widget> _terminalDiagnosisRows(TerminalDiagnosis? diagnosis) {
    if (diagnosis == null) return const [];
    final terminal = diagnosis.terminal;
    final environment = diagnosis.environment;
    final capabilities = diagnosis.capabilities;
    return [
      const Text('— terminal profile —', style: CellStyle(dim: true)),
      _row('Size', '${terminal.size.cols}×${terminal.size.rows}'),
      _row('Interactive', terminal.isInteractive ? 'yes' : 'no'),
      _row('TERM', terminal.term ?? '-'),
      if (terminal.termProgram != null)
        _row('Program', _programSummary(terminal)),
      _row('Session', _sessionSummary(environment)),
      const Text(''),
      const Text('— terminal capabilities —', style: CellStyle(dim: true)),
      _row('Color', capabilities.colorMode.name),
      _row('Glyphs', capabilities.glyphTier.name),
      _row('Images', capabilities.imageProtocol.name),
      _row('Alt screen', capabilities.alternateScreen ? 'yes' : 'no'),
      _row('Hide cursor', capabilities.hideCursor ? 'yes' : 'no'),
      _row('tmux pass', capabilities.tmuxPassthrough ? 'yes' : 'no'),
      _row('Fallbacks', '${diagnosis.fallbacks.length}'),
      _row('Warnings', '${diagnosis.warnings.length}'),
      ..._diagnosticMessageRows('fallback', diagnosis.fallbacks),
      ..._diagnosticMessageRows('warning', diagnosis.warnings),
      if (diagnosis.unsupportedFeatures.isNotEmpty)
        _row('Unsupported', diagnosis.unsupportedFeatures.take(3).join(',')),
      ..._compatibilityRows(diagnosis.compatibility),
    ];
  }

  String _programSummary(TerminalProfileReport terminal) {
    final program = terminal.termProgram;
    final version = terminal.termProgramVersion;
    if (program == null) return '-';
    return version == null ? program : '$program $version';
  }

  String _sessionSummary(TerminalEnvironmentReport environment) {
    final parts = <String>[
      if (environment.ssh) 'ssh',
      if (environment.tmux) 'tmux',
      if (environment.ci) 'ci',
      if (environment.noColor) 'no-color',
      if (environment.clicolorForce) 'force-color',
    ];
    return parts.isEmpty ? 'local' : parts.join(' ');
  }

  List<Widget> _diagnosticMessageRows(
    String label,
    List<TerminalDiagnosticMessage> messages,
  ) {
    if (messages.isEmpty) return const [];
    return [
      for (final message in messages.take(3))
        _row(label, '${message.code} ${message.severity.name}'),
      if (messages.length > 3)
        Text(
          '+${messages.length - 3} more $label messages',
          style: const CellStyle(dim: true),
        ),
    ];
  }

  List<Widget> _compatibilityRows(TerminalCompatibilityReport? report) {
    if (report == null) return const [];
    final summary = report.summary;
    return [
      const Text(''),
      const Text('— active compatibility —', style: CellStyle(dim: true)),
      _row('Findings', '${report.findings.length}'),
      if (report.skippedReason != null) _row('Probe status', 'skipped'),
      ..._compatibilitySummaryRows(summary),
      for (final finding in report.findings.take(4))
        _row(finding.label, _compatibilityFindingSummary(finding)),
      if (report.findings.length > 4)
        Text(
          '+${report.findings.length - 4} more compatibility findings',
          style: const CellStyle(dim: true),
        ),
    ];
  }

  List<Widget> _compatibilitySummaryRows(Map<String, int> summary) {
    final rows = <Widget>[];
    for (final status in TerminalCompatibilityStatus.values) {
      final count = summary[status.name] ?? 0;
      if (count > 0) {
        rows.add(_row(_compatibilityStatusLabel(status), '$count'));
      }
    }
    return rows;
  }

  String _compatibilityStatusLabel(TerminalCompatibilityStatus status) {
    return switch (status) {
      TerminalCompatibilityStatus.confirmed => 'Confirmed',
      TerminalCompatibilityStatus.activeConfirmed => 'Active confirmed',
      TerminalCompatibilityStatus.passiveUnverified => 'Passive unverified',
      TerminalCompatibilityStatus.unsupported => 'Unsupported',
      TerminalCompatibilityStatus.inconclusive => 'Inconclusive',
    };
  }

  String _compatibilityFindingSummary(TerminalCompatibilityFinding finding) {
    final parts = <String>[
      finding.status.name,
      'passive:${finding.passiveSupported ? 'yes' : 'no'}',
      if (finding.activeStatus != null) 'active:${finding.activeStatus!.name}',
      if (finding.detail != null) 'detail:${finding.detail}',
    ];
    return parts.join(' ');
  }

  SemanticNode? _appNode(List<SemanticNode> nodes) {
    for (final node in nodes) {
      if (node.role != SemanticRole.app) continue;
      final state = node.state;
      if (state.activeScreenId != null ||
          state.screenCount != null ||
          state.commandCount != null ||
          state.statusCount != null ||
          state.lastCommandId != null ||
          state.lastCommandStatus != null) {
        return node;
      }
    }
    return null;
  }

  List<Widget> _appRows(SemanticNode? appNode, List<SemanticNode> commands) {
    if (appNode == null && commands.isEmpty) return const [];
    final state = appNode?.state;
    return [
      const Text(''),
      const Text('— app state —', style: CellStyle(dim: true)),
      if (state?.activeScreenId != null)
        _row('Active screen', state!.activeScreenId!),
      if (state?.screenCount != null) _row('Screens', '${state!.screenCount}'),
      _row('Commands', '${state?.commandCount ?? commands.length}'),
      if (state?.statusCount != null) _row('Status', '${state!.statusCount}'),
      if (state?.lastCommandId != null || state?.lastCommandStatus != null)
        _row('Last command', _lastCommandSummary(state!)),
    ];
  }

  String _lastCommandSummary(SemanticState state) {
    return [
      if (state.lastCommandId != null) state.lastCommandId!,
      if (state.lastCommandStatus != null) state.lastCommandStatus!,
    ].join(' ');
  }

  List<Widget> _commandRows(List<SemanticNode> commands) {
    if (commands.isEmpty) return const [];
    final enabled = commands.where((command) => command.enabled).length;
    return [
      const Text(''),
      const Text('— commands —', style: CellStyle(dim: true)),
      _row('Enabled', '$enabled/${commands.length}'),
      for (final command in commands.take(5))
        _row(
          command.label ?? command.state.commandId ?? 'command',
          _commandSummary(command),
        ),
      if (commands.length > 5)
        Text(
          '+${commands.length - 5} more commands',
          style: const CellStyle(dim: true),
        ),
    ];
  }

  String _commandSummary(SemanticNode command) {
    final parts = [
      if (command.state.commandId != null) command.state.commandId!,
      if (command.state.shortcut != null) command.state.shortcut!,
      if (command.state.commandCategory != null) command.state.commandCategory!,
      if (!command.enabled) 'disabled',
    ];
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  List<Widget> _taskRows(List<SemanticNode> tasks) {
    if (tasks.isEmpty) return const [];
    final statusCounts = <String, int>{};
    var eventCount = 0;
    for (final task in tasks) {
      final state = task.state;
      final status = state.taskStatus;
      if (status != null) {
        statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      }
      eventCount += state.taskEventCount ?? 0;
    }
    return [
      const Text(''),
      const Text('— effects/tasks —', style: CellStyle(dim: true)),
      _row('Total', '${tasks.length}'),
      ..._taskStatusCountRows(statusCounts),
      if (eventCount > 0) _row('Events', '$eventCount'),
      for (final task in tasks.take(4))
        _row(task.label ?? task.state.taskId ?? 'task', _taskSummary(task)),
      if (tasks.length > 4)
        Text(
          '+${tasks.length - 4} more tasks',
          style: const CellStyle(dim: true),
        ),
    ];
  }

  List<Widget> _taskStatusCountRows(Map<String, int> counts) {
    if (counts.isEmpty) return const [];
    final rows = <Widget>[];
    const knownStatuses = [
      'running',
      'failed',
      'canceled',
      'succeeded',
      'idle',
    ];
    for (final status in knownStatuses) {
      final count = counts[status];
      if (count != null && count > 0) {
        rows.add(_row(_statusLabel(status), '$count'));
      }
    }
    final known = rows.length;
    if (known != counts.length) {
      final other = counts.entries
          .where((entry) => !knownStatuses.contains(entry.key))
          .fold<int>(0, (sum, entry) => sum + entry.value);
      if (other > 0) rows.add(_row('Other', '$other'));
    }
    return rows;
  }

  String _statusLabel(String status) => status.isEmpty
      ? 'Status'
      : '${status[0].toUpperCase()}${status.substring(1)}';

  String _taskSummary(SemanticNode task) {
    final state = task.state;
    final parts = [
      if (state.taskId != null) state.taskId!,
      if (state.taskStatus != null) state.taskStatus!,
      if (state.progressCurrent != null)
        'progress:${state.progressCurrent}/${state.progressTotal ?? '?'}',
      if (state.progressLabel != null) 'label:${state.progressLabel}',
      if (state.taskEventCount != null) 'events:${state.taskEventCount}',
      if (state.lastTaskEventKind != null) 'last:${state.lastTaskEventKind}',
    ];
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  bool _hasCapabilityState(SemanticNode node) {
    final state = node.state;
    return state.terminalCapability != null ||
        state.capabilityRequirement != null ||
        state.capabilityResolution != null ||
        state.activeFallback != null ||
        state.clipboardCapability != null ||
        state.clipboardCapabilityResolution != null ||
        state.clipboardFallback != null;
  }

  List<Widget> _capabilityRows(List<SemanticNode> nodes) {
    if (nodes.isEmpty) return const [];
    return [
      const Text(''),
      const Text('— capabilities —', style: CellStyle(dim: true)),
      _row('Capability nodes', '${nodes.length}'),
      ..._capabilityResolutionRows(nodes),
      ..._capabilityAttentionRows(nodes),
      for (final node in nodes.take(5))
        _row(_nodeSummary(node), _capabilitySummary(node.state)),
      if (nodes.length > 5)
        Text(
          '+${nodes.length - 5} more capability nodes',
          style: const CellStyle(dim: true),
        ),
    ];
  }

  String _capabilitySummary(SemanticState state) {
    final parts = [
      if (state.capabilityRequirement != null) state.capabilityRequirement!,
      if (state.capabilityResolution != null) state.capabilityResolution!,
      if (state.activeFallback != null) 'fallback:${state.activeFallback}',
      if (state.clipboardCapabilityResolution != null)
        'clipboard:${state.clipboardCapabilityResolution}',
      if (state.clipboardFallback != null)
        'clipboardFallback:${state.clipboardFallback}',
    ];
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  List<Widget> _capabilityResolutionRows(List<SemanticNode> nodes) {
    final counts = <String, int>{};
    var requiredBlocked = 0;
    for (final node in nodes) {
      final state = node.state;
      final resolution = state.capabilityResolution;
      if (resolution != null) {
        counts[resolution] = (counts[resolution] ?? 0) + 1;
        if (state.capabilityRequirement == 'required' &&
            resolution != 'available') {
          requiredBlocked += 1;
        }
      }
      final clipboardResolution = state.clipboardCapabilityResolution;
      if (clipboardResolution != null) {
        counts[clipboardResolution] = (counts[clipboardResolution] ?? 0) + 1;
      }
    }
    final rows = <Widget>[];
    for (final entry in const <(String, String)>[
      ('available', 'Available'),
      ('degraded', 'Degraded'),
      ('disabledByPolicy', 'Policy blocked'),
      ('unsupported', 'Unsupported'),
      ('unsafe', 'Unsafe'),
    ]) {
      final count = counts[entry.$1] ?? 0;
      if (count > 0) rows.add(_row(entry.$2, '$count'));
    }
    if (requiredBlocked > 0) {
      rows.add(_row('Required blocked', '$requiredBlocked'));
    }
    return rows;
  }

  List<Widget> _capabilityAttentionRows(List<SemanticNode> nodes) {
    final attention = nodes
        .where(_needsCapabilityAttention)
        .toList(growable: false);
    if (attention.isEmpty) return const [];
    return [
      const Text('— capability attention —', style: CellStyle(dim: true)),
      for (final node in attention.take(3))
        _row(_nodeSummary(node), _capabilityAttentionSummary(node.state)),
      if (attention.length > 3)
        Text(
          '+${attention.length - 3} more capability findings',
          style: const CellStyle(dim: true),
        ),
    ];
  }

  bool _needsCapabilityAttention(SemanticNode node) {
    final state = node.state;
    return _attentionResolution(state.capabilityResolution) ||
        _attentionResolution(state.clipboardCapabilityResolution);
  }

  bool _attentionResolution(String? resolution) {
    return resolution == 'disabledByPolicy' ||
        resolution == 'unsafe' ||
        resolution == 'unsupported';
  }

  String _capabilityAttentionSummary(SemanticState state) {
    final parts = [
      if (state.terminalCapability != null) state.terminalCapability!,
      if (state.clipboardCapability != null) state.clipboardCapability!,
      if (state.capabilityRequirement != null) state.capabilityRequirement!,
      if (state.capabilityResolution != null) state.capabilityResolution!,
      if (state.clipboardCapabilityResolution != null)
        'clipboard:${state.clipboardCapabilityResolution}',
      if (state.activeFallback != null) 'fallback:${state.activeFallback}',
      if (state.clipboardFallback != null)
        'fallback:${state.clipboardFallback}',
    ];
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  List<Widget> _safetyRows(List<SemanticNode> nodes) {
    var redacted = 0;
    var sanitized = 0;
    var truncated = 0;
    int? largestOriginalOutput;
    for (final node in nodes) {
      if (_nodeRedactsValue(node)) redacted += 1;
      if (_nodeOutputSanitized(node)) sanitized += 1;
      if (_nodeOutputTruncated(node)) truncated += 1;
      final originalOutput = _nodeOriginalOutputLength(node);
      if (originalOutput != null &&
          (largestOriginalOutput == null ||
              originalOutput > largestOriginalOutput)) {
        largestOriginalOutput = originalOutput;
      }
    }
    if (redacted == 0 &&
        sanitized == 0 &&
        truncated == 0 &&
        largestOriginalOutput == null) {
      return const [];
    }
    return [
      const Text(''),
      const Text('— safety state —', style: CellStyle(dim: true)),
      if (redacted > 0) _row('Redacted nodes', '$redacted'),
      if (sanitized > 0) _row('Sanitized output', '$sanitized nodes'),
      if (truncated > 0) _row('Truncated output', '$truncated nodes'),
      if (largestOriginalOutput != null)
        _row('Largest original', '$largestOriginalOutput chars'),
    ];
  }

  bool _nodeOutputSanitized(SemanticNode node) {
    final state = node.state;
    return state.outputSanitized == true || state.taskOutputSanitized == true;
  }

  bool _nodeOutputTruncated(SemanticNode node) {
    final state = node.state;
    return state.outputTruncated == true || state.taskOutputTruncated == true;
  }

  int? _nodeOriginalOutputLength(SemanticNode node) {
    final state = node.state;
    final output = state.outputOriginalLength;
    final taskOutput = state.taskOutputOriginalLength;
    if (output == null) return taskOutput;
    if (taskOutput == null) return output;
    return output > taskOutput ? output : taskOutput;
  }

  List<Widget> _semanticOutlineRows(
    SemanticNode root, {
    required SemanticInspectionSnapshot inspection,
  }) {
    final outline = <_SemanticOutlineEntry>[];
    _collectSemanticOutline(root, 0, outline);
    if (outline.isEmpty) return const [];
    final cursor = _clampInt(
      widget.controller.semanticCursorIndex,
      0,
      outline.length - 1,
    );
    final selected = outline[cursor];
    final windowStart = _semanticWindowStart(cursor, outline.length);
    final windowEnd = _minInt(outline.length, windowStart + 10);
    return [
      const Text(''),
      const Text('— semantic graph —', style: CellStyle(dim: true)),
      Text('[↑/↓] select semantic node', style: const CellStyle(dim: true)),
      _row(
        'Cursor',
        '${cursor + 1}/${outline.length} ${_nodeSummary(selected.node)}',
      ),
      ..._selectedSemanticRows(selected.node, inspection),
      const Text(''),
      const Text('— graph window —', style: CellStyle(dim: true)),
      if (windowStart > 0)
        Text('↑ $windowStart nodes above', style: const CellStyle(dim: true)),
      for (var i = windowStart; i < windowEnd; i++)
        _row(
          _outlineRole(outline[i], selected: i == cursor),
          _outlineSummary(outline[i].node),
        ),
      if (windowEnd < outline.length)
        Text(
          '↓ ${outline.length - windowEnd} nodes below',
          style: const CellStyle(dim: true),
        ),
    ];
  }

  int _semanticWindowStart(int cursor, int length) {
    if (length <= 10) return 0;
    final centered = cursor - 4;
    final maxStart = length - 10;
    return _clampInt(centered, 0, maxStart);
  }

  void _collectSemanticOutline(
    SemanticNode node,
    int depth,
    List<_SemanticOutlineEntry> out,
  ) {
    out.add(_SemanticOutlineEntry(node: node, depth: depth));
    for (final child in node.children) {
      _collectSemanticOutline(child, depth + 1, out);
    }
  }

  List<Widget> _selectedSemanticRows(
    SemanticNode node,
    SemanticInspectionSnapshot inspection,
  ) {
    final inspected = inspection.nodeById(sanitizeForDisplay(node.id.value));
    if (inspected != null) {
      return _selectedInspectionRows(inspected);
    }

    return [
      const Text('— selected node —', style: CellStyle(dim: true)),
      _row('ID', sanitizeForDisplay(node.id.value)),
      _row('Inspection', 'unavailable'),
    ];
  }

  List<Widget> _selectedInspectionRows(SemanticInspectionNode node) {
    final flags = _inspectionNodeFlags(node);
    return [
      const Text('— selected node —', style: CellStyle(dim: true)),
      _row('ID', node.id),
      _row('Role', node.role),
      if (node.label != null) _row('Label', node.label!),
      if (node.value != null) _row('Value', node.value.toString()),
      if (flags.isNotEmpty) _row('Flags', flags),
      if (node.actions.isNotEmpty) _row('Actions', node.actions.join(',')),
      if (node.validationError != null) _row('Error', node.validationError!),
      if (node.state.isNotEmpty) _row('State', _inspectionStateSummary(node)),
    ];
  }

  String _inspectionNodeFlags(SemanticInspectionNode node) {
    final flags = [
      if (node.focused) 'focused',
      if (node.selected) 'selected',
      if (!node.enabled) 'disabled',
      if (node.busy) 'busy',
      if (node.checked != null) 'checked:${node.checked}',
      if (node.expanded != null) 'expanded:${node.expanded}',
    ];
    return flags.join(' ');
  }

  String _inspectionStateSummary(SemanticInspectionNode node) {
    final entries = node.state.entries.toList(growable: false);
    final shown = entries.take(4).map((entry) {
      return '${entry.key}:${entry.value}';
    });
    final suffix = entries.length > 4 ? ' +${entries.length - 4} more' : '';
    return '${shown.join(' ')}$suffix';
  }

  String _outlineRole(_SemanticOutlineEntry entry, {required bool selected}) {
    return '${selected ? '>' : ' '} ${'  ' * entry.depth}${_roleLabel(entry.node.role)}';
  }

  String _outlineSummary(SemanticNode node) {
    final redacted = _nodeRedactsValue(node);
    final parts = [
      if (node.label != null) node.label!,
      if (node.value != null)
        redacted ? 'value:<redacted>' : 'value:${node.value}',
      if (node.focused) 'focused',
      if (node.selected) 'selected',
      if (!node.enabled) 'disabled',
      if (node.busy) 'busy',
      if (node.actions.isNotEmpty)
        'actions:${node.actions.map((action) => action.name).join(',')}',
      if (node.validationError != null)
        redacted ? 'error:<redacted>' : 'error:${node.validationError}',
    ];
    return parts.isEmpty ? node.id.value : parts.join(' ');
  }

  bool _nodeRedactsValue(SemanticNode node) {
    final state = node.state;
    return state.redactedValue == true ||
        state.obscureText == true ||
        state.clipboardRedacted == true;
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  int _minInt(int a, int b) => a < b ? a : b;

  String _dirtySummary(FrameEvent frame) {
    final bounds = _dirtyBoundsSummary(frame.dirtyBounds);
    return bounds == '-'
        ? '${frame.dirtyCells} cells'
        : '${frame.dirtyCells} $bounds';
  }

  String _dirtyBoundsSummary(CellRect? rect) {
    if (rect == null) return '-';
    return '${rect.left},${rect.top} ${rect.size.cols}×${rect.size.rows}';
  }

  String _dirtySpanSummary(DirtySpanFrameStats stats) {
    if (!stats.hasDirtySpans) return '-';
    return '${stats.spanCount} spans / ${stats.rowCount} rows, '
        'avg ${stats.averageSpanLength.toStringAsFixed(1)}, '
        'max ${stats.longestSpan}';
  }

  String _repaintBoundarySummary(RepaintBoundaryFrameStats stats) {
    if (!stats.hasBoundaries) return '-';
    return '${stats.boundaryCount} total, '
        '${stats.repaintedCount} repainted, '
        '${stats.cachedCount} cached, '
        '${stats.copiedCellCount} cells';
  }

  String _layoutSummary(RenderLayoutFrameStats stats) {
    if (!stats.hasLayouts) return '-';
    return '${stats.performedCount} run, ${stats.skippedCount} skipped';
  }

  String _sourceSummary(List<String> sources) {
    if (sources.isEmpty) return '-';
    final shown = sources.take(2).join(', ');
    final remaining = sources.length - 2;
    return remaining > 0 ? '$shown, +$remaining more' : shown;
  }

  List<Widget> _dirtySourceRows(List<String> sources) {
    if (sources.isEmpty) return const [];
    return [
      const Text(''),
      const Text('— dirty sources —', style: CellStyle(dim: true)),
      for (final source in sources.take(6)) Text(source),
      if (sources.length > 6)
        Text(
          '+${sources.length - 6} more sources',
          style: const CellStyle(dim: true),
        ),
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

  // Real frames-per-second: frames actually rendered in the last wallclock
  // second. An idle, event-driven app reads 0 — it renders nothing when nothing
  // changes, which is the honest number (and one of Fleury's better traits).
  // The old metric was 1e6/avg-frame-time, i.e. per-frame headroom, which read
  // ~200 even at rest; per-frame cost is already shown separately as `Avg`.
  int _fps() {
    final cutoff = widget.clock.now.inMilliseconds - 1000;
    var n = 0;
    for (final t in _frameStamps) {
      if (t >= cutoff) n++;
    }
    return n;
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

  String _nodeSummary(SemanticNode node) {
    final label = node.label;
    return label == null
        ? _roleLabel(node.role)
        : '${_roleLabel(node.role)} $label';
  }

  String _roleLabel(SemanticRole role) => role.name;

  /// One phase line: `Label  3.2ms ▁▂▃▄▅▆▇█` — color the value red
  /// when over budget (~4ms is a reasonable per-phase ceiling at 60fps
  /// since the four phases share a 16ms total).
  /// Sparkline sample count that fits the phase row: [_contentWidth] (the real
  /// laid-out content width) minus the "label 0000.0ms " prefix (15 cols), so
  /// each graph stays on one line instead of overflowing and wrapping into the
  /// next row — at any dock side, in fullscreen, or on a narrow terminal.
  int get _sparkWidth => (_contentWidth - 15).clamp(6, 40);

  Widget _phaseRow(String label, Duration latest, Iterable<Duration> series) {
    final ms = latest.inMicroseconds / 1000;
    final overBudget = ms > 4.0;
    final spark = _sparkline(
      series.map((d) => d.inMicroseconds).toList(),
      _sparkWidth,
    );
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
  static String _sparkline(List<int> values, [int maxLen = 60]) {
    if (values.isEmpty) return '';
    // Keep only the most recent [maxLen] samples so the graph fits its column.
    final window = values.length > maxLen
        ? values.sublist(values.length - maxLen)
        : values;
    const blocks = ' ▁▂▃▄▅▆▇█';
    final maxV = window.reduce((a, b) => a > b ? a : b);
    if (maxV == 0) return blocks[0] * window.length;
    final buf = StringBuffer();
    for (final v in window) {
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
        ? '←→ tabs · Esc dock · Ctrl+G close'
        : '←→ tabs · F11 expand · Ctrl+G close';
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
        // Clickable: a mouse tap selects the tab (arrows / Tab also cycle via
        // the shell's key handler). The chips read as buttons — now they act
        // like them.
        GestureDetector(
          onTap: () => controller.selectTab(tab),
          child: Text(
            ' ${_label(tab)} ',
            style: selected
                ? const CellStyle(
                    foreground: RgbColor(0, 0, 0),
                    background: RgbColor(120, 200, 255),
                    bold: true,
                  )
                : const CellStyle(dim: true),
          ),
        ),
      );
    }
    // Wrap, not Row: five tabs no longer fit the default 32-cell panel on
    // one line; narrow panels flow the strip onto a second row instead of
    // truncating the trailing tabs.
    return Wrap(children: cells);
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
      case DebugTab.errors:
        return 'Errors';
    }
  }
}

final class _SemanticOutlineEntry {
  const _SemanticOutlineEntry({required this.node, required this.depth});

  final SemanticNode node;
  final int depth;
}

/// The Logs tab: fd-captured stdout/stderr with an incremental search field
/// (`/`) and a source filter (`s`), both driven from [DebugController]. Tails
/// like a console (newest at the bottom) and reads the buffer from the ambient
/// [LogBufferScope] runApp installs. Search matches are highlighted in place;
/// only the visible tail is styled, so a long buffer stays cheap.
class _LogsView extends StatelessWidget {
  const _LogsView({required this.controller});

  final DebugController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = LogBufferScope.maybeOf(context)?.lines ?? const <LogLine>[];
    final source = controller.logSourceFilter;
    final lowerQuery = controller.logQuery.toLowerCase();
    final filtered = <LogLine>[
      for (final line in all)
        if (_matches(line, source, lowerQuery)) line,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        _statusBar(theme, matches: filtered.length, total: all.length),
        Expanded(child: _list(theme, filtered, controller.logQuery)),
      ],
    );
  }

  bool _matches(LogLine line, LogSourceFilter source, String lowerQuery) {
    if (source == LogSourceFilter.stdout && line.source != LogSource.stdout) {
      return false;
    }
    if (source == LogSourceFilter.stderr && line.source != LogSource.stderr) {
      return false;
    }
    return lowerQuery.isEmpty || line.text.toLowerCase().contains(lowerQuery);
  }

  // The live search field (while typing) or a one-line status:
  // source · "query" · matches/total.
  Widget _statusBar(
    ThemeData theme, {
    required int matches,
    required int total,
  }) {
    if (controller.logSearching) {
      return Text(
        '/${controller.logQuery}▏',
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: CellStyle(foreground: theme.colorScheme.primary, bold: true),
      );
    }
    final parts = <String>[controller.logSourceFilter.label];
    if (controller.logQuery.isNotEmpty) {
      parts
        ..add('"${controller.logQuery}"')
        ..add('$matches/$total');
    } else {
      parts.add('$total ${total == 1 ? 'line' : 'lines'}');
    }
    return Text(
      parts.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: const CellStyle(dim: true),
    );
  }

  Widget _list(ThemeData theme, List<LogLine> lines, String query) {
    final normalStyle = theme.textStyle;
    final stderrStyle = CellStyle(foreground: theme.colorScheme.error);
    final hitStyle = CellStyle(
      foreground: theme.colorScheme.background,
      background: theme.colorScheme.warning,
      bold: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (lines.isEmpty) {
          return Text(
            query.isEmpty
                ? 'no output captured yet'
                : 'no lines match "$query"',
            style: const CellStyle(dim: true),
          );
        }
        // Tail: show the most recent lines that fit, newest at the bottom.
        final maxRows = constraints.maxRows;
        final visible = (maxRows != null && lines.length > maxRows)
            ? lines.sublist(lines.length - maxRows)
            : lines;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in visible)
              _row(
                line,
                query,
                base: line.source == LogSource.stderr
                    ? stderrStyle
                    : normalStyle,
                hit: hitStyle,
              ),
          ],
        );
      },
    );
  }

  Widget _row(
    LogLine line,
    String query, {
    required CellStyle base,
    required CellStyle hit,
  }) {
    if (query.isEmpty) {
      return Text(
        line.text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: base,
      );
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.clip,
      text: TextSpan(style: base, children: _spans(line.text, query, hit)),
    );
  }

  // Splits [text] into styled spans, highlighting each case-insensitive [query]
  // occurrence with [hit]. [query] is non-empty here.
  List<TextSpan> _spans(String text, String query, CellStyle hit) {
    final spans = <TextSpan>[];
    final haystack = text.toLowerCase();
    final needle = query.toLowerCase();
    var start = 0;
    while (true) {
      final idx = haystack.indexOf(needle, start);
      if (idx < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(
        TextSpan(text: text.substring(idx, idx + needle.length), style: hit),
      );
      start = idx + needle.length;
    }
    return spans;
  }
}
