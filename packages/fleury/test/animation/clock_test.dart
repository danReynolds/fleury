import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('FakeClock', () {
    test('default starts at zero', () {
      expect(FakeClock().now, Duration.zero);
    });

    test('custom initial value', () {
      expect(
        FakeClock(const Duration(seconds: 5)).now,
        const Duration(seconds: 5),
      );
    });

    test('advance adds to current time', () {
      final clock = FakeClock();
      clock.advance(const Duration(milliseconds: 100));
      clock.advance(const Duration(milliseconds: 50));
      expect(clock.now, const Duration(milliseconds: 150));
    });

    test('set jumps to a specific time', () {
      final clock = FakeClock();
      clock.set(const Duration(seconds: 10));
      expect(clock.now, const Duration(seconds: 10));
    });

    test('negative advance throws (monotonic invariant)', () {
      final clock = FakeClock(const Duration(seconds: 1));
      expect(
        () => clock.advance(const Duration(seconds: -1)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('set to past throws (monotonic invariant)', () {
      final clock = FakeClock(const Duration(seconds: 5));
      expect(
        () => clock.set(const Duration(seconds: 2)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SystemClock', () {
    test('returns monotonically non-decreasing values', () {
      const clock = SystemClock();
      final first = clock.now;
      final second = clock.now;
      expect(second >= first, isTrue);
    });
  });
}
