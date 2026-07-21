// ListView integration tests. Driven by FleuryTester so input
// dispatch + focus + rendering use the canonical test surface.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc) => KeyEvent(kc);

MouseEvent _mouse(MouseEventKind kind, int col, int row) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row);

Widget _itemBuilder(BuildContext context, int index, bool selected) {
  return Text('Item $index');
}

Widget _keyedStringList(
  List<String> items, {
  ListController? controller,
  int height = 3,
  void Function(int)? onActivate,
  Widget Function(BuildContext, int, bool)? itemBuilder,
}) {
  final indexByKey = <String, int>{
    for (var index = 0; index < items.length; index++) items[index]: index,
  };
  return SizedBox(
    width: 12,
    height: height,
    child: ListView.builder(
      controller: controller,
      itemCount: items.length,
      itemKeyBuilder: (index) => items[index],
      findChildIndexCallback: (key) => indexByKey[key],
      onActivate: onActivate,
      itemBuilder:
          itemBuilder ?? (context, index, selected) => Text(items[index]),
    ),
  );
}

void main() {
  group('pointer selection', () {
    testWidgets('tapping an item selects it and fires onActivate', (tester) {
      final controller = ListController(selectedIndex: 0);
      final activated = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 4,
          child: ListView.builder(
            controller: controller,
            itemCount: 4,
            onActivate: activated.add,
            itemBuilder: (context, index, selected) =>
                SizedBox(width: 12, height: 1, child: Text('item $index')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 4)); // register gesture regions

      // Tap the third row (index 2): press + release in the same cell.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));

      expect(controller.selectedIndex, 2);
      expect(activated, [2]);
    });

    testWidgets('tap survives a rebuild between press and release', (tester) {
      // Over the serve wire, down and up arrive in separate frames, and the
      // press triggers a click-to-focus rebuild in between — which recreates
      // the lazy list's item render objects. Acting on the press (not a
      // release-time identity match) keeps the selection working anyway.
      final controller = ListController(selectedIndex: 0);
      final activated = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 4,
          child: ListView.builder(
            controller: controller,
            itemCount: 4,
            onActivate: activated.add,
            itemBuilder: (context, index, selected) =>
                SizedBox(width: 12, height: 1, child: Text('item $index')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 4));

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.pump(); // full rebuild between down and up, as serve does
      tester.render(size: const CellSize(12, 4));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));

      expect(controller.selectedIndex, 2);
      expect(activated, [2]);
    });

    testWidgets('a drag wiggle between press and release still taps', (tester) {
      // A real mouse click in the browser client emits a tiny drag between
      // pointerdown and pointerup. That wiggle must not suppress the tap.
      final controller = ListController(selectedIndex: 0);
      final activated = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 4,
          child: ListView.builder(
            controller: controller,
            itemCount: 4,
            onActivate: activated.add,
            itemBuilder: (context, index, selected) =>
                SizedBox(width: 12, height: 1, child: Text('item $index')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 4));

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.sendMouse(_mouse(MouseEventKind.drag, 1, 2)); // wiggle, same cell
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));

      expect(controller.selectedIndex, 2);
      expect(activated, [2]);
    });
  });

  group('selection movement', () {
    testWidgets('arrowDown advances selectedIndex', (tester) {
      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.selectedIndex, 0);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.selectedIndex, 1);
      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.selectedIndex, 2);
    });

    testWidgets('arrowUp decrements selectedIndex', (tester) {
      final controller = ListController(selectedIndex: 3);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.selectedIndex, 3);

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(controller.selectedIndex, 2);
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
      expect(controller.selectedIndex, 7);
      tester.sendKey(_code(KeyCode.home));
      expect(controller.selectedIndex, 0);
    });

    testWidgets('Enter fires onActivate with the current index', (tester) {
      int? selected;
      tester.pumpWidget(
        ListView.builder(
          itemCount: 3,
          itemBuilder: _itemBuilder,
          autofocus: true,
          onActivate: (i) => selected = i,
        ),
      );

      tester.sendKey(_code(KeyCode.arrowDown));
      tester.sendKey(_code(KeyCode.enter));
      expect(selected, 1);
    });

    testWidgets('selection movement and activation are separate events', (
      tester,
    ) {
      final controller = ListController(selectedIndex: 0);
      final selections = <int>[];
      final activations = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 3,
          child: ListView.builder(
            controller: controller,
            itemCount: 3,
            autofocus: true,
            onSelectionChanged: selections.add,
            onActivate: activations.add,
            itemBuilder: (context, index, selected) => Text('item $index'),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 3));

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(selections, [1]);
      expect(activations, isEmpty);

      tester.sendKey(_code(KeyCode.enter));
      expect(selections, [1]);
      expect(activations, [1]);

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      expect(selections, [1, 2]);
      expect(activations, [1, 2]);

      controller.selectedIndex = 0;
      expect(selections, [
        1,
        2,
      ], reason: 'programmatic selection is not reported as user input');
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
            KeyBinding(KeyCode.arrowUp, onTrigger: () => bubbled += 1),
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
            KeyBinding(KeyCode.arrowUp, onTrigger: () => bubbled += 1),
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
      final controller = ListController(selectedIndex: 2);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.arrowDown, onTrigger: () => bubbled += 1),
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

    testWidgets('selection moving past the bottom scrolls the viewport', (
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
      expect(controller.visibleRange, (first: 0, last: 4));

      controller.selectedIndex = 6;
      tester.render(size: const CellSize(10, 5));
      expect(controller.selectedIndex, 6);
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
      final activated = <int>[];
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 5,
          child: ListView.builder(
            controller: controller,
            itemCount: 20,
            onActivate: activated.add,
            autofocus: true,
            itemBuilder: (context, index, selected) =>
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
      controller.selectedIndex = 6;
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
      expect(controller.selectedIndex, 2);
      expect(activated, [2]);
    });

    testWidgets('selection moving above the top scrolls back up', (tester) {
      final controller = ListController(selectedIndex: 10);
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

      controller.selectedIndex = 4;
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
      expect(controller.selectedIndex, 1);
    });

    testWidgets('itemCount change clamps the existing selection', (tester) {
      final controller = ListController(selectedIndex: 9);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 10,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.selectedIndex, 9);

      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      expect(controller.selectedIndex, 2);
    });

    testWidgets('swapping controllers attaches without counting arrivals', (
      tester,
    ) {
      var controller = ListController(selectedIndex: 3);

      Widget app() => ListView.builder(
        controller: controller,
        itemCount: 5,
        itemBuilder: _itemBuilder,
      );

      tester.pumpWidget(app());
      expect(controller.itemCount, 5);
      expect(controller.unseenCount, 0);

      controller = ListController(selectedIndex: 2);
      tester.pumpWidget(app());

      expect(controller.itemCount, 5);
      expect(controller.selectedIndex, 2);
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
      // the selection onto the replacement controller — exactly as initState
      // does — or the lazy render object reads itemCount == 0, unmounts every
      // row, and stays blank until some later itemCount change. Prior tests
      // only assert the controller's mirror fields; this pins the actual frame
      // and that arrow nav survives.
      var controller = ListController(selectedIndex: 0);
      Widget app(ListController? c) => SizedBox(
        width: 12,
        height: 4,
        child: ListView.builder(
          controller: c,
          itemCount: 5,
          autofocus: true,
          itemBuilder: (context, index, selected) => Text('Item $index'),
        ),
      );

      tester.pumpWidget(app(controller));
      expect(
        tester.renderToString(size: const CellSize(12, 4), emptyMark: ' '),
        contains('Item 0'),
      );

      // (1) Swap to a *different* controller instance, itemCount unchanged.
      controller = ListController(selectedIndex: 0);
      tester.pumpWidget(app(controller));
      expect(
        tester.renderToString(size: const CellSize(12, 4), emptyMark: ' '),
        contains('Item 0'),
        reason: 'a fresh controller instance must not blank the lazy list',
      );
      expect(controller.itemCount, 5);

      // Keyboard nav is alive on the swapped-in controller.
      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.selectedIndex, 1);

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
      expect(controller.selectedIndex, isNull);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.selectedIndex, isNull);
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
      expect(controller.selectedIndex, isNull);
      count = 3;
      tester.pumpWidget(app());
      expect(controller.selectedIndex, 0);
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
      controller.selectedIndex = null;
      count = 3;
      tester.pumpWidget(app());
      expect(controller.selectedIndex, isNull);
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
      tester.pumpWidget(
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
      tester.pumpWidget(
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
      tester.pumpWidget(
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
      expect(controller.selectedIndex, 1);
    });

    testWidgets('builder selected flag is active only while list is focused', (
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
                itemBuilder: (context, index, selected) =>
                    Text('${selected ? '>' : ' '} Item $index'),
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
      expect(controller.selectedIndex, 0);
      expect(output, isNot(contains('> Item 0')));
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
      expect(controller.selectedIndex, 0);

      tester.sendKey(_code(KeyCode.pageDown));
      // Viewport is 5 rows of 1-row items, so page = 5.
      expect(controller.selectedIndex, 5);
    });

    testWidgets('PageUp moves back by the page size', (tester) {
      final controller = ListController(selectedIndex: 20);
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
      expect(controller.selectedIndex, 15);
    });

    testWidgets('PageDown clamps at the last item', (tester) {
      final controller = ListController(selectedIndex: 97);
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
      expect(controller.selectedIndex, 99);
    });

    testWidgets('PageDown at the last item respects edgeBehavior bubble', (
      tester,
    ) {
      var bubbled = 0;
      final controller = ListController(selectedIndex: 2);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.pageDown, onTrigger: () => bubbled += 1),
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

  group('pinToBottom', () {
    testWidgets('appending items moves the selection to the new last '
        'item', (tester) {
      final controller = ListController(pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(
        controller.selectedIndex,
        2,
        reason: 'following starts on the tail (following implies at-bottom)',
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
        controller.selectedIndex,
        4,
        reason: 'pinToBottom should advance to new last item',
      );
    });

    testWidgets('default off: appending items does not move the '
        'selection', (tester) {
      final controller = ListController(); // pinToBottom defaults to false
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(controller.selectedIndex, 0);

      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(
        controller.selectedIndex,
        0,
        reason: 'without pinToBottom the cursor stays where it was',
      );
    });

    testWidgets('itemCount shrinking does not trigger pinToBottom', (tester) {
      final controller = ListController(selectedIndex: 3, pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(controller.selectedIndex, 3);

      // Shrink. pinToBottom should NOT advance — count went down,
      // not up. But the existing selection gets clamped to 1 (new
      // last index).
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 2,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(controller.selectedIndex, 1);
    });
  });

  group('tail-follow (F2)', () {
    testWidgets('scrolling off the tail unpins and counts arrivals; '
        'jumpToBottom catches up', (tester) {
      final controller = ListController(pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(controller.selectedIndex, 4);
      expect(controller.pinToBottom, isTrue);
      expect(controller.atBottom, isTrue);

      // User scrolls up to read history — moving off the tail stops following.
      controller.selectedIndex = 1;
      expect(controller.pinToBottom, isFalse);
      expect(controller.atBottom, isFalse);

      // New items arrive while unfollowed: the cursor stays put (no yank) and
      // the arrivals are counted.
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 8,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(controller.selectedIndex, 1, reason: 'no yank while reading');
      expect(controller.unseenCount, 3);
      expect(controller.pinToBottom, isFalse);

      // Catch up.
      controller.jumpToBottom();
      expect(controller.selectedIndex, 7);
      expect(controller.pinToBottom, isTrue);
      expect(controller.unseenCount, 0);
      expect(controller.atBottom, isTrue);
    });

    testWidgets('returning the cursor to the tail re-pins and clears unseen', (
      tester,
    ) {
      final controller = ListController(pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();

      controller.selectedIndex = 2; // scroll up → unpin
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 7,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(controller.unseenCount, 2);
      expect(controller.pinToBottom, isFalse);

      // Cursor back to the last item → re-pin, unseen cleared.
      controller.selectedIndex = 6;
      expect(controller.pinToBottom, isTrue);
      expect(controller.unseenCount, 0);
      expect(controller.atBottom, isTrue);

      // Subsequent appends follow again.
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 9,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(controller.selectedIndex, 8);
      expect(controller.unseenCount, 0);
    });

    testWidgets('unseenCount stays zero while following', (tester) {
      final controller = ListController(pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 6,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(controller.selectedIndex, 5);
      expect(controller.unseenCount, 0, reason: 'following → nothing unseen');
    });

    testWidgets('a non-following list is NOT dragged into follow by selecting '
        'its last item', (tester) {
      // A plain selection list (a JSON tree, a file picker, a chat with follow
      // turned off) constructs a controller with no pinToBottom. Landing the
      // cursor on the last item must not silently engage follow — otherwise
      // appends would start yanking the cursor to the tail. Regression guard:
      // the F2 cursor↔follow coupling must stay scoped to follow-capable lists.
      final controller = ListController(selectedIndex: 0);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();
      expect(controller.pinToBottom, isFalse);

      controller.selectedIndex = 4; // onto the last item
      expect(
        controller.pinToBottom,
        isFalse,
        reason: 'selecting the tail must not engage follow on a plain list',
      );

      // An append does not yank the cursor down either.
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 7,
          itemBuilder: _itemBuilder,
        ),
      );
      expect(controller.selectedIndex, 4, reason: 'no yank on a plain list');
    });

    testWidgets('enabling pinToBottom makes a plain list follow-capable so the '
        'cursor coupling then engages', (tester) {
      // Turning following on later (via the setter) latches follow-capability:
      // from then on the cursor couples the way a constructed-following list
      // does — off the tail unpins, back to the tail re-pins.
      final controller = ListController(selectedIndex: 0);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: _itemBuilder,
        ),
      );
      tester.render();

      // Precondition: not yet follow-capable — selecting the tail must NOT pin.
      // (Without the _followsCursor gate this would wrongly engage follow, so
      // this step makes the test a real guard for the latch, not just a
      // happy-path characterization of the already-following coupling.)
      controller.selectedIndex = 4;
      expect(
        controller.pinToBottom,
        isFalse,
        reason: 'a not-yet-follow-capable list does not pin on tail selection',
      );

      controller.pinToBottom = true; // explicit enable → snaps to tail
      expect(controller.selectedIndex, 4);
      expect(controller.pinToBottom, isTrue);

      controller.selectedIndex = 1; // scroll up now unpins
      expect(controller.pinToBottom, isFalse);

      controller.selectedIndex = 4; // back to the tail re-pins
      expect(controller.pinToBottom, isTrue);
    });

    testWidgets('following a growing list anchors the tail at the BOTTOM of '
        'the viewport, not the top', (tester) {
      // Regression: a following list must show the newest *screenful* — the
      // tail at the bottom — not collapse to just the last item at row 0 with
      // a blank viewport below. Advancing the selection is what pulls the
      // viewport; a pending jump on every append would top-anchor the newest
      // item and hide everything above it (a chat that only shows its last
      // message).
      final controller = ListController(pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 3,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));

      // Grow well past the viewport while following.
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));

      expect(controller.selectedIndex, 19, reason: 'follow advanced to tail');
      expect(
        controller.visibleRange,
        (first: 15, last: 19),
        reason: 'the last screenful is visible with the tail at the bottom',
      );
      expect(controller.atBottom, isTrue);
    });

    testWidgets('jumpToBottom bottom-anchors the tail after scrolling up', (
      tester,
    ) {
      // Locks the explicit catch-up path (the setter / jumpToBottom snap-to-
      // tail), not just the append path exercised above: after scrolling up to
      // read history, catching up must show the newest screenful with the tail
      // at the bottom — a pending jump here would top-anchor it and blank the
      // rows above.
      final controller = ListController(pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: _itemBuilder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));
      expect(controller.visibleRange, (first: 15, last: 19));

      // Scroll up to read history — moving off the tail unpins.
      controller.selectedIndex = 2;
      tester.render(size: const CellSize(10, 5));
      expect(controller.pinToBottom, isFalse);
      expect(controller.visibleRange, (first: 2, last: 6));

      // Catch up.
      controller.jumpToBottom();
      tester.render(size: const CellSize(10, 5));
      expect(controller.selectedIndex, 19);
      expect(controller.pinToBottom, isTrue);
      expect(
        controller.visibleRange,
        (first: 15, last: 19),
        reason: 'jumpToBottom shows the last screenful, tail at the bottom',
      );
    });
  });

  group('lazy ListView.builder', () {
    testWidgets('duplicate keyed items fail on their initial mount', (tester) {
      tester.pumpWidget(
        ListView.builder(
          itemCount: 2,
          itemKeyBuilder: (_) => 'duplicate',
          findChildIndexCallback: (_) => 0,
          itemBuilder: (context, index, selected) => Text('item $index'),
        ),
      );

      expect(
        () => tester.render(size: const CellSize(10, 2)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('being mounted at index 1'),
          ),
        ),
      );
    });

    testWidgets('itemBuilder is only invoked for visible items', (tester) {
      final builtIndices = <int>[];
      Widget builder(BuildContext context, int i, bool selected) {
        builtIndices.add(i);
        return Text('Item $i');
      }

      tester.pumpWidget(
        ListView.builder(itemCount: 1000, itemBuilder: builder),
      );
      tester.render(size: const CellSize(10, 5));

      // 1000 items in the list, viewport is 5 rows, items are 1 row each.
      // Only the visible window (plus what the auto-scroll-to-selection
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
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 30,
          itemBuilder: (context, index, selected) => _LifecycleWidget(
            index: index,
            mounts: mountCounts,
            unmounts: unmountCounts,
          ),
        ),
      );
      tester.render(size: const CellSize(10, 5));

      controller.selectedIndex = 10;
      tester.render(size: const CellSize(10, 5));

      expect(controller.visibleRange, (first: 6, last: 10));
      expect(mountCounts[5], 1, reason: 'index 5 was the first probe not fit');
      expect(
        unmountCounts[5],
        1,
        reason: 'a non-visible probe must not leak in the sparse element map',
      );
    });

    testWidgets('a following list does not leak its pre-jump first-walk window '
        'on the first layout (L)', (tester) {
      // Audit #1337: pinToBottom sets the selection to the last item in
      // initState, so the *first* layout walks the anchor-0 window (0..9),
      // then the selection (999) forces the backward probe + a re-walk to the
      // tail. The end-of-layout sweep must dispose the pre-jump first walk AND
      // the non-fitting probe boundary — not just the (empty) prior active set,
      // or those subtrees stay mounted forever and get rebuilt every rebuild.
      final mountCounts = <int, int>{};
      final unmountCounts = <int, int>{};
      final controller = ListController(pinToBottom: true);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 1000,
          itemBuilder: (context, index, selected) => _LifecycleWidget(
            index: index,
            mounts: mountCounts,
            unmounts: unmountCounts,
          ),
        ),
      );
      tester.render(size: const CellSize(10, 10));

      expect(controller.selectedIndex, 999);
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

    testWidgets('selection styling updates active items without '
        'remounting', (tester) {
      final mountCounts = <int, int>{};
      final unmountCounts = <int, int>{};
      final lastSelected = <int, bool>{};
      Widget builder(BuildContext context, int i, bool sel) {
        lastSelected[i] = sel;
        return _LifecycleWidget(
          index: i,
          mounts: mountCounts,
          unmounts: unmountCounts,
        );
      }

      final controller = ListController();
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: builder,
          autofocus: true,
        ),
      );
      tester.render(size: const CellSize(10, 5));
      expect(lastSelected[0], isTrue);
      final initialMounts = Map<int, int>.from(mountCounts);

      // Move selection within the visible window.
      tester.sendKey(_code(KeyCode.arrowDown));
      tester.render(size: const CellSize(10, 5));

      // Items shouldn't have remounted — the lazy element updates
      // existing children with new widgets reflecting the new
      // `selected` flag.
      expect(mountCounts, initialMounts);
      expect(unmountCounts, isEmpty);
      expect(lastSelected[0], isFalse);
      expect(lastSelected[1], isTrue);
    });

    testWidgets('keyed prepend preserves selection, viewport, and row state', (
      tester,
    ) {
      var items = <String>['a', 'b', 'c', 'd'];
      final controller = ListController(selectedIndex: 1);
      final mounts = <String, int>{};
      final unmounts = <String, int>{};

      Widget app() => SizedBox(
        width: 12,
        height: 2,
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          itemKeyBuilder: (index) => items[index],
          findChildIndexCallback: (key) {
            final index = items.indexWhere((item) => item == key);
            return index == -1 ? null : index;
          },
          itemBuilder: (context, index, selected) => _KeyedLifecycleWidget(
            id: items[index],
            mounts: mounts,
            unmounts: unmounts,
          ),
        ),
      );

      tester.pumpWidget(app());
      controller.jumpToIndex(1);
      expect(tester.renderToString(size: const CellSize(12, 2)), 'b:b\nc:c\n');
      expect(controller.visibleRange, (first: 1, last: 2));

      items = ['x', ...items];
      tester.pumpWidget(app());

      expect(tester.renderToString(size: const CellSize(12, 2)), 'b:b\nc:c\n');
      expect(controller.selectedIndex, 2, reason: 'the selected key is b');
      expect(controller.visibleRange, (first: 2, last: 3));
      expect(controller.unseenCount, 0, reason: 'a prepend is not tail growth');
      expect(mounts['b'], 1);
      expect(mounts['c'], 1);
      expect(unmounts, isEmpty);

      items = [...items, 'e'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));
      expect(controller.selectedIndex, 2);
      expect(controller.unseenCount, 1, reason: 'only the true append is new');
    });

    testWidgets('keyed reorder preserves the selected data item', (tester) {
      var items = <String>['a', 'b', 'c', 'd'];
      final controller = ListController(selectedIndex: 2);

      Widget app() => SizedBox(
        width: 12,
        height: 4,
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          itemKeyBuilder: (index) => items[index],
          findChildIndexCallback: (key) {
            final index = items.indexWhere((item) => item == key);
            return index == -1 ? null : index;
          },
          itemBuilder: (context, index, selected) => Text(items[index]),
        ),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 4));
      items = ['c', 'a', 'd', 'b'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 4));

      expect(controller.selectedIndex, 0, reason: 'the selected key remains c');
      expect(controller.unseenCount, 0);
    });

    testWidgets(
      'keyed reorder disengages follow when selected identity leaves tail',
      (tester) {
        var items = <String>['a', 'b', 'c'];
        final controller = ListController(pinToBottom: true);

        Widget app() => _keyedStringList(items, controller: controller);

        tester.pumpWidget(app());
        tester.render(size: const CellSize(12, 3));
        expect(controller.selectedIndex, 2);
        expect(controller.pinToBottom, isTrue);
        expect(controller.atBottom, isTrue);

        items = ['c', 'a', 'b'];
        tester.pumpWidget(app());
        tester.render(size: const CellSize(12, 3));

        expect(controller.selectedIndex, 0, reason: 'selected identity is c');
        expect(
          controller.pinToBottom,
          isFalse,
          reason: 'identity preservation wins over following after reorder',
        );
        expect(controller.atBottom, isFalse);
        expect(controller.unseenCount, 0);

        items = [...items, 'd'];
        tester.pumpWidget(app());

        expect(controller.selectedIndex, 0, reason: 'append does not yank c');
        expect(controller.unseenCount, 1);
      },
    );

    testWidgets('keyed scroll-only pin remains on the current tail', (tester) {
      var items = <String>['a', 'b', 'c'];
      final controller = ListController(pinToBottom: true);

      Widget app() =>
          _keyedStringList(items, controller: controller, height: 2);

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));
      controller.selectedIndex = null;
      tester.render(size: const CellSize(12, 2));
      expect(controller.pinToBottom, isTrue);
      expect(controller.atBottom, isTrue);

      items = ['c', 'a', 'b'];
      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 2));

      expect(controller.selectedIndex, isNull);
      expect(controller.pinToBottom, isTrue);
      expect(controller.atBottom, isTrue);
      expect(controller.visibleRange?.last, 2);
    });

    testWidgets('removing the selected key chooses its surviving successor', (
      tester,
    ) {
      var items = <String>['a', 'b', 'c'];
      final controller = ListController(selectedIndex: 1);
      final mounts = <String, int>{};
      final unmounts = <String, int>{};

      Widget app() => _keyedStringList(
        items,
        controller: controller,
        itemBuilder: (context, index, selected) => _KeyedLifecycleWidget(
          id: items[index],
          mounts: mounts,
          unmounts: unmounts,
        ),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      items = ['a', 'c'];
      tester.pumpWidget(app());

      expect(controller.selectedIndex, 1, reason: 'c succeeds the removed b');
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
        itemBuilder: (context, index, selected) => _KeyedLifecycleWidget(
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
      final controller = ListController(selectedIndex: 0);
      final activated = <({int index, String id})>[];

      Widget app() => _keyedStringList(
        items,
        controller: controller,
        onActivate: (index) => activated.add((index: index, id: items[index])),
        itemBuilder: (context, index, selected) =>
            SizedBox(width: 12, height: 1, child: Text(items[index])),
      );

      tester.pumpWidget(app());
      tester.render(size: const CellSize(12, 3));
      items = ['a', 'c', 'b'];
      tester.pumpWidget(app());
      expect(tester.renderToString(size: const CellSize(12, 3)), 'a\nc\nb\n');

      tester.sendMouse(_mouse(MouseEventKind.down, 1, 1));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 1));

      expect(controller.selectedIndex, 1);
      expect(activated, [(index: 1, id: 'c')]);
    });

    testWidgets('explicit jump wins over keyed anchor preservation', (tester) {
      var items = <String>['a', 'b', 'c', 'd', 'e'];
      final controller = ListController(selectedIndex: 2);

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

    testWidgets('cursor movement does not rerun keyed data reconciliation', (
      tester,
    ) {
      final items = [for (var i = 0; i < 1000; i++) 'item-$i'];
      var reverseLookups = 0;
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 5,
          child: ListView.builder(
            itemCount: items.length,
            autofocus: true,
            itemKeyBuilder: (index) => items[index],
            findChildIndexCallback: (key) {
              reverseLookups++;
              final index = items.indexWhere((item) => item == key);
              return index == -1 ? null : index;
            },
            itemBuilder: (context, index, selected) => Text(items[index]),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 5));
      reverseLookups = 0;

      tester.sendKey(_code(KeyCode.arrowDown));
      tester.render(size: const CellSize(12, 5));

      expect(
        reverseLookups,
        0,
        reason: 'selection-only rebuilds must stay O(visible rows)',
      );
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
          findChildIndexCallback: keyed
              ? (key) {
                  final index = items.indexWhere((item) => item == key);
                  return index == -1 ? null : index;
                }
              : null,
          itemBuilder: (context, index, selected) => _KeyedLifecycleWidget(
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
    Widget itemB(BuildContext c, int i, bool sel) => Text('item$i');
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
      final selections = <int>[];
      final controller = ListController();
      tester.pumpWidget(
        ListView.separated(
          controller: controller,
          itemCount: 4,
          itemBuilder: itemB,
          separatorBuilder: sepB,
          autofocus: true,
          onActivate: selections.add,
        ),
      );
      tester.render(size: const CellSize(8, 12)); // 4 items + 3 seps = 7 rows
      expect(controller.selectedIndex, 0);
      // Each Down lands on the next item index — no half-step onto a separator.
      for (final expected in [1, 2, 3]) {
        tester.sendKey(_code(KeyCode.arrowDown));
        tester.render(size: const CellSize(8, 12));
        expect(controller.selectedIndex, expected);
      }
      // At the last item, Down is an edge — no phantom trailing-separator row.
      tester.sendKey(_code(KeyCode.arrowDown));
      tester.render(size: const CellSize(8, 12));
      expect(controller.selectedIndex, 3);
      // Enter reports the item index, not a separator position.
      tester.sendKey(_code(KeyCode.enter));
      expect(selections, [3]);
    });

    testWidgets('clicking a separator selects the item it trails; clicking an '
        'item selects and fires onActivate', (tester) {
      // A separator is composed into the block of the item it trails, and the
      // block is one tap target — so a click on the separator row selects that
      // item (it holds no index of its own).
      final activated = <int>[];
      final controller = ListController(selectedIndex: 0);
      tester.pumpWidget(
        SizedBox(
          width: 12,
          height: 6,
          child: ListView.separated(
            controller: controller,
            itemCount: 3,
            onActivate: activated.add,
            itemBuilder: (c, i, sel) =>
                SizedBox(width: 12, height: 1, child: Text('item$i')),
            separatorBuilder: (c, i) =>
                SizedBox(width: 12, height: 1, child: Text('sep$i')),
          ),
        ),
      );
      tester.render(size: const CellSize(12, 6));
      // Rows: 0 item0, 1 sep0, 2 item1, 3 sep1, 4 item2.
      // sep0 (row 1) trails item0, so clicking it selects item0.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 1));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 1));
      expect(controller.selectedIndex, 0);
      expect(activated, [0], reason: 'a separator click selects its item');
      // The item on row 2 selects and fires onActivate(1) as usual.
      tester.sendMouse(_mouse(MouseEventKind.down, 1, 2));
      tester.sendMouse(_mouse(MouseEventKind.up, 1, 2));
      expect(controller.selectedIndex, 1);
      expect(activated, [0, 1]);
    });

    testWidgets('an item in an overflowing separator block stays clickable at '
        'its real row', (tester) {
      // A tall separator after item 1 makes item1's composed block overflow the
      // viewport, so the block paints through RenderFlex's clip path. The item
      // must still register its tap region at its true screen row (regression:
      // the clip path dropped screenOffset, leaving item1 unclickable and its
      // phantom region stealing item0's clicks at the scratch origin).
      final activated = <int>[];
      final controller = ListController(selectedIndex: 0);
      tester.pumpWidget(
        SizedBox(
          width: 8,
          height: 6,
          child: ListView.separated(
            controller: controller,
            itemCount: 4,
            onActivate: activated.add,
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
      expect(controller.selectedIndex, 0);
      // Clicking item1's row selects item1 (clickable despite its overflow).
      tester.sendMouse(_mouse(MouseEventKind.down, 0, 1));
      tester.sendMouse(_mouse(MouseEventKind.up, 0, 1));
      expect(controller.selectedIndex, 1);
      expect(activated, [0, 1]);
    });
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

    testWidgets('a selected item taller than the viewport is shown from its '
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

      // Jump the selection onto the oversized item, far below the fold.
      controller.selectedIndex = 5000;
      tester.render(size: const CellSize(8, 5));

      // Graceful: the tall item anchors to the top and fills the viewport —
      // the "does the selection fit?" math resolves to a single-item window
      // instead of throwing or looping on an item bigger than the viewport.
      expect(controller.selectedIndex, 5000);
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
      tester.pump();
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

    testWidgets('a selection move repaints only the two affected rows', (
      tester,
    ) {
      // Selection is the primary per-frame driver for keyboard-navigated
      // lists. Moving it re-invokes itemBuilder with a new `selected` flag for
      // exactly the old and new rows, so only those two boundaries repaint —
      // the rest of the visible window blits from cache.
      final controller = ListController(selectedIndex: 0);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 20,
          autofocus: true,
          selectionActive: true,
          itemBuilder: (context, index, selected) => SizedBox(
            width: 10,
            height: 1,
            child: Text(selected ? '>item $index' : ' item $index'),
          ),
        ),
      );
      tester.render(size: const CellSize(10, 6)); // warm the visible caches

      controller.selectedIndex = 3; // 0 deselects, 3 selects — two rows change
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(10, 6));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(
        stats.repaintedCount,
        2,
        reason: 'only the deselected + selected rows repaint',
      );
      expect(
        stats.cachedCount,
        greaterThan(0),
        reason: 'the untouched visible rows blit from cache',
      );
    });
  });
}

/// A minimal ChangeNotifier for driving a per-row rebuild (ValueNotifier is
/// not exported).
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
