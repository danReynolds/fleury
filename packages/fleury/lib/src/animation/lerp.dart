// Lerp<T>: the interpolation primitive for the continuous animation
// lane.
//
// The Animation engine's curve path computes interpolated values
// through this one tested surface. A `Lerp<T>` answers a single
// question: given
// two endpoints and a normalized `t` in [0, 1], what's the value in
// between?
//
// Concrete lerps cover the cell-quantized cases TUI animations hit:
//
//   doubleLerp     — straight linear interpolation.
//   intLerp        — linear then rounded (cell positions / counts).
//   rgbColorLerp   — channel-wise linear interpolation.
//   DiscreteLerp   — snap at t = 0.5; for values with no meaningful
//                    midpoint (indexed colors, glyph swaps).

import '../rendering/cell.dart';

/// Interpolates between two values of type [T].
///
/// Implementations must satisfy `lerp(a, b, 0) == a` and
/// `lerp(a, b, 1) == b`. Behavior for `t` outside `[0, 1]` is
/// implementation-defined (linear lerps extrapolate; discrete lerps
/// clamp at the threshold).
abstract class Lerp<T> {
  const Lerp();

  /// The value [t] of the way from [a] to [b].
  T call(T a, T b, double t);
}

class _DoubleLerp extends Lerp<double> {
  const _DoubleLerp();
  @override
  double call(double a, double b, double t) => a + (b - a) * t;
}

class _IntLerp extends Lerp<int> {
  const _IntLerp();
  @override
  int call(int a, int b, double t) => (a + (b - a) * t).round();
}

class _RgbColorLerp extends Lerp<RgbColor> {
  const _RgbColorLerp();
  @override
  RgbColor call(RgbColor a, RgbColor b, double t) {
    int ch(int from, int to) => (from + (to - from) * t).round();
    return RgbColor(ch(a.r, b.r), ch(a.g, b.g), ch(a.b, b.b));
  }
}

/// Snaps from [a] to [b] at `t == 0.5`. For values that don't sit on
/// a meaningful number line (indexed colors, glyph swaps, icon
/// transitions).
class DiscreteLerp<T> extends Lerp<T> {
  const DiscreteLerp();
  @override
  T call(T a, T b, double t) => t < 0.5 ? a : b;
}

/// Linear interpolation of doubles.
const Lerp<double> doubleLerp = _DoubleLerp();

/// Linear interpolation rounded to the nearest integer. Easing
/// curves still control *when* each integer step happens.
const Lerp<int> intLerp = _IntLerp();

/// Channel-wise linear interpolation of an [RgbColor].
const Lerp<RgbColor> rgbColorLerp = _RgbColorLerp();
