import 'dart:convert';
import 'dart:typed_data';

import '../debug/debug_frame_log.dart';
import 'output_capture.dart';
import 'runtime_error_overlay.dart';

/// The debug record kinds a remote peer can pull. Strings on the wire so the
/// set can grow without a protocol bump; an unknown kind yields an empty
/// document.
const debugKindFrames = 'frames';
const debugKindLogs = 'logs';
const debugKindErrors = 'errors';

/// Assembles the JSON answer to a peer [DebugRequestFrame], newest records
/// last, bounded to [limit]. Shared by the remote wire path and its tests so
/// the shape is defined once. Returns a UTF-8 JSON list document; unknown
/// kinds return `[]` rather than erroring, so a newer peer probing an unknown
/// kind degrades cleanly.
Uint8List buildDebugResponseJson(
  String kind, {
  required int limit,
  DebugFrameLog? frameLog,
  LogBuffer? logBuffer,
  RuntimeErrorReporter? errorReporter,
}) {
  final effLimit = limit < 0 ? 0 : limit;
  final List<Object?> records;
  switch (kind) {
    case debugKindFrames:
      records = frameLog?.toJson(limit: effLimit) ?? const [];
    case debugKindLogs:
      final lines = logBuffer?.lines ?? const <LogLine>[];
      final start = lines.length > effLimit ? lines.length - effLimit : 0;
      records = [
        for (final l in lines.sublist(start))
          <String, Object?>{'source': l.source.name, 'text': l.text},
      ];
    case debugKindErrors:
      final history = errorReporter?.history ?? const <RuntimeErrorRecord>[];
      final start = history.length > effLimit ? history.length - effLimit : 0;
      records = [
        for (final r in history.sublist(start))
          <String, Object?>{
            'at': r.when.toIso8601String(),
            'error': r.error.toString(),
            // Full trace is agent-consumable — it's the point of the tab; the
            // panel truncates for space, an agent wants the whole thing.
            'stack': r.stackTrace.toString(),
          },
      ];
    default:
      records = const [];
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(records)));
}
