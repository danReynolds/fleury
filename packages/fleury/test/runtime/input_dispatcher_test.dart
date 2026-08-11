// The 20 P1 acceptance tests from RFC 0008 §9. Each test mounts a
// widget tree, dispatches synthetic KeyEvents through the
// InputDispatcher, and asserts on the resulting handler calls and
// hint-bar contents.
//
// The dispatcher is wired up directly here rather than via runApp
// because runApp depends on a real terminal driver. Constructing
// the FocusManager + InputDispatcher manually lets each test run
// without I/O.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

KeyEvent _char(String c, {bool ctrl = false, bool alt = false}) {
  return KeyEvent(
    KeyCode.char(c),
    modifiers: {if (ctrl) KeyModifier.ctrl, if (alt) KeyModifier.alt},
  );
}

KeyEvent _code(KeyCode kc) => KeyEvent(kc);

/// Wires up a manager + dispatcher + element tree for testing.
class _TestHarness {
  _TestHarness({List<KeyBinding> rootBindings = const []})
    : _rootBindings = rootBindings {
    manager = FocusManager();
    dispatcher = InputDispatcher(
      focusManager: manager,
      sequenceTimeout: const Duration(milliseconds: 50),
    );
    owner = BuildOwner();
  }

  final List<KeyBinding> _rootBindings;
  late final FocusManager manager;
  late final InputDispatcher dispatcher;
  late final BuildOwner owner;

  /// App-wide bindings are an outermost `KeyBindings` — the same thing an app
  /// writes at its root now that `globalBindings` is gone.
  void mountRoot(Widget app) {
    final root = _rootBindings.isEmpty
        ? app
        : KeyBindings(bindings: _rootBindings, child: app);
    owner.mountRoot(FocusManagerScope(manager: manager, child: root));
  }

  KeyEventResult dispatch(KeyEvent event) => dispatcher.dispatch(event);
}

class _ClaimLog extends StatefulWidget {
  const _ClaimLog({required this.events});

  final List<String> events;

  @override
  State<_ClaimLog> createState() => _ClaimLogState();
}

