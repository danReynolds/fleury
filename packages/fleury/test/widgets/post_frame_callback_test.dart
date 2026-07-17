// Tests for TuiBinding.addPostFrameCallback. Drains run after the
// build flush in tests (mirroring "after renderDiff" in the runtime),
// so a callback registered before pump fires once after that pump.

import 'dart:async';

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

class _RegisterInInitState extends StatefulWidget {
  const _RegisterInInitState({required this.onFire});
  final void Function(Duration) onFire;

  @override
  State<_RegisterInInitState> createState() => _RegisterInInitStateState();
}

class _RegisterInInitStateState extends State<_RegisterInInitState> {
  @override
  void initState() {
    super.initState();
    TuiBinding.of(context).addPostFrameCallback(widget.onFire);
  }

  @override
  Widget build(BuildContext context) => const Text('hi');
}

class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.onBuild});
  final void Function(int) onBuild;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  void bump() => setState(() => count += 1);

  @override
  Widget build(BuildContext context) {
    widget.onBuild(count);
    return Text('$count');
  }
}

void main() {
  group('TuiBinding.addPostFrameCallback', () {
    testWidgets('one-shot callback fires exactly once after the next pump', (
      tester,
    ) {
      tester.pumpWidget(const Text('seed'));
      // Advance the clock so the drain sees a non-zero elapsed.
      tester.clock.advance(const Duration(milliseconds: 50));

      final fires = <Duration>[];
      tester.binding.addPostFrameCallback(fires.add);

      expect(fires, isEmpty, reason: 'not drained until pump');
      tester.pump();
      expect(fires, hasLength(1));
      expect(fires.single, const Duration(milliseconds: 50));

      tester.pump();
      expect(
        fires,
        hasLength(1),
        reason: 'one-shot; a second pump must not refire',
      );
    });

    testWidgets('registering inside initState fires after that frame', (
      tester,
    ) {
      final fires = <Duration>[];
      tester.pumpWidget(_RegisterInInitState(onFire: fires.add));
      // After pumpWidget, initState ran and registered. The drain
      // happens at the end of pump(); pumpWidget on first mount calls
      // mountRoot directly (no pump), so we need an explicit pump.
      tester.pump();
      expect(fires, hasLength(1));
    });

    testWidgets('a throwing callback does not abort sibling callbacks', (
      tester,
    ) {
      tester.pumpWidget(const Text('seed'));
      final fires = <String>[];
      tester.binding.addPostFrameCallback((_) {
        fires.add('a');
      });
      tester.binding.addPostFrameCallback((_) {
        fires.add('b');
        throw StateError('boom');
      });
      tester.binding.addPostFrameCallback((_) {
        fires.add('c');
      });

      // The exception is reported via the zone's uncaught error
      // handler. Run the drain inside a guarded zone so the test
      // doesn't fail on the captured error.
      Object? captured;
      runZonedGuarded(tester.pump, (error, _) => captured = error);
      expect(fires, [
        'a',
        'b',
        'c',
      ], reason: 'sibling callbacks must still fire');
      expect(captured, isA<StateError>());
    });

    testWidgets('a callback registered from inside a drain queues for next '
        'frame', (tester) {
      tester.pumpWidget(const Text('seed'));
      final fires = <String>[];
      tester.binding.addPostFrameCallback((_) {
        fires.add('outer');
        tester.binding.addPostFrameCallback((_) => fires.add('inner'));
      });
      tester.pump();
      expect(fires, [
        'outer',
      ], reason: 'the nested callback queues but does not refire here');
      tester.pump();
      expect(fires, ['outer', 'inner']);
    });

    testWidgets('idle pump (no rebuilds) still drains queued callbacks', (
      tester,
    ) {
      tester.pumpWidget(const Text('seed'));
      var fired = false;
      tester.binding.addPostFrameCallback((_) => fired = true);
      // No state change, no animation, no rebuild — purely idle.
      tester.pump();
      expect(fired, isTrue);
    });

    testWidgets('a callback can schedule a setState rebuild', (tester) {
      final builds = <int>[];
      final counterKey = GlobalKey<_CounterState>();
      tester.pumpWidget(_Counter(key: counterKey, onBuild: builds.add));
      expect(builds, [0]);

      tester.binding.addPostFrameCallback((_) {
        counterKey.currentState!.bump();
      });
      tester.pump();
      // The callback bumped the counter; the next pump rebuilds.
      tester.pump();
      expect(builds, [0, 1]);
    });

    testWidgets(
      'a post-frame callback enqueued from an idle Timer.run triggers a '
      'scheduleFrame via onPostFrameCallbackRegistered',
      (tester) {
        // The runtime wires `binding.onPostFrameCallback = scheduleFrame`.
        // Tests don't run a real loop, so they wire it manually and assert
        // the signal arrives — without it, a Timer.run that adds a
        // callback during idle would queue indefinitely (no setState, no
        // event would schedule a frame).
        var pumpScheduled = 0;
        tester.binding.onPostFrameCallback = () => pumpScheduled++;
        tester.pumpWidget(const Text('seed'));
        // Idle: no setState, no event. A Timer.run-style addPostFrameCallback.
        tester.binding.addPostFrameCallback((_) {});
        expect(
          pumpScheduled,
          1,
          reason: 'enqueue must signal the runtime to schedule a frame',
        );
      },
    );

    testWidgets('TickerScheduler.dispose drains queued callbacks', (tester) {
      // A callback registered just before shutdown otherwise vanishes
      // silently. dispose() snapshots, swaps, and runs everything once
      // before clearing.
      tester.pumpWidget(const Text('seed'));
      final fires = <Duration>[];
      tester.binding.addPostFrameCallback(fires.add);
      tester.clock.advance(const Duration(milliseconds: 7));
      tester.scheduler.dispose();
      expect(
        fires,
        hasLength(1),
        reason: 'dispose must drain pending callbacks',
      );
      expect(fires.single, const Duration(milliseconds: 7));
    });

    testWidgets(
      'dispose drain catches exceptions per-callback so siblings still fire',
      (tester) {
        tester.pumpWidget(const Text('seed'));
        final fires = <String>[];
        tester.binding.addPostFrameCallback((_) => fires.add('a'));
        tester.binding.addPostFrameCallback((_) {
          fires.add('b');
          throw StateError('boom-on-dispose');
        });
        tester.binding.addPostFrameCallback((_) => fires.add('c'));

        Object? captured;
        runZonedGuarded(
          () => tester.scheduler.dispose(),
          (error, _) => captured = error,
        );
        expect(
          fires,
          ['a', 'b', 'c'],
          reason: 'sibling callbacks must still fire during the dispose drain',
        );
        expect(captured, isA<StateError>());
      },
    );

    testWidgets('nested flushPostFrameCallbacks triggers an assert in debug', (
      tester,
    ) {
      // Re-entering the drain consumes the next-frame queue and breaks
      // the FOLLOWING-frame guarantee. Debug-mode assert catches the
      // anti-pattern early. The assert raises inside the per-callback
      // try/catch in `flushPostFrameCallbacks`, so the error is routed
      // via Zone.current — capture it with runZonedGuarded.
      tester.pumpWidget(const Text('seed'));
      tester.binding.addPostFrameCallback((_) {
        // This callback drives a re-entrant drain — the assertion in
        // flushPostFrameCallbacks must fire.
        tester.binding.flushPostFrameCallbacks(tester.clock.now);
      });
      Object? captured;
      runZonedGuarded(tester.pump, (error, _) => captured = error);
      expect(
        captured,
        isA<AssertionError>(),
        reason: 'a re-entrant drain must trip the depth assert',
      );
    });
  });
}
