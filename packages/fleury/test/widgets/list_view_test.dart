// ListView integration tests. Driven by FleuryTester so input
// dispatch + focus + rendering use the canonical test surface.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc) => KeyEvent(kc);

MouseEvent _mouse(MouseEventKind kind, int col, int row) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row);

Widget _itemBuilder(BuildContext context, int index, bool highlighted) {
  return Text('Item $index');
}

Widget _keyedStringList(
  List<String> items, {
  ListController? controller,
  int height = 3,
  void Function(int)? onSelect,
  Widget Function(BuildContext, int, bool)? itemBuilder,
}) {
  return SizedBox(
    width: 12,
    height: height,
    child: ListView.builder(
      controller: controller,
      itemCount: items.length,
      itemKeyBuilder: (index) => items[index],
      onSelect: onSelect,
      itemBuilder:
          itemBuilder ?? (context, index, highlighted) => Text(items[index]),
    ),
  );
}

void main() {
  group('pointer selection', () {
    testWidgets('tapping an item selects it and fires onSelect', (tester) {
      final controller = ListController(initialIndex: 0);
      final chosenItems = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 4,
          child: ListView.builder(
            controller: controller,
            itemCount: 4,
            onSelect: chosenItems.add,
            itemBuilder: (context, index, highlighted) =>
                SizedBox(width: 12, height: 1, child: Text('item $index')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 4)); // register gesture regions

      // Tap the third row (index 2): press + release in the same cell.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));

      expect(controller.currentIndex, 2);
      expect(chosenItems, [2]);
    });

    testWidgets('tap survives a rebuild between press and release', (tester) {
      // Over the serve wire, down and up arrive in separate frames, and the
      // press triggers a click-to-focus rebuild in between. The release
      // must still resolve the same logical item and select it once.
      final controller = ListController(initialIndex: 0);
      final chosenItems = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 4,
          child: ListView.builder(
            controller: controller,
            itemCount: 4,
            onSelect: chosenItems.add,
            itemBuilder: (context, index, highlighted) =>
                SizedBox(width: 12, height: 1, child: Text('item $index')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 4));

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.pump(); // full rebuild between down and up, as serve does
      tester.render(size: const CellSize(12, 4));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));

      expect(controller.currentIndex, 2);
      expect(chosenItems, [2]);
    });

    testWidgets('a drag wiggle between press and release still taps', (tester) {
      // A real mouse click in the browser client emits a tiny drag between
      // pointerdown and pointerup. That wiggle must not suppress the tap.
      final controller = ListController(initialIndex: 0);
      final chosenItems = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 4,
          child: ListView.builder(
            controller: controller,
            itemCount: 4,
            onSelect: chosenItems.add,
            itemBuilder: (context, index, highlighted) =>
                SizedBox(width: 12, height: 1, child: Text('item $index')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 4));

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.sendMouse(_mouse(MouseEventKind.drag, 1, 2)); // wiggle, same cell
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));

      expect(controller.currentIndex, 2);
      expect(chosenItems, [2]);
    });
  });

  group('cursor movement', () {
    testWidgets('arrowDown advances currentIndex', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.currentIndex, 0);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.currentIndex, 1);
      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.currentIndex, 2);
    });

    testWidgets('arrowUp decrements currentIndex', (tester) {
      final controller = ListController(initialIndex: 3);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.currentIndex, 3);

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(controller.currentIndex, 2);
    });

    testWidgets('home jumps to first, end jumps to last', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 8,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );

      tester.sendKey(_code(KeyCode.end));
      expect(controller.currentIndex, 7);
      tester.sendKey(_code(KeyCode.home));
      expect(controller.currentIndex, 0);
    });

    testWidgets('Enter fires onSelect with the current index', (tester) {
      int? selected;
      tester.pumpWidget(
        ListView.builder(
          itemCount: 3,
          itemBuilder: _itemBuilder,
          autofocus: true,
          onSelect: (i) => selected = i,
        ),
      );

      tester.sendKey(_code(KeyCode.arrowDown));
      tester.sendKey(_code(KeyCode.enter));
      expect(selected, 1);
    });

    testWidgets('browsing and selection are separate events', (tester) {
      final controller = ListController(initialIndex: 0);
      final focusedItems = <int>[];
      final choices = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 3,
          child: ListView.builder(
            controller: controller,
            itemCount: 3,
            autofocus: true,
            onFocusedItemChanged: focusedItems.add,
            onSelect: choices.add,
            itemBuilder: (context, index, highlighted) => Text('item $index'),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 3));

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(focusedItems, [1]);
      expect(choices, isEmpty);

      tester.sendKey(_code(KeyCode.enter));
      expect(focusedItems, [1]);
      expect(choices, [1]);

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      expect(focusedItems, [1, 2]);
      expect(choices, [1]);
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));
      expect(choices, [1, 2]);

      controller.currentIndex = 0;
      expect(
        focusedItems,
        [1, 2],
        reason: 'programmatic cursor movement is not reported as user input',
      );
    });
  });

  group('boundary handling', () {
    testWidgets('contain (opt-in) consumes up at the first item', (tester) {
      // The default is now bubble (boundary escape); contain is the opt-in for
      // a standalone/primary list that should keep focus at its edges.
      var bubbled = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.arrowUp, onTrigger: (_) => bubbled += 1),
          ],
          child: ListView.builder(
            itemCount: 3,
            itemBuilder: _itemBuilder,
            autofocus: true,
            edgeBehavior: EdgeBehavior.contain,
          ),
        ),
      );

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(bubbled, 0);
    });

    testWidgets('bubble lets up at the first item reach ancestor '
        'bindings', (tester) {
      var bubbled = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.arrowUp, onTrigger: (_) => bubbled += 1),
          ],
          child: ListView.builder(
            itemCount: 3,
            itemBuilder: _itemBuilder,
            autofocus: true,
            edgeBehavior: EdgeBehavior.bubble,
          ),
        ),
      );

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(bubbled, 1);
    });

    testWidgets('bubble lets down at the last item reach ancestor '
        'bindings', (tester) {
      var bubbled = 0;
      final controller = ListController(initialIndex: 2);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.arrowDown, onTrigger: (_) => bubbled += 1),
          ],
          child: ListView.builder(
            controller: controller,
            itemCount: 3,
            itemBuilder: _itemBuilder,
            autofocus: true,
            edgeBehavior: EdgeBehavior.bubble,
          ),
        ),
      );

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(bubbled, 1);
    });
  });

  group('viewport / scrolling', () {
    testWidgets('visibleRange reflects items that fit in the viewport', (
      tester,
    ) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));
      expect(controller.itemCount, 20);
      expect(controller.visibleRange, (first: 0, last: 4));
    });

    testWidgets('cursor moving past the bottom scrolls the viewport', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));
      expect(controller.visibleRange, (first: 0, last: 4));

      controller.currentIndex = 6;
      tester.render(size: const CellSize(10, 5));
      expect(controller.currentIndex, 6);
      expect(controller.visibleRange, (first: 2, last: 6));
    });

    testWidgets('a scrolled, cached lazy item stays tappable at its new row', (
      tester,
    ) {
      // The lazy path wraps each item in a RepaintBoundary. When the list
      // scrolls, an unchanged item's boundary cache-hits and blits at the new
      // row — it must ALSO replay its tap region at the threaded screenOffset,
      // or the row goes dead / hits a stale index. This is the lazy-specific
      // guard the eager path can't provide.
      final controller = ListController();
      final chosenItems = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 5,
          child: ListView.builder(
            controller: controller,
            itemCount: 20,
            onSelect: chosenItems.add,
            autofocus: true,
            itemBuilder: (context, index, highlighted) =>
                SizedBox(width: 10, height: 1, child: Text('item $index')),
          ),
        ),
      );
      tester.render(size: const CellSize(10, 5)); // item 2 painted at row 2
      expect(controller.visibleRange, (first: 0, last: 4));

      // Scroll: item 2 moves to row 0. Its content is unchanged, so its
      // boundary cache-hits on this frame — assert that explicitly, or the tap
      // below would pass even if item 2 repainted (live registration) and the
      // replay path this test exists for were broken.
      controller.currentIndex = 6;
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(10, 5));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      RepaintBoundaryDebugStats.beginFrame(enabled: false);
      expect(controller.visibleRange, (first: 2, last: 6));
      expect(
        stats.cachedCount,
        greaterThan(0),
        reason:
            'retained rows (incl. item 2) cache-hit on scroll — so the '
            'tap below goes through the region replay, not a live repaint',
      );

      // Tap row 0 — now item 2. The region only lands here because the cached
      // boundary replayed it at the new screen row, mapped to the right index.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 0));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 0));
      expect(controller.currentIndex, 2);
      expect(chosenItems, [2]);
    });

    testWidgets('cursor moving above the top scrolls back up', (tester) {
      final controller = ListController(initialIndex: 10);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));
      expect(controller.visibleRange, (first: 6, last: 10));

      controller.currentIndex = 4;
      tester.render(size: const CellSize(10, 5));
      expect(controller.visibleRange, (first: 4, last: 8));
    });

    testWidgets('jumpToIndex aligns the target to the top of the '
        'viewport', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );

      controller.jumpToIndex(8);
      tester.render(size: const CellSize(10, 5));
      expect(controller.visibleRange, (first: 8, last: 12));
    });
  });

  group('controller ownership', () {
    testWidgets('external controller survives widget unmount and '
        'stays usable', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.currentIndex, 1);
    });

    testWidgets('itemCount change clamps the existing cursor', (tester) {
      final controller = ListController(initialIndex: 9);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 10,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.currentIndex, 9);

      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.currentIndex, 2);
    });

    testWidgets('swapping controllers attaches without counting arrivals', (
      tester,
    ) {
      var controller = ListController(initialIndex: 3);

      Widget app() => ListView.builder(
        controller: controller,
        itemCount: 5,
        itemBuilder: _itemBuilder,
      );

      tester.pumpWidget(app());
      expect(controller.itemCount, 5);
      expect(controller.unseenCount, 0);

      controller = ListController(initialIndex: 2);
      tester.pumpWidget(app());

      expect(controller.itemCount, 5);
      expect(controller.currentIndex, 2);
      expect(
        controller.unseenCount,
        0,
        reason: 'attaching existing data is not a five-item arrival',
      );
    });

    testWidgets('a controller swap keeps the lazy list rendering and '
        'keyboard-navigable (L)', (tester) {
      // The audit's "renders permanently blank after a controller swap"
      // cluster (#473/#487): didUpdateWidget must re-push the count and default
      // the cursor onto the replacement controller — exactly as initState
      // does — or the lazy render object reads itemCount == 0, unmounts every
      // row, and stays blank until some later itemCount change. Prior tests
      // only assert the controller's mirror fields; this pins the actual frame
      // and that arrow nav survives.
      var controller = ListController(initialIndex: 0);
      Widget app(ListController? c) => SizedBox(
        width: 12,
        height: 4,
        child: ListView.builder(
          controller: c,
          itemCount: 5,
          autofocus: true,
          itemBuilder: (context, index, highlighted) => Text('Item $index'),
        ),
      );

      tester.pumpWidget(app(controller));
      expect(
        tester.renderToString(size: const CellSize(12, 4), emptyMark: ' '),
        contains('Item 0'),
      );

      // (1) Swap to a *different* controller instance, itemCount unchanged.
      controller = ListController(initialIndex: 0);
      tester.pumpWidget(app(controller));
      expect(
        tester.renderToString(size: const CellSize(12, 4), emptyMark: ' '),
        contains('Item 0'),
        reason: 'a fresh controller instance must not blank the lazy list',
      );
      expect(controller.itemCount, 5);

      // Keyboard nav is alive on the swapped-in controller.
      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.currentIndex, 1);

      // (2) Drop the controller entirely — the state builds its own fallback.
      tester.pumpWidget(app(null));
      expect(
        tester.renderToString(size: const CellSize(12, 4), emptyMark: ' '),
        contains('Item 0'),
        reason:
            'dropping the controller for the internal fallback must not '
            'blank the list',
      );
    });
  });

  group('empty list', () {
    testWidgets('itemCount 0 ignores arrow chords', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 0,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.currentIndex, isNull);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.currentIndex, isNull);
    });

    testWidgets('a list populated after mounting restores its default cursor', (
      tester,
    ) {
      var count = 0;
      final controller = ListController();

      Widget app() => ListView.builder(
        controller: controller,
        itemCount: count,
        itemBuilder: _itemBuilder,
      );

      tester.pumpWidget(app());
      expect(controller.currentIndex, isNull);
      count = 3;
      tester.pumpWidget(app());
      expect(controller.currentIndex, 0);
    });

    testWidgets('an explicitly cleared cursor stays in scroll-only mode', (
      tester,
    ) {
      var count = 2;
      final controller = ListController();

      Widget app() => ListView.builder(
        controller: controller,
        itemCount: count,
        itemBuilder: _itemBuilder,
      );

      tester.pumpWidget(app());
      controller.currentIndex = null;
      count = 3;
      tester.pumpWidget(app());
      expect(controller.currentIndex, isNull);
    });
  });

  group('unbounded height (L)', () {
    // A ListView windows its items to the viewport height. Under an unbounded
    // maxRows (a ScrollView, or a mainAxisSize.min Column/Row child) there is
    // no window to fill, so every item would silently vanish. The list must
    // fail loudly — like Scrollbar under unbounded width — instead of dropping
    // content with no diagnostic.
    Matcher throwsUnboundedHeight() => throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        allOf(contains('ListView'), contains('bounded height')),
      ),
    );

    testWidgets('eager ListView under a ScrollView throws instead of '
        'rendering nothing', (tester) {
      tester.mountWidget(
        ScrollView(
          child: ListView(
            children: [for (var i = 0; i < 5; i++) Text('item $i')],
          ),
        ),
      );
      expect(
        () => tester.render(size: const CellSize(20, 8)),
        throwsUnboundedHeight(),
      );
    });

    testWidgets('lazy ListView.builder under a ScrollView throws instead of '
        'rendering nothing', (tester) {
      tester.mountWidget(
        ScrollView(
          child: ListView.builder(itemCount: 5, itemBuilder: _itemBuilder),
        ),
      );
      expect(
        () => tester.render(size: const CellSize(20, 8)),
        throwsUnboundedHeight(),
      );
    });

    testWidgets('the reported nested-Column scenario fails loudly rather than '
        'silently dropping the list', (tester) {
      // ScrollView > Column(min) > [header, ListView, footer]: the ScrollView
      // measures the Column with an unbounded main axis, so the nested list
      // receives maxRows == null.
      tester.mountWidget(
        ScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('header'),
              ListView.builder(itemCount: 5, itemBuilder: _itemBuilder),
              const Text('footer'),
            ],
          ),
        ),
      );
      expect(
        () => tester.render(size: const CellSize(20, 8)),
        throwsUnboundedHeight(),
      );
    });

    testWidgets('an empty list under unbounded height renders empty, not a '
        'throw — there is no content to lose', (tester) {
      tester.pumpWidget(
        ScrollView(
          child: ListView.builder(itemCount: 0, itemBuilder: _itemBuilder),
        ),
      );
      expect(() => tester.render(size: const CellSize(20, 8)), returnsNormally);
    });
  });

  group('external focusNode', () {
    testWidgets('uses the supplied node so parents can drive focus', (tester) {
      final focusNode = FocusNode(debugLabel: 'external');
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          focusNode: focusNode,
          itemCount: 3,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(focusNode.hasFocus, isFalse);

      focusNode.requestFocus();
      expect(focusNode.hasFocus, isTrue);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.currentIndex, 1);
    });

    testWidgets('current row stays highlighted when focus moves outside', (
      tester,
    ) {
      final controller = ListController();
      final outside = FocusNode(debugLabel: 'outside');
      tester.pumpWidget(
        Row(
          children: [
            SizedBox(
              width: 12,
              child: ListView.builder(
                controller: controller,
                itemCount: 3,
                autofocus: true,
                itemBuilder: (context, index, highlighted) =>
                    Text('${highlighted ? '>' : ' '} Item $index'),
              ),
            ),
            Focus(focusNode: outside, child: const Text('Outside')),
          ],
        ),
      );

      var output = tester.renderToString(
        size: const CellSize(40, 4),
        emptyMark: ' ',
      );
      expect(output, contains('> Item 0'));

      outside.requestFocus();
      tester.pump();
      output = tester.renderToString(
        size: const CellSize(40, 4),
        emptyMark: ' ',
      );
      expect(controller.currentIndex, 0);
      expect(outside.hasFocus, isTrue);
      expect(output, contains('> Item 0'));
      expect(output, contains('Item 0'));

      outside.dispose();
    });
  });

  group('PageUp / PageDown', () {
    testWidgets('PageDown advances by the visible page size', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));
      expect(controller.currentIndex, 0);

      tester.sendKey(_code(KeyCode.pageDown));
      // Viewport is 5 rows of 1-row items, so page = 5.
      expect(controller.currentIndex, 5);
    });

    testWidgets('PageUp moves back by the page size', (tester) {
      final controller = ListController(initialIndex: 20);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));

      tester.sendKey(_code(KeyCode.pageUp));
      expect(controller.currentIndex, 15);
    });

    testWidgets('PageDown clamps at the last item', (tester) {
      final controller = ListController(initialIndex: 97);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));

      tester.sendKey(_code(KeyCode.pageDown));
      expect(controller.currentIndex, 99);
    });

    testWidgets('PageDown at the last item respects edgeBehavior bubble', (
      tester,
    ) {
      var bubbled = 0;
      final controller = ListController(initialIndex: 2);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.pageDown, onTrigger: (_) => bubbled += 1),
          ],
          child: ListView.builder(
            controller: controller,
            itemCount: 3,
            itemBuilder: _itemBuilder,
            autofocus: true,
            edgeBehavior: EdgeBehavior.bubble,
          ),
        ),
      );
      tester.sendKey(_code(KeyCode.pageDown));
      expect(bubbled, 1);
    });
  });

  group('tail clamp — the anchor never sits past the last full page', () {
    // A scroll-only list (no cursor) that follows its tail used to anchor
    // the NEWEST item at the top of the viewport: every frame showed exactly
    // one item over a blank screen, forever, for a tailing log — a documented
    // configuration. The "cursor below the viewport" re-anchor only ran
    // when there was a cursor. The viewport now re-anchors whenever the
    // forward walk runs out of items with rows to spare.
    testWidgets('a scroll-only list following its tail shows a full last '
        'page (lazy)', (tester) {
      final controller = ListController();
      Widget list(int count) => ListView.builder(
        controller: controller,
        itemCount: count,
        itemBuilder: _itemBuilder,
      );
      tester.pumpWidget(list(20));
      tester.render(size: const CellSize(20, 5));
      controller.currentIndex = null; // scroll-only
      controller.followTail = true; // follow the tail
      tester.render(size: const CellSize(20, 5));
      expect(controller.visibleRange, (first: 15, last: 19));

      // A new item arrives: still a full page, ending at the new tail.
      tester.pumpWidget(list(21));
      tester.render(size: const CellSize(20, 5));
      expect(controller.visibleRange, (first: 16, last: 20));
    });

    testWidgets('a scroll-only list following its tail shows a full last '
        'page (eager)', (tester) {
      final controller = ListController();
      Widget list(int count) => ListView(
        controller: controller,
        children: [for (var i = 0; i < count; i++) Text('item $i')],
      );
      tester.pumpWidget(list(20));
      tester.render(size: const CellSize(20, 5));
      controller.currentIndex = null;
      controller.jumpToBottom();
      tester.render(size: const CellSize(20, 5));
      expect(controller.visibleRange, (first: 15, last: 19));
    });

    testWidgets('jumpToIndex near the end clamps to the last full page', (
      tester,
    ) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render(size: const CellSize(20, 5));
      controller.jumpToIndex(18);
      tester.render(size: const CellSize(20, 5));
      expect(controller.visibleRange, (first: 15, last: 19));
    });

    testWidgets('a viewport that grows taller re-fills from the tail', (
      tester,
    ) {
      final controller = ListController(initialIndex: 19);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render(size: const CellSize(20, 5));
      expect(controller.visibleRange, (first: 15, last: 19));
      tester.render(size: const CellSize(20, 8));
      expect(controller.visibleRange, (first: 12, last: 19));
    });
  });

  group('followTail', () {
    testWidgets('following appends preserves the current item', (tester) {
      final controller = ListController(followTail: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(
        controller.currentIndex,
        0,
        reason: 'following scrolls without selecting a different item',
      );
      expect(controller.atBottom, isTrue);

      // Simulate a new message arriving.
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(
        controller.currentIndex,
        0,
        reason: 'following does not advance the cursor',
      );
    });

    testWidgets('default off: appending items does not move the '
        'cursor', (tester) {
      final controller = ListController(); // followTail defaults to false
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(controller.currentIndex, 0);

      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(
        controller.currentIndex,
        0,
        reason: 'appending never changes the current item',
      );
    });

    testWidgets('itemCount shrinking clamps cursor', (tester) {
      final controller = ListController(initialIndex: 3, followTail: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(controller.currentIndex, 3);

      // Shrinking clamps the current item to a surviving index. But the existing cursor gets clamped to 1 (new
      // last index).
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 2,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(controller.currentIndex, 1);
    });
  });

  // Viewport-based following (including passive lists and oversized items)
  // is exercised for both renderers in list_view_dx_test.dart.

  group('lazy ListView.builder', () {
    testWidgets('duplicate offscreen keys fail before mounting rows', (tester) {
      var rowsBuilt = 0;
      expect(
        () => tester.pumpWidget(
          ListView.builder(
            itemCount: 100,
            itemKeyBuilder: (index) => index == 99 ? 98 : index,
            itemBuilder: (context, index, highlighted) {
              rowsBuilt++;
              return Text('item $index');
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('indices 98 and 99'),
          ),
        ),
      );
      expect(rowsBuilt, 0);
    });

    testWidgets('itemBuilder is only invoked for visible items', (tester) {
      final builtIndices = <int>[];
      Widget builder(BuildContext context, int i, bool highlighted) {
        builtIndices.add(i);
        return Text('Item $i');
      }

      tester.viewportSize = const CellSize(10, 5);
      tester.pumpWidget(
        ListView.builder(itemCount: 1000, itemBuilder: builder),
      );
      tester.render(size: const CellSize(10, 5));

      // 1000 items in the list, viewport is 5 rows, items are 1 row each.
      // Only the visible window (plus what the auto-scroll-to-cursor
      // probe touches) should be built.
      expect(
        builtIndices.length,
        lessThan(20),
        reason:
            'Expected ~5 visible items built, got '
            '${builtIndices.length}',
      );
      // Specifically: indices 0..4 should be among the builds.
      expect(builtIndices.toSet(), containsAll([0, 1, 2, 3, 4]));
      // And 999 (out of view) should NOT be built.
      expect(builtIndices, isNot(contains(999)));
    });

    testWidgets('mounted items unmount when they scroll out of view', (tester) {
      final mountCounts = <int, int>{};
      final unmountCounts = <int, int>{};
      final controller = ListController();
      tester.viewportSize = const CellSize(10, 5);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (ctx, i, sel) => _LifecycleWidget(
            index: i,
            mounts: mountCounts,
            unmounts: unmountCounts,
          ),
        ),
      );
      tester.render(size: const CellSize(10, 5));
      // Items 0..4 are visible and mounted; nothing else.
      expect(mountCounts.keys, containsAll([0, 1, 2, 3, 4]));
      expect(unmountCounts, isEmpty);

      // Jump to a far-away region.
      controller.jumpToIndex(50);
      tester.render(size: const CellSize(10, 5));

      // Items 0..4 should now be unmounted; 50..54 mounted.
      for (var i = 0; i < 5; i++) {
        expect(
          unmountCounts[i],
          1,
          reason: 'item $i should have unmounted exactly once',
        );
      }
      expect(mountCounts.keys, containsAll([50, 51, 52, 53, 54]));
    });

    testWidgets('a non-fitting anchor probe is unmounted after layout', (
      tester,
    ) {
      final mountCounts = <int, int>{};
      final unmountCounts = <int, int>{};
      final controller = ListController();
      tester.viewportSize = const CellSize(10, 5);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 30,
          itemBuilder: (context, index, highlighted) => _LifecycleWidget(
            index: index,
            mounts: mountCounts,
            unmounts: unmountCounts,
          ),
        ),
      );
      tester.render(size: const CellSize(10, 5));

      controller.currentIndex = 10;
      tester.render(size: const CellSize(10, 5));

      expect(controller.visibleRange, (first: 6, last: 10));
      final mounted = {
        for (final e in mountCounts.entries)
          if (e.value > (unmountCounts[e.key] ?? 0)) e.key,
      };
      expect(
        mounted,
        {6, 7, 8, 9, 10},
        reason:
            'only the final viewport remains mounted, including after probes',
      );
    });

    testWidgets('a following list does not leak its pre-jump first-walk window '
        'on the first layout (L)', (tester) {
      // Starting at the tail must leave only the final viewport mounted,
      // including any items visited while measuring the bottom alignment.
      final mountCounts = <int, int>{};
      final unmountCounts = <int, int>{};
      final controller = ListController(followTail: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 1000,
          itemBuilder: (context, index, highlighted) => _LifecycleWidget(
            index: index,
            mounts: mountCounts,
            unmounts: unmountCounts,
          ),
        ),
      );
      tester.render(size: const CellSize(10, 10));

      expect(controller.currentIndex, 0);
      expect(controller.visibleRange, (first: 990, last: 999));

      // Net-mounted = mounted but not (yet) unmounted. Only the visible tail
      // window may remain; the first walk (0..9) and the probe boundary (989)
      // must all have been swept.
      final netMounted = {
        for (final entry in mountCounts.entries)
          if (entry.value > (unmountCounts[entry.key] ?? 0)) entry.key,
      };
      expect(
        netMounted,
        {for (var i = 990; i <= 999; i++) i},
        reason:
            'only the visible tail window stays mounted; the pre-jump '
            'first walk (0..9) and the probe boundary (989) must not leak',
      );
    });

    testWidgets('highlight styling updates mounted items without '
        'remounting', (tester) {
      final mountCounts = <int, int>{};
      final unmountCounts = <int, int>{};
      final lastHighlighted = <int, bool>{};
      Widget builder(BuildContext context, int i, bool highlighted) {
        lastHighlighted[i] = highlighted;
        return _LifecycleWidget(
          index: i,
          mounts: mountCounts,
          unmounts: unmountCounts,
        );
      }

      final controller = ListController();
      tester.viewportSize = const CellSize(10, 5);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: builder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));
      expect(lastHighlighted[0], isTrue);
      final initialMounts = Map<int, int>.from(mountCounts);

      // Move the cursor within the visible window.
      tester.sendKey(_code(KeyCode.arrowDown));
      tester.render(size: const CellSize(10, 5));

      // Items shouldn't have remounted — the lazy element updates
      // existing children with new widgets reflecting the new
      // `highlighted` flag.
      expect(mountCounts, initialMounts);
      expect(unmountCounts, isEmpty);
      expect(lastHighlighted[0], isFalse);
      expect(lastHighlighted[1], isTrue);
    });

    testWidgets('keyed prepend preserves the cursor, viewport, and row state', (
      tester,
    ) {
      var items = <String>['a', 'b', 'c', 'd'];
      final controller = ListController(initialIndex: 1);
      final mounts = <String, int>{};
      final unmounts = <String, int>{};

      Widget app() => SizedBox(
        width: 12,
        height: 2,
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          itemKeyBuilder: (index) => items[index],
          itemBuilder: (context, index, highlighted) => _KeyedLifecycleWidget(
            id: items[index],
            mounts: mounts,
            unmounts: unmounts,
          ),
        ),
      );

      tester.mountWidget(app());
      controller.jumpToIndex(1);
      expect(tester.renderToString(size: const CellSize(12, 2)), 'b:b\nc:c\n');
      expect(controller.visibleRange, (first: 1, last: 2));

      items = ['x', ...items];
      tester.pumpWidget(app());

      expect(tester.renderToString(size: const CellSize(12, 2)), 'b:b\nc:c\n');
      expect(controller.currentIndex, 2, reason: 'the current key is b');
      expect(controller.visibleRange, (first: 2, last: 3));
      expect(controller.unseenCount, 0, reason: 'a prepend is not tail growth');
      expect(mounts['b'], 1);
      expect(mounts['c'], 1);
      expect(unmounts, isEmpty);

      items = [...items, 'e'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));
      expect(controller.currentIndex, 2);
      expect(controller.unseenCount, 1, reason: 'only the true append is new');
    });

    testWidgets('keyed reorder preserves the current data item', (tester) {
      var items = <String>['a', 'b', 'c', 'd'];
      final controller = ListController(initialIndex: 2);

      Widget app() => SizedBox(
        width: 12,
        height: 4,
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          itemKeyBuilder: (index) => items[index],
          itemBuilder: (context, index, highlighted) => Text(items[index]),
        ),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 4));
      items = ['c', 'a', 'd', 'b'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 4));

      expect(controller.currentIndex, 0, reason: 'the current key remains c');
      expect(controller.unseenCount, 0);
    });

    testWidgets(
      'keyed reorder preserves the cursor while viewport keeps following',
      (tester) {
        var items = <String>['a', 'b', 'c'];
        final controller = ListController(initialIndex: 2, followTail: true);

        Widget app() => _keyedStringList(items, controller: controller);

        tester.pumpWidget(app());
        tester.render(size: const CellSize(12, 3));
        expect(controller.currentIndex, 2);
        expect(controller.isFollowing, isTrue);
        expect(controller.atBottom, isTrue);

        items = ['c', 'a', 'b'];
        tester.pumpWidget(app());
        tester.render(size: const CellSize(12, 3));

        expect(controller.currentIndex, 0, reason: 'current identity is c');
        expect(
          controller.isFollowing,
          isTrue,
          reason:
              'following describes the viewport, independently of the cursor',
        );
        expect(controller.atBottom, isTrue);
        expect(controller.unseenCount, 0);

        items = [...items, 'd'];
        tester.pumpWidget(app());

        expect(controller.currentIndex, 0, reason: 'append does not yank c');
        expect(controller.unseenCount, 0);
      },
    );

    testWidgets('a keyed rolling window (drop oldest, append newest) keeps '
        'following', (tester) {
      // A capped transcript or log: every arrival evicts the oldest item, so
      // the count never changes. Classifying growth by net count reported
      // zero, and the reorder guard then read the followed item's new
      // second-to-last index as "left the tail" — follow died on the FIRST
      // eviction, silently, with unseenCount stuck at 0.
      var items = <String>['a', 'b', 'c'];
      final controller = ListController(initialIndex: 2, followTail: true);

      Widget app() => _keyedStringList(items, controller: controller);

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      expect(controller.currentIndex, 2);
      expect(controller.isFollowing, isTrue);

      items = ['b', 'c', 'd'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      expect(
        controller.isFollowing,
        isTrue,
        reason: 'an eviction is not a reorder',
      );
      expect(controller.currentIndex, 1, reason: 'cursor remains on c');
      expect(controller.atBottom, isTrue);
      expect(controller.unseenCount, 0);

      items = ['c', 'd', 'e'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      expect(controller.isFollowing, isTrue, reason: 'and stays engaged');
      expect(controller.currentIndex, 0, reason: 'cursor remains on c');
    });

    testWidgets('a keyed rolling window while NOT following counts the '
        'arrival', (tester) {
      var items = <String>['a', 'b', 'c'];
      final controller = ListController(initialIndex: 1);

      Widget app() =>
          _keyedStringList(items, controller: controller, height: 2);

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      expect(controller.isFollowing, isFalse);

      items = ['b', 'c', 'd'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      expect(controller.currentIndex, 0, reason: 'current identity is b');
      expect(controller.isFollowing, isFalse);
      expect(controller.unseenCount, 1, reason: 'd arrived at the tail');
    });

    testWidgets('keyed scroll-only pin remains on the current tail', (tester) {
      var items = <String>['a', 'b', 'c'];
      final controller = ListController(followTail: true);

      Widget app() =>
          _keyedStringList(items, controller: controller, height: 2);

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));
      controller.currentIndex = null;
      tester.render(size: const CellSize(12, 2));
      expect(controller.isFollowing, isTrue);
      expect(controller.atBottom, isTrue);

      items = ['c', 'a', 'b'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));

      expect(controller.currentIndex, isNull);
      expect(controller.isFollowing, isTrue);
      expect(controller.atBottom, isTrue);
      expect(controller.visibleRange?.last, 2);
    });

    testWidgets('removing the current key chooses its surviving successor', (
      tester,
    ) {
      var items = <String>['a', 'b', 'c'];
      final controller = ListController(initialIndex: 1);
      final mounts = <String, int>{};
      final unmounts = <String, int>{};

      Widget app() => _keyedStringList(
        items,
        controller: controller,
        itemBuilder: (context, index, highlighted) => _KeyedLifecycleWidget(
          id: items[index],
          mounts: mounts,
          unmounts: unmounts,
        ),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      items = ['a', 'c'];
      tester.pumpWidget(app());

      expect(controller.currentIndex, 1, reason: 'c succeeds the removed b');
      expect(
        tester.renderToString(size: const CellSize(12, 3)),
        'a:a\nc:c\n\n',
      );
      expect(mounts, {'a': 1, 'b': 1, 'c': 1});
      expect(unmounts, {'b': 1}, reason: 'removed row state is disposed');
    });

    testWidgets('keyed reorder moves mounted row State with data identity', (
      tester,
    ) {
      var items = <String>['a', 'b', 'c'];
      final mounts = <String, int>{};
      final unmounts = <String, int>{};

      Widget app() => _keyedStringList(
        items,
        itemBuilder: (context, index, highlighted) => _KeyedLifecycleWidget(
          id: items[index],
          mounts: mounts,
          unmounts: unmounts,
        ),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      items = ['a', 'c', 'b'];
      tester.pumpWidget(app());

      expect(
        tester.renderToString(size: const CellSize(12, 3)),
        'a:a\nc:c\nb:b\n',
      );
      expect(
        tester
            .semantics()
            .where(role: SemanticRole.text)
            .map((node) => node.label),
        ['a:a', 'c:c', 'b:b'],
        reason: 'semantic traversal follows the reordered visual rows',
      );
      expect(mounts, {'a': 1, 'b': 1, 'c': 1});
      expect(unmounts, isEmpty);
    });

    testWidgets('pointer activation after reorder reports the current index', (
      tester,
    ) {
      var items = <String>['a', 'b', 'c'];
      final controller = ListController(initialIndex: 0);
      final chosenItems = <({int index, String id})>[];

      Widget app() => _keyedStringList(
        items,
        controller: controller,
        onSelect: (index) => chosenItems.add((index: index, id: items[index])),
        itemBuilder: (context, index, highlighted) =>
            SizedBox(width: 12, height: 1, child: Text(items[index])),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      items = ['a', 'c', 'b'];
      tester.pumpWidget(app());
      expect(tester.renderToString(size: const CellSize(12, 3)), 'a\nc\nb\n');

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 1));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 1));

      expect(controller.currentIndex, 1);
      expect(chosenItems, [(index: 1, id: 'c')]);
    });

    testWidgets('explicit jump wins over keyed anchor preservation', (tester) {
      var items = <String>['a', 'b', 'c', 'd', 'e'];
      final controller = ListController(initialIndex: 2);

      Widget app() =>
          _keyedStringList(items, controller: controller, height: 2);

      tester.pumpWidget(app());
      controller.jumpToIndex(2);
      expect(tester.renderToString(size: const CellSize(12, 2)), 'c\nd\n');

      controller.jumpToIndex(0);
      items = ['x', ...items];
      tester.pumpWidget(app());

      expect(tester.renderToString(size: const CellSize(12, 2)), 'x\na\n');
      expect(controller.visibleRange, (first: 0, last: 1));
    });

    testWidgets('key snapshots refresh on data updates, not cursor or scroll', (
      tester,
    ) {
      final items = [for (var i = 0; i < 1000; i++) 'item-$i'];
      final controller = ListController(initialIndex: 2);
      var keysRead = 0;
      var rowsBuilt = 0;
      // Deliberately reuse the same closure and mutate the same collection.
      Object keyAt(int index) {
        keysRead++;
        return items[index];
      }

      Widget app() => SizedBox(
        width: 16,
        height: 5,
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          autofocus: true,
          itemKeyBuilder: keyAt,
          itemBuilder: (context, index, highlighted) {
            rowsBuilt++;
            return Text(items[index]);
          },
        ),
      );
      tester.pumpWidget(app());
      expect(keysRead, 1000);
      expect(rowsBuilt, lessThan(30), reason: 'row widgets stay lazy');
      keysRead = 0;
      tester.press(KeySequence.down);
      controller.jumpToIndex(500);
      tester.pump();
      expect(keysRead, 0, reason: 'cursor and viewport reuse the snapshot');

      items.insert(0, 'new');
      tester.pumpWidget(app());
      expect(keysRead, 1001, reason: 'each key is read once on data update');
      expect(controller.currentIndex, 4);
      expect(tester.renderToString(), contains('item-500'));
    });

    testWidgets('leaving and re-entering keyed mode remounts safely', (tester) {
      var items = <String>['a', 'b'];
      var keyed = true;
      final mounts = <String, int>{};
      final unmounts = <String, int>{};

      Widget app() => SizedBox(
        width: 12,
        height: 2,
        child: ListView.builder(
          itemCount: items.length,
          itemKeyBuilder: keyed ? (index) => items[index] : null,
          itemBuilder: (context, index, highlighted) => _KeyedLifecycleWidget(
            id: items[index],
            mounts: mounts,
            unmounts: unmounts,
          ),
        ),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));
      keyed = false;
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));

      items = ['b', 'a'];
      keyed = true;
      tester.pumpWidget(app());
      expect(tester.renderToString(size: const CellSize(12, 2)), 'b:b\na:a\n');
      expect(unmounts, {'a': 1, 'b': 1});
      expect(mounts, {'a': 2, 'b': 2});
    });
  });

  group('ListView.separated (F3)', () {
    // Single-line 'item{i}' rows and 'sep{i}' separators, so viewport row
    // math is easy to reason about in the assertions below.
    Widget itemB(BuildContext c, int i, bool highlighted) => Text('item$i');
    Widget? sepB(BuildContext c, int i) => Text('sep$i');

    List<String> nonEmptyRows(FleuryTester tester, CellSize size) => tester
        .renderToString(size: size)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();

    testWidgets('separators render beneath each item, none after the last', (
      tester,
    ) {
      tester.pumpWidget(
        ListView.separated(
          itemCount: 3,
          itemBuilder: itemB,
          separatorBuilder: sepB,
        ),
      );
      expect(nonEmptyRows(tester, const CellSize(8, 6)), [
        'item0',
        'sep0',
        'item1',
        'sep1',
        'item2',
      ]);
    });

    testWidgets('separatorBuilder is called per gap (0..count-2), never after '
        'the last item', (tester) {
      final gaps = <int>[];
      tester.pumpWidget(
        ListView.separated(
          itemCount: 3,
          itemBuilder: itemB,
          separatorBuilder: (c, i) {
            gaps.add(i);
            return Text('sep$i');
          },
        ),
      );
      tester.render(size: const CellSize(8, 10)); // all three items fit
      expect(gaps.toSet(), {0, 1});
      expect(gaps, isNot(contains(2)));
    });

    testWidgets('separators consume viewport rows, so fewer items fit', (
      tester,
    ) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.separated(
          controller: controller,
          itemCount: 20,
          itemBuilder: itemB,
          separatorBuilder: sepB,
        ),
      );
      // 5 rows: item0/sep0/item1/sep1/item2 — three items, last visible = 2.
      // (Plain .builder would show 0..4 in the same 5 rows.)
      tester.render(size: const CellSize(8, 5));
      expect(controller.visibleRange, (first: 0, last: 2));
    });

    testWidgets('a null separator is omitted for that gap', (tester) {
      tester.pumpWidget(
        ListView.separated(
          itemCount: 3,
          itemBuilder: itemB,
          // Separator only after item 0; the item1|item2 gap is null.
          separatorBuilder: (c, i) => i == 0 ? Text('sep$i') : null,
        ),
      );
      expect(nonEmptyRows(tester, const CellSize(8, 6)), [
        'item0',
        'sep0',
        'item1',
        'item2',
      ]);
    });

    testWidgets('arrow nav walks items only — separators never take the '
        'cursor', (tester) {
      final focusedItems = <int>[];
      final controller = ListController();
      tester.pumpWidget(
        ListView.separated(
          controller: controller,
          itemCount: 4,
          itemBuilder: itemB,
          separatorBuilder: sepB,
          autofocus: true,
          onSelect: focusedItems.add,
        ),
      );
      tester.render(size: const CellSize(8, 12)); // 4 items + 3 seps = 7 rows
      expect(controller.currentIndex, 0);
      // Each Down lands on the next item index — no half-step onto a separator.
      for (final expected in [1, 2, 3]) {
        tester.sendKey(_code(KeyCode.arrowDown));
        tester.render(size: const CellSize(8, 12));
        expect(controller.currentIndex, expected);
      }
      // At the last item, Down is an edge — no phantom trailing-separator row.
      tester.sendKey(_code(KeyCode.arrowDown));
      tester.render(size: const CellSize(8, 12));
      expect(controller.currentIndex, 3);
      // Enter reports the item index, not a separator position.
      tester.sendKey(_code(KeyCode.enter));
      expect(focusedItems, [3]);
    });

    testWidgets('separators and trailing space are inert; items select', (
      tester,
    ) {
      final chosenItems = <int>[];
      final controller = ListController(initialIndex: 1);
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 6,
          child: ListView.separated(
            controller: controller,
            itemCount: 3,
            onSelect: chosenItems.add,
            itemBuilder: (c, i, sel) =>
                SizedBox(width: 12, height: 1, child: Text('item$i')),
            separatorBuilder: (c, i) =>
                SizedBox(width: 12, height: 1, child: Text('sep$i')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 6));
      // Rows: 0 item0, 1 sep0, 2 item1, 3 sep1, 4 item2.
      // A separator neither moves the cursor nor selects a neighbor.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 1));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 1));
      expect(controller.currentIndex, 1);
      expect(chosenItems, isEmpty);
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 5));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 5));
      expect(controller.currentIndex, 1);
      expect(chosenItems, isEmpty);
      // The item on row 2 selects and fires onSelect(1) as usual.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));
      expect(controller.currentIndex, 1);
      expect(chosenItems, [1]);
    });

    testWidgets('separated clicks preserve completion and cancellation rules', (
      tester,
    ) {
      final controller = ListController();
      final chosenItems = <String>[];
      var items = ['a', 'b', 'c'];
      Widget app() => SizedBox(
        width: 12,
        height: 6,
        child: ListView.separated(
          controller: controller,
          itemCount: items.length,
          itemKeyBuilder: (index) => items[index],
          onSelect: (index) => chosenItems.add(items[index]),
          itemBuilder: (_, index, _) =>
              SizedBox(width: 12, height: 1, child: Text(items[index])),
          separatorBuilder: (_, _) => const SizedBox(height: 1),
        ),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 6));
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      expect(controller.currentIndex, 1);
      expect(chosenItems, isEmpty);
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 6));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));
      expect(chosenItems, ['b']);

      // Releasing over the separator cancels a press on the preceding item.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 0));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 1));
      expect(controller.currentIndex, 0);
      expect(chosenItems, ['b']);
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 0));
      tester.sendMouse(_mouse(MouseEventKind.cancel, 1, 0));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 0));
      expect(chosenItems, ['b']);

      // A replacement at the pressed index cannot inherit the old click.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      items = ['a', 'replacement', 'c'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 6));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));
      expect(chosenItems, ['b']);
    });

    testWidgets('an item in an overflowing separator block stays clickable at '
        'its real row', (tester) {
      // A tall separator after item 1 makes item1's composed block overflow the
      // viewport, so the block paints through RenderFlex's clip path. The item
      // must still register its tap region at its true screen row (regression:
      // the clip path dropped screenOffset, leaving item1 unclickable and its
      // phantom region stealing item0's clicks at the scratch origin).
      final chosenItems = <int>[];
      final controller = ListController(initialIndex: 0);
      tester.pumpWidget(
        SizedBox(
          width: 8,
          height: 6,
          child: ListView.separated(
            controller: controller,
            itemCount: 4,
            onSelect: chosenItems.add,
            itemBuilder: (c, i, sel) =>
                SizedBox(width: 8, height: 1, child: Text('i$i')),
            // Only item 1 gets a (tall) trailing separator, so its block
            // overflows; the others have none.
            separatorBuilder: (c, i) => i == 1
                ? const SizedBox(width: 8, height: 10, child: Text('sep'))
                : null,
          ),
        ),
      );
      tester.render(size: const CellSize(8, 6));
      // Layout: row 0 = i0, row 1 = i1, then sep1 overflows below.
      // Clicking item0's row selects item0 (no phantom steal from i1's block).
      tester.sendMouse(_mouse(MouseEventKind.down, 0, 0));
      tester.sendMouse(_mouse(MouseEventKind.up, 0, 0));
      expect(controller.currentIndex, 0);
      // Clicking item1's row selects item1 (clickable despite its overflow).
      tester.sendMouse(_mouse(MouseEventKind.down, 0, 1));
      tester.sendMouse(_mouse(MouseEventKind.up, 0, 1));
      expect(controller.currentIndex, 1);
      expect(chosenItems, [0, 1]);
    });

    testWidgets(
      'separated hit regions follow variable-height rows after scrolling and repaint',
      (tester) {
        final chosenItems = <int>[];
        final controller = ListController(initialIndex: 0);
        tester.pumpWidget(
          SizedBox(
            width: 12,
            height: 7,
            child: ListView.separated(
              controller: controller,
              itemCount: 20,
              onSelect: chosenItems.add,
              itemBuilder: (_, i, _) => SizedBox(
                height: i.isEven ? 2 : 1,
                width: 12,
                child: Text('item$i'),
              ),
              separatorBuilder: (_, _) =>
                  const SizedBox(height: 1, child: Text('---')),
            ),
          ),
        );
        tester.render(size: const CellSize(12, 7));
        controller.currentIndex = 2;
        controller.jumpToIndex(2);
        tester.render(size: const CellSize(12, 7));
        // Rows: item2 [0,1], separator [2], item3 [3], separator [4].
        // Repeating after repaint exercises cached item boundaries as well.
        for (var pass = 0; pass < 2; pass++) {
          for (final row in [2, 4]) {
            tester.sendMouse(_mouse(MouseEventKind.down, 5, row));
            tester.sendMouse(_mouse(MouseEventKind.up, 5, row));
          }
          expect(chosenItems, List.filled(pass, 3));
          tester.sendMouse(_mouse(MouseEventKind.down, 10, 3));
          tester.sendMouse(_mouse(MouseEventKind.up, 10, 3));
          expect(chosenItems, List.filled(pass + 1, 3));
          tester.render(size: const CellSize(12, 7));
        }
        controller.dispose();
      },
    );
  });

  group('ListView.builder at chat scale (F3 tall-row verification)', () {
    testWidgets('10k items: only the viewport window is built', (tester) {
      final built = <int>{};
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 10000,
          itemBuilder: (c, i, sel) {
            built.add(i);
            return Text('i$i');
          },
        ),
      );
      tester.render(size: const CellSize(8, 5));
      // Jump deep into the list; measure only what the jump mounts. (A jump
      // re-runs the outgoing window's builders once before layout moves on,
      // so `built` holds ~two windows — never all 10k.)
      built.clear();
      controller.jumpToIndex(9000);
      tester.render(size: const CellSize(8, 5));
      expect(
        built.length,
        lessThan(30),
        reason: 'lazy build must not visit all 10k items, saw ${built.length}',
      );
      expect(built, containsAll([9000, 9001, 9002, 9003, 9004]));
      // The mounted viewport moved to the target — index 0 is well out of view.
      expect(controller.visibleRange, (first: 9000, last: 9004));
    });

    testWidgets('a current item taller than the viewport is shown from its '
        'top without wedging the auto-scroll math', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 10000,
          itemBuilder: (c, i, sel) => SizedBox(
            width: 8,
            height: i == 5000 ? 8 : 1, // item 5000 is taller than the 5 rows
            child: Text('i$i'),
          ),
        ),
      );
      tester.render(size: const CellSize(8, 5));
      expect(controller.visibleRange, (first: 0, last: 4));

      // Move the cursor onto the oversized item, far below the fold.
      controller.currentIndex = 5000;
      tester.render(size: const CellSize(8, 5));

      // Graceful: the tall item anchors to the top and fills the viewport —
      // the "does the current item fit?" math resolves to a single-item window
      // instead of throwing or looping on an item bigger than the viewport.
      expect(controller.currentIndex, 5000);
      expect(controller.visibleRange, (first: 5000, last: 5000));
    });
  });

  group('auto repaint boundaries', () {
    // beginFrame flips a process-global; make sure it never leaks recording
    // into a later test in the same run.
    tearDown(() => RepaintBoundaryDebugStats.beginFrame(enabled: false));

    // Deterministic structural lock for the paint-walk win (no timing): with
    // per-item boundaries on by default, a localized update repaints exactly
    // the changed item and blits the rest from cache.
    testWidgets('a localized update repaints only the changed item', (tester) {
      final rows = [for (var i = 0; i < 6; i++) _Bump()];
      addTearDown(() {
        for (final n in rows) {
          n.dispose();
        }
      });
      tester.pumpWidget(
        ListView(
          children: [
            for (var i = 0; i < 6; i++)
              ListenableBuilder(
                listenable: rows[i],
                builder: (context, _) => Text('row $i = ${rows[i].value}'),
              ),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 6)); // warm every item's cache

      rows[2].bump(); // one row changes
      tester.owner.flushBuild();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(20, 6));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(stats.boundaryCount, 6, reason: 'each item is auto-wrapped');
      expect(
        stats.repaintedCount,
        1,
        reason: 'only the changed row repaints — the paint-walk win',
      );
      expect(stats.cachedCount, 5, reason: 'the rest blit from cache');
    });

    testWidgets('addRepaintBoundaries: false wraps nothing', (tester) {
      tester.pumpWidget(
        const ListView(
          addRepaintBoundaries: false,
          children: [Text('a'), Text('b'), Text('c')],
        ),
      );
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(10, 3));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        stats.boundaryCount,
        0,
        reason: 'the escape hatch inserts no boundaries',
      );
    });

    testWidgets('a cursor move repaints only the two affected rows', (tester) {
      // Cursor movement is the primary per-frame driver for keyboard-navigated
      // lists. Moving it re-invokes itemBuilder with a new `highlighted` flag for
      // exactly the old and new rows, so only those two boundaries repaint —
      // the rest of the visible window blits from cache.
      final controller = ListController(initialIndex: 0);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          autofocus: true,
          itemBuilder: (context, index, highlighted) => SizedBox(
            width: 10,
            height: 1,
            child: Text(highlighted ? '>item $index' : ' item $index'),
          ),
        ),
      );
      tester.render(size: const CellSize(10, 6)); // warm the visible caches

      controller.currentIndex =
          3; // highlight moves from 0 to 3 — two rows change
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(10, 6));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(
        stats.repaintedCount,
        2,
        reason: 'only the old and new highlighted rows repaint',
      );
      expect(
        stats.cachedCount,
        greaterThan(0),
        reason: 'the untouched visible rows blit from cache',
      );
    });
  });
}

