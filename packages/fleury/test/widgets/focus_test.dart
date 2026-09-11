import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

KeyEvent _key(String char, {bool ctrl = false, bool alt = false}) {
  return KeyEvent(
    KeyCode.char(char),
    modifiers: {if (ctrl) KeyModifier.ctrl, if (alt) KeyModifier.alt},
  );
}

/// The key path an app actually runs on.
///
/// `InputDispatcher.dispatch` is what `runApp` wires the terminal to, and it
/// owns everything routing means: bindings, the release fence, modal
/// boundaries, pending sequences, and only then the `KeyDetector` floor. A
/// manager-only shortcut that walked detectors alone certified semantics
/// production never delivered, so these tests dispatch through the real one.
/// No I/O is involved — the dispatcher only needs a [FocusManager].
InputDispatcher _dispatcherFor(FocusManager manager) {
  final dispatcher = InputDispatcher(focusManager: manager);
  addTearDown(dispatcher.dispose);
  return dispatcher;
}

void main() {
  _enclosingNodeLookup();
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
      final dispatcher = _dispatcherFor(manager);
      final owner = BuildOwner();
      final node = FocusNode(debugLabel: 'owned');
      var hits = 0;
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyDetector(
            onKey: (event) {
              hits++;
              event.consume();
            },
            child: Focus(
              focusNode: node,
              autofocus: true,
              child: const EmptyBox(),
            ),
          ),
        ),
      );
      expect(dispatcher.dispatch(_key('x')), KeyEventResult.handled);
      expect(hits, 1, reason: 'the live chain routes keys before disposal');
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
      // Routing is the dispatcher's, not the manager's. Disposal empties the
      // chain, so a key that arrives during teardown reaches nobody and is
      // reported unhandled — it must NOT throw back into the input loop, and
      // it must not reach the detector that was live a moment ago. (The
      // dispatcher's own post-dispose guard is pinned in
      // test/runtime/input_dispatcher_test.dart.)
      expect(dispatcher.dispatch(_key('x')), KeyEventResult.ignored);
      expect(hits, 1, reason: 'no handler runs against a disposed manager');
    });

    test(
      'manager disposal cancels a queued scope-change notification',
      () async {
        final manager = FocusManager();
        manager.notifyBindingsChanged();

        manager.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(manager.hasListeners, isFalse);
      },
    );
  });

  group('KeyDetector routing through the dispatcher', () {
    test('delivers key to the focused node\'s detector first', () {
      final manager = FocusManager();
      final dispatcher = _dispatcherFor(manager);
      final owner = BuildOwner();
      final received = <String>[];

      final node = FocusNode();
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyDetector(
            onKey: (event) {
              received.add('inner:${event.code.character}');
              event.consume();
            },
            child: Focus(
              focusNode: node,
              autofocus: true,
              child: const EmptyBox(),
            ),
          ),
        ),
      );

      dispatcher.dispatch(_key('a'));
      expect(received, ['inner:a']);
    });

    test('bubbles up through ancestor Focus widgets when child ignores', () {
      final manager = FocusManager();
      final dispatcher = _dispatcherFor(manager);
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyDetector(
            onKey: (event) {
              received.add('outer:${event.code.character}');
              event.consume();
            },
            child: Focus(
              child: KeyDetector(
                onKey: (event) {
                  received.add('inner:${event.code.character}');
                },
                child: Focus(autofocus: true, child: const EmptyBox()),
              ),
            ),
          ),
        ),
      );

      dispatcher.dispatch(_key('x'));
      expect(received, ['inner:x', 'outer:x']);
    });

    test('handled key does not reach ancestors', () {
      final manager = FocusManager();
      final dispatcher = _dispatcherFor(manager);
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyDetector(
            onKey: (event) {
              received.add('outer:${event.code.character}');
              event.consume();
            },
            child: Focus(
              child: KeyDetector(
                onKey: (event) {
                  received.add('inner:${event.code.character}');
                  event.consume();
                },
                child: Focus(autofocus: true, child: const EmptyBox()),
              ),
            ),
          ),
        ),
      );

      dispatcher.dispatch(_key('x'));
      expect(received, ['inner:x']);
    });
  });

  group('FocusScope', () {
    test('ordinary scope does not block bubble-up', () {
      final manager = FocusManager();
      final dispatcher = _dispatcherFor(manager);
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyDetector(
            onKey: (event) {
              received.add('app');
              event.consume();
            },
            child: Focus(
              child: FocusScope(
                child: KeyDetector(
                  onKey: (event) {
                    received.add('inner');
                  },
                  child: Focus(autofocus: true, child: const EmptyBox()),
                ),
              ),
            ),
          ),
        ),
      );

      dispatcher.dispatch(_key('a'));
      expect(received, ['inner', 'app']);
    });

    test('trapFocus does not change key-event propagation', () {
      final manager = FocusManager();
      final dispatcher = _dispatcherFor(manager);
      final owner = BuildOwner();
      final received = <String>[];

      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyDetector(
            onKey: (event) {
              received.add('app');
              event.consume();
            },
            child: Focus(
              child: FocusScope(
                trapFocus: true,
                child: KeyDetector(
                  onKey: (event) {
                    received.add('inner');
                  },
                  child: Focus(autofocus: true, child: const EmptyBox()),
                ),
              ),
            ),
          ),
        ),
      );

      dispatcher.dispatch(_key('a'));
      expect(
        received,
        ['inner', 'app'],
        reason: 'FocusScope controls focus location, not event propagation',
      );
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
      // the node but builds a FRESH element. Dispatch walks UP from
      // `node._element`; if `_register` keeps the stale pointer, that walk
      // traverses the defunct tree and never reaches the remounted ANCESTOR
      // bindings (the focused node's own handler still fires — the head of the
      // chain — so the bug only shows for ancestors, as it did in the app).
      final manager = FocusManager();
      final dispatcher = _dispatcherFor(manager);
      final node = FocusNode(debugLabel: 'reused');
      var hits = 0;
      final owner = BuildOwner();

      // The focused child bubbles (returns ignored); an ANCESTOR Focus counts
      // the hit. The hit only lands if the dispatcher's upward walk from the
      // child's element reaches the ancestor.
      Widget host({required bool show}) => FocusManagerScope(
        manager: manager,
        child: show
            ? KeyDetector(
                onKey: (event) {
                  hits++;
                  event.consume();
                },
                child: Focus(
                  child: KeyDetector(
                    onKey: (event) {
                      if (((e) => KeyEventResult.ignored)(event) ==
                          KeyEventResult.handled) {
                        event.consume();
                      }
                    },
                    child: Focus(focusNode: node, child: const EmptyBox()),
                  ),
                ),
              )
            : const EmptyBox(),
      );

      var root = owner.mountRoot(host(show: true));
      node.requestFocus();
      dispatcher.dispatch(_key('a'));
      expect(
        hits,
        1,
        reason: 'the ancestor Focus is reached when first mounted',
      );

      root = owner.updateRoot(root, host(show: false)); // subtree unmounts
      root = owner.updateRoot(root, host(show: true)); // remounts, reusing node

      node.requestFocus();
      dispatcher.dispatch(_key('a'));
      expect(
        hits,
        2,
        reason:
            'the remounted ancestor binding still fires — the reattach '
            'refreshed node._element so the upward walk reaches it',
      );
    });

    test('requestFocus on a node whose Focus was unmounted no-ops — it must '
        'not focus a dead node', () {
      // A caller-provided node outlives its Focus widget. After the widget
      // unmounts, requestFocus must no-op (per the FocusNode doc: "No-op
      // when ... this node is not attached") — focusing the dead node routes
      // every subsequent key into a handler whose State is disposed, which
      // throws on first widget access and bypasses the Ctrl+C exit guard.
      final manager = FocusManager();
      final dispatcher = _dispatcherFor(manager);
      final node = FocusNode(debugLabel: 'kept');
      var deadHits = 0;
      var liveHits = 0;
      final owner = BuildOwner();

      final liveNode = FocusNode(debugLabel: 'live');

      Widget host({required bool show}) => FocusManagerScope(
        manager: manager,
        child: KeyDetector(
          onKey: (event) {
            liveHits++;
            event.consume();
          },
          child: Focus(
            canRequestFocus: false,
            child: Column(
              children: [
                Focus(focusNode: liveNode, child: const EmptyBox()),
                if (show)
                  KeyDetector(
                    onKey: (event) {
                      deadHits++;
                      event.consume();
                    },
                    child: Focus(focusNode: node, child: const EmptyBox()),
                  ),
              ],
            ),
          ),
        ),
      );

      var root = owner.mountRoot(host(show: true));
      node.requestFocus();
      expect(node.hasFocus, isTrue);

      root = owner.updateRoot(root, host(show: false)); // widget unmounts

      expect(node.isAttached, isFalse, reason: 'unregister detaches the node');
      expect(node.context, isNull, reason: 'context is null when unattached');

      node.requestFocus();
      expect(
        manager.focusedNode,
        isNull,
        reason: 'a dead node must not become the focused node',
      );
      expect(node.hasFocus, isFalse);

      // Keys route to the live tree, never through the unmounted handler.
      // Detectors are focus-scoped (RFC 0020 §17), so the live half is
      // reached by focusing a surviving node rather than ambiently.
      liveNode.requestFocus();
      dispatcher.dispatch(_key('a'));
      expect(deadHits, 0);
      expect(liveHits, 1, reason: 'the live chain still receives keys');
    });
  });

  group('FocusDetector', () {
    testWidgets('reports only when focus crosses its subtree boundary', (
      tester,
    ) {
      final title = FocusNode(debugLabel: 'title');
      final body = FocusNode(debugLabel: 'body');
      final preview = FocusNode(debugLabel: 'preview');
      final changes = <bool>[];

      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            children: [
              FocusDetector(
                onFocusChange: changes.add,
                child: Column(
                  children: [
                    Focus(
                      focusNode: title,
                      autofocus: true,
                      child: const Text('Title'),
                    ),
                    Focus(focusNode: body, child: const Text('Body')),
                  ],
                ),
              ),
              Focus(focusNode: preview, child: const Text('Preview')),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 4));

      expect(changes, [true], reason: 'autofocus entered the observed region');

      body.requestFocus();
      expect(changes, [
        true,
      ], reason: 'moving between children is not a leave-and-enter cycle');

      preview.requestFocus();
      expect(changes, [true, false]);

      title.requestFocus();
      expect(changes, [true, false, true]);
    });
  });
}

