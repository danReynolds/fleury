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
  });
}
