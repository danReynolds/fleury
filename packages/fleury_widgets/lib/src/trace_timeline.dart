import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

/// Protocol-neutral lifecycle state for a timeline event.
enum TraceTimelineStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  warning,
  info,
}

/// Protocol-neutral kind for one timeline event.
enum TraceTimelineKind {
  app,
  command,
  task,
  process,
  tool,
  diagnostic,
  debug,
  input,
  output,
  render,
  network,
  other,
}

/// One event in a [TraceTimeline].
final class TraceTimelineEntry {
  const TraceTimelineEntry({
    required this.id,
    required this.label,
    this.detail,
    this.kind = TraceTimelineKind.other,
    this.status = TraceTimelineStatus.info,
    this.source,
    this.timestamp,
    this.duration,
    this.enabled = true,
    this.metadata = const <String, Object?>{},
  });

  /// Stable identity used by semantics, selection, and callbacks.
  final Object id;

  /// Primary event label.
  final String label;

  /// Optional longer detail text.
  final String? detail;

  /// Event kind used for styling and semantics.
  final TraceTimelineKind kind;

  /// Event lifecycle status.
  final TraceTimelineStatus status;

  /// Optional source/origin label.
  final String? source;

  /// Optional wall-clock timestamp.
  final DateTime? timestamp;

  /// Optional elapsed duration for the event.
  final Duration? duration;

  /// Whether this event can be selected and activated.
  final bool enabled;

  /// App-specific semantic state carried by the event.
  final Map<String, Object?> metadata;

  String get displayId => id.toString();

  bool get busy => status == TraceTimelineStatus.running;
}

/// Converts a [TaskEvent] into a safe [TraceTimelineEntry].
///
/// The adapter intentionally keeps task output and errors metadata-only. Raw
/// output belongs in `LogRegion`/`TerminalOutputRegion`; trace timelines should
/// explain ordering, progress, status, and safety flags without becoming a
/// second output log.
TraceTimelineEntry traceTimelineEntryForTaskEvent<T>(
  TaskEvent<T> event, {
  required Object taskId,
  String? taskLabel,
  TraceTimelineKind kind = TraceTimelineKind.task,
  String? source,
}) {
  final safeTaskId = _sanitizeTraceText(taskId.toString());
  final safeLabel = _sanitizeTraceText(taskLabel ?? safeTaskId);
  final output = event.output;
  final eventSource = output == null
      ? source
      : (source == null ? output.source : '$source/${output.source}');
  return TraceTimelineEntry(
    id: '$safeTaskId.run-${event.runId}.event-${event.sequence}',
    label: '$safeLabel ${_taskEventVerb(event.kind)}',
    detail: _taskEventDetail(event),
    kind: kind,
    status: _traceStatusForTaskEvent(event),
    source: eventSource == null ? null : _sanitizeTraceText(eventSource),
    metadata: <String, Object?>{
      'taskId': safeTaskId,
      'taskRunId': event.runId,
      'taskEventSequence': event.sequence,
      'taskEventKind': event.kind.name,
      'taskStatus': event.status.name,
      'progressCurrent': ?event.progress?.current,
      'progressTotal': ?event.progress?.total,
      if (event.progress?.label case final label?)
        'progressLabel': _sanitizeTraceText(label),
      if (output != null) ...{
        'taskOutputSequence': output.sequence,
        'taskOutputSource': _sanitizeTraceText(output.source),
        'taskOutputSeverity': output.severity.name,
        'taskOutputSanitized': output.sanitized,
        'taskOutputTruncated': output.truncated,
        if (output.originalLength != null)
          'taskOutputOriginalLength': output.originalLength,
      },
    },
  );
}

/// Converts recent [TaskEvent] records into timeline entries.
///
/// [maxEvents] keeps live task histories compact for dashboard and inspector
/// timelines. Older events remain available on the task controller.
List<TraceTimelineEntry> traceTimelineEntriesForTaskEvents<T>(
  Iterable<TaskEvent<T>> events, {
  required Object taskId,
  String? taskLabel,
  TraceTimelineKind kind = TraceTimelineKind.task,
  String? source,
  int? maxEvents,
}) {
  assert(maxEvents == null || maxEvents >= 0);
  final all = events.toList(growable: false);
  final start = maxEvents == null || all.length <= maxEvents
      ? 0
      : all.length - maxEvents;
  return [
    for (final event in all.skip(start))
      traceTimelineEntryForTaskEvent(
        event,
        taskId: taskId,
        taskLabel: taskLabel,
        kind: kind,
        source: source,
      ),
  ];
}

