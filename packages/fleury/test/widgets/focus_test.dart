import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

KeyEvent _key(String char, {bool ctrl = false, bool alt = false}) {
  return KeyEvent(
    char: char,
    modifiers: {if (ctrl) KeyModifier.ctrl, if (alt) KeyModifier.alt},
  );
}

void main() {
  group('FocusNode and FocusManager', () {
    test('requestFocus moves focus and notifies listeners', () {
      final manager = FocusManager();
      var notifyCalls = 0;
      manager.addListener(() => notifyCalls += 1);

      final owner = BuildOwner();
      final node = FocusNode(debugLabel: 'test');
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(focusNode: node, child: const EmptyBox()),
        ),
      );

      expect(manager.focusedNode, isNull);
      node.requestFocus();
      expect(manager.focusedNode, same(node));
      expect(node.hasFocus, isTrue);
      expect(notifyCalls, 1);
    });

    test('canRequestFocus=false silently refuses', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final node = FocusNode(canRequestFocus: false);
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(focusNode: node, child: const EmptyBox()),
        ),
      );

      node.requestFocus();
      expect(manager.focusedNode, isNull);
    });

    test('autofocus claims focus on first mount if nothing focused', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final node = FocusNode();
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            focusNode: node,
            autofocus: true,
            child: const EmptyBox(),
          ),
        ),
      );

      expect(manager.focusedNode, same(node));
    });

    test('autofocus does NOT steal focus if something is already focused', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      // first is focused before second mounts.
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            focusNode: first,
            autofocus: true,
            child: Focus(
              focusNode: second,
              autofocus: true,
              child: const EmptyBox(),
            ),
          ),
        ),
      );

      expect(manager.focusedNode, same(first));
    });

    test('disposing focused node clears focus', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final node = FocusNode();
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            focusNode: node,
            autofocus: true,
            child: const EmptyBox(),
          ),
        ),
      );
      expect(manager.focusedNode, same(node));

      node.dispose();
      expect(manager.focusedNode, isNull);
    });

    test('manager dispose detaches nodes and rejects focus work', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final node = FocusNode(debugLabel: 'owned');
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            focusNode: node,
            autofocus: true,
            child: const EmptyBox(),
          ),
        ),
      );
      expect(manager.focusedNode, same(node));
      expect(node.isAttached, isTrue);

      manager.dispose();
      manager.dispose();

      expect(manager.focusedNode, isNull);
      expect(manager.attachedNodes, isEmpty);
      expect(node.isAttached, isFalse);
      expect(node.hasFocus, isFalse);
      expect(() => node.requestFocus(), returnsNormally);
      expect(() => node.dispose(), returnsNormally);
      expect(
        () => manager.requestFocus(node),
        _stateError('FocusManager has been disposed.'),
      );
      expect(
        () => manager.focusNext(),
        _stateError('FocusManager has been disposed.'),
      );
      expect(
        () => manager.focusPrevious(),
        _stateError('FocusManager has been disposed.'),
      );
      expect(
        () => manager.dispatchKey(_key('x')),
        _stateError('FocusManager has been disposed.'),
      );
    });
  });

  group('Focus.onKey routing', () {
    test('delivers key to focused node\'s onKey first', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final received = <String>[];

      final node = FocusNode();
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            focusNode: node,
            autofocus: true,
            onKey: (e) {
              received.add('inner:${e.char}');
              return KeyEventResult.handled;
            },
            child: const EmptyBox(),
          ),
        ),
      );

      manager.dispatchKey(_key('a'));
      expect(received, ['inner:a']);
    });

    test('bubbles up through ancestor Focus widgets when child ignores', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            onKey: (e) {
              received.add('outer:${e.char}');
              return KeyEventResult.handled;
            },
            child: Focus(
              autofocus: true,
              onKey: (e) {
                received.add('inner:${e.char}');
                return KeyEventResult.ignored;
              },
              child: const EmptyBox(),
            ),
          ),
        ),
      );

      manager.dispatchKey(_key('x'));
      expect(received, ['inner:x', 'outer:x']);
    });

    test('handled key does not reach ancestors', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            onKey: (e) {
              received.add('outer:${e.char}');
              return KeyEventResult.handled;
            },
            child: Focus(
              autofocus: true,
              onKey: (e) {
                received.add('inner:${e.char}');
                return KeyEventResult.handled;
              },
              child: const EmptyBox(),
            ),
          ),
        ),
      );

      manager.dispatchKey(_key('x'));
      expect(received, ['inner:x']);
    });
  });

  group('FocusScope', () {
    test('non-modal scope does not block bubble-up', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            onKey: (e) {
              received.add('app');
              return KeyEventResult.handled;
            },
            child: FocusScope(
              child: Focus(
                autofocus: true,
                onKey: (e) {
                  received.add('inner');
                  return KeyEventResult.ignored;
                },
                child: const EmptyBox(),
              ),
            ),
          ),
        ),
      );

      manager.dispatchKey(_key('a'));
      expect(received, ['inner', 'app']);
    });

    test('modal scope stops bubble-up at its boundary', () {
      final manager = FocusManager();
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            onKey: (e) {
              received.add('app');
              return KeyEventResult.handled;
            },
            child: FocusScope(
              modal: true,
              child: Focus(
                autofocus: true,
                onKey: (e) {
                  received.add('inner');
                  return KeyEventResult.ignored;
                },
                child: const EmptyBox(),
              ),
            ),
          ),
        ),
      );

      manager.dispatchKey(_key('a'));
      // 'app' must NOT fire — the modal scope blocked bubble-up.
      expect(received, ['inner']);
    });
  });
}
