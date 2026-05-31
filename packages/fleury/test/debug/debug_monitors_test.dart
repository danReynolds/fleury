// Custom-monitor registry tests. The registry is a global singleton,
// so each test clears state in setUp.

import 'package:fleury/src/debug/debug_monitors.dart';
import 'package:test/test.dart';

void main() {
  setUp(FleuryDebug.clearMonitors);

  group('FleuryDebug.registerMonitor', () {
    test('appends a monitor and notifies', () {
      var notified = 0;
      FleuryDebug.instance.addListener(() => notified++);

      FleuryDebug.registerMonitor('peers', () => 7);
      expect(FleuryDebug.instance.monitors, hasLength(1));
      expect(FleuryDebug.instance.monitors.single.name, 'peers');
      expect(FleuryDebug.instance.monitors.single.value(), 7);
      expect(notified, 1);
    });

    test('re-registering a name overwrites in place', () {
      FleuryDebug.registerMonitor('queue', () => 3);
      FleuryDebug.registerMonitor('queue', () => 9);
      expect(FleuryDebug.instance.monitors, hasLength(1));
      expect(FleuryDebug.instance.monitors.single.value(), 9);
    });

    test('unregisterMonitor removes by name (no-op if absent)', () {
      var notified = 0;
      FleuryDebug.instance.addListener(() => notified++);
      FleuryDebug.registerMonitor('a', () => 1);
      FleuryDebug.registerMonitor('b', () => 2);
      FleuryDebug.unregisterMonitor('a');
      expect(FleuryDebug.instance.monitors.map((m) => m.name), ['b']);
      // a (register) + b (register) + remove a = 3 notifies
      expect(notified, 3);
      // No-op removal must not notify.
      FleuryDebug.unregisterMonitor('nope');
      expect(notified, 3);
    });

    test('clearMonitors empties + notifies, idempotent', () {
      var notified = 0;
      FleuryDebug.registerMonitor('x', () => 1);
      FleuryDebug.instance.addListener(() => notified++);
      FleuryDebug.clearMonitors();
      expect(FleuryDebug.instance.monitors, isEmpty);
      expect(notified, 1);
      FleuryDebug.clearMonitors();
      expect(notified, 1, reason: 'empty → empty must not notify');
    });

    test('monitors snapshot is unmodifiable', () {
      FleuryDebug.registerMonitor('x', () => 1);
      final m = FleuryDebug.instance.monitors;
      expect(() => m.clear(), throwsUnsupportedError);
    });
  });
}
