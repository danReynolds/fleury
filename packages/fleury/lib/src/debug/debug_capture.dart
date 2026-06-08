import 'dart:async';

import '../animation/clock.dart';
import '../effects/task.dart';
import '../foundation/geometry.dart';
import '../rendering/render_layout_stats.dart';
import '../rendering/render_repaint_boundary.dart';
import '../rendering/text_sanitizer.dart';
import '../semantics/accessibility.dart';
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import '../terminal/diagnostics.dart';
import 'debug_events.dart';

final class DebugOutputSummary {
  const DebugOutputSummary({
    required this.source,
    required this.lineCount,
    this.sanitizedCount = 0,
    this.truncatedCount = 0,
  });

  final String source;
  final int lineCount;
  final int sanitizedCount;
  final int truncatedCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'lineCount': lineCount,
    'sanitizedCount': sanitizedCount,
    'truncatedCount': truncatedCount,
  };
}

/// Safe marker for deterministic test/replay clock progress.
///
/// The marker records a monotonic duration from a caller-owned clock, not a
/// wall-clock timestamp. That keeps artifacts deterministic and avoids leaking
/// host timing into replay-oriented tests.
final class DebugTimeMarker {
  const DebugTimeMarker({
    required this.label,
    this.source,
    this.elapsed = Duration.zero,
    this.sequence,
    this.fakeTime = true,
  });

  factory DebugTimeMarker.fromClock({
    required String label,
    required Clock clock,
    String? source,
    int? sequence,
    bool fakeTime = true,
  }) {
    return DebugTimeMarker(
      label: label,
      source: source,
      elapsed: clock.now,
      sequence: sequence,
      fakeTime: fakeTime,
    );
  }

  final String label;
  final String? source;
  final Duration elapsed;
  final int? sequence;
  final bool fakeTime;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': sanitizeForDisplay(label),
    if (source != null) 'source': sanitizeForDisplay(source!),
    'elapsedMicros': elapsed.inMicroseconds,
    if (sequence != null) 'sequence': sequence,
    'fakeTime': fakeTime,
  };
}

/// Safe, metadata-only summary of a task event for debug-capture artifacts.
///
/// Raw task output, result values, error messages, and stack traces are
/// intentionally omitted. Those fields can contain application secrets; capture
/// artifacts should preserve workflow shape without becoming a second output
/// log.
final class DebugTaskEventSummary {
  const DebugTaskEventSummary({
    required this.source,
    required this.sequence,
    required this.runId,
    required this.kind,
    required this.status,
    this.progressCurrent,
    this.progressTotal,
    this.progressLabel,
    this.outputSource,
    this.outputSeverity,
    this.outputSanitized = false,
    this.outputTruncated = false,
    this.outputOriginalLength,
    this.valueType,
    this.errorType,
  });

  static DebugTaskEventSummary fromTaskEvent<T>(
    TaskEvent<T> event, {
    required String source,
  }) {
    final progress = event.progress;
    final output = event.output;
    final value = event.value;
    final error = event.error;
    return DebugTaskEventSummary(
      source: source,
      sequence: event.sequence,
      runId: event.runId,
      kind: event.kind.name,
      status: event.status.name,
      progressCurrent: progress?.current,
      progressTotal: progress?.total,
      progressLabel: progress?.label == null
          ? null
          : sanitizeForDisplay(progress!.label!),
      outputSource: output?.source,
      outputSeverity: output?.severity.name,
      outputSanitized: output?.sanitized ?? false,
      outputTruncated: output?.truncated ?? false,
      outputOriginalLength: output?.originalLength,
      valueType: value?.runtimeType.toString(),
      errorType: error?.runtimeType.toString(),
    );
  }

  final String source;
  final int sequence;
  final int runId;
  final String kind;
  final String status;
  final num? progressCurrent;
  final num? progressTotal;
  final String? progressLabel;
  final String? outputSource;
  final String? outputSeverity;
  final bool outputSanitized;
  final bool outputTruncated;
  final int? outputOriginalLength;
  final String? valueType;
  final String? errorType;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'sequence': sequence,
    'runId': runId,
    'kind': kind,
    'status': status,
    if (progressCurrent != null) 'progressCurrent': progressCurrent,
    if (progressTotal != null) 'progressTotal': progressTotal,
    if (progressLabel != null) 'progressLabel': progressLabel,
    if (outputSource != null) 'outputSource': outputSource,
    if (outputSeverity != null) 'outputSeverity': outputSeverity,
    if (outputSanitized) 'outputSanitized': true,
    if (outputTruncated) 'outputTruncated': true,
    if (outputOriginalLength != null)
      'outputOriginalLength': outputOriginalLength,
    if (valueType != null) 'valueType': valueType,
    if (errorType != null) 'errorType': errorType,
  };
}