/// Controller for [TraceTimeline] selection and viewport state.
class TraceTimelineController extends ChangeNotifier {
  TraceTimelineController({int selectedIndex = 0})
    : _list = ListController(selectedIndex: selectedIndex) {
    _list.addListener(notifyListeners);
  }

  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    _list.jumpToIndex(index);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TraceTimelineController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _list.removeListener(notifyListeners);
    _list.dispose();
    super.dispose();
  }
}

/// Clipboard/export behavior for [TraceTimeline] selected-event copy.
final class TraceTimelineCopyOptions {
  const TraceTimelineCopyOptions({
    this.includeDetail = true,
    this.includeSource = true,
    this.includeTimestamp = true,
    this.includeDuration = true,
    this.maxDetailLength = 1000,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  }) : assert(maxDetailLength == null || maxDetailLength >= 0);

  /// Whether copied event text includes [TraceTimelineEntry.detail].
  final bool includeDetail;

  /// Whether copied event text includes [TraceTimelineEntry.source].
  final bool includeSource;

  /// Whether copied event text includes [TraceTimelineEntry.timestamp].
  final bool includeTimestamp;

  /// Whether copied event text includes [TraceTimelineEntry.duration].
  final bool includeDuration;

  /// Maximum copied detail length.
  final int? maxDetailLength;

  /// Clipboard write behavior for copied event text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [TraceTimeline] copies the selected event.
final class TraceTimelineCopyResult {
  const TraceTimelineCopyResult({
    required this.eventIndex,
    required this.event,
    required this.text,
    required this.report,
  });

  final int eventIndex;
  final TraceTimelineEntry event;
  final String text;
  final ClipboardWriteReport report;
}

/// Result delivered after [TraceTimeline] activates one event.
final class TraceTimelineSelectResult {
  const TraceTimelineSelectResult({
    required this.eventIndex,
    required this.event,
  });

  final int eventIndex;
  final TraceTimelineEntry event;
}

/// Exports one [TraceTimelineEntry] as sanitized clipboard/debug text.
String exportTraceTimelineEntry(
  TraceTimelineEntry event, {
  TraceTimelineCopyOptions options = const TraceTimelineCopyOptions(),
}) {
  final parts = <String>[
    _sanitizeTraceText(event.label),
    event.kind.name,
    event.status.name,
    if (options.includeDuration && event.duration != null)
      '${event.duration!.inMilliseconds}ms',
    if (options.includeSource && event.source != null)
      _sanitizeTraceText(event.source!),
    if (options.includeTimestamp && event.timestamp != null)
      event.timestamp!.toIso8601String(),
    if (options.includeDetail && event.detail != null)
      _truncateGraphemes(
        _sanitizeTraceText(event.detail!),
        options.maxDetailLength,
      ),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' | ');
}

String _taskEventVerb(TaskEventKind kind) {
  return switch (kind) {
    TaskEventKind.started => 'started',
    TaskEventKind.progress => 'progress',
    TaskEventKind.output => 'output',
    TaskEventKind.succeeded => 'succeeded',
    TaskEventKind.failed => 'failed',
    TaskEventKind.canceled => 'canceled',
    TaskEventKind.reset => 'reset',
  };
}

String _taskEventDetail<T>(TaskEvent<T> event) {
  final parts = <String>['run ${event.runId}'];
  switch (event.kind) {
    case TaskEventKind.started:
      parts.add('started');
    case TaskEventKind.progress:
      final progress = event.progress;
      if (progress == null) {
        parts.add('progress');
      } else if (progress.current != null && progress.total != null) {
        parts.add('progress ${progress.current} of ${progress.total}');
      } else if (progress.current != null) {
        parts.add('progress ${progress.current}');
      } else {
        parts.add('progress');
      }
      if (progress?.label case final label?) {
        parts.add(_sanitizeTraceText(label));
      }
    case TaskEventKind.output:
      final output = event.output;
      if (output == null) {
        parts.add('output');
      } else {
        parts.add('output ${_sanitizeTraceText(output.source)}');
        parts.add(output.severity.name);
        if (output.sanitized) parts.add('sanitized');
        if (output.truncated) parts.add('truncated');
        if (output.originalLength != null) {
          parts.add('original ${output.originalLength} chars');
        }
      }
    case TaskEventKind.succeeded:
      parts.add('succeeded');
    case TaskEventKind.failed:
      parts.add('failed');
    case TaskEventKind.canceled:
      parts.add('canceled');
    case TaskEventKind.reset:
      parts.add('reset');
  }
  parts.add('status ${event.status.name}');
  parts.add('event ${event.sequence}');
  return parts.join(', ');
}

TraceTimelineStatus _traceStatusForTaskEvent<T>(TaskEvent<T> event) {
  return switch (event.kind) {
    TaskEventKind.succeeded => TraceTimelineStatus.succeeded,
    TaskEventKind.failed => TraceTimelineStatus.failed,
    TaskEventKind.canceled => TraceTimelineStatus.cancelled,
    TaskEventKind.reset => TraceTimelineStatus.info,
    TaskEventKind.started ||
    TaskEventKind.progress ||
    TaskEventKind.output => switch (event.status) {
      TaskStatus.idle => TraceTimelineStatus.queued,
      TaskStatus.running => TraceTimelineStatus.running,
      TaskStatus.succeeded => TraceTimelineStatus.succeeded,
      TaskStatus.failed => TraceTimelineStatus.failed,
      TaskStatus.canceled => TraceTimelineStatus.cancelled,
    },
  };
}

/// Compact inspectable timeline for task/process/debug workflow events.
class TraceTimeline extends StatefulWidget {
  const TraceTimeline({
    super.key,
    required this.events,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.label = 'Trace timeline',
    this.showTimestamp = false,
    this.copySelection = true,
    this.copyOptions = const TraceTimelineCopyOptions(),
    this.onSelect,
    this.onCopy,
  });

