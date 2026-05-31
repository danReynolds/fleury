// Spring: the default Animation engine.
//
// A spring is the engine of choice not for visual flourish (at 30 Hz
// on a cell grid, the difference between a spring and a tuned easing
// curve is barely perceptible) but for *interruption*. A spring
// integrates position and velocity in value-space, so retargeting it
// mid-flight continues from the current value AND velocity — no
// restart-snap. That property is what makes "spam-toggle a panel"
// feel right with zero special handling.
//
// The simulation is a damped harmonic oscillator solved
// *analytically*, not integrated step-by-step. At 30 Hz the
// timestep (~33 ms) is large relative to a snappy spring's time
// constant, and explicit integration (Euler/RK) goes unstable for
// stiff springs at large steps. The closed-form solution is exact at
// any timestep and costs the same per frame. Defaults are critically
// damped (no overshoot), which reads cleanest in a terminal; a small
// `bounce` opens up overshoot for the rare case it's wanted.

import 'dart:math' as math;

/// Parameters for a damped-spring simulation (unit mass).
///
/// Construct via the named presets ([Spring.snappy], [Spring.smooth],
/// [Spring.gentle]) for tuned feels, or the raw constructor for full
/// control. [response] is the approximate settle time; [bounce] in
/// `[0, 1)` adds overshoot (0 = critically damped, no overshoot).
class Spring {
  /// Creates a spring from an intuitive [response] / [bounce] pair
  /// (the SwiftUI parameterization), converted internally to
  /// stiffness + damping.
  const Spring({
    this.response = const Duration(milliseconds: 250),
    this.bounce = 0.0,
  }) : assert(bounce >= 0.0 && bounce < 1.0, 'bounce must be in [0, 1)');

  /// Approximate time to settle. Lower = snappier.
  final Duration response;

  /// Overshoot amount in `[0, 1)`. 0 is critically damped.
  final double bounce;

  /// Fast, no overshoot. Taps, selections, focus changes.
  static const Spring snappy = Spring(response: Duration(milliseconds: 150));

  /// Balanced, no overshoot. Layout shifts, panel resizes.
  static const Spring smooth = Spring(response: Duration(milliseconds: 280));

  /// Slow, no overshoot. Cosmetic / ambient animation.
  static const Spring gentle = Spring(response: Duration(milliseconds: 450));

  /// Angular frequency derived from [response]. `response` is taken
  /// as one period of the undamped oscillator: ω = 2π / period.
  double get _omega {
    final seconds = response.inMicroseconds / 1e6;
    return (2 * math.pi) / (seconds <= 0 ? 1e-6 : seconds);
  }

  /// Stiffness k = ω² (unit mass).
  double get stiffness => _omega * _omega;

  /// Damping ratio ζ. `bounce == 0` → ζ = 1 (critical damping, no
  /// overshoot); `bounce` in `(0, 1)` → ζ < 1 (underdamped, some
  /// overshoot). We never produce ζ > 1 (overdamped).
  double get dampingRatio => 1.0 - bounce;

  /// Advances a single scalar component by [dt] seconds using the
  /// closed-form solution of `x'' = -ω²(x - target) - 2ζω·x'`.
  /// Exact and unconditionally stable for any [dt].
  (double position, double velocity) step({
    required double position,
    required double velocity,
    required double target,
    required double dt,
  }) {
    final w = _omega;
    final zeta = dampingRatio;
    final y0 = position - target; // displacement from equilibrium
    final v0 = velocity;

    final double y;
    final double v;
    if (zeta >= 1.0) {
      // Critically damped: ζ = 1.
      final e = math.exp(-w * dt);
      final coeff = v0 + w * y0;
      y = (y0 + coeff * dt) * e;
      v = (v0 - w * coeff * dt) * e;
    } else {
      // Underdamped: 0 < ζ < 1.
      final wd = w * math.sqrt(1.0 - zeta * zeta);
      final e = math.exp(-zeta * w * dt);
      final cosT = math.cos(wd * dt);
      final sinT = math.sin(wd * dt);
      final c1 = y0;
      final c2 = (v0 + zeta * w * y0) / wd;
      y = e * (c1 * cosT + c2 * sinT);
      v =
          e *
          (-zeta * w * (c1 * cosT + c2 * sinT) + wd * (-c1 * sinT + c2 * cosT));
    }
    return (target + y, v);
  }
}
