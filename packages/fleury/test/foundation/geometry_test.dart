import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('CellSize', () {
    test('rejects negative dimensions in asserts', () {
      expect(() => CellSize(-1, 0), throwsA(isA<AssertionError>()));
      expect(() => CellSize(0, -1), throwsA(isA<AssertionError>()));
    });

    test('isEmpty when either dimension is zero', () {
      expect(const CellSize(0, 10).isEmpty, isTrue);
      expect(const CellSize(10, 0).isEmpty, isTrue);
      expect(const CellSize(1, 1).isEmpty, isFalse);
    });

    test('value equality and hashCode', () {
      expect(const CellSize(3, 4), equals(const CellSize(3, 4)));
      expect(const CellSize(3, 4).hashCode, const CellSize(3, 4).hashCode);
    });
  });

  group('CellOffset', () {
    test('addition and subtraction', () {
      const a = CellOffset(1, 2);
      const b = CellOffset(3, 5);
      expect(a + b, equals(const CellOffset(4, 7)));
      expect(b - a, equals(const CellOffset(2, 3)));
    });
  });

  group('CellRect', () {
    test('contains uses half-open semantics', () {
      final rect = CellRect.fromLTWH(2, 3, 4, 5); // cols 2..5, rows 3..7
      expect(rect.contains(const CellOffset(2, 3)), isTrue);
      expect(rect.contains(const CellOffset(5, 7)), isTrue);
      expect(rect.contains(const CellOffset(6, 7)), isFalse);
      expect(rect.contains(const CellOffset(5, 8)), isFalse);
      expect(rect.contains(const CellOffset(1, 3)), isFalse);
    });
  });
}
