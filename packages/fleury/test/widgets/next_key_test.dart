// RFC 0020 §17.2 / decision 9 — `Keyboard.nextKey`, the interactive capture.
//
// The whole point is that the awaiter decides: while a capture is pending it
// outranks every routed lane, so the editor's own bindings cannot steal the
// key it is waiting for. That is a claim about FOUR lanes (bindings,
// detectors, text, pending sequences), and it is only true if every one of
// them consults the gate.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _Probe extends StatelessWidget {
  const _Probe(this.builder);
  final Widget Function(BuildContext context) builder;
  @override
  Widget build(BuildContext context) => builder(context);
}

/// Mounts a tree with a binding on `a`, a detector, and a text claimant, then
/// hands back a way to arm a capture from inside it.
({List<String> log, Future<KeyEvent?> Function() arm}) _scene(
  FleuryTester tester, {
  List<KeyBinding> extraBindings = const [],
}) {
  final log = <String>[];
  late BuildContext captured;
  tester.pumpFleuryHome(
    KeyBindings(
      bindings: [
        KeyBinding(KeyCode.a, onTrigger: (_) => log.add('binding:a')),
        KeyBinding(KeyCode.escape, onTrigger: (_) => log.add('binding:esc')),
        ...extraBindings,
      ],
      child: KeyDetector(
        onKey: (event) => log.add('detector:${event.code.character ?? ''}'),
        child: _Probe((context) {
          captured = context;
          return const Focus(autofocus: true, child: Text('x'));
        }),
      ),
    ),
  );
  tester.pump();
  return (log: log, arm: () => Keyboard.nextKey(captured));
}

void main() {
  group('the awaiter outranks the routed lanes', () {
    testWidgets('a key event goes to the capture, not to a binding', (
      tester,
    ) async {
      final scene = _scene(tester);
      final pending = scene.arm();
      tester.sendKey(const KeyEvent(KeyCode.a));
      final key = await pending;
      expect(key?.code, KeyCode.a);
      expect(scene.log, isEmpty, reason: 'no lane may see a captured key');
    });

    testWidgets('a TEXT-borne printable is captured too', (tester) async {
      // The regression this file exists for. Where a terminal reports
      // printables only as bytes, a letter arrives as text and never as a key
      // event. A gate consulted only on the key path would ignore exactly the
      // keys nextKey is normally waiting FOR — and worse, let them fall
      // through to whatever binding owns them, so pressing `a` at a prompt
      // would fire the app's `a` command.
      final scene = _scene(tester);
      final pending = scene.arm();
      tester.type('a');
      final key = await pending;
      expect(key?.code.character, 'a');
      expect(scene.log, isEmpty);
    });

    testWidgets('it beats even the app\'s own Escape binding', (tester) async {
      final scene = _scene(tester);
      final pending = scene.arm();
      tester.sendKey(const KeyEvent(KeyCode.escape));
      expect((await pending)?.code, KeyCode.escape);
      expect(scene.log, isEmpty, reason: 'the awaiter decides what Esc means');
    });

    testWidgets('a pending sequence does not get first refusal', (
      tester,
    ) async {
      // Sequence-bypassing (decision 9): a half-typed chord must not swallow
      // the key an awaiter is blocked on, or a prompt opened mid-sequence
      // could never be answered.
      final scene = _scene(
        tester,
        extraBindings: [KeyBinding(KeySequence.g.g, onTrigger: (_) => {})],
      );
      tester.type('g'); // opens the `g` prefix
      final pending = scene.arm();
      tester.type('g'); // would complete `gg` if the sequence won
      expect((await pending)?.code.character, 'g');
    });
  });

  group('what must NOT complete it', () {
    testWidgets('a recovery-synthesized event never completes a capture', (
      tester,
    ) async {
      // A blur that closes a held Ctrl must not "choose" Ctrl for a rebind
      // row — the user never pressed anything.
      final scene = _scene(tester);
      final pending = scene.arm();
      tester.sendKey(
        const KeyEvent(KeyCode.a, type: KeyEventType.up, synthesized: true),
      );
      var done = false;
      unawaited(pending.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      // Still armed: a real press completes it.
      tester.sendKey(const KeyEvent(KeyCode.a));
      expect((await pending)?.code, KeyCode.a);
    });

    testWidgets('an auto-repeat does not complete it — one press, not many', (
      tester,
    ) async {
      final scene = _scene(tester);
      final pending = scene.arm();
      tester.sendKey(const KeyEvent(KeyCode.a, type: KeyEventType.repeat));
      var done = false;
      unawaited(pending.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      tester.sendKey(const KeyEvent(KeyCode.b));
      expect((await pending)?.code, KeyCode.b);
    });
  });

  group('scope-tied by signature (§15)', () {
    testWidgets('unmounting the arming context completes it with null', (
      tester,
    ) async {
      final scene = _scene(tester);
      final pending = scene.arm();
      // The UI that opened the prompt goes away — a capture that outlived it
      // would quietly eat the app's input with nobody left to receive it.
      tester.pumpFleuryHome(const Focus(autofocus: true, child: Text('gone')));
      tester.pump();
      tester.sendKey(const KeyEvent(KeyCode.a));
      expect(await pending, isNull);
    });
  });
}