  /// Source events to display, activate, and copy.
  final List<TraceTimelineEntry> events;

  /// External selection and visible-range controller.
  final TraceTimelineController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the timeline should request focus when mounted.
  final bool autofocus;

  /// Semantic and visual label for the timeline.
  final String label;

  /// Prefix each row with the event's [TraceTimelineEntry.timestamp] as a
  /// local `HH:mm:ss` clock, when one is set. Off by default — the row
  /// already shows elapsed duration; turn this on to anchor events to wall
  /// time as well.
  final bool showTimestamp;

  /// Whether Ctrl+C and semantic copy export the selected event.
  final bool copySelection;

  /// Clipboard/export options for selected-event copy.
  final TraceTimelineCopyOptions copyOptions;

  /// Called when an event is activated.
  final void Function(TraceTimelineSelectResult result)? onSelect;

  /// Called after a copy attempt completes.
  final void Function(TraceTimelineCopyResult result)? onCopy;

  @override
  State<TraceTimeline> createState() => _TraceTimelineState();
}

class _TraceTimelineState extends State<TraceTimeline> {
  late TraceTimelineController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;
  Object? _pendingSelectedTraceId;
  int _selectionSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TraceTimelineController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TraceTimeline');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant TraceTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TraceTimelineController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TraceTimeline');
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.events != oldWidget.events) {
      _syncSelectionAfterEventUpdate(oldWidget.events);
    }
  }

  void _onControllerChange() => setState(() {});

  void _syncSelectionAfterEventUpdate(List<TraceTimelineEntry> oldEvents) {
    _selectionSyncGeneration++;
    _pendingSelectedTraceId = null;
    if (widget.events.isEmpty) {
      _controller.selectedIndex = null;
      return;
    }
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) {
      _controller.selectedIndex = 0;
      return;
    }
    if (selectedIndex >= 0 && selectedIndex < oldEvents.length) {
      final selectedId = oldEvents[selectedIndex].id;
      final nextIndex = widget.events.indexWhere(
        (event) => event.id == selectedId,
      );
      if (nextIndex != -1) {
        _selectIndexAfterListCountRefresh(selectedId, nextIndex);
        return;
      }
    }
    _controller.selectedIndex = selectedIndex.clamp(
      0,
      widget.events.length - 1,
    );
  }

  void _selectIndexAfterListCountRefresh(Object selectedId, int nextIndex) {
    final knownItemCount = _controller._listController.itemCount;
    if (knownItemCount == 0 || nextIndex < knownItemCount) {
      _controller.selectedIndex = nextIndex;
      return;
    }

    _pendingSelectedTraceId = selectedId;
    final generation = _selectionSyncGeneration;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() {
        _applyPendingSelection(generation, selectedId);
      });
      return;
    }
    binding.addPostFrameCallback((_) {
      _applyPendingSelection(generation, selectedId);
    });
  }

  void _applyPendingSelection(int generation, Object selectedId) {
    if (!mounted || generation != _selectionSyncGeneration) return;
    if (_pendingSelectedTraceId != selectedId) return;
    final nextIndex = widget.events.indexWhere(
      (event) => event.id == selectedId,
    );
    if (nextIndex == -1) {
      _pendingSelectedTraceId = null;
      return;
    }
    _pendingSelectedTraceId = null;
    _controller.selectedIndex = nextIndex;
  }

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection || widget.events.isEmpty) return;
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.events.length - 1,
    );
    final event = widget.events[selected];
    final text = exportTraceTimelineEntry(event, options: widget.copyOptions);
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      TraceTimelineCopyResult(
        eventIndex: selected,
        event: event,
        text: text,
        report: report,
      ),
    );
  }

  void _selectCurrent() {
    if (widget.events.isEmpty) return;
    _focusNode.requestFocus();
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.events.length - 1,
    );
    final event = widget.events[selected];
    if (!event.enabled) return;
    widget.onSelect?.call(
      TraceTimelineSelectResult(eventIndex: selected, event: event),
    );
  }

  Future<void> _selectAt(int index) async {
    if (index < 0 || index >= widget.events.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    _selectCurrent();
  }

  Future<void> _copyAt(int index) async {
    if (index < 0 || index >= widget.events.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection();
  }

  Future<void> _handleTimelineAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.submit:
        _selectCurrent();
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _controller.selectedIndex;
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && widget.events.isNotEmpty;
    final canSelect = widget.onSelect != null;
    final selectedEvent =
        selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= widget.events.length
        ? null
        : widget.events[selectedIndex];

    Widget list = widget.events.isEmpty
        ? Text('No trace events')
        : ListView.builder(
            controller: _controller._listController,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            itemCount: widget.events.length,
            onSelect: (_) => _selectCurrent(),
            itemBuilder: (context, index, activeSelected) {
              final selected = index == _controller.selectedIndex;
              return _TraceTimelineRow(
                event: widget.events[index],
                index: index,
                selected: selected,
                activeSelection: activeSelected,
                canSelect: canSelect,
                copyEnabled: copyEnabled,
                showTimestamp: widget.showTimestamp,
                onSelect: () => _selectAt(index),
                onCopy: () => _copyAt(index),
              );
            },
          );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy trace event',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    final counts = _statusCounts(widget.events);
    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.traceTimeline,
        label: _sanitizeTraceText(widget.label),
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (canSelect) SemanticAction.submit,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleTimelineAction,
        state: SemanticState({
          'collectionRowCount': widget.events.length,
          'traceEventCount': widget.events.length,
          'runningTraceEventCount': counts[TraceTimelineStatus.running] ?? 0,
          'failedTraceEventCount': counts[TraceTimelineStatus.failed] ?? 0,
          'warningTraceEventCount': counts[TraceTimelineStatus.warning] ?? 0,
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          'selectedIndex': ?selectedIndex,
          if (selectedEvent != null) ..._selectedTraceState(selectedEvent),
        }),
        child: list,
      ),
    );
  }
}

