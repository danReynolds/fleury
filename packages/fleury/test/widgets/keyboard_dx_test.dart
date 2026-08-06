// RFC 0020 Part II acceptance: the public DX surface.
//
// Covers the pieces P4 introduces — repeat policy (§14.2), KeyBinding.hold
// (§14.5), KeyBindings(modal:) (§14.3), KeyDetector (§17), and the Keyboard
// handle's asymmetric reactivity (§15).

import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/keyboard_state.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// Minimal inline-build helper (Fleury has no `Builder`).
class _Probe extends StatelessWidget {
  const _Probe(this.builder);

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

KeyEvent _down(KeyCode code) => KeyEvent(code);
KeyEvent _repeat(KeyCode code) => KeyEvent(code, type: KeyEventType.repeat);
KeyEvent _up(KeyCode code) => KeyEvent(code, type: KeyEventType.up);

void main() {
  group('repeat policy (§14.2)', () {
    testWidgets('a binding fires once per press, not per auto-repeat', (
      tester,
    ) {
      var fired = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [KeyBinding(KeyCode.p, onTrigger: (_) => fired++)],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.p));
      tester.sendKey(_repeat(KeyCode.p));
      tester.sendKey(_repeat(KeyCode.p));
      expect(fired, 1, reason: 'held P must toggle once, not three times');
    });

    testWidgets('includeRepeats opts a movement binding back in', (tester) {
      var moved = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.j,
              includeRepeats: true,
              onTrigger: (_) => moved++,
            ),
          ],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.j));
      tester.sendKey(_repeat(KeyCode.j));
      tester.sendKey(_repeat(KeyCode.j));
      expect(moved, 3);
    });

    testWidgets('an untagged surface still fires — degradation is honest', (
      tester,
    ) {
      // A legacy terminal cannot distinguish auto-repeat, so every arrival
      // is a `down` and suppression is simply unavailable.
      var fired = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [KeyBinding(KeyCode.p, onTrigger: (_) => fired++)],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.p));
      tester.sendKey(_down(KeyCode.p));
      expect(fired, 2);
    });

    testWidgets('a repeat never arms a sequence', (tester) {
      var fired = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [KeyBinding(KeySequence.g.g, onTrigger: (_) => fired++)],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      tester.sendKey(_repeat(KeyCode.g));
      expect(fired, 0, reason: 'holding g must not arm or complete gg');
    });
  });

  group('KeyBinding.hold (§14.5)', () {
    testWidgets('start fires on the down, end on the paired release', (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final log = <String>[];
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [
            KeyBinding.hold(
              KeyCode.space,
              onHoldStart: (_) => log.add('start'),
              onHoldEnd: (_) => log.add('end'),
            ),
          ],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.space));
      expect(log, ['start'], reason: 'zero latency: no threshold to wait for');
      tester.sendKey(_repeat(KeyCode.space));
      expect(log, ['start'], reason: 'repeats are meaningless to a hold');
      tester.sendKey(_up(KeyCode.space));
      expect(log, ['start', 'end']);
    });

    testWidgets('the end still fires when a descendant consumes the key', (
      tester,
    ) {
      // The pairing rides the observation lane precisely so command-lane
      // consumption cannot break it.
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final log = <String>[];
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [
            KeyBinding.hold(
              KeyCode.space,
              onHoldStart: (_) => log.add('start'),
              onHoldEnd: (_) => log.add('end'),
            ),
          ],
          child: KeyBindings(
            bindings: [KeyBinding(KeyCode.space, onTrigger: (_) {})],
            child: const Focus(autofocus: true, child: Text('x')),
          ),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.space));
      tester.sendKey(_up(KeyCode.space));
      expect(log, ['start', 'end']);
    });

    testWidgets('a hold is inert where the surface reports no held state', (
      tester,
    ) {
      // Legacy: no releases, so no end could ever pair — the contract is
      // "inert", never "silently a toggle".
      final log = <String>[];
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [
            KeyBinding.hold(
              KeyCode.space,
              onHoldStart: (_) => log.add('start'),
              onHoldEnd: (_) => log.add('end'),
            ),
          ],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.space));
      expect(log, isEmpty);
    });
  });

  group('KeyBindings(modal:) (§14.3)', () {
    testWidgets('unmatched keys stop at a modal scope', (tester) {
      var appSaw = 0;
      var dialogSaw = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [KeyBinding(KeyCode.j, onTrigger: (_) => appSaw++)],
          child: KeyBindings(
            modal: true,
            bindings: [KeyBinding(KeyCode.y, onTrigger: (_) => dialogSaw++)],
            child: const Focus(autofocus: true, child: Text('dialog')),
          ),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.y));
      expect(dialogSaw, 1);
      tester.sendKey(_down(KeyCode.j)); // matches nothing in the dialog
      expect(appSaw, 0, reason: 'the app behind must not see it');
    });

    testWidgets('a bubbling binding at the boundary is the passthrough', (
      tester,
    ) {
      var appSaw = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.q, onTrigger: (_) => appSaw++),
          ],
          child: KeyBindings(
            modal: true,
            bindings: [
              KeyBinding(KeySequence.ctrl.q, onTrigger: (e) => e.bubble()),
            ],
            child: const Focus(autofocus: true, child: Text('dialog')),
          ),
        ),
      );
      tester.pump();

      tester.sendKey(const KeyEvent(KeyCode.q, modifiers: {KeyModifier.ctrl}));
      expect(appSaw, 1);
    });
  });

  group('KeyDetector (§17)', () {
    testWidgets('propagates by default, consumes on request', (tester) {
      final seen = <String>[];
      var ancestorSaw = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.a, onTrigger: (_) => ancestorSaw++),
            KeyBinding(KeyCode.b, onTrigger: (_) => ancestorSaw++),
          ],
          child: KeyDetector(
            onKey: (event) {
              seen.add(event.code.character!);
              if (event.code == KeyCode.b) event.consume();
            },
            child: const Focus(autofocus: true, child: Text('x')),
          ),
        ),
      );
      tester.pump();

      tester.sendKey(_down(KeyCode.a));
      tester.sendKey(_down(KeyCode.b));
      expect(seen, ['a', 'b']);
      expect(ancestorSaw, 1, reason: 'only the unconsumed key propagated');
    });

    testWidgets('a detector never sees releases', (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final phases = <KeyEventType>[];
      tester.pumpFleuryHome(
        KeyDetector(
          onKey: (event) => phases.add(event.type),
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      // A non-printable: on a full-capability surface an unmodified
      // printable's key half is owed to the text lane, so it never reaches
      // the command walk at all (the P3 interim routing rule).
      tester.sendKey(_down(KeyCode.arrowLeft));
      tester.sendKey(_up(KeyCode.arrowLeft));
      expect(phases, [
        KeyEventType.down,
      ], reason: 'a consumable release would wedge an ancestor pressed set');
    });

    testWidgets('adding a detector does not change Tab traversal', (tester) {
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      tester.pumpFleuryHome(
        Column(
          children: [
            KeyDetector(
              onKey: (_) {},
              child: Focus(
                focusNode: first,
                autofocus: true,
                child: const Text('a'),
              ),
            ),
            Focus(focusNode: second, child: const Text('b')),
          ],
        ),
      );
      tester.pump();
      expect(first.hasFocus, isTrue);

      tester.sendKey(_down(KeyCode.tab));
      tester.pump();
      expect(
        second.hasFocus,
        isTrue,
        reason: 'the detector marker must be invisible to traversal',
      );
    });
  });

  group('Keyboard handle (§15)', () {
    testWidgets('capabilities are readable in build; snapshot is not', (
      tester,
    ) {
      late Keyboard handle;
      tester.pumpFleuryHome(
        _Probe((context) {
          handle = Keyboard.of(context);
          // Legal here — this is what subscribes to negotiation.
          expect(handle.capabilities.supportsHeldState, isFalse);
          expect(() => handle.snapshot, throwsStateError);
          return const Text('x');
        }),
      );
      tester.pump();

      // Outside build, sampling is legal.
      expect(handle.snapshot.pressed, isEmpty);
    });

    testWidgets('sampled queries stay empty without held-state support', (
      tester,
    ) {
      late Keyboard handle;
      tester.pumpFleuryHome(
        _Probe((context) {
          handle = Keyboard.of(context);
          return const Focus(autofocus: true, child: Text('x'));
        }),
      );
      tester.pump();
      tester.sendKey(_down(KeyCode.w));
      tester.pump();

      expect(
        handle.snapshot.isHeld(KeyCode.w),
        isFalse,
        reason: 'a set with no releases would be a lying set',
      );
    });

    testWidgets('held state samples on a capable surface', (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      late Keyboard handle;
      tester.pumpFleuryHome(
        _Probe((context) {
          handle = Keyboard.of(context);
          return const Focus(autofocus: true, child: Text('x'));
        }),
      );
      tester.pump();

      tester.sendKey(const KeyEvent(KeyCode.w, position: KeyPosition.w));
      tester.latchFrame();
      expect(handle.snapshot.isHeld(KeyPosition.w), isTrue);
      expect(handle.snapshot.wasPressed(KeyPosition.w), isTrue);

      tester.sendKey(
        const KeyEvent(
          KeyCode.w,
          position: KeyPosition.w,
          type: KeyEventType.up,
        ),
      );
      tester.latchFrame();
      expect(handle.snapshot.isHeld(KeyPosition.w), isFalse);
      expect(handle.snapshot.wasReleased(KeyPosition.w), isTrue);
    });
  });

  group('positional gestures (§13.3)', () {
    testWidgets('a positional binding matches by physical key', (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      var fired = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [KeyBinding(KeyPosition.w, onTrigger: (_) => fired++)],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      // AZERTY: the QWERTY-W spot types 'z'. A LOGICAL binding on .w would
      // miss this entirely; the positional one is the point.
      tester.sendKey(
        const KeyEvent(KeyCode.char('z'), position: KeyPosition.w),
      );
      expect(fired, 1);

      // The key that types 'w' on that layout is a different spot.
      tester.sendKey(
        const KeyEvent(KeyCode.char('w'), position: KeyPosition.z),
      );
      expect(fired, 1, reason: 'same character, different physical key');
    });

    testWidgets('a positional binding degrades to its US twin', (tester) {
      // No positional reporting: the same declaration still works, matching
      // the twin — one identity model, one comparison, shared with sampling.
      var fired = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [KeyBinding(KeyPosition.w, onTrigger: (_) => fired++)],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();
      tester.sendKey(const KeyEvent(KeyCode.w));
      expect(fired, 1);
    });

    testWidgets('positional steps compose with modifiers and aliases', (
      tester,
    ) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      var fired = 0;
      tester.pumpFleuryHome(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.code(KeyPosition.a),
              aliases: [KeyPosition.d],
              onTrigger: (_) => fired++,
            ),
          ],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.pump();

      tester.sendKey(
        const KeyEvent(
          KeyCode.char('q'),
          modifiers: {KeyModifier.ctrl},
          position: KeyPosition.a,
        ),
      );
      expect(fired, 1, reason: 'Ctrl + the A position, whatever it types');
      tester.sendKey(
        const KeyEvent(KeyCode.char('d'), position: KeyPosition.d),
      );
      expect(fired, 2, reason: 'the positional alias fires too');
    });
  });

  group(
    'the frame latch is published by the FRAME, not by the test (§5.6)',
    () {
      testWidgets('a ticker sees a held key without any explicit latch', (t) {
        // THE regression this file exists for. `publishLatch` used to be called
        // only by the test harness, so every sampled-input test passed while a
        // real app never latched at all and `isHeld` was false forever — A/D
        // did not steer the asteroids showcase. Nothing here may call
        // `latchFrame()`: the point is that pumping a frame is enough.
        t.keyboardCapabilities = KeyboardCapabilities.full;
        final seen = <bool>[];
        late Keyboard keyboard;
        t.pumpWidget(
          _TickerProbe(
            onReady: (k) => keyboard = k,
            onTick: () => seen.add(keyboard.snapshot.isHeld(KeyPosition.a)),
          ),
        );
        t.holdKey(KeyPosition.a);
        t.pump(const Duration(milliseconds: 100));
        expect(
          seen.any((held) => held),
          isTrue,
          reason:
              'a ticker sampling during a pumped frame must observe the '
              'held key — if this fails the runtime is not latching per frame',
        );
      });

      testWidgets('releasing it clears the sampled state', (t) {
        t.keyboardCapabilities = KeyboardCapabilities.full;
        final seen = <bool>[];
        late Keyboard keyboard;
        t.pumpWidget(
          _TickerProbe(
            onReady: (k) => keyboard = k,
            onTick: () => seen.add(keyboard.snapshot.isHeld(KeyPosition.a)),
          ),
        );
        t.holdKey(KeyPosition.a);
        t.pump(const Duration(milliseconds: 50));
        t.releaseKey(KeyPosition.a);
        seen.clear();
        t.pump(const Duration(milliseconds: 50));
        expect(seen, isNot(contains(true)));
      });
    },
  );

  group('a surface that claims phases and does not send them (§5.7)', () {
    test('Warp\'s exact byte stream demotes the session to press-only', () {
      // Captured from Warp 2026-08: it answers the Kitty status query with
      // `CSI ?31u` — all five flags — and then emits an IDENTICAL
      // `CSI 97;1;97 u` for the initial press and every auto-repeat, with no
      // event-type sub-parameter and nothing at all on release.
      //
      // Believing that claim is catastrophic and silent: with no releases,
      // every key sticks down forever, so `isHeld` never returns to false and
      // a held-key control latches on permanently. Holding W in the asteroids
      // showcase thrusted until the app was killed.
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      var demotedTo = KeyboardCapabilities.full;
      session.onCapabilitiesDemoted = (caps) => demotedTo = caps;

      const warpPress = KeyEvent(KeyCode.a, position: KeyPosition.a);
      session.ingest(warpPress);
      expect(
        session.publishLatch().isHeld(KeyPosition.a),
        isTrue,
        reason: 'the first press is indistinguishable from an honest one',
      );

      // Auto-repeat arrives as another bare `down`, which an honest flag-2
      // terminal could never send for an already-held key.
      session.ingest(warpPress);
      expect(
        session.capabilities.supportsHeldState,
        isTrue,
        reason: 'one strike is a dropped release, not proof',
      );

      session.ingest(warpPress);
      expect(
        session.capabilities.supportsHeldState,
        isFalse,
        reason: 'caught: stop promising held state on this surface',
      );
      expect(demotedTo.supportsHeldState, isFalse);
      expect(
        session.publishLatch().isHeld(KeyPosition.a),
        isFalse,
        reason: 'the phantom hold must not survive the demotion',
      );
    });

    test('the demotion owes a release for every phantom hold', () {
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      const press = KeyEvent(KeyCode.a, position: KeyPosition.a);
      session.ingest(press);
      session.ingest(press);
      session.ingest(press);
      final releases = session.drainDemotionReleases();
      expect(releases, hasLength(1));
      expect(releases.single.type, KeyEventType.up);
      expect(
        releases.single.synthesized,
        isTrue,
        reason: 'a synthesized release must not trigger command bindings',
      );
      expect(session.drainDemotionReleases(), isEmpty, reason: 'drained once');
    });

    test('an honest flag-2 terminal is never demoted', () {
      // Press, tagged repeats, release — no contradiction, no demotion.
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      session.ingest(const KeyEvent(KeyCode.a, position: KeyPosition.a));
      for (var i = 0; i < 20; i++) {
        session.ingest(
          const KeyEvent(
            KeyCode.a,
            position: KeyPosition.a,
            type: KeyEventType.repeat,
          ),
        );
      }
      session.ingest(
        const KeyEvent(
          KeyCode.a,
          position: KeyPosition.a,
          type: KeyEventType.up,
        ),
      );
      expect(session.capabilities.supportsHeldState, isTrue);
      expect(session.publishLatch().isHeld(KeyPosition.a), isFalse);
    });
  });
}

/// A widget that runs a ticker and samples the keyboard from it — the
/// game-loop shape RFC 0020 §7 is designed around.
class _TickerProbe extends StatefulWidget {
  const _TickerProbe({required this.onReady, required this.onTick});

  final void Function(Keyboard) onReady;
  final void Function() onTick;

  @override
  State<_TickerProbe> createState() => _TickerProbeState();
}

class _TickerProbeState extends State<_TickerProbe> {
  Ticker? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onReady(Keyboard.of(context));
    _ticker ??= TuiBinding.of(context).createTicker((_) => widget.onTick())
      ..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Focus(autofocus: true, child: Text('probe'));
}
