import 'dart:async';

import 'debug_events.dart';

/// A bounded, subscribe-once ring of recent [FrameEvent]s off [DebugEvents].
///
/// The in-terminal debug panel keeps its own history for rendering; this is
/// the *headless* equivalent — a frame log a remote debug consumer (the agent
/// bridge, a future browser DevTools panel) can pull from over the wire, in a
/// session that has no panel. Constructing it makes [DebugEvents.hasListeners]
/// true, which is what turns on per-frame timing capture — so create it only
/// when a debug consumer is actually attached, and [dispose] it when they
/// detach.
class DebugFrameLog {
  DebugFrameLog({this.capacity = 120}) {
    _sub = DebugEvents.stream.listen((event) {
      if (event is! FrameDebugEvent) return;
      _records.add(event.frame);
      if (_records.length > capacity) _records.removeAt(0);
    });
  }

  final int capacity;
  final List<FrameEvent> _records = <FrameEvent>[];
  StreamSubscription<DebugEvent>? _sub;

  /// The most recent frames, oldest first, at most [capacity].
  List<FrameEvent> get records => List<FrameEvent>.unmodifiable(_records);

  /// The last [limit] frames as JSON-friendly maps, oldest first — the wire
  /// shape a debug consumer receives for `kind == 'frames'`.
  List<Map<String, Object?>> toJson({int limit = 50}) {
    final start = _records.length > limit ? _records.length - limit : 0;
    return [
      for (final f in _records.sublist(start))
        <String, Object?>{
          'frame': f.frameNumber,
          'reason': f.reason,
          'buildUs': f.build.inMicroseconds,
          'layoutUs': f.layout.inMicroseconds,
          'paintUs': f.paint.inMicroseconds,
          'diffUs': f.diff.inMicroseconds,
          'dirtyCells': f.dirtyCells,
          'w': f.bufferSize.cols,
          'h': f.bufferSize.rows,
        },
    ];
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _records.clear();
  }
}
