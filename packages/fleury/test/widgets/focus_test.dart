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

  group('Focus widget flags on a caller-provided node', () {
    Element mount(FocusManager manager, Widget child) => BuildOwner().mountRoot(
      FocusManagerScope(manager: manager, child: child),
    );

    test('skipTraversal applies to a provided node', () {
      // Silently ignoring the widget flag was a footgun: the code compiled
      // and looked right while Tab still landed on the node.
      final manager = FocusManager();
      final node = FocusNode(debugLabel: 'provided');
      mount(
        manager,
        Focus(focusNode: node, skipTraversal: true, child: const EmptyBox()),
      );
      expect(node.skipTraversal, isTrue);
      expect(manager.isTraversable(node), isFalse);
    });

    test('canRequestFocus applies to a provided node', () {
      final manager = FocusManager();
      final node = FocusNode(debugLabel: 'provided');
      mount(
        manager,
        Focus(focusNode: node, canRequestFocus: false, child: const EmptyBox()),
      );
      expect(node.canRequestFocus, isFalse);
      node.requestFocus();
      expect(manager.focusedNode, isNull, reason: 'request silently refused');
    });

    test('a widget update re-applies changed flags to the provided node', () {
      final manager = FocusManager();
      final node = FocusNode(debugLabel: 'provided');
      final owner = BuildOwner();
      final root = owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(
            focusNode: node,
            skipTraversal: true,
            child: const EmptyBox(),
          ),
        ),
      );
      expect(node.skipTraversal, isTrue);

      owner.updateRoot(
        root,
        FocusManagerScope(
          manager: manager,
          child: Focus(
            focusNode: node,
            skipTraversal: false,
            child: const EmptyBox(),
          ),
        ),
      );
      expect(node.skipTraversal, isFalse);
    });

    test('a null flag leaves the node\'s own setting alone', () {
      // Null = "the widget doesn't manage this": a provided node's
      // constructor flags survive (and a previously applied value sticks).
      final manager = FocusManager();
      final node = FocusNode(debugLabel: 'provided', skipTraversal: true);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: Focus(focusNode: node, child: const EmptyBox()),
        ),
      );
      expect(node.skipTraversal, isTrue, reason: 'constructor flag kept');

      owner.updateRoot(
        root,
        FocusManagerScope(
          manager: manager,
          child: Focus(focusNode: node, child: const EmptyBox()),
        ),
      );
      expect(node.skipTraversal, isTrue);
    });

    test('an internal node keeps the focusable/traversable defaults', () {
      final manager = FocusManager();
      mount(manager, Focus(debugLabel: 'internal', child: const EmptyBox()));
      // The node attached to the manager is the internal one.
      final attached = manager.attachedNodes
          .where((n) => n.debugLabel == 'internal')
          .single;
      expect(attached.canRequestFocus, isTrue);
      expect(attached.skipTraversal, isFalse);
    });
  });

  group('FocusNode reattach', () {
    test('a reused node reattaches to a new element — ANCESTOR bindings stay '
        'live after unmount + remount', () {
      // A widget that holds a long-lived node, unmounts, then remounts reuses
      // the node but builds a FRESH element. dispatchKey walks UP from
      // `node._element`; if `_register` keeps the stale pointer, that walk
      // traverses the defunct tree and never reaches the remounted ANCESTOR
      // bindings (the focused node's own handler still fires — the head of the
      // chain — so the bug only shows for ancestors, as it did in the app).
      final manager = FocusManager();
      final node = FocusNode(debugLabel: 'reused');
      var hits = 0;
      final owner = BuildOwner();

      // The focused child bubbles (returns ignored); an ANCESTOR Focus counts
      // the hit. The hit only lands if dispatchKey's upward walk from the
      // child's element reaches the ancestor.
      Widget host({required bool show}) => FocusManagerScope(
            manager: manager,
            child: show
                ? Focus(
                    onKey: (e) {
                      hits++;
                      return KeyEventResult.handled;
                    },
                    child: Focus(
                      focusNode: node,
                      onKey: (e) => KeyEventResult.ignored,
                      child: const EmptyBox(),
                    ),
                  )
                : const EmptyBox(),
          );

      var root = owner.mountRoot(host(show: true));
      node.requestFocus();
      manager.dispatchKey(_key('a'));
      expect(hits, 1, reason: 'the ancestor Focus is reached when first mounted');

      root = owner.updateRoot(root, host(show: false)); // subtree unmounts
      root = owner.updateRoot(root, host(show: true)); // remounts, reusing node

      node.requestFocus();
      manager.dispatchKey(_key('a'));
      expect(hits, 2,
          reason: 'the remounted ancestor binding still fires — the reattach '
              'refreshed node._element so the upward walk reaches it');
    });

    test('requestFocus on a node whose Focus was unmounted no-ops — it must '
        'not focus a dead node', () {
      // A caller-provided node outlives its Focus widget. After the widget
      // unmounts, requestFocus must no-op (per the FocusNode doc: "No-op
      // when ... this node is not attached") — focusing the dead node routes
      // every subsequent key into a handler whose State is disposed, which
      // throws on first widget access and bypasses the Ctrl+C exit guard.
      final manager = FocusManager();
      final node = FocusNode(debugLabel: 'kept');
      var deadHits = 0;
      var liveHits = 0;
      final owner = BuildOwner();

      Widget host({required bool show}) => FocusManagerScope(
            manager: manager,
            // Non-focusable, so it participates in the ambient (unfocused)
            // dispatch chain — where keys land once nothing holds focus.
            child: Focus(
              canRequestFocus: false,
              onKey: (e) {
                liveHits++;
                return KeyEventResult.handled;
              },
              child: show
                  ? Focus(
                      focusNode: node,
                      onKey: (e) {
                        deadHits++;
                        return KeyEventResult.handled;
                      },
                      child: const EmptyBox(),
                    )
                  : const EmptyBox(),
            ),
          );

      var root = owner.mountRoot(host(show: true));
      node.requestFocus();
      expect(node.hasFocus, isTrue);

      root = owner.updateRoot(root, host(show: false)); // widget unmounts

      expect(node.isAttached, isFalse, reason: 'unregister detaches the node');
      expect(node.context, isNull, reason: 'context is null when unattached');

      node.requestFocus();
      expect(manager.focusedNode, isNull,
          reason: 'a dead node must not become the focused node');
      expect(node.hasFocus, isFalse);

      // Keys route to the live tree, never through the unmounted handler.
      manager.dispatchKey(_key('a'));
      expect(deadHits, 0);
      expect(liveHits, 1,
          reason: 'the live ambient chain still receives keys');
    });
  });
}
