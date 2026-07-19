import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Counter extends ChangeNotifier {
  int value = 0;
  void increment() {
    value += 1;
    notifyListeners();
  }
}

void main() {
  group('ChangeNotifier', () {
    test('fires every registered listener on notifyListeners', () {
      final c = _Counter();
      var a = 0;
      var b = 0;
      c.addListener(() => a += 1);
      c.addListener(() => b += 1);

      c.increment();
      c.increment();

      expect(a, 2);
      expect(b, 2);
      expect(c.value, 2);
    });

    test('removeListener stops calls', () {
      final c = _Counter();
      var calls = 0;
      void listener() => calls += 1;
      c.addListener(listener);
      c.increment();
      c.removeListener(listener);
      c.increment();

      expect(calls, 1);
    });

    test('hasListeners flips with subscriptions', () {
      final c = _Counter();
      expect(c.hasListeners, isFalse);
      void l() {}
      c.addListener(l);
      expect(c.hasListeners, isTrue);
      c.removeListener(l);
      expect(c.hasListeners, isFalse);
    });

    test('dispose prevents further addListener calls', () {
      final c = _Counter();
      c.dispose();
      expect(() => c.addListener(() {}), throwsA(isA<StateError>()));
    });

    test('a listener that adds another listener during notification '
        'does not crash the iteration', () {
      final c = _Counter();
      var calls = 0;
      void inner() => calls += 1;
      void outer() {
        calls += 1;
        c.addListener(inner);
      }

      c.addListener(outer);
      c.increment();
      // outer ran; inner did not yet because it was added during iteration
      expect(calls, 1);
      c.increment();
      // both run on next notification
      expect(calls, 3);
    });

    test('a listener removed during notification is not subsequently called',
        () {
      final c = _Counter();
      var first = 0;
      var second = 0;
      late final VoidCallback secondListener;
      void firstListener() {
        first += 1;
        // Remove the not-yet-invoked second listener mid-notification.
        c.removeListener(secondListener);
      }

      secondListener = () => second += 1;
      c.addListener(firstListener);
      c.addListener(secondListener);

      c.increment();

      expect(first, 1);
      expect(
        second,
        0,
        reason: 'a listener removed during notification must not be called '
            '(Listenable contract; guards use-after-dispose)',
      );
    });

    test('disposing the notifier mid-notification halts the remaining listeners',
        () {
      final c = _Counter();
      var later = 0;
      c.addListener(c.dispose);
      c.addListener(() => later += 1);

      c.increment();

      expect(
        later,
        0,
        reason: 'listeners after an in-notification dispose must not run',
      );
    });

    test('compaction keeps surviving listeners live across later notifications',
        () {
      final c = _Counter();
      var first = 0;
      var third = 0;
      late final VoidCallback middle;
      void firstListener() {
        first += 1;
        c.removeListener(middle); // nulls the middle slot mid-pass
      }

      middle = () {};
      void thirdListener() => third += 1;
      c.addListener(firstListener);
      c.addListener(middle);
      c.addListener(thirdListener);

      c.increment(); // removes middle; compaction runs when the pass unwinds
      expect(first, 1);
      expect(third, 1);

      // After compaction only [firstListener, thirdListener] remain and both
      // still fire on the next notification.
      c.increment();
      expect(first, 2);
      expect(third, 2);
      expect(c.hasListeners, isTrue);
    });

    test('reentrant notifyListeners fires each level without corrupting state',
        () {
      final c = _Counter();
      var outer = 0;
      var inner = 0;
      var reentered = false;
      c.addListener(() {
        outer += 1;
        if (!reentered) {
          reentered = true;
          c.increment(); // reentrant notifyListeners from inside a pass
        }
      });
      c.addListener(() => inner += 1);

      c.increment();

      // Both listeners fire on the outer pass AND the nested reentrant pass;
      // the nested pass must not compact early or skip a slot.
      expect(outer, 2);
      expect(inner, 2);
      expect(c.hasListeners, isTrue);
    });

    test('a listener added twice and removed once still fires once', () {
      final c = _Counter();
      var calls = 0;
      void listener() => calls += 1;
      c.addListener(listener);
      c.addListener(listener);
      c.removeListener(listener); // removes one occurrence, like List.remove

      c.increment();

      expect(calls, 1, reason: 'the surviving occurrence fires exactly once');
    });
  });
}
