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
  late BuildOwner owner;

  setUp(() {
    focusManager = FocusManager();
    warnings = <FleuryError>[];
    owner = BuildOwner();
    dispatcher = InputDispatcher(focusManager: focusManager)
      ..onDeveloperWarning = warnings.add
      ..updateKeyboardCapabilities(KeyboardCapabilities.legacy);
  });

  /// Mounts app-wide bindings the way an app does — an outermost
  /// `KeyBindings` — so they land in the focus chain the check reads.
  void mountBindings(List<KeyBinding> bindings) {
    owner.mountRoot(
      FocusManagerScope(
        manager: focusManager,
        child: KeyBindings(
          bindings: bindings,
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      ),
    );
  }

  KeyboardSnapshot sample(KeySelector selector) {
    final snapshot = dispatcher.keyboardSession.publishLatch(
      KeyboardLatchClock.frame,
    );
    snapshot.isHeld(selector); // what a game's ticker does every frame
    return snapshot;
  }

  /// One frame of app life on a legacy surface: the ticker samples, then an
  /// input event arrives and the dispatcher's debug check runs.
  void frame(KeySelector selector) {
    sample(selector);
    dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));
  }

  /// The warning deliberately needs TWO uncovered sightings after the last
  /// capability change (one could be a reactive rebuild still in flight), and
  /// the first check after a change only absorbs the transition. Three frames
  /// is therefore the earliest a genuinely dead control can warn.
  void settleAndTrip(KeySelector selector) {
    frame(selector); // absorbs the capability transition
    frame(selector); // first sighting: suspect
    frame(selector); // second sighting: warn
  }

  test('a sampled key with no binding warns, naming the key and the fix', () {
    settleAndTrip(KeyPosition.a);

    expect(warnings, hasLength(1));
    expect(warnings.single.summary, contains('KeyPosition.a'));
    expect(warnings.single.hint, contains('KeyBinding'));
    expect(warnings.single.hint, contains('includeRepeats'));
  });

  test('a sampled key WITH a binding is silent', () {
    mountBindings([
      KeyBinding(KeyCode.a, label: 'Turn left', onTrigger: (_) {}),
    ]);
    settleAndTrip(KeyPosition.a);
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
    mountBindings([
      KeyBinding(KeyPosition.a, label: 'Turn left', onTrigger: (_) {}),
    ]);
    settleAndTrip(KeyPosition.a);
    expect(
      warnings,
      isEmpty,
      reason: 'a positional binding must count as coverage for its own key',
    );
  });

  test('a surface that DOES report held keys is silent', () {
    dispatcher.updateKeyboardCapabilities(KeyboardCapabilities.full);
    settleAndTrip(KeyPosition.a);
    expect(warnings, isEmpty);
  });

  test('a control sampled every frame warns exactly once', () {
    for (var i = 0; i < 20; i++) {
      frame(KeyPosition.a);
    }
    expect(warnings, hasLength(1), reason: 'a per-frame read must not spam');
  });

  test('a rebuild that lands one frame LATE still does not warn', () {
    // The stall case the two-sighting rule exists for: the transition check
    // has already been absorbed, the control gets sighted uncovered once, and
    // only then does the reactive rebuild deliver its binding. One sighting
    // must stay a suspicion, and coverage must retire it.
    frame(KeyPosition.a); // absorbs the capability transition
    frame(KeyPosition.a); // sighted uncovered ONCE — suspect, not warning
    expect(
      warnings,
      isEmpty,
      reason: 'one sighting can be a rebuild in flight',
    );
    mountBindings([
      KeyBinding(KeyPosition.a, label: 'Turn left', onTrigger: (_) {}),
    ]);
    frame(KeyPosition.a); // covered: suspicion retired
    frame(KeyPosition.a);
    frame(KeyPosition.a);
    expect(warnings, isEmpty);
  });

  test('the demotion window does not warn falsely', () {
    // The flagship scenario, end to end: a capable surface (correctly no
    // fallback bindings), a Warp-style demotion mid-session, and the app's
    // reactive rebuild landing AFTER the next auto-repeat. The warning must
    // wait out the window — one false positive here teaches developers to
    // ignore the diagnostic everywhere.
    dispatcher.updateKeyboardCapabilities(KeyboardCapabilities.full);
    sample(KeyPosition.w);
    const w = KeyEvent(KeyCode.w, position: KeyPosition.w);
    dispatcher.dispatch(w); // held
    dispatcher.dispatch(w); // duplicate down: strike one
    dispatcher.dispatch(w); // strike two: demotes mid-dispatch
    // Next repeat arrives BEFORE the app rebuilt with fallbacks.
    sample(KeyPosition.w);
    dispatcher.dispatch(w);
    expect(warnings, isEmpty, reason: 'the rebuild has not had its frame yet');

    // The rebuild lands: the fallback binding appears. Never warns.
    mountBindings([
      KeyBinding(KeyPosition.w, label: 'Thrust', onTrigger: (_) {}),
    ]);
    frame(KeyPosition.w);
    frame(KeyPosition.w);
    frame(KeyPosition.w);
    expect(warnings, isEmpty);
  });

  test('after demotion, a control with NO fallback still warns', () {
    dispatcher.updateKeyboardCapabilities(KeyboardCapabilities.full);
    const w = KeyEvent(KeyCode.w, position: KeyPosition.w);
    dispatcher.dispatch(w);
    dispatcher.dispatch(w);
    dispatcher.dispatch(w); // demoted
    settleAndTrip(KeyPosition.w);
    expect(warnings, hasLength(1), reason: 'grace must not disarm the check');
  });

  test('the real Asteroids hole is caught, and names every dead control', () {
    // The shape that actually shipped: four movement controls sampled, one
    // fallback binding. Kept as a regression case because no test, review, or
    // real-terminal run caught it — the user found it by playing the game.
    mountBindings([KeyBinding(KeyCode.w, label: 'Thrust', onTrigger: (_) {})]);
    // Three frames of play, all four controls sampled each frame — the
    // two-sighting cadence needs a transition-absorbing check plus two
    // uncovered sightings before it will speak.
    for (var i = 0; i < 3; i++) {
      final snapshot = dispatcher.keyboardSession.publishLatch(
        KeyboardLatchClock.frame,
      );
      for (final key in [
        KeyPosition.w,
        KeyPosition.a,
        KeyPosition.d,
        KeyPosition.s,
      ]) {
        snapshot.isHeld(key);
      }
      dispatcher.dispatch(const KeyEvent(KeyCode.a, position: KeyPosition.a));
    }

    final named = warnings.map((w) => w.summary).join(' ');
    expect(named, contains('KeyPosition.a'), reason: 'turn left was dead');
    expect(named, contains('KeyPosition.d'), reason: 'turn right was dead');
    expect(named, contains('KeyPosition.s'), reason: 'brake was dead');
    expect(named, isNot(contains('KeyPosition.w')), reason: 'thrust WAS bound');
  });
}
