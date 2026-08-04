// RFC 0020 Part II acceptance: the public DX surface.
//
// Covers the pieces P4 introduces — repeat policy (§14.2), KeyBinding.hold
// (§14.5), KeyBindings(modal:) (§14.3), KeyDetector (§17), and the Keyboard
// handle's asymmetric reactivity (§15).

import 'package:fleury/fleury.dart';
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
}
