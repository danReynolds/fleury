// Modal-scoped focus traversal: Tab / Shift+Tab cycle WITHIN the
// active modal scope only; arrow-driven directional moves obey the
// same boundary. suppressGlobals is a separate axis and does NOT
// confine traversal.
//
// Test layout note: Tab is dispatched along the focus chain (deepest
// first, stopping at the modal boundary). For a FocusTraversalGroup
// binding to see Tab inside a modal, the group must sit between the
// focused node and the modal marker. Real-world apps follow this
// shape — a modal dialog wraps its content in its own
// FocusTraversalGroup. The bug these tests guard against: even
// correctly nested, focusNext() previously walked the manager's
// global attachedNodes list and could move focus to a node OUTSIDE
// the modal.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc, {bool shift = false}) => KeyEvent(
  keyCode: kc,
  modifiers: shift ? const {KeyModifier.shift} : const {},
);

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
  group('modal-scope Tab traversal', () {
    testWidgets('Tab cycles only between focusables inside a modal scope', (
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
                modal: true,
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
      expect(inA.hasFocus, isTrue, reason: 'wraps within the modal');
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

    testWidgets('Shift+Tab obeys the same modal boundary', (tester) {
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
                modal: true,
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

    testWidgets('arrow traversal stays inside the active modal', (tester) {
      // Layout: outside sits to the LEFT of the modal; inA sits to the
      // LEFT of inB inside the modal. With inA focused, ArrowLeft would
      // naturally land on `outside` (spatially adjacent) — but the
      // modal filter must reject it. We check the full transition trace
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
                modal: true,
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

    testWidgets('nested modals: innermost wins', (tester) {
      final outerOnly = FocusNode(debugLabel: 'outerOnly');
      final innerA = FocusNode(debugLabel: 'innerA');
      final innerB = FocusNode(debugLabel: 'innerB');

      tester.pumpWidget(
        FocusScope(
          modal: true,
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
                  modal: true,
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
        reason: 'inner modal must not leak to the outer-only node',
      );
      trace.dispose();
    });

    testWidgets(
      'programmatic focusNext respects the modal even with a detached '
      'focused node',
      (tester) {
        // B1 guard. _focusedNode goes null whenever the focused node detaches
        // (its widget unmounts mid-rebuild). Calling focusManager.focusNext()
        // imperatively in that window — e.g. from an app-level "advance focus"
        // shortcut — used to walk the entire attached set because the modal
        // anchor was derived from the (now-null) focused node. The fix is the
        // marker-tracked _activeModalScopes set on FocusManager.
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
                  modal: true,
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

        // Programmatically advance focus. The modal must still bound the walk
        // even though no node holds focus.
        tester.focusManager.focusNext();
        expect(
          inA.hasFocus,
          isTrue,
          reason:
              'focusNext with no current focus picks the first IN-modal '
              'node, not the outside one',
        );
        expect(outside.hasFocus, isFalse);
      },
    );

    testWidgets(
      'FocusTraversalGroup OUTSIDE the modal still cannot leak Tab out',
      (tester) {
        // T1 guard. Earlier drafts placed FocusTraversalGroup outside the
        // modal — but activeChain() stops at the modal boundary, so Tab never
        // reaches the group's binding and the test passes for the wrong
        // reason. To prove the _traversalOrder modal filter actually does the
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
                    modal: true,
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

    testWidgets('suppressGlobals without modal does NOT trap Tab', (tester) {
      // Regression guard: suppressGlobals is a dispatch-time gate for
      // global key bindings, not a traversal boundary. A scope with
      // suppressGlobals:true, modal:false must let Tab leave it.
      final inside = FocusNode(debugLabel: 'inside');
      final outside = FocusNode(debugLabel: 'outside');

      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: FocusScope(
                  suppressGlobals: true,
                  child: Focus(
                    focusNode: inside,
                    autofocus: true,
                    child: const Text('inside'),
                  ),
                ),
              ),
              SizedBox(
                height: 1,
                child: Focus(focusNode: outside, child: const Text('outside')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));
      expect(inside.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.tab));
      expect(
        outside.hasFocus,
        isTrue,
        reason: 'suppressGlobals does not confine traversal',
      );
    });
  });

  group('element-snapshotted modal scope', () {
    testWidgets(
      'rebuilding a FocusScope with same modal flag keeps modal anchor stable',
      (tester) {
        // A FocusScope rebuilds on every parent setState — `FocusScope.build`
        // allocates a fresh `FocusScopeRef` each time. If the marker tracked
        // identity off the widget-level ref, every rebuild would look like
        // "a different modal" and break the active-modal invariant. The
        // marker element captures the modal flag once and survives rebuilds.
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
                      modal: true,
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
        // survives via update(). The modal anchor stays the same logical scope.
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
          reason: 'rebuild must not break the modal boundary',
        );
        trace.dispose();
      },
    );

    testWidgets('flipping modal:false at rebuild releases the modal anchor', (
      tester,
    ) {
      // Driver: a host that toggles `modal` on its FocusScope. After
      // the flip, Tab must be able to leave the (no-longer-modal) scope.
      final inside = FocusNode(debugLabel: 'inside');
      final outside = FocusNode(debugLabel: 'outside');

      tester.pumpWidget(
        _ModalToggleHost(startModal: true, inside: inside, outside: outside),
      );
      tester.render(size: const CellSize(20, 2));
      expect(inside.hasFocus, isTrue);

      // Modal active: Tab confined.
      tester.sendKey(_code(KeyCode.tab));
      expect(inside.hasFocus, isTrue, reason: 'Tab confined to modal');

      // Flip modal off via setState — same marker element, captured
      // _capturedModal toggles in update().
      _ModalToggleHost.of(tester)!.toggleModal();
      tester.pump();
      tester.render(size: const CellSize(20, 2));

      tester.sendKey(_code(KeyCode.tab));
      expect(
        outside.hasFocus,
        isTrue,
        reason: 'modal flipped off; Tab can now leave the scope',
      );
    });

    testWidgets('flipping modal:true on a rebuild starts confining Tab', (
      tester,
    ) {
      // The inverse: a scope starts non-modal, then gets a new
      // _capturedModal=true via update(). The manager must learn about
      // the modal without remounting the subtree.
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');
      final outside = FocusNode(debugLabel: 'outside');

      tester.pumpWidget(
        _ModalGrowHost(startModal: false, outside: outside, inA: inA, inB: inB),
      );
      tester.render(size: const CellSize(20, 3));
      expect(inA.hasFocus, isTrue);

      // Non-modal: Tab leaves the scope freely.
      tester.sendKey(_code(KeyCode.tab));
      expect(inB.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(
        outside.hasFocus,
        isTrue,
        reason: 'non-modal: Tab escapes the scope',
      );

      // Move focus back into the scope and then flip modal on.
      inA.requestFocus();
      _ModalGrowHost.of(tester)!.toggleModal();
      tester.pump();
      tester.render(size: const CellSize(20, 3));

      final trace = _FocusTrace(tester.focusManager);
      tester.sendKey(_code(KeyCode.tab));
      expect(inB.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(inA.hasFocus, isTrue, reason: 'wraps within the now-modal scope');
      expect(
        trace.sequence.contains(outside),
        isFalse,
        reason: 'modal flipped on; outside must no longer appear',
      );
      trace.dispose();
    });

    testWidgets(
      'equal-depth modals: later-mounted marker wins the deepest tiebreak',
      (tester) {
        // Two modals at the SAME element depth (siblings under the same
        // parent). The deepest-active-modal picker must use the monotonic
        // `_mountSeq` tiebreak so the later-mounted one anchors the modal
        // boundary — Set iteration order is not depended on.
        //
        // Children mount in slot order, so slot[1] (B) has a higher
        // _mountSeq than slot[0] (A). The deepest-active picker must
        // pick B's marker.
        final aNode = FocusNode(debugLabel: 'aNode');
        final bNode = FocusNode(debugLabel: 'bNode');

        tester.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: FocusScope(
                  modal: true,
                  child: Focus(focusNode: aNode, child: const Text('A')),
                ),
              ),
              SizedBox(
                height: 1,
                child: FocusScope(
                  modal: true,
                  child: Focus(focusNode: bNode, child: const Text('B')),
                ),
              ),
            ],
          ),
        );
        tester.render(size: const CellSize(20, 2));

        // No node focused, two equal-depth modals open. focusNext() must
        // confine to the LATER-mounted modal (B), per the mountSeq tiebreak.
        tester.focusManager.requestFocus(null);
        tester.focusManager.focusNext();
        expect(
          aNode.hasFocus,
          isFalse,
          reason: 'earlier-mounted modal (A) should NOT be the anchor',
        );
        expect(
          bNode.hasFocus,
          isTrue,
          reason:
              'later-mounted modal (B) anchors the deepest-modal '
              'tiebreak when depths are equal',
        );
      },
    );

    testWidgets(
      'suppressGlobals mid-life rebuild flips dispatcher decision next event',
      (tester) {
        // A FocusScope toggles `suppressGlobals` between renders. The
        // marker element captures the flag in update(), and the manager
        // reads it on `_capturedSuppressGlobals` — no re-registration
        // needed, and the next dispatcher consultation sees the new value.
        var globalFired = 0;
        final binding = KeyBinding(
          KeyChord.char('g'),
          onEvent: (_) => globalFired += 1,
          label: 'g',
        );
        final dispatcher = InputDispatcher(
          focusManager: tester.focusManager,
          globalBindings: [binding],
        );

        final inside = FocusNode(debugLabel: 'inside');
        tester.pumpWidget(
          _ModalSuppressToggleHost(startSuppress: false, inside: inside),
        );
        tester.render(size: const CellSize(20, 1));
        expect(inside.hasFocus, isTrue);

        // suppressGlobals=false: global fires.
        dispatcher.dispatch(_char('g'));
        expect(globalFired, 1);

        // Toggle on.
        _ModalSuppressToggleHost.of(tester)!.toggleSuppress();
        tester.pump();
        tester.render(size: const CellSize(20, 1));

        dispatcher.dispatch(_char('g'));
        expect(
          globalFired,
          1,
          reason: 'suppressGlobals flipped on; global must NOT fire',
        );

        // Toggle off.
        _ModalSuppressToggleHost.of(tester)!.toggleSuppress();
        tester.pump();
        tester.render(size: const CellSize(20, 1));

        dispatcher.dispatch(_char('g'));
        expect(globalFired, 2, reason: 'flipped back off; global fires again');

        dispatcher.dispose();
      },
    );

    testWidgets(
      'non-modal FocusScope with suppressGlobals still gates globals',
      (tester) {
        // Regression: the manager must read suppressGlobals from the
        // focused node's enclosing scope when there's no active modal.
        var globalFired = 0;
        final binding = KeyBinding(
          KeyChord.char('g'),
          onEvent: (_) => globalFired += 1,
          label: 'g',
        );
        final dispatcher = InputDispatcher(
          focusManager: tester.focusManager,
          globalBindings: [binding],
        );

        final inside = FocusNode(debugLabel: 'inside');
        tester.pumpWidget(
          FocusScope(
            suppressGlobals: true,
            child: SizedBox(
              height: 1,
              child: Focus(
                focusNode: inside,
                autofocus: true,
                child: const Text('inside'),
              ),
            ),
          ),
        );
        tester.render(size: const CellSize(20, 1));
        expect(inside.hasFocus, isTrue);

        dispatcher.dispatch(_char('g'));
        expect(
          globalFired,
          0,
          reason: 'non-modal suppressGlobals must still gate globals',
        );

        dispatcher.dispose();
      },
    );
  });
}

KeyEvent _char(String c) => KeyEvent(char: c);

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

/// Host with a single FocusScope whose `modal` is toggleable.
class _ModalToggleHost extends StatefulWidget {
  const _ModalToggleHost({
    required this.startModal,
    required this.inside,
    required this.outside,
  });
  final bool startModal;
  final FocusNode inside;
  final FocusNode outside;

  static _ModalToggleHostState? of(FleuryTester tester) {
    final el =
        tester.find(byType(_ModalToggleHost)).singleOrNull as StatefulElement?;
    return el?.state as _ModalToggleHostState?;
  }

  @override
  State<_ModalToggleHost> createState() => _ModalToggleHostState();
}

class _ModalToggleHostState extends State<_ModalToggleHost> {
  late bool _modal = widget.startModal;
  void toggleModal() => setState(() => _modal = !_modal);

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
              modal: _modal,
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

/// Host with a FocusScope that flips from non-modal to modal.
class _ModalGrowHost extends StatefulWidget {
  const _ModalGrowHost({
    required this.startModal,
    required this.outside,
    required this.inA,
    required this.inB,
  });
  final bool startModal;
  final FocusNode outside;
  final FocusNode inA;
  final FocusNode inB;

  static _ModalGrowHostState? of(FleuryTester tester) {
    final el =
        tester.find(byType(_ModalGrowHost)).singleOrNull as StatefulElement?;
    return el?.state as _ModalGrowHostState?;
  }

  @override
  State<_ModalGrowHost> createState() => _ModalGrowHostState();
}

class _ModalGrowHostState extends State<_ModalGrowHost> {
  late bool _modal = widget.startModal;
  void toggleModal() => setState(() => _modal = !_modal);

  @override
  Widget build(BuildContext context) {
    // Outer FocusTraversalGroup handles Tab from the outside node; the
    // inner one binds Tab inside the scope (Tab's chain-stops-at-modal
    // walk means the outer binding never sees Tab while the scope is
    // modal, so the inner binding is required to make Tab work inside).
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
              modal: _modal,
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

/// Host whose FocusScope toggles `suppressGlobals` (modal stays true).
class _ModalSuppressToggleHost extends StatefulWidget {
  const _ModalSuppressToggleHost({
    required this.startSuppress,
    required this.inside,
  });
  final bool startSuppress;
  final FocusNode inside;

  static _ModalSuppressToggleHostState? of(FleuryTester tester) {
    final el =
        tester.find(byType(_ModalSuppressToggleHost)).singleOrNull
            as StatefulElement?;
    return el?.state as _ModalSuppressToggleHostState?;
  }

  @override
  State<_ModalSuppressToggleHost> createState() =>
      _ModalSuppressToggleHostState();
}

class _ModalSuppressToggleHostState extends State<_ModalSuppressToggleHost> {
  late bool _suppress = widget.startSuppress;
  void toggleSuppress() => setState(() => _suppress = !_suppress);

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      key: const ValueKey('suppress-scope'),
      modal: true,
      suppressGlobals: _suppress,
      child: SizedBox(
        height: 1,
        child: Focus(
          focusNode: widget.inside,
          autofocus: true,
          child: const Text('inside'),
        ),
      ),
    );
  }
}

extension<E> on List<E> {
  E? get singleOrNull => length == 1 ? single : null;
}