/// A purpose-built ChangeNotifier for driving a per-row rebuild.
class _Bump extends ChangeNotifier {
  int value = 0;
  void bump() {
    value++;
    notifyListeners();
  }
}

/// Tracks mount/unmount per index for lazy-list lifecycle assertions.
class _LifecycleWidget extends StatefulWidget {
  const _LifecycleWidget({
    required this.index,
    required this.mounts,
    required this.unmounts,
  });
  final int index;
  final Map<int, int> mounts;
  final Map<int, int> unmounts;

  @override
  State<_LifecycleWidget> createState() => _LifecycleWidgetState();
}

class _LifecycleWidgetState extends State<_LifecycleWidget> {
  @override
  void initState() {
    super.initState();
    widget.mounts.update(widget.index, (v) => v + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    widget.unmounts.update(widget.index, (v) => v + 1, ifAbsent: () => 1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('item ${widget.index}');
}

class _KeyedLifecycleWidget extends StatefulWidget {
  const _KeyedLifecycleWidget({
    required this.id,
    required this.mounts,
    required this.unmounts,
  });

  final String id;
  final Map<String, int> mounts;
  final Map<String, int> unmounts;

  @override
  State<_KeyedLifecycleWidget> createState() => _KeyedLifecycleWidgetState();
}

class _KeyedLifecycleWidgetState extends State<_KeyedLifecycleWidget> {
  late final String mountedFor;

  @override
  void initState() {
    super.initState();
    mountedFor = widget.id;
    widget.mounts.update(widget.id, (value) => value + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    widget.unmounts.update(mountedFor, (value) => value + 1, ifAbsent: () => 1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('${widget.id}:$mountedFor');
}
