// The framework knows when a control cannot possibly work. It should say so.
//
// Sampling a key on a surface that reports no held state returns false on
// every frame. That is fine when a KeyBinding carries the same key — the
// press-driven fallback a capability branch is supposed to have. With no
// binding the control is dead, and the app just looks broken.
//
// Both facts live in the framework: the capability, and every registered
// binding. Nothing compared them, so Asteroids shipped sampling four movement
// controls behind a fallback covering one, and four terminals' worth of
// testing said nothing.
import 'package:fleury/fleury.dart';
import 'package:fleury/src/foundation/fleury_error.dart';
import 'package:fleury/src/runtime/input_dispatcher.dart';
import 'package:test/test.dart';

void main() {
  late FocusManager focusManager;
  late InputDispatcher dispatcher;
  late List<FleuryError> warnings;

  setUp(() {
    focusManager = FocusManager();
    warnings = <FleuryError>[];
    dispatcher = InputDispatcher(focusManager: focusManager)
      ..onDeveloperWarning = warnings.add
      ..updateKeyboardCapabilities(KeyboardCapabilities.legacy);
  });

  KeyboardSnapshot sample(KeySelector selector) {
    final snapshot = dispatcher.keyboardSession.publishLatch();
    snapshot.isHeld(selector); // what a game's ticker does every frame
    return snapshot;
  }

  test('a sampled key with no binding warns, naming the key and the fix', () {
    sample(KeyPosition.a);
    dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));

    expect(warnings, hasLength(1));
    expect(warnings.single.summary, contains('KeyPosition.a'));
    expect(warnings.single.hint, contains('KeyBinding'));
    expect(warnings.single.hint, contains('includeRepeats'));
  });

  test('a sampled key WITH a binding is silent', () {
    dispatcher.globalBindings = [
      KeyBinding(KeyCode.a, label: 'Turn left', onTrigger: (_) {}),
    ];
    sample(KeyPosition.a);
    dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));
    expect(
      warnings,
      isEmpty,
      reason: 'a positional sample is carried by a binding on its US twin',
    );
  });


  test('a POSITIONAL binding covers its sampled position', () {
    // The exact shape Asteroids ships on a legacy terminal: sampled
    // KeyPosition.a, fallback KeyBinding(KeyPosition.a). KeyPosition
    // implements KeySequence, so a covered-set filter that only admits
    // `sequence is KeyCode` silently drops every positional binding and this
    // warns falsely — on the one app that has its fallbacks right.
    dispatcher.globalBindings = [
      KeyBinding(KeyPosition.a, label: 'Turn left', onTrigger: (_) {}),
    ];
    sample(KeyPosition.a);
    dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));
    expect(
      warnings,
      isEmpty,
      reason: 'a positional binding must count as coverage for its own key',
    );
  });

  test('a surface that DOES report held keys is silent', () {
    dispatcher.updateKeyboardCapabilities(KeyboardCapabilities.full);
    sample(KeyPosition.a);
    dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));
    expect(warnings, isEmpty);
  });

  test('a control sampled every frame warns exactly once', () {
    for (var i = 0; i < 20; i++) {
      sample(KeyPosition.a);
      dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));
    }
    expect(warnings, hasLength(1), reason: 'a per-frame read must not spam');
  });

  test('the real Asteroids hole is caught, and names every dead control', () {
    // The shape that actually shipped: four movement controls sampled, one
    // fallback binding. Kept as a regression case because no test, review, or
    // real-terminal run caught it — the user found it by playing the game.
    dispatcher.globalBindings = [
      KeyBinding(KeyCode.w, label: 'Thrust', onTrigger: (_) {}),
    ];
    final snapshot = dispatcher.keyboardSession.publishLatch();
    for (final key in [
      KeyPosition.w,
      KeyPosition.a,
      KeyPosition.d,
      KeyPosition.s,
    ]) {
      snapshot.isHeld(key);
    }
    dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));

    final named = warnings.map((w) => w.summary).join(' ');
    expect(named, contains('KeyPosition.a'), reason: 'turn left was dead');
    expect(named, contains('KeyPosition.d'), reason: 'turn right was dead');
    expect(named, contains('KeyPosition.s'), reason: 'brake was dead');
    expect(named, isNot(contains('KeyPosition.w')), reason: 'thrust WAS bound');
  });
}
