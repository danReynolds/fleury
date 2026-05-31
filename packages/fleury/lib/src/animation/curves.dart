// Curves: easing functions that map a normalized parameter t in
// [0, 1] to another value in [0, 1]. Passed to `Animation.to(curve:)`
// for deterministic easing on the continuous lane.
//
// All curves preserve the boundaries: transform(0) == 0,
// transform(1) == 1. Internal shape determines the easing.

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// An easing function that maps a normalized parameter `t` in
/// `[0, 1]` to another value in `[0, 1]`.
@immutable
abstract class Curve {
  const Curve();

  /// Transforms `t`. The default implementation handles the
  /// boundary clamp and forwards to [transformInternal], which
  /// subclasses implement for the actual easing shape.
  double transform(double t) {
    assert(t >= 0.0 && t <= 1.0, 'Curve.transform(t) requires t in [0,1].');
    if (t == 0.0 || t == 1.0) return t;
    return transformInternal(t);
  }

  /// Implementation hook — subclasses define the easing shape here
  /// for `t` strictly between 0 and 1.
  @protected
  double transformInternal(double t);
}

/// Named curves. Each preserves the boundaries and is `const`.
class Curves {
  Curves._();

  /// `t` — the identity curve.
  static const Curve linear = _LinearCurve();

  /// Quadratic ease-in: starts slow, accelerates. `t * t`.
  static const Curve easeIn = _EaseInCurve();

  /// Quadratic ease-out: starts fast, decelerates. `1 - (1-t)²`.
  static const Curve easeOut = _EaseOutCurve();

  /// Quadratic ease-in-out: slow → fast → slow.
  static const Curve easeInOut = _EaseInOutCurve();

  /// Cubic ease-in: starts very slow, accelerates harder than
  /// quadratic.
  static const Curve easeInCubic = _EaseInCubicCurve();

  /// Cubic ease-out: decelerates harder than quadratic.
  static const Curve easeOutCubic = _EaseOutCubicCurve();

  /// Snap to one of [count] discrete steps. Useful for cell-
  /// quantized output where smooth intermediate values round-trip
  /// to a step anyway. For example, `Curves.steps(4)` produces
  /// {0, 0.25, 0.5, 0.75, 1.0}.
  static Curve steps(int count) {
    assert(count > 0, 'Curves.steps requires count > 0.');
    return _StepsCurve(count);
  }

  /// Bounce easing — the value bounces back several times after
  /// approaching the target.
  static const Curve bounceIn = _BounceInCurve();
  static const Curve bounceOut = _BounceOutCurve();

  /// Elastic easing — overshoots then oscillates back. Often used
  /// for "snap into place" effects with character.
  static const Curve elasticIn = _ElasticInCurve();
  static const Curve elasticOut = _ElasticOutCurve();
}

class _LinearCurve extends Curve {
  const _LinearCurve();
  @override
  double transformInternal(double t) => t;
}

class _EaseInCurve extends Curve {
  const _EaseInCurve();
  @override
  double transformInternal(double t) => t * t;
}

class _EaseOutCurve extends Curve {
  const _EaseOutCurve();
  @override
  double transformInternal(double t) => 1 - (1 - t) * (1 - t);
}

class _EaseInOutCurve extends Curve {
  const _EaseInOutCurve();
  @override
  double transformInternal(double t) {
    if (t < 0.5) return 2 * t * t;
    return 1 - 2 * (1 - t) * (1 - t);
  }
}

class _EaseInCubicCurve extends Curve {
  const _EaseInCubicCurve();
  @override
  double transformInternal(double t) => t * t * t;
}

class _EaseOutCubicCurve extends Curve {
  const _EaseOutCubicCurve();
  @override
  double transformInternal(double t) {
    final inverted = 1 - t;
    return 1 - inverted * inverted * inverted;
  }
}

class _StepsCurve extends Curve {
  const _StepsCurve(this.count);
  final int count;

  @override
  double transformInternal(double t) {
    final stepped = (t * count).floor() / count;
    return stepped.clamp(0.0, 1.0);
  }
}

/// Bounce easing inspired by Robert Penner's formulas. Used by
/// both bounceIn (inverted) and bounceOut (direct).
double _bounceOut(double t) {
  if (t < 1 / 2.75) {
    return 7.5625 * t * t;
  } else if (t < 2 / 2.75) {
    final adjusted = t - 1.5 / 2.75;
    return 7.5625 * adjusted * adjusted + 0.75;
  } else if (t < 2.5 / 2.75) {
    final adjusted = t - 2.25 / 2.75;
    return 7.5625 * adjusted * adjusted + 0.9375;
  } else {
    final adjusted = t - 2.625 / 2.75;
    return 7.5625 * adjusted * adjusted + 0.984375;
  }
}

class _BounceInCurve extends Curve {
  const _BounceInCurve();
  @override
  double transformInternal(double t) => 1 - _bounceOut(1 - t);
}

class _BounceOutCurve extends Curve {
  const _BounceOutCurve();
  @override
  double transformInternal(double t) => _bounceOut(t);
}

/// Elastic easing — same family as Penner's elasticIn/Out.
double _elasticIn(double t) {
  const period = 0.4;
  final s = period / 4;
  final result =
      -math.pow(2, 10 * (t - 1)) *
      math.sin((t - 1 - s) * (2 * math.pi) / period);
  return result.toDouble();
}

double _elasticOut(double t) {
  const period = 0.4;
  final s = period / 4;
  final result =
      math.pow(2, -10 * t) * math.sin((t - s) * (2 * math.pi) / period) + 1;
  return result.toDouble();
}

class _ElasticInCurve extends Curve {
  const _ElasticInCurve();
  @override
  double transformInternal(double t) => _elasticIn(t);
}

class _ElasticOutCurve extends Curve {
  const _ElasticOutCurve();
  @override
  double transformInternal(double t) => _elasticOut(t);
}
