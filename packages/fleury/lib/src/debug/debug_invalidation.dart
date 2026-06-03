import 'debug_events.dart';

/// Debug-only collector for frame invalidation causes.
///
/// The hot path checks [DebugEvents.hasListeners] before allocating labels, so
/// production runs with no debug subscriber pay only a branch. `runTui` drains
/// the pending sources once per emitted [FrameEvent].
final class DebugInvalidations {
  DebugInvalidations._();

  static final Map<String, int> _pending = <String, int>{};

  static void recordBuild(String source) {
    _record('build', source);
  }

  static void recordLayout(String source) {
    _record('layout', source);
  }

  static void recordPaint(String source) {
    _record('paint', source);
  }

  static void _record(String kind, String source) {
    if (!DebugEvents.hasListeners) return;
    final key = '$kind:$source';
    _pending[key] = (_pending[key] ?? 0) + 1;
  }

  /// Returns pending sources ordered by impact, then clears the collector.
  static List<String> drain({int limit = 8}) {
    if (_pending.isEmpty) return const <String>[];
    final entries = _pending.entries.toList(growable: false)
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    _pending.clear();

    final result = <String>[];
    final take = entries.length < limit ? entries.length : limit;
    for (var i = 0; i < take; i++) {
      final entry = entries[i];
      result.add(entry.value == 1 ? entry.key : '${entry.key} x${entry.value}');
    }
    if (entries.length > limit) {
      result.add('+${entries.length - limit} more');
    }
    return result;
  }

  static void reset() {
    _pending.clear();
  }
}
