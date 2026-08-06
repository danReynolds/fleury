import 'package:fleury/fleury_core.dart';

import 'neon_asteroids_model.dart';

/// One frame of movement intent, resolved from whichever input sources this
/// surface actually has.
///
/// Three can drive the ship and any of them may be missing: **sampled** held
/// keys (live only where the surface reports held state), **press-driven**
/// bindings (the fallback that keeps every control alive where it does not),
/// and the **pointer**. Each control asks all three here, in one place.
///
/// That single-place part is the point. The first version of this scene
/// resolved the sources inline at each use site, which made it easy to add a
/// press-driven fallback for thrust and silently leave turning and braking
/// with none — the ship thrusted once on a legacy terminal and could then
/// neither steer nor stop. A control missing a source is now a missing line
/// in one short method rather than an absence spread across a file.
class ShipControls {
  /// How many simulation steps one press (or auto-repeat) of a press-driven
  /// control stays active. Long enough for a single tap to be visible, short
  /// enough that auto-repeat blends consecutive presses into continuous
  /// motion rather than stacking them.
  static const pressDrivenSteps = 8;

  int _turnDirection = 0;
  int _turnSteps = 0;
  int _brakeSteps = 0;

  /// Where held keys are unavailable, thrust is a toggle rather than a hold.
  bool thrustLatched = false;

  bool pointerThrust = false;
  bool _pointerFire = false;

  /// Whether the in-flight pointer press began during play.
  bool pointerArmed = false;

  void turn(int direction) {
    _turnDirection = direction;
    _turnSteps = pressDrivenSteps;
  }

  void brake() => _brakeSteps = pressDrivenSteps;

  void fire() => _pointerFire = true;

  void reset() {
    _turnDirection = 0;
    _turnSteps = 0;
    _brakeSteps = 0;
    thrustLatched = false;
    pointerThrust = false;
    _pointerFire = false;
    pointerArmed = false;
  }

  /// Resolves this frame's movement, consuming one step of press-driven
  /// state. Fire is not included: it is an edge, taken once per press by
  /// [takeFire] so a tap is exactly one shot.
  NeonAsteroidsInput resolveMovement(
    KeyboardSnapshot keys, {
    required KeySelector left,
    required KeySelector right,
    required KeySelector thrust,
    required KeySelector brake,
  }) {
    if (_turnSteps > 0) _turnSteps--;
    if (_brakeSteps > 0) _brakeSteps--;
    return NeonAsteroidsInput(
      rotateLeft:
          keys.isHeld(left) ||
          keys.isHeld(KeyCode.arrowLeft) ||
          (_turnSteps > 0 && _turnDirection < 0),
      rotateRight:
          keys.isHeld(right) ||
          keys.isHeld(KeyCode.arrowRight) ||
          (_turnSteps > 0 && _turnDirection > 0),
      thrust:
          keys.isHeld(thrust) ||
          keys.isHeld(KeyCode.arrowUp) ||
          thrustLatched ||
          pointerThrust,
      brake:
          keys.isHeld(brake) ||
          keys.isHeld(KeyCode.arrowDown) ||
          _brakeSteps > 0,
    );
  }

  /// True once per press. `wasPressed` is an EDGE, so it survives a
  /// press+release landing entirely between two frames — a quick tap is never
  /// swallowed — and consuming it here keeps one press to one shot.
  bool takeFire(KeyboardSnapshot keys) {
    final fire = keys.wasPressed(KeyCode.space) || _pointerFire;
    _pointerFire = false;
    return fire;
  }
}
