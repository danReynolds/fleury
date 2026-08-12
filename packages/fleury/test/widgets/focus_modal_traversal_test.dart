// Focus-trapped traversal: Tab / Shift+Tab cycle WITHIN the active trap;
// arrow-driven directional moves obey the same boundary.
//
// FocusScope itself does not own Tab or key propagation. The traversal group
// supplies movement; trapFocus constrains the candidates selected by that
// policy. The bug these tests guard against: focusNext() previously walked the
// manager's global attachedNodes list and could move focus outside the trap.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc, {bool shift = false}) =>
    KeyEvent(kc, modifiers: shift ? const {KeyModifier.shift} : const {});

/// Records every focused node the manager broadcasts to, so a test can
/// inspect the full transition path — not just where focus ended up.
class _FocusTrace {
  _FocusTrace(this.manager) {
    manager.addListener(_capture);
  }
  final FocusManager manager;
  final List<FocusNode?> sequence = <FocusNode?>[];
  void _capture() => sequence.add(manager.focusedNode);
  void dispose() => manager.removeListener(_capture);
}

void main() {
  group('trapped FocusScope traversal', () {
    testWidgets('direct focus requests cannot escape the active focus trap', (
      tester,
    ) {
      final outside = FocusNode(debugLabel: 'outside');
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');

      tester.pumpWidget(
        Column(
          children: [
            Focus(focusNode: outside, child: const Text('outside')),
            FocusScope(
              trapFocus: true,
              child: Column(
                children: [
                  Focus(
                    focusNode: inA,
                    autofocus: true,
                    child: const Text('inA'),
                  ),
                  Focus(focusNode: inB, child: const Text('inB')),
                ],
              ),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(inA.hasFocus, isTrue);

      inB.requestFocus();
      expect(inB.hasFocus, isTrue, reason: 'requests inside the modal work');

      expect(
        tester.focusManager.requestFocus(outside),
        isFalse,
        reason: 'the manager rejects a request outside the focus trap',
      );
      outside.requestFocus();
      expect(
        inB.hasFocus,
        isTrue,
        reason: 'FocusNode.requestFocus cannot bypass the focus trap',
      );
      expect(outside.hasFocus, isFalse);
    });

    testWidgets('Tab cycles only between focusables inside a focus trap', (
      tester,
    ) {
      final outside = FocusNode(debugLabel: 'outside');
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');

      tester.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 1,
              child: Focus(focusNode: outside, child: const Text('outside')),
            ),
            SizedBox(
              height: 2,
              child: FocusScope(
                trapFocus: true,
                child: FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 1,
                        child: Focus(
                          focusNode: inA,
                          autofocus: true,
                          child: const Text('inA'),
                        ),
                      ),
                      SizedBox(
                        height: 1,
                        child: Focus(focusNode: inB, child: const Text('inB')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(inA.hasFocus, isTrue);

      final trace = _FocusTrace(tester.focusManager);

      tester.sendKey(_code(KeyCode.tab));
      expect(inB.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(inA.hasFocus, isTrue, reason: 'wraps within the focus trap');
      tester.sendKey(_code(KeyCode.tab));
      expect(inB.hasFocus, isTrue);

      // The outside node was never visited.
      expect(
        trace.sequence.contains(outside),
        isFalse,
        reason: 'outside-modal focus must never appear in the trace',
      );
      trace.dispose();
    });

    testWidgets('Shift+Tab obeys the same focus trap', (tester) {
      final outside = FocusNode(debugLabel: 'outside');
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');

      tester.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 1,
              child: Focus(focusNode: outside, child: const Text('outside')),
            ),
            SizedBox(
              height: 2,
              child: FocusScope(
                trapFocus: true,
                child: FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 1,
                        child: Focus(
                          focusNode: inA,
                          autofocus: true,
                          child: const Text('inA'),
                        ),
                      ),
                      SizedBox(
                        height: 1,
                        child: Focus(focusNode: inB, child: const Text('inB')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(inA.hasFocus, isTrue);

      final trace = _FocusTrace(tester.focusManager);

      tester.sendKey(_code(KeyCode.tab, shift: true));
      expect(inB.hasFocus, isTrue, reason: 'Shift+Tab wraps backward in scope');
      tester.sendKey(_code(KeyCode.tab, shift: true));
      expect(inA.hasFocus, isTrue);

      expect(trace.sequence.contains(outside), isFalse);
      trace.dispose();
    });

    testWidgets('arrow traversal stays inside the active focus trap', (tester) {
      // Layout: outside sits to the LEFT of the modal; inA sits to the
      // LEFT of inB inside the modal. With inA focused, ArrowLeft would
      // naturally land on `outside` (spatially adjacent) — but the
      // focus-trap filter must reject it. We check the full transition trace
      // (T2 guard) rather than just inA.hasFocus, so a "stayed by accident"
      // outcome can't pass for the wrong reason.
      final outside = FocusNode(debugLabel: 'outside');
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');

      tester.pumpWidget(
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 4,
              child: Focus(focusNode: outside, child: const Text('OUT')),
            ),
            SizedBox(
              width: 12,
              child: FocusScope(
                trapFocus: true,
                child: FocusTraversalGroup(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 4,
                        child: Focus(
                          focusNode: inA,
                          autofocus: true,
                          child: const Text('A'),
                        ),
                      ),
                      SizedBox(
                        width: 4,
                        child: Focus(focusNode: inB, child: const Text('B')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 1));
      expect(inA.hasFocus, isTrue);

      final trace = _FocusTrace(tester.focusManager);

      // ArrowLeft from inA: outside lies to the left but is outside the
      // modal — the filter must drop it, leaving no candidate.
      tester.sendKey(_code(KeyCode.arrowLeft));
      expect(
        inA.hasFocus,
        isTrue,
        reason: 'no leftward candidate inside the modal',
      );

      // ArrowRight reaches inB normally.
      tester.sendKey(_code(KeyCode.arrowRight));
      expect(inB.hasFocus, isTrue);

      // From inB, ArrowRight has nothing further — focus stays put.
      tester.sendKey(_code(KeyCode.arrowRight));
      expect(inB.hasFocus, isTrue);

      expect(
        trace.sequence.contains(outside),
        isFalse,
        reason: 'outside-modal focus must never appear in the trace',
      );
      trace.dispose();
    });

    testWidgets('nested focus traps: innermost wins', (tester) {
      final outerOnly = FocusNode(debugLabel: 'outerOnly');
      final innerA = FocusNode(debugLabel: 'innerA');
      final innerB = FocusNode(debugLabel: 'innerB');

      tester.pumpWidget(
        FocusScope(
          trapFocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Focus(focusNode: outerOnly, child: const Text('OUTER')),
              ),
              SizedBox(
                height: 2,
                child: FocusScope(
                  trapFocus: true,
                  child: FocusTraversalGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 1,
                          child: Focus(
                            focusNode: innerA,
                            autofocus: true,
                            child: const Text('iA'),
                          ),
                        ),
                        SizedBox(
                          height: 1,
                          child: Focus(
                            focusNode: innerB,
                            child: const Text('iB'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(innerA.hasFocus, isTrue);

      final trace = _FocusTrace(tester.focusManager);

      tester.sendKey(_code(KeyCode.tab));
      expect(innerB.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(innerA.hasFocus, isTrue);

      expect(
        trace.sequence.contains(outerOnly),
        isFalse,
        reason: 'inner focus trap must not leak to the outer-only node',
      );
      trace.dispose();
    });

    testWidgets('programmatic focusNext respects the trap even with a detached '
        'focused node', (tester) {
      // B1 guard. _focusedNode goes null whenever the focused node detaches
      // (its widget unmounts mid-rebuild). Calling focusManager.focusNext()
      // imperatively in that window — e.g. from an app-level "advance focus"
      // shortcut — used to walk the entire attached set because the modal
      // anchor was derived from the (now-null) focused node. The fix is the
      // marker-tracked active focus-trap set on FocusManager.
      final outside = FocusNode(debugLabel: 'outside');
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');

      tester.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 1,
              child: Focus(focusNode: outside, child: const Text('outside')),
            ),
            SizedBox(
              height: 2,
              child: FocusScope(
                trapFocus: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 1,
                      child: Focus(
                        focusNode: inA,
                        autofocus: true,
                        child: const Text('inA'),
                      ),
                    ),
                    SizedBox(
                      height: 1,
                      child: Focus(focusNode: inB, child: const Text('inB')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(inA.hasFocus, isTrue);

      // Drop focus (mimics the focused node detaching mid-build).
      tester.focusManager.requestFocus(null);
      expect(tester.focusManager.focusedNode, isNull);

      // Programmatically advance focus. The trap must still bound the walk
      // even though no node holds focus.
      tester.focusManager.focusNext();
      expect(
        inA.hasFocus,
        isTrue,
        reason:
            'focusNext with no current focus picks the first trapped '
            'node, not the outside one',
      );
      expect(outside.hasFocus, isFalse);
    });

    testWidgets(
      'FocusTraversalGroup outside the trap still cannot leak focus out',
      (tester) {
        // T1 guard. Earlier drafts placed FocusTraversalGroup outside the
        // trap. To prove the _traversalOrder focus filter actually does the
        // work, we drive focusNext() programmatically here. Reverting the
        // filter in focus.dart's _traversalOrder makes this test fail with
        // the outside nodes appearing in the trace.
        final outsideBefore = FocusNode(debugLabel: 'outsideBefore');
        final inA = FocusNode(debugLabel: 'inA');
        final inB = FocusNode(debugLabel: 'inB');
        final outsideAfter = FocusNode(debugLabel: 'outsideAfter');

        tester.pumpWidget(
          FocusTraversalGroup(
            child: Stack(
              children: [
                // outsideBefore (top of the screen)
                Positioned(
                  top: 0,
                  left: 0,
                  width: 20,
                  height: 1,
                  child: Focus(
                    focusNode: outsideBefore,
                    child: const Text('before'),
                  ),
                ),
                // modal in the middle
                Positioned(
                  top: 1,
                  left: 0,
                  width: 20,
                  height: 2,
                  child: FocusScope(
                    trapFocus: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 1,
                          child: Focus(
                            focusNode: inA,
                            autofocus: true,
                            child: const Text('inA'),
                          ),
                        ),
                        SizedBox(
                          height: 1,
                          child: Focus(
                            focusNode: inB,
                            child: const Text('inB'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // outsideAfter (bottom)
                Positioned(
                  top: 3,
                  left: 0,
                  width: 20,
                  height: 1,
                  child: Focus(
                    focusNode: outsideAfter,
                    child: const Text('after'),
                  ),
                ),
              ],
            ),
          ),
        );
        tester.render(size: const CellSize(20, 4));
        expect(inA.hasFocus, isTrue);

        final trace = _FocusTrace(tester.focusManager);

        // Drive focusNext() directly — bypassing the dispatcher proves the
        // _traversalOrder filter, not the chain-stops-at-modal behaviour.
        for (var i = 0; i < 6; i++) {
          tester.focusManager.focusNext();
        }
        // Same in reverse.
        for (var i = 0; i < 6; i++) {
          tester.focusManager.focusPrevious();
        }

        expect(
          trace.sequence.contains(outsideBefore),
          isFalse,
          reason:
              'outside-modal focus must never appear in the trace (forward)',
        );
        expect(
          trace.sequence.contains(outsideAfter),
          isFalse,
          reason:
              'outside-modal focus must never appear in the trace (reverse)',
        );
        // Sanity: the in-modal nodes were exercised.
        expect(trace.sequence.contains(inB), isTrue);
        trace.dispose();
      },
    );
  });

  group('element-snapshotted focus trap', () {
    testWidgets(
      'rebuilding a FocusScope with same trapFocus keeps its anchor stable',
      (tester) {
        // A FocusScope rebuilds on every parent setState — `FocusScope.build`
        // allocates a fresh `FocusScopeRef` each time. If the marker tracked
        // identity off the widget-level ref, every rebuild would look like
        // "a different modal" and break the active-modal invariant. The
        // marker element captures trapFocus once and survives rebuilds.
        final inA = FocusNode(debugLabel: 'inA');
        final inB = FocusNode(debugLabel: 'inB');
        final outside = FocusNode(debugLabel: 'outside');

        tester.pumpWidget(
          _RebuildHost(
            builder: (rebuildCount) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 1,
                    child: Focus(
                      focusNode: outside,
                      child: Text('out$rebuildCount'),
                    ),
                  ),
                  SizedBox(
                    height: 2,
                    child: FocusScope(
                      key: const ValueKey('marker-host'),
                      trapFocus: true,
                      child: FocusTraversalGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 1,
                              child: Focus(
                                focusNode: inA,
                                autofocus: true,
                                child: const Text('inA'),
                              ),
                            ),
                            SizedBox(
                              height: 1,
                              child: Focus(
                                focusNode: inB,
                                child: const Text('inB'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
        tester.render(size: const CellSize(20, 3));
        expect(inA.hasFocus, isTrue);

        // Rebuild the host: the FocusScope's `_FocusScopeMarker` widget is a
        // brand-new instance (new FocusScopeRef) but the marker element
        // survives via update(). The trap anchor stays the same logical scope.
        _RebuildHost.of(tester)!.bump();
        tester.pump();
        tester.render(size: const CellSize(20, 3));

        // After the rebuild, modal still bounds Tab traversal.
        final trace = _FocusTrace(tester.focusManager);
        tester.sendKey(_code(KeyCode.tab));
        expect(inB.hasFocus, isTrue);
        tester.sendKey(_code(KeyCode.tab));
        expect(inA.hasFocus, isTrue);
        expect(
          trace.sequence.contains(outside),
          isFalse,
          reason: 'rebuild must not break the focus trap',
        );
        trace.dispose();
      },
    );

    testWidgets('flipping trapFocus off releases the trap', (tester) {
      // Driver: a host that toggles `modal` on its FocusScope. After
      // the flip, Tab must be able to leave the (no-longer-modal) scope.
      final inside = FocusNode(debugLabel: 'inside');
      final outside = FocusNode(debugLabel: 'outside');

      tester.pumpWidget(
        _TrapToggleHost(startTrapped: true, inside: inside, outside: outside),
      );
      tester.render(size: const CellSize(20, 2));
      expect(inside.hasFocus, isTrue);

      // Trap active: Tab confined.
      tester.sendKey(_code(KeyCode.tab));
      expect(inside.hasFocus, isTrue, reason: 'Tab confined to modal');

      // Flip the trap off via setState on the same marker element.
      _TrapToggleHost.of(tester)!.toggleTrap();
      tester.pump();
      tester.render(size: const CellSize(20, 2));

      tester.sendKey(_code(KeyCode.tab));
      expect(
        outside.hasFocus,
        isTrue,
        reason: 'trap flipped off; Tab can now leave the scope',
      );
    });

    testWidgets('flipping trapFocus on starts confining Tab', (tester) {
      // The inverse: a scope starts open, then enables trapFocus in update().
      // The manager must learn about the trap without remounting the subtree.
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');
      final outside = FocusNode(debugLabel: 'outside');

      tester.pumpWidget(
        _TrapGrowHost(
          startTrapped: false,
          outside: outside,
          inA: inA,
          inB: inB,
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(inA.hasFocus, isTrue);

      // Open scope: Tab leaves the scope freely.
      tester.sendKey(_code(KeyCode.tab));
      expect(inB.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(
        outside.hasFocus,
        isTrue,
        reason: 'open scope: Tab escapes the scope',
      );

      // Move focus back into the scope and then enable its trap.
      inA.requestFocus();
      _TrapGrowHost.of(tester)!.toggleTrap();
      tester.pump();
      tester.render(size: const CellSize(20, 3));

      final trace = _FocusTrace(tester.focusManager);
      tester.sendKey(_code(KeyCode.tab));
      expect(inB.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(inA.hasFocus, isTrue, reason: 'wraps within the trapped scope');
      expect(
        trace.sequence.contains(outside),
        isFalse,
        reason: 'trap enabled; outside must no longer appear',
      );
      trace.dispose();
    });

    testWidgets(
      'the most recently activated sibling trap wins regardless of depth',
      (tester) {
        // A popup inserted later may sit in a shallower overlay branch than
        // the popup behind it. Focus-trap order must therefore follow
        // activation, not element depth. Children mount in slot order here;
        // A is deliberately deeper, but B activates later and must win.
        final aNode = FocusNode(debugLabel: 'aNode');
        final bNode = FocusNode(debugLabel: 'bNode');

        tester.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: FocusScope(
                    trapFocus: true,
                    child: Focus(focusNode: aNode, child: const Text('A')),
                  ),
                ),
              ),
              SizedBox(
                height: 1,
                child: FocusScope(
                  trapFocus: true,
                  child: Focus(focusNode: bNode, child: const Text('B')),
                ),
              ),
            ],
          ),
        );
        tester.render(size: const CellSize(20, 2));

        // No node focused, two sibling traps open. focusNext() must confine to
        // the later-activated trap (B), even though A's marker is deeper.
        tester.focusManager.requestFocus(null);
        tester.focusManager.focusNext();
        expect(
          aNode.hasFocus,
          isFalse,
          reason: 'earlier-mounted trap (A) should NOT be the anchor',
        );
        expect(
          bNode.hasFocus,
          isTrue,
          reason: 'later-activated trap (B) owns the active frontier',
        );
      },
    );
  });
}

/// Host whose `build()` calls a builder with the current rebuild count.
/// Tests trigger a rebuild via `bump()`.
class _RebuildHost extends StatefulWidget {
  const _RebuildHost({required this.builder});
  final Widget Function(int rebuildCount) builder;

  static _RebuildHostState? of(FleuryTester tester) {
    final el =
        tester.find(byType(_RebuildHost)).singleOrNull as StatefulElement?;
    return el?.state as _RebuildHostState?;
  }

  @override
  State<_RebuildHost> createState() => _RebuildHostState();
}

class _RebuildHostState extends State<_RebuildHost> {
  int _count = 0;
  void bump() => setState(() => _count += 1);

  @override
  Widget build(BuildContext context) => widget.builder(_count);
}

/// Host with a single FocusScope whose trap is toggleable.
class _TrapToggleHost extends StatefulWidget {
  const _TrapToggleHost({
    required this.startTrapped,
    required this.inside,
    required this.outside,
  });
  final bool startTrapped;
  final FocusNode inside;
  final FocusNode outside;

  static _TrapToggleHostState? of(FleuryTester tester) {
    final el =
        tester.find(byType(_TrapToggleHost)).singleOrNull as StatefulElement?;
    return el?.state as _TrapToggleHostState?;
  }

  @override
  State<_TrapToggleHost> createState() => _TrapToggleHostState();
}

class _TrapToggleHostState extends State<_TrapToggleHost> {
  late bool _trapFocus = widget.startTrapped;
  void toggleTrap() => setState(() => _trapFocus = !_trapFocus);

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 1,
            child: FocusScope(
              key: const ValueKey('toggle-scope'),
              trapFocus: _trapFocus,
              child: Focus(
                focusNode: widget.inside,
                autofocus: true,
                child: const Text('inside'),
              ),
            ),
          ),
          SizedBox(
            height: 1,
            child: Focus(
              focusNode: widget.outside,
              child: const Text('outside'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Host with a FocusScope that enables focus trapping after mount.
class _TrapGrowHost extends StatefulWidget {
  const _TrapGrowHost({
    required this.startTrapped,
    required this.outside,
    required this.inA,
    required this.inB,
  });
  final bool startTrapped;
  final FocusNode outside;
  final FocusNode inA;
  final FocusNode inB;

  static _TrapGrowHostState? of(FleuryTester tester) {
    final el =
        tester.find(byType(_TrapGrowHost)).singleOrNull as StatefulElement?;
    return el?.state as _TrapGrowHostState?;
  }

  @override
  State<_TrapGrowHost> createState() => _TrapGrowHostState();
}

class _TrapGrowHostState extends State<_TrapGrowHost> {
  late bool _trapFocus = widget.startTrapped;
  void toggleTrap() => setState(() => _trapFocus = !_trapFocus);

  @override
  Widget build(BuildContext context) {
    // Outer FocusTraversalGroup handles Tab from the outside node; the
    // inner one is deliberately redundant for key reachability now that
    // focus trapping and key propagation are separate. It still provides a
    // narrower spatial search region while focus is inside the scope.
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 1,
            child: Focus(
              focusNode: widget.outside,
              child: const Text('outside'),
            ),
          ),
          SizedBox(
            height: 2,
            child: FocusScope(
              key: const ValueKey('grow-scope'),
              trapFocus: _trapFocus,
              child: FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 1,
                      child: Focus(
                        focusNode: widget.inA,
                        autofocus: true,
                        child: const Text('inA'),
                      ),
                    ),
                    SizedBox(
                      height: 1,
                      child: Focus(
                        focusNode: widget.inB,
                        child: const Text('inB'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension<E> on List<E> {
  E? get singleOrNull => length == 1 ? single : null;
}