final class DebugCaptureRecorder {
  DebugCaptureRecorder({
    this.maxFrames = 30,
    this.maxInputs = 80,
    this.maxOutputSummaries = 20,
    this.maxTaskEvents = 80,
    this.maxTimeMarkers = 80,
  });

  final int maxFrames;
  final int maxInputs;
  final int maxOutputSummaries;
  final int maxTaskEvents;
  final int maxTimeMarkers;

  final List<FrameEvent> _frames = <FrameEvent>[];
  final List<InputDebugEvent> _inputs = <InputDebugEvent>[];
  final List<DebugOutputSummary> _outputSummaries = <DebugOutputSummary>[];
  final List<DebugTaskEventSummary> _taskEvents = <DebugTaskEventSummary>[];
  final List<DebugTimeMarker> _timeMarkers = <DebugTimeMarker>[];
  TerminalDiagnosis? _terminalDiagnosis;
  StreamSubscription<DebugEvent>? _subscription;
  bool _disposed = false;

  List<FrameEvent> get frames => List<FrameEvent>.unmodifiable(_frames);
  List<InputDebugEvent> get inputs =>
      List<InputDebugEvent>.unmodifiable(_inputs);
  List<DebugOutputSummary> get outputSummaries =>
      List<DebugOutputSummary>.unmodifiable(_outputSummaries);
  List<DebugTaskEventSummary> get taskEvents =>
      List<DebugTaskEventSummary>.unmodifiable(_taskEvents);
  List<DebugTimeMarker> get timeMarkers =>
      List<DebugTimeMarker>.unmodifiable(_timeMarkers);
  TerminalDiagnosis? get terminalDiagnosis => _terminalDiagnosis;

  void attach() {
    _checkNotDisposed();
    _subscription ??= DebugEvents.stream.listen(record);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  void record(DebugEvent event) {
    _checkNotDisposed();
    switch (event) {
      case FrameDebugEvent(:final frame):
        _appendBounded(_frames, frame, maxFrames);
      case InputDebugEvent():
        _appendBounded(_inputs, event, maxInputs);
      case TerminalDebugEvent(:final diagnosis):
        _terminalDiagnosis = diagnosis;
    }
  }

  void recordOutputSummary(DebugOutputSummary summary) {
    _checkNotDisposed();
    _appendBounded(_outputSummaries, summary, maxOutputSummaries);
  }

  void recordTaskEvent<T>(String source, TaskEvent<T> event) {
    _checkNotDisposed();
    _appendBounded(
      _taskEvents,
      DebugTaskEventSummary.fromTaskEvent(event, source: source),
      maxTaskEvents,
    );
  }

  void recordTaskEvents<T>(String source, Iterable<TaskEvent<T>> events) {
    _checkNotDisposed();
    for (final event in events) {
      recordTaskEvent(source, event);
    }
  }

  void recordTimeMarker(DebugTimeMarker marker) {
    _checkNotDisposed();
    _appendBounded(_timeMarkers, marker, maxTimeMarkers);
  }

  DebugCaptureSnapshot snapshot({
    SemanticTree? semanticTree,
    AccessibilitySnapshot? accessibilitySnapshot,
    TerminalDiagnosis? terminalDiagnosis,
  }) {
    return DebugCaptureSnapshot(
      terminalDiagnosis: terminalDiagnosis ?? _terminalDiagnosis,
      semanticTree: semanticTree,
      accessibilitySnapshot: accessibilitySnapshot,
      frames: List<FrameEvent>.unmodifiable(_frames),
      inputs: List<InputDebugEvent>.unmodifiable(_inputs),
      outputSummaries: List<DebugOutputSummary>.unmodifiable(_outputSummaries),
      taskEvents: List<DebugTaskEventSummary>.unmodifiable(_taskEvents),
      timeMarkers: List<DebugTimeMarker>.unmodifiable(_timeMarkers),
    );
  }

  static void _appendBounded<T>(List<T> target, T value, int limit) {
    if (limit <= 0) return;
    target.add(value);
    if (target.length > limit) {
      target.removeRange(0, target.length - limit);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('DebugCaptureRecorder has been disposed.');
    }
  }
}

final class DebugCaptureSnapshot {
  const DebugCaptureSnapshot({
    this.schemaVersion = 1,
    this.terminalDiagnosis,
    this.semanticTree,
    this.accessibilitySnapshot,
    this.frames = const <FrameEvent>[],
    this.inputs = const <InputDebugEvent>[],
    this.outputSummaries = const <DebugOutputSummary>[],
    this.taskEvents = const <DebugTaskEventSummary>[],
    this.timeMarkers = const <DebugTimeMarker>[],
  });

