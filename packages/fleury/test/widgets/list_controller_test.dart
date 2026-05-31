import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('ListController construction', () {
    test('default has null selection and zero item count', () {
      final c = ListController();
      expect(c.selectedIndex, isNull);
      expect(c.itemCount, 0);
      expect(c.visibleRange, isNull);
    });

    test('initial selectedIndex is kept as-is before widget mounts', () {
      // Before a widget pushes itemCount, the controller can't clamp;
      // the initial value is stored verbatim.
      final c = ListController(selectedIndex: 7);
      expect(c.selectedIndex, 7);
    });
  });

  group('selectedIndex setter', () {
    test('notifies when value changes', () {
      final c = ListController(selectedIndex: 0);
      var fires = 0;
      c.addListener(() => fires += 1);
      c.selectedIndex = 1;
      expect(c.selectedIndex, 1);
      expect(fires, 1);
    });

    test('no-op when set to the same value', () {
      final c = ListController(selectedIndex: 3);
      var fires = 0;
      c.addListener(() => fires += 1);
      c.selectedIndex = 3;
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
}