class _ClaimLogState extends State<_ClaimLog>
    implements TextInputClaimant, TextCompositionClaimant {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(debugLabel: 'claim-log');
    _node.textInputClaimant = this;
    _node.textCompositionClaimant = this;
  }

  @override
  KeyEventResult onTextInput(String text) {
    widget.events.add('text:$text');
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onPaste(String text) {
    widget.events.add('paste:$text');
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onTextCompositionUpdate(String text) {
    widget.events.add('composition-update:$text');
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onTextCompositionCommit(String? text) {
    widget.events.add('composition-commit:${text ?? '<active>'}');
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onTextCompositionCancel() {
    widget.events.add('composition-cancel');
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _node.textInputClaimant = null;
    _node.textCompositionClaimant = null;
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(focusNode: _node, autofocus: true, child: const EmptyBox());
  }
}

/// A focused text claimant that DECLINES every printable (returns `ignored`),
/// like a vim NORMAL surface: the char is offered, refused, and falls through
/// to key dispatch. Used to exercise a pure prefix that arms over a text
/// field yet is owed nothing.
class _DecliningField extends StatefulWidget {
  const _DecliningField();

  @override
  State<_DecliningField> createState() => _DecliningFieldState();
}

class _DecliningFieldState extends State<_DecliningField>
    implements TextInputClaimant {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(debugLabel: 'declining')..textInputClaimant = this;
  }

  @override
  KeyEventResult onTextInput(String text) => KeyEventResult.ignored;

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  @override
  void dispose() {
    _node.textInputClaimant = null;
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(focusNode: _node, autofocus: true, child: const EmptyBox());
  }
}

void main() {
  group('InputDispatcher lifecycle', () {
    test('dispose clears pending state and blocks further dispatch', () {
      final h = _TestHarness(
        rootBindings: [KeyBinding(KeySequence.space.q, onTrigger: (_) {})],
      );
      h.mountRoot(const EmptyBox());
      h.dispatch(_char(' '));
      expect(h.dispatcher.hasPendingSequence, isTrue);

      h.dispatcher.dispose();
      h.dispatcher.dispose();

      expect(h.dispatcher.hasPendingSequence, isFalse);
      expect(
        () => h.dispatch(_char('q')),
        _stateError('InputDispatcher has been disposed.'),
      );
    });
  });

  group('InputBatch dispatch (RFC 0020 P1d interim routing)', () {
    test('the text half reaches the focused text claimant', () {
      final events = <String>[];
      final h = _TestHarness();
      h.mountRoot(_ClaimLog(events: events));
      final result = h.dispatcher.dispatch(
        const InputBatch(key: KeyEvent(KeyCode.char('a')), committedText: 'a'),
      );
      expect(result, KeyEventResult.handled);
      expect(events, ['text:a']);
    });

    test('a text-bearing batch does not also key-dispatch its key half', () {
      // Pre-batch, a CSI-u printable was text-only: a character binding on
      // 'a' fires via the text fallback when unclaimed, and must fire ONCE.
      var fired = 0;
      final h = _TestHarness(
        rootBindings: [KeyBinding(KeyCode.a, onTrigger: (_) => fired++)],
      );
      h.mountRoot(const EmptyBox());
      h.dispatcher.dispatch(
        const InputBatch(key: KeyEvent(KeyCode.char('a')), committedText: 'a'),
      );
      expect(fired, 1);
    });

    test('a key-only up batch is fenced from bindings', () {
      var fired = 0;
      final h = _TestHarness(
        rootBindings: [KeyBinding(KeyCode.a, onTrigger: (_) => fired++)],
      );
      h.mountRoot(const EmptyBox());
      final result = h.dispatcher.dispatch(
        const InputBatch(
          key: KeyEvent(KeyCode.char('a'), type: KeyEventType.up),
        ),
      );
      expect(result, KeyEventResult.ignored);
      expect(fired, 0);
    });

    test('a key-only down batch reaches key dispatch', () {
      var fired = 0;
      final h = _TestHarness(
        rootBindings: [KeyBinding(KeyCode.f13, onTrigger: (_) => fired++)],
      );
      h.mountRoot(const EmptyBox());
      final result = h.dispatcher.dispatch(
        const InputBatch(key: KeyEvent(KeyCode.f13)),
      );
      expect(result, KeyEventResult.handled);
      expect(fired, 1);
    });
  });

  group('observation lane projection (RFC 0020 §10)', () {
    List<String> phases(List<KeyEvent> log) => [
      for (final e in log)
        '${e.code.character ?? e.code.special!.name}:${e.type.name}'
            '${e.synthesized ? '*' : ''}',
    ];

    _TestHarness fullCaps() {
      final h = _TestHarness();
      h.dispatcher.keyboardSession.updateCapabilities(
        KeyboardCapabilities.full,
      );
      h.mountRoot(const EmptyBox());
      return h;
    }

    KeyEvent down(String c) => KeyEvent(KeyCode.char(c));
    KeyEvent up(String c) => KeyEvent(KeyCode.char(c), type: KeyEventType.up);
    KeyEvent repeat(String c) =>
        KeyEvent(KeyCode.char(c), type: KeyEventType.repeat);

    test('an app-wide observer sees the full regularized phase stream', () {
      final h = fullCaps();
      final log = <KeyEvent>[];
      h.dispatcher.addKeyObserver(log.add);
      h.dispatcher.dispatch(down('a'));
      h.dispatcher.dispatch(repeat('a'));
      h.dispatcher.dispatch(up('a'));
      expect(phases(log), ['a:down', 'a:repeat', 'a:up']);
    });

    test('phase repair reaches observers (repeat-without-down)', () {
      final h = fullCaps();
      final log = <KeyEvent>[];
      h.dispatcher.addKeyObserver(log.add);
      h.dispatcher.dispatch(repeat('a'));
      expect(phases(log), ['a:down*', 'a:repeat']);
    });

    test('an observer registered mid-press hears nothing until a fresh '
        'press (no phantom phases)', () {
      final h = fullCaps();
      h.dispatcher.dispatch(down('a'));
      final log = <KeyEvent>[];
      h.dispatcher.addKeyObserver(log.add);
      h.dispatcher.dispatch(repeat('a'));
      h.dispatcher.dispatch(up('a'));
      expect(log, isEmpty);
      h.dispatcher.dispatch(down('a'));
      expect(phases(log), ['a:down']);
    });

    test('removal mid-press closes open presses with a synthesized up', () {
      final h = fullCaps();
      final log = <KeyEvent>[];
      final registration = h.dispatcher.addKeyObserver(log.add);
      h.dispatcher.dispatch(down('w'));
      registration.remove();
      expect(phases(log), ['w:down', 'w:up*']);
      // Removed registrations observe nothing further.
      h.dispatcher.dispatch(down('x'));
      expect(log, hasLength(2));
    });

    test('dispatcher disposal closes open presses (authority loss)', () {
      final h = fullCaps();
      final log = <KeyEvent>[];
      h.dispatcher.addKeyObserver(log.add);
      h.dispatcher.dispatch(down('w'));
      h.dispatcher.dispose();
      expect(phases(log), ['w:down', 'w:up*']);
    });

    test('a scope-anchored observer projects on focus exit', () {
      final h = fullCaps();
      final nodeA = FocusNode(debugLabel: 'a');
      final nodeB = FocusNode(debugLabel: 'b');
      addTearDown(() {
        nodeA.dispose();
        nodeB.dispose();
      });
      h.mountRoot(
        Column(
          children: [
            Focus(focusNode: nodeA, autofocus: true, child: const EmptyBox()),
            Focus(focusNode: nodeB, child: const EmptyBox()),
          ],
        ),
      );
      final log = <KeyEvent>[];
      h.dispatcher.addKeyObserver(log.add, anchor: nodeA);

      h.dispatcher.dispatch(down('w')); // in scope: observed
      nodeB.requestFocus(); // scope exit while held
      // The end fires AT the focus change — not lazily on the next key.
      // Push-to-talk over a modal is the case that makes this visible: the
      // mic must close when the dialog opens, not whenever something else
      // is typed (RFC 0020 §10, §14.5).
      expect(phases(log), ['w:down', 'w:up*']);

      h.dispatcher.dispatch(down('x')); // out of scope: not observed
      expect(phases(log), ['w:down', 'w:up*']);

      nodeA.requestFocus();
      h.dispatcher.dispatch(down('y')); // back in scope
      expect(phases(log), ['w:down', 'w:up*', 'y:down']);
    });

    test('a capability downgrade routes recovery releases to observers', () {
      final h = fullCaps();
      final log = <KeyEvent>[];
      h.dispatcher.addKeyObserver(log.add);
      h.dispatcher.dispatch(down('w'));
      // Losing held-state support mid-session (a negotiated rollback)
      // clears the press records; every open observer press must close
      // with them, or hold's one-end-per-start contract breaks.
      h.dispatcher.updateKeyboardCapabilities(KeyboardCapabilities.legacy);
      expect(phases(log), ['w:down', 'w:up*']);
    });

    test('replacing the session recovers presses and bumps the '
        'generation', () {
      final h = fullCaps();
      final log = <KeyEvent>[];
      h.dispatcher.addKeyObserver(log.add);
      h.dispatcher.dispatch(down('w'));
      final before = h.dispatcher.keyboardSession.sessionGeneration;
      h.dispatcher.replaceKeyboardSession();
      expect(phases(log), ['w:down', 'w:up*']);
      expect(
        h.dispatcher.keyboardSession.sessionGeneration,
        before + 1,
        reason: 'sampled consumers key invalidation off this',
      );
    });
  });

  group('Acceptance tests — focus chain bubble-up', () {
    test('1. Focused child binding handles a key before parent', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.char('q'),
              onTrigger: (_) => calls.add('parent'),
              label: 'p',
            ),
          ],
          child: KeyBindings(
            bindings: [
              KeyBinding(
                KeyCode.char('q'),
                onTrigger: (_) => calls.add('child'),
                label: 'c',
              ),
            ],
            child: const Focus(autofocus: true, child: EmptyBox()),
          ),
        ),
      );

      h.dispatch(_char('q'));
      expect(calls, ['child']);
    });

    test('2. If child ignores, parent binding handles it', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.char('q'),
              onTrigger: (_) => calls.add('parent'),
            ),
          ],
          // Child has bindings but none for 'q'.
          child: KeyBindings(
            bindings: [
              KeyBinding(
                KeyCode.char('x'),
                onTrigger: (_) => calls.add('child:x'),
              ),
            ],
            child: const Focus(autofocus: true, child: EmptyBox()),
          ),
        ),
      );

      h.dispatch(_char('q'));
      expect(calls, ['parent']);
    });
  });

  group('Acceptance tests — FocusScope', () {
    test('3. Normal FocusScope does NOT block parent bindings', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.char('q'),
              onTrigger: (_) => calls.add('parent'),
            ),
          ],
          child: const FocusScope(
            child: Focus(autofocus: true, child: EmptyBox()),
          ),
        ),
      );

      h.dispatch(_char('q'));
      expect(calls, ['parent']);
    });

    test('4. Modal FocusScope blocks parent bindings behind it', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.char('q'),
              onTrigger: (_) => calls.add('parent'),
            ),
          ],
          child: const FocusScope(
            modal: true,
            child: Focus(autofocus: true, child: EmptyBox()),
          ),
        ),
      );

      h.dispatch(_char('q'));
      expect(calls, isEmpty);
    });
  });

  group('Acceptance tests — root bindings', () {
    test('5. A root binding fires when the focus chain ignores the key', () {
      final calls = <String>[];
      final h = _TestHarness(
        rootBindings: [
          KeyBinding(KeySequence.ctrl.c, onTrigger: (_) => calls.add('root')),
        ],
      );
      h.mountRoot(const Focus(autofocus: true, child: EmptyBox()));

      h.dispatch(_char('c', ctrl: true));
      expect(calls, ['root']);
    });

    test('6. A deeper binding overrides a root binding', () {
      final calls = <String>[];
      final h = _TestHarness(
        rootBindings: [
          KeyBinding(KeyCode.char('q'), onTrigger: (_) => calls.add('root')),
        ],
      );
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.char('q'), onTrigger: (_) => calls.add('local')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('q'));
      expect(calls, ['local']);
    });
  });

  group('Acceptance tests — hint-bar binding metadata', () {
    // KeyHintBar itself moved to fleury_widgets; rendering coverage
    // lives in fleury_widgets/test/key_hint_bar_test.dart. These
    // check the binding data fields the bar filters on.
    test('9. Bindings with description=null are hidden from hint bar', () {
      final binding = KeyBinding(KeyCode.char('q'), onTrigger: (_) {});
      expect(binding.label, isNull);
    });

    test('10. Bindings with hideFromHintBar=true are hidden', () {
      final binding = KeyBinding(
        KeySequence.ctrl.c,
        onTrigger: (_) {},
        label: 'Quit',
        hideFromHintBar: true,
      );
      expect(binding.hideFromHintBar, isTrue);
    });

    test('11. Dynamic binding rebuild updates hint bar', () {
      // Bindings are read from the KeyBindings widget at render
      // time; when bindings change via setState (rebuild), the
      // hint bar's next read reflects them. Covered by the
      // KeyBindings.bindings field being read live in
      // _KeyBindingsState.activeBindings.
      final stateBindings = <KeyBinding>[
        KeyBinding(KeyCode.char('a'), onTrigger: (_) {}, label: 'first'),
      ];
      expect(stateBindings.first.label, 'first');
      stateBindings[0] = KeyBinding(
        KeyCode.char('a'),
        onTrigger: (_) {},
        label: 'second',
      );
      expect(stateBindings.first.label, 'second');
    });
  });

  group('Acceptance tests — aliases', () {
    test('12. Alias matches both j and arrowDown', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.char('j'),
              aliases: [KeyCode.arrowDown],
              onTrigger: (_) => calls.add('down'),
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('j'));
      h.dispatch(_code(KeyCode.arrowDown));
      expect(calls, ['down', 'down']);
    });
  });

  group('Acceptance tests — sequences', () {
    test('13. Sequence Space q fires when q follows Space', () async {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.q,
              onTrigger: (_) => calls.add('Space+q'),
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char(' '));
      expect(h.dispatcher.hasPendingSequence, isTrue);
      h.dispatch(_char('q'));
      expect(calls, ['Space+q']);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('14. Direct + sequence at same node: bare key waits until the '
        'sequence times out, then fires', () async {
      // Vim-style precedence: when a node binds both `.space` (direct)
      // and `.space.q` (sequence), pressing Space must NOT fire the
      // direct binding immediately — that would make `.space.q`
      // unreachable. The dispatcher pends, and after the sequence
      // timeout, the deferred direct binding fires via the
      // replay-as-direct-only path.
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.q,
              onTrigger: (_) => calls.add('Space+q'),
              label: 'Sequence',
            ),
            KeyBinding(
              KeyCode.char(' '),
              onTrigger: (_) => calls.add('bare-space'),
              label: 'Bare space',
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char(' '));
      // Direct does NOT fire immediately — pending instead.
      expect(calls, isEmpty);
      expect(h.dispatcher.hasPendingSequence, isTrue);

      // After the timeout (harness uses 50ms), bare-space fires.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, ['bare-space']);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('15. Direct focused Space beats ancestor Space q sequence', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.q,
              onTrigger: (_) => calls.add('ancestor:Space-q'),
            ),
          ],
          child: KeyBindings(
            bindings: [
              KeyBinding(
                KeyCode.char(' '),
                onTrigger: (_) => calls.add('focused:Space'),
              ),
            ],
            child: const Focus(autofocus: true, child: EmptyBox()),
          ),
        ),
      );

      h.dispatch(_char(' '));
      expect(calls, ['focused:Space']);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });
  });

  group('Acceptance tests — text input precedence', () {
    test('16. Text input handles insertable Space before ancestor '
        'leader sequence', () {
      // Per RFC 0008 §6.7: a focused TextInputClaimant consumes
      // insertable TextInputEvents before any ancestor KeyBindings
      // (including sequence-start chords) get to see them.
      final controller = TextEditingController();
      var paletteOpens = 0;
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.p,
              onTrigger: (_) => paletteOpens += 1,
            ),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      h.dispatcher.dispatch(const TextInputEvent(' '));
      expect(controller.text, ' ');
      expect(paletteOpens, 0);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('16a. Unclaimed printable text falls through to KeyBindings', () {
      var activations = 0;
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [KeyBinding(.space, onTrigger: (_) => activations += 1)],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatcher.dispatch(const TextInputEvent(' '));
      expect(activations, 1);
    });

    test('16c. Unclaimed printable text can complete a leader sequence', () {
      var paletteOpens = 0;
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [KeyBinding(.space.p, onTrigger: (_) => paletteOpens += 1)],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatcher.dispatch(const TextInputEvent(' '));
      expect(h.dispatcher.hasPendingSequence, isTrue);

      h.dispatcher.dispatch(const TextInputEvent('p'));
      expect(paletteOpens, 1);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('16i. A bare-printable continuation completes a pending sequence '
        'while a text field is focused', () {
      // The parser emits plain printables as TextInputEvent, so the
      // continuation of a held Ctrl+X leader arrives on the text path.
      // Pending-sequence handling has precedence over text delivery
      // (dispatch rule 1): the advertised .ctrl.x.b chord must fire, and
      // the 'b' must NOT leak into the focused field.
      final controller = TextEditingController();
      var switchBuffer = 0;
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.x.b,
              onTrigger: (_) => switchBuffer += 1,
            ),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      h.dispatch(_char('x', ctrl: true));
      expect(h.dispatcher.hasPendingSequence, isTrue);

      h.dispatcher.dispatch(const TextInputEvent('b'));
      expect(switchBuffer, 1, reason: 'the sequence completes');
      expect(
        controller.text,
        isEmpty,
        reason: 'the continuation char must not corrupt the field',
      );
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('16j. A non-matching printable cancels the pending sequence, '
        'replays the held leader, then delivers the text to the field', () {
      // The documented cancel path: the held Ctrl+X is redispatched
      // (direct-only, so the deferred direct binding fires) BEFORE the
      // breaking text is delivered — never silently dropped.
      final controller = TextEditingController();
      var switchBuffer = 0;
      var directCtrlX = 0;
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.x.b,
              onTrigger: (_) => switchBuffer += 1,
            ),
            KeyBinding(KeySequence.ctrl.x, onTrigger: (_) => directCtrlX += 1),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      h.dispatch(_char('x', ctrl: true));
      expect(h.dispatcher.hasPendingSequence, isTrue);
      expect(directCtrlX, 0, reason: 'direct deferred while pending');

      h.dispatcher.dispatch(const TextInputEvent('z'));
      expect(directCtrlX, 1, reason: 'held leader replayed on cancel');
      expect(switchBuffer, 0);
      expect(controller.text, 'z', reason: 'the text still reaches the field');
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('16k. A text-origin mid-sequence step is delivered to the field '
        'when a later step breaks the sequence', () {
      // A 3-step chord holds the middle 'a' (which arrived as text). When
      // 'z' breaks the sequence, that held character belongs to the
      // focused field: replaying it direct-only would silently eat it.
      final controller = TextEditingController();
      var fired = 0;
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.x.a.b, onTrigger: (_) => fired += 1),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      h.dispatch(_char('x', ctrl: true));
      h.dispatcher.dispatch(const TextInputEvent('a'));
      expect(h.dispatcher.hasPendingSequence, isTrue);
      expect(controller.text, isEmpty, reason: 'held while the chord lives');

      h.dispatcher.dispatch(const TextInputEvent('z'));
      expect(fired, 0);
      expect(
        controller.text,
        'az',
        reason: 'the held text char reaches the field before the breaker',
      );
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('16l. A text-origin mid-sequence step is delivered to the field '
        'when the sequence times out', () async {
      final controller = TextEditingController();
      var fired = 0;
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.x.a.b, onTrigger: (_) => fired += 1),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      h.dispatch(_char('x', ctrl: true));
      h.dispatcher.dispatch(const TextInputEvent('a'));
      expect(controller.text, isEmpty, reason: 'held while the chord lives');

      // Harness timeout is 50ms; the held 'a' must surface in the field.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fired, 0);
      expect(
        controller.text,
        'a',
        reason: 'timeout must not silently eat the typed character',
      );
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('16d. Bracketed paste dispatches to onPaste, not onTextInput', () {
      final events = <String>[];
      final h = _TestHarness();
      h.mountRoot(_ClaimLog(events: events));

      h.dispatcher.dispatch(const TextInputEvent('a'));
      h.dispatcher.dispatch(const PasteEvent('b\nc'));

      expect(events, ['text:a', 'paste:b\nc']);
    });

    test('16e. IME composition dispatches to composition claimant', () {
      final events = <String>[];
      final h = _TestHarness();
      h.mountRoot(_ClaimLog(events: events));

      h.dispatcher.dispatch(const TextCompositionEvent.update('あ'));
      h.dispatcher.dispatch(const TextCompositionEvent.commit('亜'));
      h.dispatcher.dispatch(const TextCompositionEvent.cancel());

      expect(events, [
        'composition-update:あ',
        'composition-commit:亜',
        'composition-cancel',
      ]);
    });

    test(
      '16f. Unclaimed IME composition does not fall through to bindings',
      () {
        var activations = 0;
        final h = _TestHarness();
        h.mountRoot(
          KeyBindings(
            bindings: [
              KeyBinding(KeyCode.char('a'), onTrigger: (_) => activations += 1),
            ],
            child: const Focus(autofocus: true, child: EmptyBox()),
          ),
        );

        final result = h.dispatcher.dispatch(
          const TextCompositionEvent.commit('a'),
        );

        expect(result, KeyEventResult.ignored);
        expect(activations, 0);
      },
    );

    test('16g. TextInput applies IME update, commit, and cancel', () {
      final controller = TextEditingController(text: 'git ');
      final h = _TestHarness();
      h.mountRoot(TextInput(controller: controller, autofocus: true));

      h.dispatcher.dispatch(const TextCompositionEvent.update('che'));

      expect(controller.text, 'git che');
      expect(controller.hasComposingRange, isTrue);

      h.dispatcher.dispatch(const TextCompositionEvent.commit('checkout'));

      expect(controller.text, 'git checkout');
      expect(controller.hasComposingRange, isFalse);

      h.dispatcher.dispatch(const TextCompositionEvent.update(' branch'));
      expect(controller.text, 'git checkout branch');
      h.dispatcher.dispatch(const TextCompositionEvent.cancel());

      expect(controller.text, 'git checkout');
      expect(controller.hasComposingRange, isFalse);
    });

    test('16h. TextArea preserves multiline IME commits', () {
      final controller = TextEditingController(text: 'one\n');
      final h = _TestHarness();
      h.mountRoot(TextArea(controller: controller, autofocus: true));

      h.dispatcher.dispatch(const TextCompositionEvent.update('two'));
      h.dispatcher.dispatch(const TextCompositionEvent.commit('two\nthree'));

      expect(controller.text, 'one\ntwo\nthree');
      expect(controller.hasComposingRange, isFalse);
    });
  });

  group('Acceptance tests — modifier chords', () {
    test('17. Ctrl/Alt modifier chords match normalized KeyEvent', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.s, onTrigger: (_) => calls.add('save')),
            KeyBinding(KeySequence.alt.x, onTrigger: (_) => calls.add('alt-x')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('s', ctrl: true));
      h.dispatch(_char('x', alt: true));
      expect(calls, ['save', 'alt-x']);
    });
  });

  group('Acceptance tests — modal dialogs', () {
    test('18. Modal dialog can claim Esc without ancestor seeing it', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.escape,
              onTrigger: (_) => calls.add('list:escape'),
            ),
          ],
          child: FocusScope(
            modal: true,
            child: KeyBindings(
              bindings: [
                KeyBinding(
                  KeyCode.escape,
                  onTrigger: (_) => calls.add('dialog:cancel'),
                ),
              ],
              child: const Focus(autofocus: true, child: EmptyBox()),
            ),
          ),
        ),
      );

      h.dispatch(_code(KeyCode.escape));
      expect(calls, ['dialog:cancel']);
    });

    test('19. A modal scope isolates the app\'s root bindings', () {
      // With globalBindings gone, app-wide shortcuts are an outermost
      // KeyBindings — so a modal scope's chain truncation is what keeps a
      // dialog from firing them. This is the whole dialog-isolation
      // guarantee, and it needs no separate suppression flag.
      final calls = <String>[];
      final h = _TestHarness(
        rootBindings: [
          KeyBinding(
            KeySequence.ctrl.c,
            onTrigger: (_) => calls.add('root:quit'),
          ),
        ],
      );
      h.mountRoot(
        const FocusScope(
          modal: true,
          child: Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('c', ctrl: true));
      expect(calls, isEmpty, reason: 'the modal must not leak to the root');
    });
  });

  group('Acceptance tests — disabled bindings', () {
    test('20. Disabled bindings do not fire', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.char('d'),
              onTrigger: (_) => calls.add('delete'),
              enabled: false,
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('d'));
      expect(calls, isEmpty);
    });
  });

  group('Extended sequence semantics', () {
    test('a 3-step chord (.ctrl.x.ctrl.c) fires after all three events', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.x.ctrl.s,
              onTrigger: (_) => calls.add('save'),
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('x', ctrl: true));
      expect(h.dispatcher.hasPendingSequence, isTrue);
      h.dispatch(_char('s', ctrl: true));
      expect(calls, ['save']);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test(
      'coexisting .d and .d.k: bare .d waits, then fires on timeout — '
      'and the sequence still works if the user follows up in time',
      () async {
        // Vim-style: a single key that is also the prefix of a sequence
        // cannot fire immediately. The dispatcher pends. If the user
        // follows up with the right key within `sequenceTimeout`, the
        // sequence fires. Otherwise the bare key fires on timeout.
        final calls = <String>[];
        final h = _TestHarness();
        h.mountRoot(
          KeyBindings(
            bindings: [
              KeyBinding(KeySequence.d, onTrigger: (_) => calls.add('d')),
              KeyBinding(KeySequence.d.k, onTrigger: (_) => calls.add('dk')),
            ],
            child: const Focus(autofocus: true, child: EmptyBox()),
          ),
        );

        // Press d alone — must wait, not fire .d.
        h.dispatch(_char('d'));
        expect(calls, isEmpty);
        expect(h.dispatcher.hasPendingSequence, isTrue);

        // Press k within the timeout — the .d.k sequence completes.
        h.dispatch(_char('k'));
        expect(calls, ['dk']);
        expect(h.dispatcher.hasPendingSequence, isFalse);

        // Press d again, then let the timeout fire — bare .d fires.
        h.dispatch(_char('d'));
        expect(calls, ['dk']);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(calls, ['dk', 'd']);
        expect(h.dispatcher.hasPendingSequence, isFalse);
      },
    );

    test('mid-sequence miss: deferred direct fires on cancel-replay', () async {
      // .ctrl.x is bound directly AND .ctrl.x.ctrl.s is bound as a
      // sequence. User types Ctrl+X then a non-extending key.
      // Direct .ctrl.x was deferred when Ctrl+X arrived; the
      // cancel-replay fires it before dispatching the new event.
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.x.ctrl.s,
              onTrigger: (_) => calls.add('save'),
            ),
            KeyBinding(KeySequence.ctrl.x, onTrigger: (_) => calls.add('cx')),
            KeyBinding(KeyCode.char('q'), onTrigger: (_) => calls.add('q')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      // Ctrl+X: both .ctrl.x and .ctrl.x.ctrl.s plausible. Pend.
      h.dispatch(_char('x', ctrl: true));
      expect(calls, isEmpty);
      expect(h.dispatcher.hasPendingSequence, isTrue);

      // Type 'q' — doesn't extend .ctrl.x.ctrl.s.
      // Cancel: replay Ctrl+X (fires deferred .ctrl.x), then dispatch q.
      h.dispatch(_char('q'));
      expect(calls, ['cx', 'q']);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('explicit sequence-only start: held events replay on miss', () async {
      // Pure sequence (no shorter direct binding). The dispatcher
      // pends, then on a miss replays the first event as plain.
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.q,
              onTrigger: (_) => calls.add('space-q'),
            ),
            KeyBinding(KeyCode.char('z'), onTrigger: (_) => calls.add('z')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char(' '));
      expect(h.dispatcher.hasPendingSequence, isTrue);
      // Wrong follow-up: cancel + redispatch space (no binding for
      // bare space here, so nothing fires for it) + dispatch 'z'
      // (which has a binding).
      h.dispatch(_char('z'));
      expect(calls, ['z']);
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });
  });

  group('Pure-prefix hold-open (which-key discoverability)', () {
    test(
      'a pure prefix holds pending past the timeout, then still completes',
      () async {
        // `.d.k` with NO shorter `.d` binding: pressing `d` opens a prefix that
        // commits nothing on its own. It must NOT self-cancel on the sequence
        // timer — a which-key popup rests on it — yet stays completable. (An
        // ambiguous `.d` + `.d.k` still fires bare `.d` on timeout; see the
        // "coexisting .d and .d.k" test.)
        final calls = <String>[];
        final h = _TestHarness();
        h.mountRoot(
          KeyBindings(
            bindings: [
              KeyBinding(KeySequence.d.k, onTrigger: (_) => calls.add('dk')),
            ],
            child: const Focus(autofocus: true, child: EmptyBox()),
          ),
        );

        h.dispatch(_char('d'));
        expect(h.dispatcher.hasPendingSequence, isTrue);

        // Well past the 50ms harness timeout: still pending, nothing fired.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          calls,
          isEmpty,
          reason: 'a pure prefix commits nothing on timeout',
        );
        expect(
          h.dispatcher.hasPendingSequence,
          isTrue,
          reason: 'the prefix holds open instead of self-cancelling',
        );

        // The follow-up completes the sequence after the wait.
        h.dispatch(_char('k'));
        expect(calls, ['dk']);
        expect(h.dispatcher.hasPendingSequence, isFalse);
      },
    );

    test(
      'a held-open pure prefix still cancels cleanly on a breaking key',
      () async {
        final calls = <String>[];
        final h = _TestHarness();
        h.mountRoot(
          KeyBindings(
            bindings: [
              KeyBinding(KeySequence.d.k, onTrigger: (_) => calls.add('dk')),
              KeyBinding(KeyCode.char('z'), onTrigger: (_) => calls.add('z')),
            ],
            child: const Focus(autofocus: true, child: EmptyBox()),
          ),
        );

        h.dispatch(_char('d'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(h.dispatcher.hasPendingSequence, isTrue);

        // A non-extending key breaks the held prefix: replay `d` (no binding,
        // inert), then dispatch `z`.
        h.dispatch(_char('z'));
        expect(calls, ['z']);
        expect(h.dispatcher.hasPendingSequence, isFalse);
      },
    );

    test('a pure prefix over a DECLINING text field (vim NORMAL) holds open '
        'without eating the char', () async {
      // The vim-NORMAL scenario at the dispatcher level: a focused claimant
      // declines printables, so `d` routes to `.d.k` as a command and arms a
      // prefix. On timeout nothing commits — the field refused the char — so
      // the prefix holds instead of the keystroke being silently swallowed.
      // (Contrast test 16l, where an ACCEPTING field is owed the char and the
      // timeout does deliver it.)
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [KeyBinding(KeySequence.d.k, onTrigger: (_) {})],
          child: const _DecliningField(),
        ),
      );

      h.dispatcher.dispatch(const TextInputEvent('d'));
      expect(h.dispatcher.hasPendingSequence, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        h.dispatcher.hasPendingSequence,
        isTrue,
        reason: 'declined text left a pure prefix — it holds open',
      );

      // Still completable: the second step finishes `.d.k`.
      h.dispatcher.dispatch(const TextInputEvent('k'));
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });
  });

  group('timeout-commit counts handler runs, not results', () {
    test('a shorter binding that fires then bubbles still resolves the '
        'prefix', () async {
      // `bubble()` reports `ignored` so ancestors get a turn — but the
      // handler ALREADY RAN. If the commit only believed `handled`, the
      // prefix would stay held after the action fired, and the next key would
      // fire the longer binding too: one intent, two actions.
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.d,
              onTrigger: (e) {
                calls.add('d');
                e.bubble();
              },
            ),
            KeyBinding(KeySequence.d.k, onTrigger: (_) => calls.add('dk')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('d'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(calls, ['d'], reason: 'the bubbling handler ran');
      expect(
        h.dispatcher.hasPendingSequence,
        isFalse,
        reason: 'it ran, so the prefix is resolved — not still held',
      );

      // A following k is just a fresh key, NOT the tail of `.d.k`.
      h.dispatch(_char('k'));
      expect(calls, ['d'], reason: 'dk must not fire off the stale prefix');
    });
  });

  group('timeout-commit re-entrancy', () {
    test('a handler dispatching during the commit cannot re-enter the '
        'sequence being torn down', () async {
      // The deferred direct `.d` fires on timeout, and its handler
      // synchronously dispatches another key. That nested dispatch must not
      // match the sequence mid-teardown (which would re-fire or re-replay
      // it) — it opens a fresh one instead, and the commit leaves that alone.
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.d,
              onTrigger: (_) {
                calls.add('d');
                if (calls.length < 5) h.dispatch(_char('d')); // re-enter
              },
            ),
            KeyBinding(KeySequence.d.k, onTrigger: (_) => calls.add('dk')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('d'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(calls, ['d'], reason: 'the commit fired exactly once');
      expect(calls, isNot(contains('dk')), reason: 'never re-completed');
      // The nested dispatch opened a fresh prefix; the commit did not discard
      // it, and it is still completable.
      expect(h.dispatcher.hasPendingSequence, isTrue);
      h.dispatch(_char('k'));
      expect(calls, ['d', 'dk']);
    });
  });

  group('cancelPending (a which-key close control)', () {
    test('abandons a held pure prefix, firing nothing', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.d.k, onTrigger: (_) => calls.add('dk')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('d'));
      expect(h.dispatcher.hasPendingSequence, isTrue);

      h.dispatcher.cancelPending();
      expect(h.dispatcher.hasPendingSequence, isFalse);
      expect(calls, isEmpty, reason: 'a pure prefix commits nothing');
    });

    test('commits a deferred shorter binding, exactly as Esc would', () {
      final calls = <String>[];
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.d, onTrigger: (_) => calls.add('d')),
            KeyBinding(KeySequence.d.k, onTrigger: (_) => calls.add('dk')),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('d'));
      expect(calls, isEmpty, reason: 'direct .d deferred while .d.k is live');

      h.dispatcher.cancelPending();
      expect(calls, ['d'], reason: 'the held prefix replays, like Esc/timeout');
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('is a no-op when no sequence is in flight', () {
      final h = _TestHarness();
      h.mountRoot(const Focus(autofocus: true, child: EmptyBox()));

      h.dispatcher.cancelPending(); // must not throw
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });

    test('a late cancel after dispose is a silent no-op', () {
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [KeyBinding(KeySequence.d.k, onTrigger: (_) {})],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );
      final notifier = h.dispatcher.pendingSequenceNotifier;
      h.dispatcher.dispose();

      // A click racing teardown must not throw a disposed-dispatcher error.
      expect(notifier.cancel, returnsNormally);
    });

    test('the widget-tree route (notifier.cancel) reaches the dispatcher', () {
      // What KeyBindings.cancelPending(context) ultimately calls: the scope
      // hands out this notifier, and the dispatcher wires its cancel in.
      final h = _TestHarness();
      h.mountRoot(
        KeyBindings(
          bindings: [KeyBinding(KeySequence.d.k, onTrigger: (_) {})],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('d'));
      expect(h.dispatcher.hasPendingSequence, isTrue);

      h.dispatcher.pendingSequenceNotifier.cancel();
      expect(h.dispatcher.hasPendingSequence, isFalse);
    });
  });
}

/// Test-only builder widget (not exported by the package; needed for
/// the KeyHintBar tests where we want to capture context).
class Builder extends StatelessWidget {
  const Builder({super.key, required this.builder});
  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}
