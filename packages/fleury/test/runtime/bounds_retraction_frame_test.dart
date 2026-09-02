// A retracted anchor hides its float in the REAL runtime.
//
// The paint-pass sweep retracts an observer that stopped painting, and the
// anchored float marks itself dirty — but that happens inside the frame,
// after the float already painted, and the frame loop consumes that damage
// with the frame's own. Nothing requested the next frame, and a request that
// did come took the no-change skip: the float stayed over the new tab until
// an unrelated rebuild. The widget test passed only because the tester
// renders unconditionally. This one runs the frame driver.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_events.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('switching an IndexedStack away from an anchor gets the frame that '
      'hides its float', () async {
    final driver = FakeTerminalDriver(size: const CellSize(30, 6));
    final chip = BoundsNotifier();
    final index = ValueNotifier<int>(0);
    final frames = <FrameEvent>[];
    final sub = DebugEvents.stream.listen((event) {
      if (event is FrameDebugEvent) frames.add(event.frame);
    });
    final future = runApp(
      ListenableBuilder(
        listenable: index,
        builder: (context, _) => Stack(
          children: [
            IndexedStack(
              index: index.value,
              children: [
                BoundsObserver(notifier: chip, child: const Text('tab-a')),
                const Text('tab-b'),
              ],
            ),
            BoundsAnchor(notifier: chip, child: const Text('¤')),
          ],
        ),
      ),
      driver: driver,
      enableHotReload: false,
    );
    try {
      await _settle();
      await _settle();
      expect(chip.visibleBounds, isNotNull, reason: 'tab-a painted');
      final before = frames.length;

      index.value = 1;
      await _settle();
      await _settle();
      await _settle();

      expect(chip.visibleBounds, isNull, reason: 'retracted at pass end');
      final after = frames.skip(before).toList();
      expect(
        after.length,
        greaterThanOrEqualTo(2),
        reason:
            'the rebuild frame paints the float once more with stale '
            'bounds; a SECOND frame must follow to hide it — got '
            '${after.map((f) => f.reason).toList()}',
      );
      expect(after.last.reason, 'paint-pass-retraction');

      // ...and then it STOPS. A participant that stays mounted without
      // painting is unpublished on every later pass too, so counting a
      // retraction per pass (rather than per withdrawal of a live fact) makes
      // every frame request the next one: a retracted anchor pinned the app
      // at 100% CPU forever, and every existing assertion here — "at least
      // two frames", "the last one is a retraction" — is satisfied by a spin.
      final settled = frames.length;
      await _settle();
      await _settle();
      expect(
        frames.length,
        settled,
        reason:
            'the retraction is a one-shot: once the fact is withdrawn there '
            'is nothing left to retract, so no further frame may be '
            'scheduled. Got ${frames.length - settled} more frames after the '
            'tree went quiet.',
      );
    } finally {
      await sub.cancel();
      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await future.timeout(const Duration(seconds: 2));
      await driver.dispose();
      index.dispose();
    }
  });
}
