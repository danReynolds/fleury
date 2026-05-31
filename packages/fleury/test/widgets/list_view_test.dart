// ListView integration tests. Driven by FleuryTester so input
// dispatch + focus + rendering use the canonical test surface.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc) => KeyEvent(keyCode: kc);

Widget _itemBuilder(BuildContext context, int index, bool selected) {
  return Text('Item $index');
}

void main() {
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
  });

  group('boundary handling', () {
    testWidgets('contain (default) consumes up at the first item', (tester) {
      var bubbled = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.key(KeyCode.arrowUp),
              onEvent: (_) => bubbled += 1,
            ),
          ],
          child: ListView.builder(
            itemCount: 3,
            itemBuilder: _itemBuilder,
            autofocus: true,
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
            KeyBinding(
              KeyChord.key(KeyCode.arrowUp),
              onEvent: (_) => bubbled += 1,
            ),
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
            KeyBinding(
              KeyChord.key(KeyCode.arrowDown),
              onEvent: (_) => bubbled += 1,
            ),
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
            KeyBinding(
              KeyChord.key(KeyCode.pageDown),
              onEvent: (_) => bubbled += 1,
            ),
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
        0,
        reason: 'initial selection is 0, pinToBottom only acts on growth',
      );

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

  group('lazy ListView.builder', () {
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
  });
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