  final int schemaVersion;
  final TerminalDiagnosis? terminalDiagnosis;
  final SemanticTree? semanticTree;
  final AccessibilitySnapshot? accessibilitySnapshot;
  final List<FrameEvent> frames;
  final List<InputDebugEvent> inputs;
  final List<DebugOutputSummary> outputSummaries;
  final List<DebugTaskEventSummary> taskEvents;
  final List<DebugTimeMarker> timeMarkers;

  Map<String, Object?> toJson() {
    final accessibility =
        accessibilitySnapshot ?? semanticTree?.toAccessibilitySnapshot();
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      if (terminalDiagnosis != null) 'terminal': terminalDiagnosis!.toJson(),
      'inputs': <Object?>[for (final input in inputs) _inputToJson(input)],
      'frames': <Object?>[for (final frame in frames) _frameToJson(frame)],
      'outputSummaries': <Object?>[
        for (final output in outputSummaries) output.toJson(),
      ],
      'taskEvents': <Object?>[for (final event in taskEvents) event.toJson()],
      'timeMarkers': <Object?>[
        for (final marker in timeMarkers) marker.toJson(),
      ],
      if (semanticTree != null) 'semantics': semanticTree!.toInspectionJson(),
      if (accessibility != null)
        'accessibility': _accessibilitySnapshotToJson(accessibility),
    };
  }
}

/// Queryable form of a [DebugCaptureSnapshot] for regression tests.
///
/// This is intentionally smaller than full replay: it indexes the redacted JSON
/// snapshot so tests can assert on captured inputs, frames, output summaries,
/// accessibility narration, and semantic facts without hand-walking nested
/// maps.
final class DebugCaptureArtifact {
  DebugCaptureArtifact._(this._json);

  factory DebugCaptureArtifact.fromSnapshot(DebugCaptureSnapshot snapshot) {
    return DebugCaptureArtifact.fromJson(snapshot.toJson());
  }

  factory DebugCaptureArtifact.fromJson(Map<String, Object?> json) {
    return DebugCaptureArtifact._(Map<String, Object?>.unmodifiable(json));
  }

  final Map<String, Object?> _json;

  Map<String, Object?> get json => _json;

  int get schemaVersion =>
      _json['schemaVersion'] is int ? _json['schemaVersion']! as int : 0;

  List<Map<String, Object?>> get inputs => _jsonMapList(_json['inputs']);

  List<Map<String, Object?>> get frames => _jsonMapList(_json['frames']);

  List<Map<String, Object?>> get outputSummaries =>
      _jsonMapList(_json['outputSummaries']);

  List<Map<String, Object?>> get taskEvents =>
      _jsonMapList(_json['taskEvents']);

  List<Map<String, Object?>> get timeMarkers =>
      _jsonMapList(_json['timeMarkers']);

  int get semanticNodeCount {
    final semantics = _jsonMap(_json['semantics']);
    final count = semantics['nodeCount'];
    return count is int ? count : 0;
  }

  int semanticRoleCount(String role) {
    final semantics = _jsonMap(_json['semantics']);
    final counts = _jsonMap(semantics['roleCounts']);
    return _jsonInt(counts[role]);
  }

  int get semanticActionCount {
    final semantics = _jsonMap(_json['semantics']);
    return _jsonInt(semantics['actionCount']);
  }

  String? get focusedSemanticNodeId {
    final semantics = _jsonMap(_json['semantics']);
    final id = semantics['focusedNodeId'];
    return id is String ? id : null;
  }

  SemanticInspectionSnapshot? get semanticInspectionSnapshot {
    final semantics = _jsonMap(_json['semantics']);
    if (semantics.isEmpty) return null;
    try {
      return SemanticInspectionSnapshot.fromJson(semantics);
    } on FormatException {
      return null;
    }
  }

  String? get accessibilityPlainText {
    final accessibility = _jsonMap(_json['accessibility']);
    final plainText = accessibility['plainText'];
    return plainText is String ? plainText : null;
  }

  Map<String, Object?> get accessibilitySummary {
    final accessibility = _jsonMap(_json['accessibility']);
    return _jsonMap(accessibility['summary']);
  }

