import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('ValueKey', () {
    test('equals another ValueKey with the same type and value', () {
      expect(const ValueKey<int>(1), equals(const ValueKey<int>(1)));
      expect(const ValueKey<String>('a'), equals(const ValueKey<String>('a')));
    });

    test('differs from a ValueKey with a different value', () {
      expect(const ValueKey<int>(1), isNot(equals(const ValueKey<int>(2))));
    });

    test('differs from a ValueKey with a different type parameter', () {
      // ignore: unrelated_type_equality_checks
      expect(
        const ValueKey<int>(1) == const ValueKey<num>(1),
        isFalse,
        reason: 'Generic type parameter participates in identity.',
      );
    });

    test('hashCode matches equality', () {
      expect(const ValueKey<int>(7).hashCode, const ValueKey<int>(7).hashCode);
    });
  });

  group('UniqueKey', () {
    test('is only equal to itself', () {
      final a = UniqueKey();
      final b = UniqueKey();
      expect(a, equals(a));
      expect(a, isNot(equals(b)));
    });
  });
}
