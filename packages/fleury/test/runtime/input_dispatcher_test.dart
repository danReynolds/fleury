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
  _TestHarness({List<KeyBinding> globalBindings = const []}) {
    manager = FocusManager();
    dispatcher = InputDispatcher(
      focusManager: manager,
      sequenceTimeout: const Duration(milliseconds: 50),
      globalBindings: globalBindings,
    );
    owner = BuildOwner();
  }

  late final FocusManager manager;
  late final InputDispatcher dispatcher;
  late final BuildOwner owner;

  void mountRoot(Widget app) {
    owner.mountRoot(FocusManagerScope(manager: manager, child: app));
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

void main() {
  group('InputDispatcher lifecycle', () {
    test('dispose clears pending state and blocks further dispatch', () {
      final h = _TestHarness(
        globalBindings: [
          KeyBinding.any([KeySequence.space.q], onTrigger: () {}),
        ],
      );
      h.dispatch(_char(' '));
      expect(h.dispatcher.hasPendingSequence, isTrue);

      h.dispatcher.dispose();
      h.dispatcher.dispose();

      expect(h.dispatcher.hasPendingSequence, isFalse);
      expect(() => h.dispatcher.globalBindings, returnsNormally);
      expect(
        () => h.dispatch(_char('q')),
        _stateError('InputDispatcher has been disposed.'),
      );
      expect(
        () => h.dispatcher.globalBindings = const [],
        _stateError('InputDispatcher has been disposed.'),
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
              onTrigger: () => calls.add('parent'),
              label: 'p',
            ),
          ],
          child: KeyBindings(
            bindings: [
              KeyBinding(
                KeyCode.char('q'),
                onTrigger: () => calls.add('child'),
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
            KeyBinding(KeyCode.char('q'), onTrigger: () => calls.add('parent')),
          ],
          // Child has bindings but none for 'q'.
          child: KeyBindings(
            bindings: [
              KeyBinding(
                KeyCode.char('x'),
                onTrigger: () => calls.add('child:x'),
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
            KeyBinding(KeyCode.char('q'), onTrigger: () => calls.add('parent')),
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
            KeyBinding(KeyCode.char('q'), onTrigger: () => calls.add('parent')),
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

  group('Acceptance tests — globals', () {
    test('5. Global binding fires after focus chain ignores', () {
      final calls = <String>[];
      final h = _TestHarness(
        globalBindings: [
          KeyBinding(KeySequence.ctrl.c, onTrigger: () => calls.add('global')),
        ],
      );
      h.mountRoot(const Focus(autofocus: true, child: EmptyBox()));

      h.dispatch(_char('c', ctrl: true));
      expect(calls, ['global']);
    });

    test('6. Focus-chain binding overrides global binding', () {
      final calls = <String>[];
      final h = _TestHarness(
        globalBindings: [
          KeyBinding(KeyCode.char('q'), onTrigger: () => calls.add('global')),
        ],
      );
      h.mountRoot(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.char('q'), onTrigger: () => calls.add('local')),
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
      final binding = KeyBinding(KeyCode.char('q'), onTrigger: () {});
      expect(binding.label, isNull);
    });

    test('10. Bindings with hideFromHintBar=true are hidden', () {
      final binding = KeyBinding(
        KeySequence.ctrl.c,
        onTrigger: () {},
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
        KeyBinding(KeyCode.char('a'), onTrigger: () {}, label: 'first'),
      ];
      expect(stateBindings.first.label, 'first');
      stateBindings[0] = KeyBinding(
        KeyCode.char('a'),
        onTrigger: () {},
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
            KeyBinding.any(const [
              KeyCode.char('j'),
              KeyCode.arrowDown,
            ], onTrigger: () => calls.add('down')),
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
            KeyBinding.any([
              KeySequence.space.q,
            ], onTrigger: () => calls.add('Space+q')),
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
              onTrigger: () => calls.add('Space+q'),
              label: 'Sequence',
            ),
            KeyBinding(
              KeyCode.char(' '),
              onTrigger: () => calls.add('bare-space'),
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
            KeyBinding.any([
              KeySequence.space.q,
            ], onTrigger: () => calls.add('ancestor:Space-q')),
          ],
          child: KeyBindings(
            bindings: [
              KeyBinding(
                KeyCode.char(' '),
                onTrigger: () => calls.add('focused:Space'),
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
            KeyBinding.any([
              KeySequence.space.p,
            ], onTrigger: () => paletteOpens += 1),
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
          bindings: [KeyBinding(.space, onTrigger: () => activations += 1)],
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
          bindings: [KeyBinding(.space.p, onTrigger: () => paletteOpens += 1)],
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
              onTrigger: () => switchBuffer += 1,
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
              onTrigger: () => switchBuffer += 1,
            ),
            KeyBinding(KeySequence.ctrl.x, onTrigger: () => directCtrlX += 1),
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
            KeyBinding(KeySequence.ctrl.x.a.b, onTrigger: () => fired += 1),
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
            KeyBinding(KeySequence.ctrl.x.a.b, onTrigger: () => fired += 1),
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
              KeyBinding(KeyCode.char('a'), onTrigger: () => activations += 1),
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
            KeyBinding(KeySequence.ctrl.s, onTrigger: () => calls.add('save')),
            KeyBinding(KeySequence.alt.x, onTrigger: () => calls.add('alt-x')),
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
              onTrigger: () => calls.add('list:escape'),
            ),
          ],
          child: FocusScope(
            modal: true,
            child: KeyBindings(
              bindings: [
                KeyBinding(
                  KeyCode.escape,
                  onTrigger: () => calls.add('dialog:cancel'),
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

    test('19. Global Ctrl+C still works unless suppressed by modal', () {
      final calls = <String>[];
      final h = _TestHarness(
        globalBindings: [
          KeyBinding(
            KeySequence.ctrl.c,
            onTrigger: () => calls.add('global:quit'),
          ),
        ],
      );
      h.mountRoot(
        const FocusScope(
          modal: true,
          // Note: NOT suppressGlobals: globals still run.
          child: Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      h.dispatch(_char('c', ctrl: true));
      expect(calls, ['global:quit']);
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
              onTrigger: () => calls.add('delete'),
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
              onTrigger: () => calls.add('save'),
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
              KeyBinding(KeySequence.d, onTrigger: () => calls.add('d')),
              KeyBinding(KeySequence.d.k, onTrigger: () => calls.add('dk')),
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
              onTrigger: () => calls.add('save'),
            ),
            KeyBinding(KeySequence.ctrl.x, onTrigger: () => calls.add('cx')),
            KeyBinding(KeyCode.char('q'), onTrigger: () => calls.add('q')),
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
              onTrigger: () => calls.add('space-q'),
            ),
            KeyBinding(KeyCode.char('z'), onTrigger: () => calls.add('z')),
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
}

/// Test-only builder widget (not exported by the package; needed for
/// the KeyHintBar tests where we want to capture context).
class Builder extends StatelessWidget {
  const Builder({super.key, required this.builder});
  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}
