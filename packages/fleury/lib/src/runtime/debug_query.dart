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
/// last, bounded to [limit] and [maxBytes]. Shared by the remote wire path and
/// its tests so the shape is defined once. Returns a UTF-8 JSON list document;
/// unknown kinds return `[]` rather than erroring, so a newer peer probing an
/// unknown kind degrades cleanly.
Uint8List buildDebugResponseJson(
  String kind, {
  required int limit,
  required int maxBytes,
  DebugFrameLog? frameLog,
  LogBuffer? logBuffer,
  RuntimeErrorReporter? errorReporter,
}) {
  if (maxBytes < 2) {
    throw ArgumentError.value(
      maxBytes,
      'maxBytes',
      'must fit at least the empty JSON list',
    );
  }
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
  return _encodeNewestSuffix(records, maxBytes: maxBytes);
}

Uint8List _encodeNewestSuffix(List<Object?> records, {required int maxBytes}) {
  // Select from newest to oldest so a large history never spends time or
  // temporary memory encoding records that cannot make the response. Stop at
  // the first record that does not fit: the result remains a contiguous newest
  // suffix, rather than silently skipping a recent fault in favor of older
  // smaller data.
  final selectedNewestFirst = <List<int>>[];
  var encodedLength = 2; // '[' + ']'
  for (var i = records.length - 1; i >= 0; i--) {
    final encoded = utf8.encode(jsonEncode(records[i]));
    final separator = selectedNewestFirst.isEmpty ? 0 : 1;
    if (encodedLength + separator + encoded.length > maxBytes) break;
    selectedNewestFirst.add(encoded);
    encodedLength += separator + encoded.length;
  }

  final out = BytesBuilder(copy: false)..addByte(0x5B); // '['
  for (var i = selectedNewestFirst.length - 1; i >= 0; i--) {
    if (i != selectedNewestFirst.length - 1) out.addByte(0x2C); // ','
    out.add(selectedNewestFirst[i]);
  }
  out.addByte(0x5D); // ']'
  final bytes = out.toBytes();
  assert(bytes.length == encodedLength);
  return bytes;
}
