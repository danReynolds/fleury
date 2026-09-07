import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';

MouseEvent at(
  MouseEventKind kind,
  int col,
  int row, {
  MouseButton button = MouseButton.left,
  bool shift = false,
}) => MouseEvent(
  kind: kind,
  button: button,
  col: col,
  row: row,
  modifiers: {if (shift) KeyModifier.shift},
);

void click(FleuryTester tester, int col, int row, {bool shift = false}) {
  tester.sendMouse(at(MouseEventKind.down, col, row, shift: shift));
  tester.pump();
  tester.sendMouse(at(MouseEventKind.up, col, row, shift: shift));
  tester.pump();
}

void main() {
  testWidgets(
    'cursor hints preserve editor state and follow presented geometry',
    (tester) {
      Widget tree(MouseCursor? cursor, int left) => Padding(
        padding: EdgeInsets.only(left: left),
        child: MouseRegion(
          cursor: cursor,
          child: const SizedBox(
            width: 8,
            child: TextInput(semanticLabel: 'Name', autofocus: true),
          ),
        ),
      );
      Iterable<SemanticNode> cursors() =>
          tester.semantics().nodes.where((n) => n.state['mouseCursor'] != null);
      tester.pumpWidget(tree(null, 0));
      tester.type('Ada');
      expect(cursors(), isEmpty);
      tester.pumpWidget(tree(MouseCursor.resizeLeftRight, 4));
      expect(cursors().single.state['mouseCursor'], 'resizeLeftRight');
      expect(cursors().single.bounds!.left, 4);
      tester.type('!');
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Name')
            .value,
        'Ada!',
      );
      tester.pumpWidget(tree(null, 4));
      expect(cursors(), isEmpty);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Name')
            .value,
        'Ada!',
      );
    },
  );

  testWidgets(
    'an absorbing boundary blocks ancestor focus but not its children',
    (tester) {
      final ancestor = FocusNode();
      final child = FocusNode();
      addTearDown(ancestor.dispose);
      addTearDown(child.dispose);
      tester.pumpWidget(
        Focus(
          focusNode: ancestor,
          child: AbsorbPointer(
            child: SizedBox(
              width: 10,
              height: 1,
              child: Row(
                children: [
                  Focus(
                    focusNode: child,
                    child: const SizedBox(width: 3, height: 1),
                  ),
                  const SizedBox(width: 7, height: 1),
                ],
              ),
            ),
          ),
        ),
      );
      click(tester, 8, 0);
      expect(ancestor.hasFocus, isFalse);
      click(tester, 1, 0);
      expect(child.hasFocus, isTrue);
    },
  );

  testWidgets(
    'tap down ends exactly once on release outside, cancel, or mismatched button',
    (tester) {
      final log = <String>[];
      tester.pumpWidget(
        GestureDetector(
          onTapDown: (_) => log.add('down'),
          onTapUp: (_) => log.add('up'),
          onTapCancel: () => log.add('cancel'),
          onTap: () => log.add('tap'),
          child: const SizedBox(width: 5, height: 1),
        ),
      );
      for (final end in [
        at(MouseEventKind.up, 8, 0),
        at(MouseEventKind.cancel, 0, 0),
        at(MouseEventKind.up, 1, 0, button: MouseButton.right),
      ]) {
        tester.sendMouse(at(MouseEventKind.down, 1, 0));
        tester.sendMouse(end);
        tester.sendMouse(at(MouseEventKind.up, 1, 0));
      }
      expect(log, ['down', 'cancel', 'down', 'cancel', 'down', 'cancel']);
      click(tester, 1, 0);
      expect(log.sublist(6), ['down', 'up', 'tap']);
    },
  );

  testWidgets(
    'first motion reaches update-only drag in local cells and cancels the tap',
    (tester) {
      final moves = <PointerDragDetails>[];
      var cancels = 0;
      var ends = 0;
      tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 2),
          child: GestureDetector(
            onTapDown: (_) {},
            onTapCancel: () => cancels++,
            onDragUpdate: moves.add,
            onDragEnd: (_) => ends++,
            child: const SizedBox(width: 5, height: 1),
          ),
        ),
      );
      tester.sendMouse(at(MouseEventKind.down, 11, 2));
      tester.sendMouse(at(MouseEventKind.drag, 11, 2));
      expect(moves, isEmpty, reason: 'same-cell jitter is not a drag');
      tester.sendMouse(at(MouseEventKind.drag, 13, 2));
      tester.sendMouse(at(MouseEventKind.drag, 24, 4));
      tester.sendMouse(at(MouseEventKind.up, 24, 4));
      expect(moves.map((e) => e.localPosition), [
        const CellOffset(3, 0),
        const CellOffset(14, 2),
      ]);
      expect(moves.map((e) => e.delta), [
        const CellOffset(2, 0),
        const CellOffset(11, 2),
      ]);
      expect(moves.first.globalPressPosition, const CellOffset(11, 2));
      expect(cancels, 1);
      expect(ends, 1);
    },
  );

  testWidgets(
    'cancel ends a drag and surface leave clears hover while retaining capture',
    (tester) {
      final log = <String>[];
      tester.pumpWidget(
        MouseRegion(
          onEnter: () => log.add('enter'),
          onExit: () => log.add('exit'),
          child: GestureDetector(
            onDragUpdate: (_) => log.add('move'),
            onDragEnd: (_) => log.add('end'),
            onDragCancel: () => log.add('cancel'),
            child: const SizedBox(width: 5, height: 1),
          ),
        ),
      );
      tester.sendMouse(at(MouseEventKind.down, 1, 0));
      tester.sendMouse(at(MouseEventKind.drag, 2, 0));
      tester.sendMouse(at(MouseEventKind.leave, 0, 0));
      expect(log, ['enter', 'move', 'exit']);
      tester.sendMouse(at(MouseEventKind.drag, 8, 0));
      tester.sendMouse(at(MouseEventKind.cancel, 0, 0));
      tester.sendMouse(at(MouseEventKind.up, 8, 0));
      expect(log, ['enter', 'move', 'exit', 'move', 'cancel']);
    },
  );

  testWidgets(
    'nested hover retains its parent and reconciles after a region moves',
    (tester) {
      final log = <String>[];
      Widget tree(int left) => MouseRegion(
        onEnter: () => log.add('outer enter'),
        onExit: () => log.add('outer exit'),
        child: SizedBox(
          width: 10,
          height: 1,
          child: Row(
            children: [
              SizedBox(width: left),
              MouseRegion(
                onEnter: () => log.add('inner enter'),
                onExit: () => log.add('inner exit'),
                child: const SizedBox(width: 3, height: 1),
              ),
            ],
          ),
        ),
      );
      tester.pumpWidget(tree(3));
      tester.sendMouse(at(MouseEventKind.moved, 1, 0));
      tester.sendMouse(at(MouseEventKind.moved, 4, 0));
      expect(log, ['outer enter', 'inner enter']);
      tester.pumpWidget(tree(6));
      expect(log, ['outer enter', 'inner enter', 'inner exit']);
      tester.sendMouse(at(MouseEventKind.leave, 0, 0));
      expect(log.last, 'outer exit');
    },
  );

  for (final edge in EdgeBehavior.values) {
    testWidgets('nested wheel respects $edge at the inner edge', (tester) {
      final outer = ScrollController();
      final inner = ScrollController(offset: 3);
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      tester.pumpWidget(
        SizedBox(
          width: 20,
          height: 4,
          child: ScrollView(
            controller: outer,
            child: Column(
              children: [
                SizedBox(
                  height: 2,
                  child: ScrollView(
                    controller: inner,
                    edgeBehavior: edge,
                    child: const Text('a\nb\nc\nd\ne'),
                  ),
                ),
                const Text('1\n2\n3\n4\n5\n6'),
              ],
            ),
          ),
        ),
      );
      tester.sendMouse(at(MouseEventKind.scrollDown, 1, 0));
      tester.pump();
      expect(inner.offset, 3);
      expect(outer.offset, edge == EdgeBehavior.bubble ? 3 : 0);
    });
  }

  testWidgets('wheel bubbles to ancestors, never an obscured sibling', (
    tester,
  ) {
    final log = <String>[];
    tester.pumpWidget(
      MouseRegion(
        onScroll: (_) {
          log.add('parent');
          return true;
        },
        child: Stack(
          children: [
            MouseRegion(
              onScroll: (_) {
                log.add('behind');
                return true;
              },
              child: const SizedBox(width: 5, height: 1),
            ),
            MouseRegion(
              onScroll: (_) {
                log.add('front');
                return false;
              },
              child: const SizedBox(width: 5, height: 1),
            ),
          ],
        ),
      ),
    );
    tester.sendMouse(at(MouseEventKind.scrollDown, 1, 0));
    expect(log, ['front', 'parent']);
  });

  testWidgets(
    'a captured region clipped out of view cancels while still mounted',
    (tester) {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final log = <String>[];
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 1,
          child: ScrollView(
            controller: scroll,
            child: Column(
              children: [
                GestureDetector(
                  onTapDown: (_) => log.add('down'),
                  onTapCancel: () => log.add('tap cancel'),
                  onDragUpdate: (_) => log.add('move'),
                  onDragCancel: () => log.add('drag cancel'),
                  child: const SizedBox(width: 10, height: 1),
                ),
                const SizedBox(height: 3),
              ],
            ),
          ),
        ),
      );
      tester.sendMouse(at(MouseEventKind.down, 1, 0));
      tester.sendMouse(at(MouseEventKind.drag, 2, 0));
      scroll.jumpTo(1);
      tester.pump();
      tester.sendMouse(at(MouseEventKind.up, 2, 0));
      expect(log, ['down', 'tap cancel', 'move', 'drag cancel']);
    },
  );

  testWidgets(
    'focus follows the front control and ignores clipped focus bounds',
    (tester) {
      final behind = FocusNode();
      final front = FocusNode();
      final clipped = FocusNode();
      addTearDown(behind.dispose);
      addTearDown(front.dispose);
      addTearDown(clipped.dispose);
      tester.pumpWidget(
        Stack(
          children: [
            Focus(
              focusNode: behind,
              child: const SizedBox(width: 5, height: 1),
            ),
            Focus(
              focusNode: front,
              child: GestureDetector(
                onTap: () {},
                child: const SizedBox(width: 5, height: 1),
              ),
            ),
          ],
        ),
      );
      click(tester, 1, 0);
      expect(front.hasFocus, isTrue);
      expect(behind.hasFocus, isFalse);
      tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SizedBox(
            height: 2,
            child: ScrollView(
              controller: ScrollController(offset: 3),
              child: Focus(
                focusNode: clipped,
                child: const SizedBox(width: 10, height: 10),
              ),
            ),
          ),
        ),
      );
      click(tester, 1, 0);
      expect(clipped.hasFocus, isFalse);
      click(tester, 1, 2);
      expect(clipped.hasFocus, isTrue);
    },
  );
}