class _TraceTimelineRow extends StatelessWidget {
  const _TraceTimelineRow({
    required this.event,
    required this.index,
    required this.selected,
    required this.activeSelection,
    required this.canSelect,
    required this.copyEnabled,
    required this.showTimestamp,
    required this.onSelect,
    required this.onCopy,
  });

  final TraceTimelineEntry event;
  final int index;
  final bool selected;
  final bool activeSelection;
  final bool canSelect;
  final bool copyEnabled;
  final bool showTimestamp;
  final Future<void> Function() onSelect;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final label = _sanitizeTraceText(event.label);
    final detail = event.detail == null
        ? null
        : _sanitizeTraceText(event.detail!);
    final source = event.source == null
        ? null
        : _sanitizeTraceText(event.source!);
    final id = _sanitizeTraceText(event.displayId);

    return Semantics(
      role: SemanticRole.traceEvent,
      label: label,
      value: event.status.name,
      hint: detail,
      selected: selected,
      enabled: event.enabled,
      busy: event.busy,
      validationError: event.status == TraceTimelineStatus.failed
          ? detail
          : null,
      actions: {
        if (event.enabled && canSelect) SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            if (event.enabled && canSelect) await onSelect();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        ...event.metadata,
        'rowIndex': index,
        'viewIndex': index,
        'rowKey': id,
        'traceId': id,
        'traceKind': event.kind.name,
        'traceStatus': event.status.name,
        'traceDurationMs': ?event.duration?.inMilliseconds,
        'traceTimestamp': ?event.timestamp?.toIso8601String(),
        'source': ?source,
        'outputSanitized': _eventWasSanitized(event),
      }),
      child: Text(
        _rowText(
          label: label,
          event: event,
          activeSelection: activeSelection,
          timestamp: showTimestamp ? event.timestamp : null,
        ),
        style: _rowStyle(
          Theme.of(context),
          selected: selected,
          activeSelection: activeSelection,
          event: event,
        ),
      ),
    );
  }
}

