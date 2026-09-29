// Counts object creations, not live heap objects or bytes. The VM service client
// runs in another process so decoding profiler responses cannot fill our buffer.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as isolates;

final _workTag = developer.UserTag('fleury-allocation-window');
final _guards = <_TraceGuard?>[null, null];

class _TraceGuard {
  _TraceGuard(this.sequence);
  final int sequence;
}

class AllocationCounts {
  int total = 0;
  int project = 0;
  final classes = <String, int>{};
}

class AllocationTraceMeter {
  AllocationTraceMeter._(this._process, this._responses, this._errors);
  final Process _process;
  final StreamIterator<String> _responses;
  final Future<String> _errors;
  int _sequence = 0;

  static Future<AllocationTraceMeter> start(String isolate,
      {bool includeCore = true}) async {
    // Load the guard before the external controller enumerates classes.
    _guards[0] = _TraceGuard(-1);
    final uri = (await developer.Service.getInfo()).serverUri!;
    final ws = uri.replace(scheme: 'ws', path: '${uri.path}ws');
    final process = await Process.start(Platform.resolvedExecutable, [
      if (await isolates.Isolate.packageConfig case final config?)
        '--packages=$config',
      Platform.script.resolve('allocation_trace_driver.dart').toFilePath(),
      ws.toString(),
      isolate,
      if (!includeCore) '--project-only',
    ]);
    final meter = AllocationTraceMeter._(
        process,
        StreamIterator(process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())),
        process.stderr.transform(utf8.decoder).join());
    try {
      await meter._read();
      return meter;
    } catch (_) {
      process.kill();
      await meter._responses.cancel();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _read() async {
    if (!await _responses.moveNext().timeout(const Duration(seconds: 60))) {
      throw StateError('Allocation controller exited: ${await _errors}');
    }
    final response = jsonDecode(_responses.current) as Map<String, dynamic>;
    if (response['error'] case final String error) throw StateError(error);
    return response;
  }

  Future<Map<String, dynamic>> _command(Map<String, Object> command) {
    _process.stdin.writeln(jsonEncode(command));
    return _read();
  }

  Future<void> measure(AllocationCounts result, void Function() work,
      {bool collectAfter = false, bool collectInside = false}) async {
    final start = developer.Timeline.now;
    final previous = _workTag.makeCurrent();
    try {
      _guards[0] = _TraceGuard(_sequence++);
      work();
      if (collectInside) {
        // Canary only; production work windows are synchronous.
        previous.makeCurrent();
        await _command({'operation': 'gc'});
        _workTag.makeCurrent();
      }
      _guards[1] = _TraceGuard(_sequence++);
    } finally {
      previous.makeCurrent();
    }
    final end = developer.Timeline.now;
    final response = await _command({
      'operation': 'capture',
      'start': start,
      'end': end,
      'gc': collectAfter,
    });
    if (_guards[0]?.sequence != _sequence - 2 ||
        _guards[1]?.sequence != _sequence - 1) {
      throw StateError('Allocation guards were not retained.');
    }
    result.total += response['total'] as int;
    result.project += response['project'] as int;
    for (final entry in (response['classes'] as Map<String, dynamic>).entries) {
      final count = entry.value as int;
      result.classes.update(entry.key, (n) => n + count, ifAbsent: () => count);
    }
  }

  Future<void> dispose() async {
    try {
      await _command({'operation': 'stop'});
      await _process.exitCode.timeout(const Duration(seconds: 10));
    } finally {
      _process.kill();
      await _responses.cancel();
      _guards[0] = null;
      _guards[1] = null;
    }
  }
}

Future<AllocationCounts> measureAllocations(String isolate,
    {required int iterations,
    required void Function() work,
    bool includeCore = true}) async {
  final meter =
      await AllocationTraceMeter.start(isolate, includeCore: includeCore);
  final result = AllocationCounts();
  try {
    // Tracing changes allocation stubs. Warm those before recording the window.
    for (var i = 0; i < 20; i++) {
      work();
    }
    // One bounded window avoids per-frame profiler/IPC overhead and keeps the
    // fixed buffer available for workload samples. Overflow fails closed.
    await meter.measure(result, () {
      for (var i = 0; i < iterations; i++) {
        work();
      }
    });
    return result;
  } finally {
    await meter.dispose();
  }
}
