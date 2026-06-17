import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// Builds a [FocusNode] with a pre-recorded `rect` so the traversal
/// algorithm has something to score without needing a full mount /
/// paint cycle.
FocusNode _node({
  required int left,
  required int top,
  required int width,
  required int height,
  String? label,
  bool canRequestFocus = true,
  bool skipTraversal = false,
}) {
  return FocusNode(
    canRequestFocus: canRequestFocus,
    skipTraversal: skipTraversal,
    debugLabel: label,
  )..rect = CellRect.fromLTWH(left, top, width, height);
}

KeyEvent _code(KeyCode kc) => KeyEvent(keyCode: kc);

Widget _stub(BuildContext context, int i, bool selected) => Text('Item $i');

void main() {
  group('nearestFocusableInDirection', () {
    test('moves right to the directly-adjacent pane', () {
      final left = _node(left: 0, top: 0, width: 5, height: 3, label: 'left');
      final right = _node(left: 6, top: 0, width: 5, height: 3, label: 'right');

      final hit = nearestFocusableInDirection(
        from: left.rect!,
        candidates: [left, right],
        excluding: left,
        direction: TraversalDirection.right,
      );
      expect(hit, same(right));
    });

    test('returns null when there is nothing in that direction', () {
      final solo = _node(left: 0, top: 0, width: 5, height: 3);

      final hit = nearestFocusableInDirection(
        from: solo.rect!,
        candidates: [solo],
        excluding: solo,
        direction: TraversalDirection.right,
      );
      expect(hit, isNull);
    });

    test('prefers the pane sharing the same row over a far-down one', () {
      // Two candidates to the right: one at the same row, one far below.
      final from = _node(left: 0, top: 0, width: 5, height: 3, label: 'from');
      final sameRow = _node(
        left: 10,
        top: 0,
        width: 5,
        height: 3,
        label: 'same',
      );
      final farDown = _node(
        left: 8,
        top: 20,
        width: 5,
        height: 3,
        label: 'down',
      );

      final hit = nearestFocusableInDirection(
        from: from.rect!,
        candidates: [from, sameRow, farDown],
        excluding: from,
        direction: TraversalDirection.right,
      );
      expect(hit, same(sameRow));
    });

    test('skips nodes flagged skipTraversal', () {
      final from = _node(left: 0, top: 0, width: 5, height: 3);
      final skip = _node(
        left: 10,
        top: 0,
        width: 5,
        height: 3,
        skipTraversal: true,
      );
      final real = _node(left: 20, top: 0, width: 5, height: 3, label: 'real');

      final hit = nearestFocusableInDirection(
        from: from.rect!,
        candidates: [from, skip, real],
        excluding: from,
        direction: TraversalDirection.right,
      );
      expect(hit, same(real));
    });

    test('skips nodes with canRequestFocus false', () {
      final from = _node(left: 0, top: 0, width: 5, height: 3);
      final noFocus = _node(
        left: 10,
        top: 0,
        width: 5,
        height: 3,
        canRequestFocus: false,
      );

      final hit = nearestFocusableInDirection(
        from: from.rect!,
        candidates: [from, noFocus],
        excluding: from,
        direction: TraversalDirection.right,
      );
      expect(hit, isNull);
    });
  });

  group('FocusTraversalGroup with real widgets', () {
    testWidgets('left/right cycles focus between two ListView panes', (tester) {
      final leftNode = FocusNode(debugLabel: 'sidebar');
      final rightNode = FocusNode(debugLabel: 'messages');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 10,
                child: ListView.builder(
                  focusNode: leftNode,
                  autofocus: true,
                  itemCount: 3,
                  itemBuilder: _stub,
                ),
              ),
              SizedBox(
                width: 10,
                child: ListView.builder(
                  focusNode: rightNode,
                  itemCount: 3,
                  itemBuilder: _stub,
                ),
              ),
            ],
          ),
        ),
      );
      // First frame: records rects on both nodes.
      tester.render(size: const CellSize(30, 5));
      expect(leftNode.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.arrowRight));
      expect(rightNode.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.arrowLeft));
      expect(leftNode.hasFocus, isTrue);
    });

    testWidgets('up/down inside a ListView still moves selection, not '
        'focus', (tester) {
      // The traversal group is present but vertical arrows are
      // consumed by the focused ListView (selection-mode) — they
      // never bubble out, so the group does nothing.
      final node = FocusNode(debugLabel: 'list');
      final controller = ListController();
      tester.pumpWidget(
        FocusTraversalGroup(
          child: ListView.builder(
            focusNode: node,
            controller: controller,
            autofocus: true,
            itemCount: 3,
            itemBuilder: _stub,
          ),
        ),
      );
      tester.render();
      expect(node.hasFocus, isTrue);
      expect(controller.selectedIndex, 0);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.selectedIndex, 1);
      expect(node.hasFocus, isTrue);
    });

    testWidgets('up at the top of a list bubbles with EdgeBehavior.bubble '
        'and moves focus to a pane above', (tester) {
      final topNode = FocusNode(debugLabel: 'top');
      final bottomNode = FocusNode(debugLabel: 'bottom');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 3,
                child: ListView.builder(
                  focusNode: topNode,
                  itemCount: 3,
                  itemBuilder: _stub,
                ),
              ),
              SizedBox(
                height: 3,
                child: ListView.builder(
                  focusNode: bottomNode,
                  autofocus: true,
                  itemCount: 3,
                  itemBuilder: _stub,
                  edgeBehavior: EdgeBehavior.bubble,
                ),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 6));
      expect(bottomNode.hasFocus, isTrue);

      // Down arrow: the bottom list's controller starts at 0; pressing
      // up at 0 is the boundary. With bubble, it escapes — the group
      // sees up and moves focus to the spatially-above pane.
      tester.sendKey(_code(KeyCode.arrowUp));
      expect(topNode.hasFocus, isTrue);
    });

    testWidgets('root traversal prefers body sibling over closer toolbar', (
      tester,
    ) {
      final leftNode = FocusNode(debugLabel: 'left pane');
      final rightNode = FocusNode(debugLabel: 'right pane');
      final toolbarNode = FocusNode(debugLabel: 'toolbar control');

      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 8,
                      child: Focus(
                        focusNode: toolbarNode,
                        child: const Text('Toolbar'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 8,
                      child: Focus(
                        focusNode: leftNode,
                        autofocus: true,
                        child: const Text('Left'),
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 8,
                      child: Focus(
                        focusNode: rightNode,
                        child: const Text('Right'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(50, 8));
      expect(leftNode.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.arrowRight));
      expect(rightNode.hasFocus, isTrue);
      expect(toolbarNode.hasFocus, isFalse);
    });

    testWidgets('traversal prefers focusable descendant over shell ancestor', (
      tester,
    ) {
      final leftNode = FocusNode(debugLabel: 'left');
      final shellNode = FocusNode(debugLabel: 'shell');
      final childNode = FocusNode(debugLabel: 'child');

      tester.pumpWidget(
        FocusTraversalGroup(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 8,
                child: Focus(
                  focusNode: leftNode,
                  autofocus: true,
                  child: const Text('Left'),
                ),
              ),
              SizedBox(
                width: 16,
                child: Focus(
                  focusNode: shellNode,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Focus(focusNode: childNode, child: const Text('C')),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(30, 4));
      expect(leftNode.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.arrowRight));
      expect(childNode.hasFocus, isTrue);
      expect(shellNode.hasFocus, isFalse);
    });

    testWidgets('nested groups keep lateral traversal in the active pane set', (
      tester,
    ) {
      final leftNode = FocusNode(debugLabel: 'left pane');
      final rightNode = FocusNode(debugLabel: 'right pane');
      final headerNode = FocusNode(debugLabel: 'header control');

      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 8,
                      child: Focus(
                        focusNode: headerNode,
                        child: const Text('Header'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Expanded(
                child: FocusTraversalGroup(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 8,
                        child: Focus(
                          focusNode: leftNode,
                          autofocus: true,
                          child: const Text('Left'),
                        ),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 8,
                        child: Focus(
                          focusNode: rightNode,
                          child: const Text('Right'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(50, 8));
      expect(leftNode.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.arrowRight));
      expect(rightNode.hasFocus, isTrue);
      expect(headerNode.hasFocus, isFalse);

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(headerNode.hasFocus, isTrue);
    });
  });

  group('Tab cycling', () {
    Widget three(FocusNode a, FocusNode b, FocusNode c) => FocusTraversalGroup(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 6,
            child: Focus(focusNode: a, autofocus: true, child: const Text('A')),
          ),
          SizedBox(
            width: 6,
            child: Focus(focusNode: b, child: const Text('B')),
          ),
          SizedBox(
            width: 6,
            child: Focus(focusNode: c, child: const Text('C')),
          ),
        ],
      ),
    );

    testWidgets('Tab / Shift+Tab cycle focus in reading order', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final c = FocusNode(debugLabel: 'c');
      tester.pumpWidget(three(a, b, c));
      tester.render(size: const CellSize(20, 3)); // record rects
      expect(a.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.tab));
      expect(b.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(c.hasFocus, isTrue);
      tester.sendKey(_code(KeyCode.tab));
      expect(a.hasFocus, isTrue, reason: 'wraps to the first');

      tester.sendKey(
        const KeyEvent(keyCode: KeyCode.tab, modifiers: {KeyModifier.shift}),
      );
      expect(c.hasFocus, isTrue, reason: 'Shift+Tab wraps backward');
    });

    testWidgets('Tab skips nodes flagged skipTraversal', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final skip = FocusNode(debugLabel: 'skip', skipTraversal: true);
      final c = FocusNode(debugLabel: 'c');
      tester.pumpWidget(three(a, skip, c));
      tester.render(size: const CellSize(20, 3));

      tester.sendKey(_code(KeyCode.tab));
      expect(c.hasFocus, isTrue, reason: 'the middle node is skipped');
      expect(skip.hasFocus, isFalse);
    });

    testWidgets('a focused widget that handles Tab keeps it from cycling', (
      tester,
    ) {
      var consumed = 0;
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 6,
                child: Focus(
                  focusNode: a,
                  autofocus: true,
                  onKey: (e) {
                    if (e.keyCode == KeyCode.tab) {
                      consumed++;
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: const Text('A'),
                ),
              ),
              SizedBox(
                width: 6,
                child: Focus(focusNode: b, child: const Text('B')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));

      tester.sendKey(_code(KeyCode.tab));
      expect(consumed, 1);
      expect(
        a.hasFocus,
        isTrue,
        reason: 'Tab was consumed before reaching the group',
      );
    });
  });

  group('click-to-focus', () {
    testWidgets('a left click focuses the widget under the pointer', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Focus(
                  focusNode: a,
                  autofocus: true,
                  child: const Text('A'),
                ),
              ),
              SizedBox(
                height: 1,
                child: Focus(focusNode: b, child: const Text('B')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(10, 2)); // record focus rects
      expect(a.hasFocus, isTrue);

      // Row 1 belongs to B's box.
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 2,
          row: 1,
        ),
      );
      expect(b.hasFocus, isTrue, reason: 'clicked into B');

      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 2,
          row: 0,
        ),
      );
      expect(a.hasFocus, isTrue, reason: 'clicked back into A');
    });

    testWidgets('a click outside any focusable changes nothing', (tester) {
      final a = FocusNode(debugLabel: 'a');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: SizedBox(
            height: 1,
            child: Focus(focusNode: a, autofocus: true, child: const Text('A')),
          ),
        ),
      );
      tester.render(size: const CellSize(10, 4));
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 0,
          row: 3,
        ),
      );
      expect(a.hasFocus, isTrue, reason: 'no focusable there; focus unchanged');
    });

    testWidgets(
      'modal open: click on a node OUTSIDE the modal does not move focus',
      (tester) {
        // Mouse path must honour the active modal boundary same as Tab.
        // A click on a node behind a modal dialog must not focus through.
        final outside = FocusNode(debugLabel: 'outside');
        final inside = FocusNode(debugLabel: 'inside');
        tester.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Focus(focusNode: outside, child: const Text('outside')),
              ),
              SizedBox(
                height: 1,
                child: FocusScope(
                  modal: true,
                  child: Focus(
                    focusNode: inside,
                    autofocus: true,
                    child: const Text('inside'),
                  ),
                ),
              ),
            ],
          ),
        );
        tester.render(size: const CellSize(10, 2));
        expect(inside.hasFocus, isTrue);

        // Click on the outside node's row.
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 2,
            row: 0,
          ),
        );
        expect(
          outside.hasFocus,
          isFalse,
          reason: 'modal active: outside click must not focus through',
        );
        expect(inside.hasFocus, isTrue, reason: 'focus stays inside the modal');
      },
    );

    testWidgets('modal open: click INSIDE the modal still focuses normally', (
      tester,
    ) {
      // Regression: modal-aware filter must not also break in-modal clicks.
      final inA = FocusNode(debugLabel: 'inA');
      final inB = FocusNode(debugLabel: 'inB');
      tester.pumpWidget(
        FocusScope(
          modal: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Focus(
                  focusNode: inA,
                  autofocus: true,
                  child: const Text('A'),
                ),
              ),
              SizedBox(
                height: 1,
                child: Focus(focusNode: inB, child: const Text('B')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(10, 2));
      expect(inA.hasFocus, isTrue);

      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 2,
          row: 1,
        ),
      );
      expect(inB.hasFocus, isTrue, reason: 'in-modal click moves focus');
    });

    testWidgets(
      'click on a skipTraversal:true node inside a modal still focuses it',
      (tester) {
        // Buttons opt out of Tab cycling (`skipTraversal: true`) but stay
        // mouse-focusable. The modal-aware filter on the click path uses
        // `isClickable`, not `isTraversable`, so the click still lands.
        final button = FocusNode(debugLabel: 'button', skipTraversal: true);
        final anchor = FocusNode(debugLabel: 'anchor');
        tester.pumpWidget(
          FocusScope(
            modal: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 1,
                  child: Focus(
                    focusNode: anchor,
                    autofocus: true,
                    child: const Text('A'),
                  ),
                ),
                SizedBox(
                  height: 1,
                  child: Focus(focusNode: button, child: const Text('btn')),
                ),
              ],
            ),
          ),
        );
        tester.render(size: const CellSize(10, 2));
        expect(anchor.hasFocus, isTrue);

        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 1,
            row: 1,
          ),
        );
        expect(
          button.hasFocus,
          isTrue,
          reason: 'skipTraversal nodes are still click-focusable',
        );
      },
    );

    testWidgets('no modal: click works as before — regression guard', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 1,
              child: Focus(
                focusNode: a,
                autofocus: true,
                child: const Text('A'),
              ),
            ),
            SizedBox(
              height: 1,
              child: Focus(focusNode: b, child: const Text('B')),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(10, 2));
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 2,
          row: 1,
        ),
      );
      expect(b.hasFocus, isTrue);
    });
  });

  group('ExcludeFocus', () {
    testWidgets('Tab skips nodes under an active ExcludeFocus', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final hidden = FocusNode(debugLabel: 'hidden');
      final c = FocusNode(debugLabel: 'c');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 6,
                child: Focus(
                  focusNode: a,
                  autofocus: true,
                  child: const Text('A'),
                ),
              ),
              SizedBox(
                width: 6,
                child: ExcludeFocus(
                  child: Focus(focusNode: hidden, child: const Text('H')),
                ),
              ),
              SizedBox(
                width: 6,
                child: Focus(focusNode: c, child: const Text('C')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));

      tester.sendKey(_code(KeyCode.tab));
      expect(c.hasFocus, isTrue, reason: 'the excluded node is skipped');
      expect(hidden.hasFocus, isFalse);
      tester.sendKey(_code(KeyCode.tab));
      expect(a.hasFocus, isTrue, reason: 'wraps past the excluded node');
    });

    testWidgets('an autofocus node under an active ExcludeFocus is denied', (
      tester,
    ) {
      final hidden = FocusNode(debugLabel: 'hidden');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: ExcludeFocus(
            child: Focus(
              focusNode: hidden,
              autofocus: true,
              child: const Text('H'),
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(
        hidden.hasFocus,
        isFalse,
        reason: 'excluded subtree must not claim autofocus',
      );
    });

    testWidgets('flipping excluding back on lets traversal in again', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      Widget tree(bool exclude) => FocusTraversalGroup(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 6,
              child: Focus(
                focusNode: a,
                autofocus: true,
                child: const Text('A'),
              ),
            ),
            SizedBox(
              width: 6,
              child: ExcludeFocus(
                excluding: exclude,
                child: Focus(focusNode: b, child: const Text('B')),
              ),
            ),
          ],
        ),
      );

      tester.pumpWidget(tree(true));
      tester.render(size: const CellSize(20, 3));
      tester.sendKey(_code(KeyCode.tab));
      expect(b.hasFocus, isFalse, reason: 'excluded while true');

      tester.pumpWidget(tree(false));
      tester.render(size: const CellSize(20, 3));
      tester.sendKey(_code(KeyCode.tab));
      expect(b.hasFocus, isTrue, reason: 'reachable once excluding is off');
    });
  });

  group('focus bounds in scrolled content', () {
    testWidgets('records a screen-space rect, offset by ancestors and scroll', (
      tester,
    ) {
      final node = FocusNode(debugLabel: 'scrolled');
      tester.pumpWidget(
        Padding(
          // Shift the viewport so screen space differs from the ScrollView's
          // content space (which is col 0, scroll-relative).
          padding: const EdgeInsets.only(left: 20, top: 3),
          child: SizedBox(
            height: 4,
            child: ScrollView(
              child: Column(
                children: [
                  const Text('r0'),
                  const Text('r1'),
                  Focus(focusNode: node, child: const Text('target')),
                  for (var i = 0; i < 10; i++) Text('row$i'),
                ],
              ),
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(40, 12));

      final rect = node.rect;
      expect(rect, isNotNull);
      // 'target' is content row 2, visible at scroll 0. Its bounds must be the
      // on-screen position, not the content-space origin (col 0) — feeding the
      // latter to directional traversal put scrolled controls at phantom
      // positions over sibling panes.
      expect(rect!.left, 20, reason: 'screen col = left padding, not content 0');
      expect(rect.top, 5, reason: 'screen row = top padding 3 + content row 2');
    });

    testWidgets('a focusable scrolled out of the viewport records no rect', (
      tester,
    ) {
      final node = FocusNode(debugLabel: 'scrolled-away');
      final ctl = ScrollController();
      tester.pumpWidget(
        SizedBox(
          height: 3,
          child: ScrollView(
            controller: ctl,
            child: Column(
              children: [
                Focus(focusNode: node, child: const Text('top')),
                for (var i = 0; i < 20; i++) Text('row$i'),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 6));
      expect(node.rect, isNotNull, reason: 'visible at the top of the content');

      ctl.scrollBy(10);
      tester.pump();
      tester.render(size: const CellSize(20, 6));
      expect(
        node.rect,
        isNull,
        reason: 'scrolled past the viewport — not a directional target',
      );
    });
  });
}