  int get accessibilityNodeCount => _jsonInt(accessibilitySummary['nodeCount']);

  String? get focusedAccessibilityNodeId {
    final id = accessibilitySummary['focusedNodeId'];
    return id is String ? id : null;
  }

  int accessibilityRoleCount(String role) {
    final counts = _jsonMap(accessibilitySummary['roleCounts']);
    return _jsonInt(counts[role]);
  }

  int get accessibilityActionCount =>
      _jsonInt(accessibilitySummary['actionCount']);

  int get accessibilityRedactedValueCount =>
      _jsonInt(accessibilitySummary['redactedValueCount']);

  bool hasInput({String? kind, String? summary}) {
    return inputs.any(
      (input) =>
          (kind == null || input['kind'] == kind) &&
          (summary == null || input['summary'] == summary),
    );
  }

  bool hasFrame({String? reason, String? dirtySource}) {
    return frames.any((frame) {
      if (reason != null && frame['reason'] != reason) return false;
      if (dirtySource == null) return true;
      final sources = frame['dirtySources'];
      return sources is List<Object?> && sources.contains(dirtySource);
    });
  }

  List<Map<String, Object?>> outputSummariesFor({String? source}) {
    return [
      for (final summary in outputSummaries)
        if (source == null || summary['source'] == source) summary,
    ];
  }

  List<Map<String, Object?>> taskEventsFor({String? source, String? kind}) {
    return [
      for (final event in taskEvents)
        if ((source == null || event['source'] == source) &&
            (kind == null || event['kind'] == kind))
          event,
    ];
  }

  bool hasTaskEvent({String? source, String? kind, String? status}) {
    return taskEvents.any(
      (event) =>
          (source == null || event['source'] == source) &&
          (kind == null || event['kind'] == kind) &&
          (status == null || event['status'] == status),
    );
  }

  List<Map<String, Object?>> timeMarkersFor({String? source, String? label}) {
    return [
      for (final marker in timeMarkers)
        if ((source == null || marker['source'] == source) &&
            (label == null || marker['label'] == label))
          marker,
    ];
  }

  bool hasTimeMarker({String? source, String? label, bool? fakeTime}) {
    return timeMarkers.any(
      (marker) =>
          (source == null || marker['source'] == source) &&
          (label == null || marker['label'] == label) &&
          (fakeTime == null || marker['fakeTime'] == fakeTime),
    );
  }