void _enclosingNodeLookup() {
  group('Focus.of resolves the enclosing node, FocusManager.of the manager', () {
    test('a descendant reads the node of the Focus it is inside', () {
      final outer = FocusNode(debugLabel: 'outer');
      final inner = FocusNode(debugLabel: 'inner');
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      FocusNode? seenByInner;
      FocusNode? seenByOuter;
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(
        Focus(
          focusNode: outer,
          child: _Probe(
            builder: (context) {
              seenByOuter = Focus.of(context);
              return Focus(
                focusNode: inner,
                child: _Probe(
                  builder: (context) {
                    seenByInner = Focus.of(context);
                    return const Text('leaf');
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(seenByOuter, same(outer));
      expect(seenByInner, same(inner));
    });

    test('hasFocus read through Focus.of rebuilds when focus moves', () {
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(
        Row(
          children: [
            Focus(
              focusNode: first,
              autofocus: true,
              child: _Probe(
                builder: (context) =>
                    Text(Focus.of(context).hasFocus ? 'first:on' : 'first:off'),
              ),
            ),
            Focus(focusNode: second, child: const Text('second')),
          ],
        ),
      );
      expect(tester.renderToString(), contains('first:on'));
      second.requestFocus();
      tester.pump();
      // No FocusDetector, no setState: reading the node subscribes the caller.
      expect(tester.renderToString(), contains('first:off'));
    });

    test('KeyBindings does not shadow Focus.of', () {
      final pane = FocusNode(debugLabel: 'pane');
      addTearDown(pane.dispose);
      late FocusNode seen;
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(
        Focus(
          focusNode: pane,
          autofocus: true,
          child: KeyBindings(
            bindings: [KeyBinding(KeyCode.escape, onTrigger: (_) {})],
            child: _Probe(
              builder: (context) {
                seen = Focus.of(context);
                return Text(seen.hasFocus ? 'on' : 'off');
              },
            ),
          ),
        ),
      );
      expect(seen, same(pane));
      expect(tester.renderToString(), contains('on'));
    });

    test('KeyDetector does not shadow Focus.of', () {
      final pane = FocusNode(debugLabel: 'pane');
      addTearDown(pane.dispose);
      late FocusNode seen;
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(
        Focus(
          focusNode: pane,
          autofocus: true,
          child: KeyDetector(
            onKey: (_) {},
            child: _Probe(
              builder: (context) {
                seen = Focus.of(context);
                return Text(seen.hasFocus ? 'on' : 'off');
              },
            ),
          ),
        ),
      );
      expect(seen, same(pane));
      expect(tester.renderToString(), contains('on'));
    });

    test('the manager is reached through FocusManager, not Focus', () {
      final node = FocusNode(debugLabel: 'node');
      addTearDown(node.dispose);
      FocusManager? manager;
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(
        Focus(
          focusNode: node,
          autofocus: true,
          child: _Probe(
            builder: (context) {
              manager = FocusManager.of(context);
              return const Text('leaf');
            },
          ),
        ),
      );
      expect(manager, same(tester.focusManager));
      expect(manager!.focusedNode, same(node));
    });

    test('Focus.of throws when the context is not inside a Focus', () {
      late BuildContext probeContext;
      final owner = BuildOwner();
      owner.mountRoot(
        _Probe(
          builder: (context) {
            probeContext = context;
            return const EmptyBox();
          },
        ),
      );
      expect(Focus.maybeOf(probeContext), isNull);
      expect(FocusManager.maybeOf(probeContext), isNull);
      expect(
        () => Focus.of(probeContext),
        _stateError(
          'No enclosing Focus found in this context. Wrap the subtree in a '
          'Focus, or use FocusManager.of(context) for the focus manager.',
        ),
      );
    });

    test('a sibling overlay entry has no enclosing Focus; the manager is still '
        'there', () {
      // runApp / FleuryTester wrap only the user overlay entry in a Focus
      // (the selection host). Additional entries are siblings of that wrap,
      // not descendants, so lookup there is the same as outside any Focus.
      late BuildContext mainContext;
      late BuildContext floatContext;
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(
        _Probe(
          builder: (context) {
            mainContext = context;
            return const Text('main');
          },
        ),
      );
      expect(Focus.maybeOf(mainContext), isNotNull);
      expect(FocusManager.of(mainContext), same(tester.focusManager));

      final float = OverlayEntry(
        builder: (context) {
          floatContext = context;
          return const Text('float');
        },
      );
      tester.overlay.insert(float);
      addTearDown(float.dispose);
      tester.pump();

      expect(Focus.maybeOf(floatContext), isNull);
      expect(
        () => Focus.of(floatContext),
        _stateError(
          'No enclosing Focus found in this context. Wrap the subtree in a '
          'Focus, or use FocusManager.of(context) for the focus manager.',
        ),
      );
      expect(FocusManager.of(floatContext), same(tester.focusManager));
    });

    test('hasFocus is identity; FocusDetector is descendant-inclusive', () {
      final pane = FocusNode(debugLabel: 'pane');
      final child = FocusNode(debugLabel: 'child');
      addTearDown(pane.dispose);
      addTearDown(child.dispose);
      final detector = <bool>[];
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(
        FocusDetector(
          onFocusChange: detector.add,
          child: Focus(
            focusNode: pane,
            child: Column(
              children: [
                _Probe(
                  builder: (context) =>
                      Text(Focus.of(context).hasFocus ? 'pane-on' : 'pane-off'),
                ),
                Focus(
                  focusNode: child,
                  autofocus: true,
                  child: const Text('child'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(child.hasFocus, isTrue);
      expect(pane.hasFocus, isFalse);
      expect(
        tester.renderToString(),
        contains('pane-off'),
        reason: 'the pane is not the focused node while a child holds it',
      );
      expect(detector, [
        true,
      ], reason: 'the detector stays true while a descendant holds focus');

      pane.requestFocus();
      tester.pump();
      expect(pane.hasFocus, isTrue);
      expect(tester.renderToString(), contains('pane-on'));
      expect(detector, [
        true,
      ], reason: 'moving to the pane itself is not a leave');

      child.requestFocus();
      tester.pump();
      expect(tester.renderToString(), contains('pane-off'));
      expect(detector, [true]);
    });

    test(
      'ListView itemBuilder fills only while the list holds the keyboard',
      () {
        const fill = AnsiColor(4);
        final outside = FocusNode(debugLabel: 'outside');
        addTearDown(outside.dispose);
        final tester = FleuryTester();
        addTearDown(tester.dispose);
        tester.pumpWidget(
          Theme(
            data: const ThemeData(
              textStyle: CellStyle(foreground: AnsiColor(2)),
              selectionStyle: CellStyle(background: fill),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  child: ListView.builder(
                    autofocus: true,
                    itemCount: 2,
                    itemBuilder: (context, index, highlighted) {
                      final theme = Theme.of(context);
                      final focused = highlighted && Focus.of(context).hasFocus;
                      return DefaultTextStyle(
                        style: focused
                            ? theme.textStyle.merge(theme.selectionStyle)
                            : theme.textStyle,
                        child: Row(
                          children: [
                            Text(highlighted ? '> ' : '  '),
                            Text('k$index'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Focus(focusNode: outside, child: const Text('out')),
              ],
            ),
          ),
        );

        const size = CellSize(20, 3);
        var buffer = tester.render(size: size);
        expect(buffer.atColRow(0, 0).style.background, fill);
        expect(
          tester.renderToString(size: size, emptyMark: ' '),
          contains('> k0'),
        );

        outside.requestFocus();
        tester.pump();
        buffer = tester.render(size: size);
        expect(
          buffer.atColRow(0, 0).style.background,
          isNull,
          reason: 'replacing DefaultTextStyle drops ListView\'s automatic fill',
        );
        expect(
          tester.renderToString(size: size, emptyMark: ' '),
          contains('> k0'),
          reason: 'the current-row marker stays when the keyboard leaves',
        );
      },
    );
  });
}

/// Minimal context probe: Fleury has no `Builder`, and these tests need a
/// build context beneath a [Focus].
final class _Probe extends StatelessWidget {
  const _Probe({required this.builder});
  final Widget Function(BuildContext) builder;
  @override
  Widget build(BuildContext context) => builder(context);
}
