// The resolver had no behavioural coverage until it was extracted: while it
// lived inside the scene as a private class, the only tests reachable were
// widget tests asserting that binding LABELS existed. A label proves a
// binding was declared, not that pressing the key moves the ship — which is
// exactly the gap the shipped bug lived in.
import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/keyboard_state.dart';
import 'package:fleury_samples/src/neon_asteroids_controls.dart';
import 'package:fleury_samples/src/neon_asteroids_model.dart';
import 'package:test/test.dart';

/// A snapshot with nothing held — a legacy surface, every frame.
KeyboardSnapshot get _nothingHeld =>
    (KeyboardSession(capabilities: KeyboardCapabilities.legacy)).publishLatch();

NeonAsteroidsInput _resolve(ShipControls controls) => controls.resolveMovement(
  _nothingHeld,
  left: KeyPosition.a,
  right: KeyPosition.d,
  thrust: KeyPosition.w,
  brake: KeyPosition.s,
);

void main() {
  group('press-driven controls on a surface with no held state', () {
    test('a single press turns for several steps, then stops', () {
      final controls = ShipControls()..turn(-1);
      var turningSteps = 0;
      for (var i = 0; i < ShipControls.pressDrivenSteps + 5; i++) {
        if (_resolve(controls).rotateLeft) turningSteps++;
      }
      expect(
        turningSteps,
        greaterThan(1),
        reason: 'one tap must produce visible rotation',
      );
      expect(
        _resolve(controls).rotateLeft,
        isFalse,
        reason:
            'and must stop on its own — a press-driven turn that never '
            'expires is the stuck-key bug in a different costume',
      );
    });

    test('turning left then right reverses immediately', () {
      final controls = ShipControls()..turn(-1);
      expect(_resolve(controls).rotateLeft, isTrue);
      controls.turn(1);
      final input = _resolve(controls);
      expect(input.rotateRight, isTrue);
      expect(input.rotateLeft, isFalse, reason: 'no ambidextrous ship');
    });

    test('brake is press-driven and expires too', () {
      final controls = ShipControls()..brake();
      expect(_resolve(controls).brake, isTrue);
      for (var i = 0; i < ShipControls.pressDrivenSteps + 2; i++) {
        _resolve(controls);
      }
      expect(_resolve(controls).brake, isFalse);
    });

    test('thrust latches and unlatches', () {
      final controls = ShipControls();
      expect(_resolve(controls).thrust, isFalse);
      controls.thrustLatched = true;
      expect(_resolve(controls).thrust, isTrue);
      controls.thrustLatched = false;
      expect(_resolve(controls).thrust, isFalse);
    });

    test('EVERY movement control has a press-driven source', () {
      // The regression guard for the actual bug: thrust had a fallback and
      // turning and braking did not, so the ship thrusted once on Warp and
      // could then neither steer nor stop.
      final left = ShipControls()..turn(-1);
      final right = ShipControls()..turn(1);
      final braking = ShipControls()..brake();
      final thrusting = ShipControls()..thrustLatched = true;
      expect(_resolve(left).rotateLeft, isTrue, reason: 'turn left dead');
      expect(_resolve(right).rotateRight, isTrue, reason: 'turn right dead');
      expect(_resolve(braking).brake, isTrue, reason: 'brake dead');
      expect(_resolve(thrusting).thrust, isTrue, reason: 'thrust dead');
    });
  });

  group('fire is an edge', () {
    test('a pointer shot fires exactly once', () {
      final controls = ShipControls()..fire();
      expect(controls.takeFire(_nothingHeld), isTrue);
      expect(
        controls.takeFire(_nothingHeld),
        isFalse,
        reason: 'one press is one shot, or holding fire empties the magazine',
      );
    });
  });

  group('reset', () {
    test('clears every source, so a new run starts still', () {
      final controls = ShipControls()
        ..turn(-1)
        ..brake()
        ..fire()
        ..thrustLatched = true
        ..pointerThrust = true
        ..pointerArmed = true;
      controls.reset();
      final input = _resolve(controls);
      expect(input.rotateLeft, isFalse);
      expect(input.brake, isFalse);
      expect(input.thrust, isFalse);
      expect(controls.takeFire(_nothingHeld), isFalse);
      expect(controls.pointerArmed, isFalse);
    });
  });
}
