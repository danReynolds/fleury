import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('CellConstraints', () {
    test('default constructor is unbounded above and zero below', () {
      const c = CellConstraints();
      expect(c.minCols, 0);
      expect(c.minRows, 0);
      expect(c.maxCols, isNull);
      expect(c.maxRows, isNull);
      expect(c.hasBoundedWidth, isFalse);
      expect(c.hasBoundedHeight, isFalse);
      expect(c.isTight, isFalse);
    });

    test('tight constraints require an exact size', () {
      final c = CellConstraints.tight(const CellSize(10, 5));
      expect(c.isTight, isTrue);
      expect(c.constrain(const CellSize(20, 50)), const CellSize(10, 5));
      expect(c.constrain(const CellSize(0, 0)), const CellSize(10, 5));
    });

    test('loose constraints allow zero up to the given size', () {
      final c = CellConstraints.loose(const CellSize(10, 5));
      expect(c.minCols, 0);
      expect(c.minRows, 0);
      expect(c.maxCols, 10);
      expect(c.maxRows, 5);
      expect(c.constrain(const CellSize(20, 50)), const CellSize(10, 5));
      expect(c.constrain(const CellSize(3, 1)), const CellSize(3, 1));
    });

    test('constrainWidth clamps to bounds', () {
      const c = CellConstraints(minCols: 5, maxCols: 10);
      expect(c.constrainWidth(0), 5);
      expect(c.constrainWidth(7), 7);
      expect(c.constrainWidth(20), 10);
    });

    test('loosen drops minimums but keeps maximums', () {
      const c = CellConstraints(
        minCols: 5,
        maxCols: 10,
        minRows: 3,
        maxRows: 6,
      );
      final l = c.loosen();
      expect(l.minCols, 0);
      expect(l.minRows, 0);
      expect(l.maxCols, 10);
      expect(l.maxRows, 6);
    });

    test('isSatisfiedBy validates both axes', () {
      const c = CellConstraints(minCols: 5, maxCols: 10, minRows: 3);
      expect(c.isSatisfiedBy(const CellSize(7, 3)), isTrue);
      expect(c.isSatisfiedBy(const CellSize(4, 3)), isFalse);
      expect(c.isSatisfiedBy(const CellSize(11, 3)), isFalse);
      expect(c.isSatisfiedBy(const CellSize(7, 2)), isFalse);
    });

    test('asserts maxCols >= minCols when bounded', () {
      expect(
        () => CellConstraints(minCols: 5, maxCols: 3),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