  Iterable<DebugCaptureSemanticNode> semanticNodes({
    String? role,
    String? label,
    Object? value,
    bool? focused,
    bool? selected,
    String? action,
    Map<String, Object?> stateContains = const <String, Object?>{},
  }) sync* {
    final semantics = _jsonMap(_json['semantics']);
    final root = _jsonMap(semantics['root']);
    if (root.isEmpty) return;

    final stack = <Map<String, Object?>>[root];
    while (stack.isNotEmpty) {
      final node = DebugCaptureSemanticNode._(stack.removeLast());
      if (node._matches(
        role: role,
        label: label,
        value: value,
        focused: focused,
        selected: selected,
        action: action,
        stateContains: stateContains,
      )) {
        yield node;
      }
      final children = node._children;
      for (var i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
  }

  DebugCaptureSemanticNode singleSemanticNode({
    String? role,
    String? label,
    Object? value,
    bool? focused,
    bool? selected,
    String? action,
    Map<String, Object?> stateContains = const <String, Object?>{},
  }) {
    final matches = semanticNodes(
      role: role,
      label: label,
      value: value,
      focused: focused,
      selected: selected,
      action: action,
      stateContains: stateContains,
    ).toList(growable: false);
    if (matches.length != 1) {
      throw StateError(
        'Expected exactly one debug-capture semantic node, found '
        '${matches.length}.',
      );
    }
    return matches.single;
  }
}

final class DebugCaptureSemanticNode {
  DebugCaptureSemanticNode._(this.json);

  final Map<String, Object?> json;

  String? get id => json['id'] is String ? json['id']! as String : null;
  String? get role => json['role'] is String ? json['role']! as String : null;
  String? get label =>
      json['label'] is String ? json['label']! as String : null;
  Object? get value => json['value'];
  bool get enabled => json['enabled'] != false;
  bool get focused => json['focused'] == true;
  bool get selected => json['selected'] == true;
  bool get busy => json['busy'] == true;
  Map<String, Object?> get state => _jsonMap(json['state']);
  List<String> get actions => _jsonStringList(json['actions']);

  Object? operator [](String key) => json[key];

  List<Map<String, Object?>> get _children => _jsonMapList(json['children']);

  bool _matches({
    String? role,
    String? label,
    Object? value,
    bool? focused,
    bool? selected,
    String? action,
    required Map<String, Object?> stateContains,
  }) {
    if (role != null && this.role != role) return false;
    if (label != null && this.label != label) return false;
    if (value != null && this.value != value) return false;
    if (focused != null && this.focused != focused) return false;
    if (selected != null && this.selected != selected) return false;
    if (action != null && !actions.contains(action)) return false;
    if (stateContains.isNotEmpty) {
      final state = this.state;
      for (final entry in stateContains.entries) {
        if (!state.containsKey(entry.key) || state[entry.key] != entry.value) {
          return false;
        }
      }
    }
    return true;
  }
}

Map<String, Object?> _inputToJson(InputDebugEvent input) {
  return <String, Object?>{
    'kind': input.kind,
    'summary': input.summary,
    if (input.resizeSize != null) 'size': _sizeToJson(input.resizeSize!),
  };
}

Map<String, Object?> _frameToJson(FrameEvent frame) {
  return <String, Object?>{
    'frameNumber': frame.frameNumber,
    'reason': frame.reason,
    'buildMicros': frame.build.inMicroseconds,
    'layoutMicros': frame.layout.inMicroseconds,
    'paintMicros': frame.paint.inMicroseconds,
    'diffMicros': frame.diff.inMicroseconds,
    'dirtyCells': frame.dirtyCells,
    if (frame.dirtyBounds != null)
      'dirtyBounds': _rectToJson(frame.dirtyBounds!),
    if (frame.dirtySpans.hasDirtySpans)
      'dirtySpans': _dirtySpansToJson(frame.dirtySpans),
    if (frame.dirtySources.isNotEmpty) 'dirtySources': frame.dirtySources,
    if (frame.layoutStats.hasLayouts)
      'layoutStats': _layoutStatsToJson(frame.layoutStats),
    if (frame.repaintBoundaries.hasBoundaries)
      'repaintBoundaries': _repaintBoundariesToJson(frame.repaintBoundaries),
    'bufferSize': _sizeToJson(frame.bufferSize),
  };
}

Map<String, Object?> _dirtySpansToJson(DirtySpanFrameStats stats) {
  return <String, Object?>{
    'rowCount': stats.rowCount,
    'spanCount': stats.spanCount,
    'coveredCellCount': stats.coveredCellCount,
    'longestSpan': stats.longestSpan,
    'averageSpanLength': stats.averageSpanLength,
    'spansPerRow': stats.spansPerRow,
  };
}

Map<String, Object?> _layoutStatsToJson(RenderLayoutFrameStats stats) {
  return <String, Object?>{
    'performedCount': stats.performedCount,
    'skippedCount': stats.skippedCount,
    'totalCount': stats.totalCount,
  };
}

Map<String, Object?> _repaintBoundariesToJson(RepaintBoundaryFrameStats stats) {
  return <String, Object?>{
    'boundaryCount': stats.boundaryCount,
    'repaintedCount': stats.repaintedCount,
    'cachedCount': stats.cachedCount,
    'emptyCount': stats.emptyCount,
    'copiedCellCount': stats.copiedCellCount,
  };
}

Map<String, Object?> _accessibilitySnapshotToJson(
  AccessibilitySnapshot snapshot,
) {
  return <String, Object?>{
    'nodeCount': snapshot.nodes.length,
    'summary': snapshot.summary.toJson(),
    'plainText': snapshot.toPlainText(),
    'root': snapshot.root.toJson(),
  };
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return const <String, Object?>{};
}

int _jsonInt(Object? value) => value is int ? value : 0;

List<Map<String, Object?>> _jsonMapList(Object? value) {
  if (value is! List<Object?>) return const <Map<String, Object?>>[];
  return [
    for (final item in value)
      if (item is Map<String, Object?>)
        item
      else if (item is Map)
        Map<String, Object?>.from(item),
  ];
}

List<String> _jsonStringList(Object? value) {
  if (value is! List<Object?>) return const <String>[];
  return [
    for (final item in value)
      if (item is String) item,
  ];
}

Map<String, Object?> _rectToJson(CellRect rect) => <String, Object?>{
  'left': rect.left,
  'top': rect.top,
  'cols': rect.size.cols,
  'rows': rect.size.rows,
};

Map<String, Object?> _sizeToJson(CellSize size) => <String, Object?>{
  'cols': size.cols,
  'rows': size.rows,
};
