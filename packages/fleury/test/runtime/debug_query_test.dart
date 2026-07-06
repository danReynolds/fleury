import 'dart:convert';

import 'package:fleury/src/debug/debug_events.dart';
import 'package:fleury/src/debug/debug_frame_log.dart';
import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/runtime/debug_query.dart';
import 'package:fleury/src/runtime/output_capture.dart';
import 'package:fleury/src/runtime/runtime_error_overlay.dart';
import 'package:test/test.dart';

FrameEvent _frame(int n) => FrameEvent(
      frameNumber: n,
      reason: 'r$n',
      build: Duration(microseconds: n),
      layout: Duration(microseconds: n * 2),
      paint: Duration(microseconds: n * 3),
      diff: Duration(microseconds: n * 4),
      dirtyCells: n,
      bufferSize: const CellSize(80, 24),
    );

List<Object?> _decode(
  String kind, {
  DebugFrameLog? frameLog,
  LogBuffer? logBuffer,
  RuntimeErrorReporter? errorReporter,
  int limit = 50,
}) =>
    jsonDecode(utf8.decode(buildDebugResponseJson(
      kind,
      limit: limit,
      frameLog: frameLog,
      logBuffer: logBuffer,
      errorReporter: errorReporter,
    ))) as List<Object?>;

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('DebugFrameLog', () {
    test('captures emitted frames, bounded, newest last', () async {
      final log = DebugFrameLog(capacity: 3);
      addTearDown(log.dispose);
      for (var i = 1; i <= 5; i++) {
        DebugEvents.emitFrame(_frame(i));
      }
      await _pump();
      final json = log.toJson();
      expect(json.map((r) => r['frame']), [3, 4, 5], reason: 'oldest dropped');
      expect(json.last['buildUs'], 5);
      expect(json.last['paintUs'], 15);
    });

    test('toJson honours the limit', () async {
      final log = DebugFrameLog();
      addTearDown(log.dispose);
      for (var i = 1; i <= 10; i++) {
        DebugEvents.emitFrame(_frame(i));
      }
      await _pump();
      expect(log.toJson(limit: 2).map((r) => r['frame']), [9, 10]);
    });

    test('dispose stops capture', () async {
      final log = DebugFrameLog()..dispose();
      DebugEvents.emitFrame(_frame(1)); // no listener now
      await _pump();
      expect(log.toJson(), isEmpty);
    });
  });

  group('buildDebugResponseJson', () {
    test('logs: source-tagged lines, newest last, limited', () {
      final buffer = LogBuffer();
      buffer.add(const LogLine('boot', LogSource.stdout));
      buffer.add(const LogLine('oops', LogSource.stderr));
      buffer.add(const LogLine('tail', LogSource.stdout));
      final records = _decode(debugKindLogs, logBuffer: buffer, limit: 2);
      expect(records, hasLength(2));
      expect((records.first as Map)['text'], 'oops');
      expect((records.last as Map)['source'], 'stdout');
    });

    test('errors: full stack, ISO timestamp, newest last', () {
      final reporter = RuntimeErrorReporter();
      addTearDown(reporter.dispose);
      reporter.report(StateError('kaboom'), StackTrace.current);
      final records = _decode(debugKindErrors, errorReporter: reporter);
      expect(records, hasLength(1));
      final rec = records.single as Map;
      expect(rec['error'].toString(), contains('kaboom'));
      expect(rec['stack'], isNotEmpty);
      expect(rec['at'], contains('T'));
    });

    test('frames delegates to the frame log', () async {
      final log = DebugFrameLog();
      addTearDown(log.dispose);
      DebugEvents.emitFrame(_frame(1));
      await _pump();
      final records = _decode(debugKindFrames, frameLog: log);
      expect(records, hasLength(1));
      expect((records.single as Map)['frame'], 1);
    });

    test('unknown kind and missing providers yield an empty document', () {
      expect(_decode('bogus'), isEmpty);
      expect(_decode(debugKindLogs), isEmpty);
      expect(_decode(debugKindErrors, limit: 0), isEmpty);
    });
  });
}