Map<TraceTimelineStatus, int> _statusCounts(List<TraceTimelineEntry> events) {
  final counts = <TraceTimelineStatus, int>{};
  for (final event in events) {
    counts[event.status] = (counts[event.status] ?? 0) + 1;
  }
  return counts;
}

Map<String, Object?> _selectedTraceState(TraceTimelineEntry event) {
  final id = _sanitizeTraceText(event.displayId);
  return <String, Object?>{
    'selectedKey': id,
    'selectedTraceId': id,
    'selectedTraceKind': event.kind.name,
    'selectedTraceStatus': event.status.name,
  };
}

String _rowText({
  required String label,
  required TraceTimelineEntry event,
  required bool activeSelection,
  DateTime? timestamp,
}) {
  final prefix = activeSelection ? '> ' : '  ';
  final clock = timestamp == null ? '' : '${_formatClock(timestamp)} ';
  final meta = <String>[
    event.kind.name,
    event.status.name,
    if (event.duration != null) '${event.duration!.inMilliseconds}ms',
    if (event.source != null) _sanitizeTraceText(event.source!),
  ];
  return '$prefix$clock${_statusMarker(event.status)} $label  '
      '${meta.join('  ')}';
}

/// Local `HH:mm:ss` clock for the optional per-row timestamp.
String _formatClock(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _statusMarker(TraceTimelineStatus status) {
  return switch (status) {
    TraceTimelineStatus.queued => '[ ]',
    TraceTimelineStatus.running => '[>]',
    TraceTimelineStatus.succeeded => '[x]',
    TraceTimelineStatus.failed => '[!]',
    TraceTimelineStatus.cancelled => '[-]',
    // Distinct from failed's [!] so the two read apart without relying on color.
    TraceTimelineStatus.warning => '[*]',
    TraceTimelineStatus.info => '[i]',
  };
}

String _truncateGraphemes(String text, int? maxLength) {
  if (maxLength == null) return text;
  if (maxLength == 0) return '';
  final characters = text.characters;
  if (characters.length <= maxLength) return text;
  return characters.take(maxLength).toString();
}

bool _eventWasSanitized(TraceTimelineEntry event) {
  return _sanitizeTraceText(event.displayId) != event.displayId ||
      _sanitizeTraceText(event.label) != event.label ||
      (event.detail != null &&
          _sanitizeTraceText(event.detail!) != event.detail) ||
      (event.source != null &&
          _sanitizeTraceText(event.source!) != event.source);
}

String _sanitizeTraceText(String text) {
  return sanitizeForDisplay(
    text.replaceAll(_traceLineBreakPattern, ' '),
  ).replaceAll(RegExp(' +'), ' ').trim();
}

final _traceLineBreakPattern = RegExp(r'[\r\n\t]');

CellStyle _rowStyle(
  ThemeData theme, {
  required bool selected,
  required bool activeSelection,
  required TraceTimelineEntry event,
}) {
  if (!event.enabled) return theme.mutedStyle;
  if (activeSelection) return theme.selectionStyle;
  if (selected) return theme.mutedStyle;
  return switch (event.status) {
    TraceTimelineStatus.queued => theme.mutedStyle,
    TraceTimelineStatus.running => const CellStyle(foreground: AnsiColor(11)),
    TraceTimelineStatus.succeeded => const CellStyle(foreground: AnsiColor(10)),
    TraceTimelineStatus.failed => const CellStyle(
      bold: true,
      foreground: AnsiColor(9),
    ),
    TraceTimelineStatus.cancelled => const CellStyle(foreground: AnsiColor(8)),
    TraceTimelineStatus.warning => const CellStyle(foreground: AnsiColor(11)),
    TraceTimelineStatus.info => CellStyle.empty,
  };
}
