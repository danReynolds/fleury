// Custom-monitor registry — user code adds named gauges (counters,
// queue depths, websocket counts, anything Stringifiable) and the
// DebugPanel's Live tab renders them alongside the built-in frame
// metrics. Inspired by Godot's `Performance.add_custom_monitor()`,
// which is the most-copyable API design in this space.
//
// Usage:
//
//   void main() {
//     FleuryDebug.registerMonitor('peers', () => peerStore.length);
//     FleuryDebug.registerMonitor('queue', () => jobQueue.depth);
//     runApp(...);
//   }
//
// Each registered getter runs once per debug-panel rebuild — keep
// them cheap (no I/O, no allocation).

import '../foundation/change_notifier.dart';

/// One named monitor row in the debug panel.
final class DebugMonitor {
  const DebugMonitor(this.name, this.value);

  /// Display label (≤ ~16 chars renders cleanly in the docked panel).
  final String name;

  /// Cheap getter. Runs each time the panel rebuilds — keep it
  /// allocation-free; this is on the dev-time render loop.
  final Object Function() value;
}

/// Global registry of custom monitors. The DebugPanel listens to this
/// and rebuilds when monitors come and go (so `registerMonitor` in
/// `initState` of some widget mid-app correctly surfaces the new
/// monitor in the live panel without a manual refresh).
final class FleuryDebug extends ChangeNotifier {
  FleuryDebug._();

  /// Singleton instance — there's exactly one debug registry per
  /// process. Keeps the API a one-liner from anywhere in user code.
  static final FleuryDebug instance = FleuryDebug._();

  final List<DebugMonitor> _monitors = [];

  /// Snapshot of registered monitors in registration order.
  List<DebugMonitor> get monitors => List.unmodifiable(_monitors);

  /// Register a named monitor. Duplicate names overwrite the previous
  /// entry — useful for "live-updating" a getter from a hot-reload.
  static void registerMonitor(String name, Object Function() value) {
    final existing = instance._monitors.indexWhere((m) => m.name == name);
    final entry = DebugMonitor(name, value);
    if (existing >= 0) {
      instance._monitors[existing] = entry;
    } else {
      instance._monitors.add(entry);
    }
    instance.notifyListeners();
  }

  /// Remove a previously-registered monitor. No-op if not registered.
  static void unregisterMonitor(String name) {
    final removed = instance._monitors.length;
    instance._monitors.removeWhere((m) => m.name == name);
    if (instance._monitors.length != removed) instance.notifyListeners();
  }

  /// Drop every registered monitor. Mainly for tests.
  static void clearMonitors() {
    if (instance._monitors.isEmpty) return;
    instance._monitors.clear();
    instance.notifyListeners();
  }
}
