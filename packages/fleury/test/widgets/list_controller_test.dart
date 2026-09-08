import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('ListController construction', () {
    test('default selects the first item and has zero item count', () {
      final c = ListController();
      expect(c.currentIndex, 0);
      expect(c.itemCount, 0);
      expect(c.visibleRange, isNull);
    });

    test('initial currentIndex is kept as-is before widget mounts', () {
      // Before a widget pushes itemCount, the controller can't clamp;
      // the initial value is stored verbatim.
      final c = ListController(initialIndex: 7);
      expect(c.currentIndex, 7);
    });
  });

  group('currentIndex setter', () {
    test('notifies when value changes', () {
      final c = ListController(initialIndex: 0);
      var fires = 0;
      c.addListener(() => fires += 1);
      c.currentIndex = 1;
      expect(c.currentIndex, 1);
      expect(fires, 1);
    });

    test('no-op when set to the same value', () {
      final c = ListController(initialIndex: 3);
      var fires = 0;
      c.addListener(() => fires += 1);
      c.currentIndex = 3;
      expect(fires, 0);
    });
  });

  group('jumpToIndex', () {
    test('notifies', () {
      final c = ListController();
      var fires = 0;
      c.addListener(() => fires += 1);
      c.jumpToIndex(5);
      expect(fires, 1);
    });
  });

  group('lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final c = ListController(initialIndex: 3, followTail: true);

      c.dispose();
      c.dispose();

      expect(c.currentIndex, 3);
      expect(c.itemCount, 0);
      expect(c.visibleRange, isNull);
      expect(c.followTail, isTrue);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final c = ListController(initialIndex: 1)..dispose();

      const message = 'ListController has been disposed.';
      expect(() => c.currentIndex = 2, _stateError(message));
      expect(() => c.jumpToIndex(2), _stateError(message));
      expect(() => c.followTail = true, _stateError(message));
    });
  });
}
