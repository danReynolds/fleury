import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('Curve boundary contract', () {
    final namedCurves = <String, Curve>{
      'linear': Curves.linear,
      'easeIn': Curves.easeIn,
      'easeOut': Curves.easeOut,
      'easeInOut': Curves.easeInOut,
      'easeInCubic': Curves.easeInCubic,
      'easeOutCubic': Curves.easeOutCubic,
      'bounceIn': Curves.bounceIn,
      'bounceOut': Curves.bounceOut,
      'elasticIn': Curves.elasticIn,
      'elasticOut': Curves.elasticOut,
      'steps(4)': Curves.steps(4),
    };

    namedCurves.forEach((name, curve) {
      test('$name preserves boundaries', () {
        expect(
          curve.transform(0.0),
          0.0,
          reason: '$name.transform(0) should be 0.0',
        );
        expect(
          curve.transform(1.0),
          1.0,
          reason: '$name.transform(1) should be 1.0',
        );
      });
    });
  });

  group('Curve midpoint values', () {
    test('linear midpoint is 0.5', () {
      expect(Curves.linear.transform(0.5), 0.5);
    });

    test('easeIn midpoint is 0.25 (t² at 0.5)', () {
      expect(Curves.easeIn.transform(0.5), 0.25);
    });

    test('easeOut midpoint is 0.75 (1 - (1-t)² at 0.5)', () {
      expect(Curves.easeOut.transform(0.5), 0.75);
    });

    test('easeInOut midpoint is 0.5 (symmetric)', () {
      expect(Curves.easeInOut.transform(0.5), 0.5);
    });

    test('easeInCubic midpoint is 0.125', () {
      expect(Curves.easeInCubic.transform(0.5), 0.125);
    });

    test('steps(4): 0.0 / 0.25 / 0.5 / 0.75 / 1.0 boundaries', () {
      final c = Curves.steps(4);
      expect(c.transform(0.0), 0.0);
      expect(c.transform(0.1), 0.0);
      expect(c.transform(0.25), 0.25);
      expect(c.transform(0.4), 0.25);
      expect(c.transform(0.5), 0.5);
      expect(c.transform(0.99), 0.75);
      expect(c.transform(1.0), 1.0);
    });
  });

  group('Curve.flipped', () {
    test('reverses and inverts the source curve', () {
      final flipped = Curves.easeOut.flipped;

      expect(flipped.transform(0), 0);
      expect(flipped.transform(0.25), closeTo(0.0625, 0.000001));
      expect(flipped.transform(0.5), closeTo(0.25, 0.000001));
      expect(flipped.transform(1), 1);
    });

    test('a curve and its flip retrace the same values', () {
      final curve = Curves.easeOutCubic;
      final flipped = curve.flipped;

      for (final t in <double>[0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]) {
        expect(
          1 - flipped.transform(t),
          closeTo(curve.transform(1 - t), 0.000001),
        );
      }
    });
  });
}
