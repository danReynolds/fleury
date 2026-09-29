import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  for (final axis in Axis.values) {
    testWidgets(
      '${axis.name} reveal can scroll an ancestor of a fitting viewport',
      (tester) {
        final outer = ScrollController();
        final inner = ScrollController();
        final first = FocusNode();
        final next = FocusNode();
        final footer = FocusNode();
        final viewports = [
          FocusNode(skipTraversal: true),
          FocusNode(skipTraversal: true),
        ];
        addTearDown(outer.dispose);
        addTearDown(inner.dispose);
        for (final node in [first, next, footer, ...viewports]) {
          addTearDown(node.dispose);
        }
        final vertical = axis == Axis.vertical;
        Widget control(FocusNode node, String text) => Focus(
          focusNode: node,
          autofocus: node == first,
          child: SizedBox(width: 3, height: 1, child: Text(text)),
        );
        final content = [
          control(first, 'one'),
          SizedBox(width: vertical ? 0 : 5, height: vertical ? 3 : 0),
          control(next, 'two'),
          SizedBox(width: vertical ? 0 : 1, height: vertical ? 1 : 0),
        ];
        final view = SizedBox(
          width: vertical ? 20 : 6,
          height: vertical ? 3 : 3,
          child: ScrollView(
            controller: outer,
            focusNode: viewports[0],
            scrollDirection: axis,
            child: SizedBox(
              width: vertical ? 20 : 12,
              height: vertical ? 6 : 3,
              child: ScrollView(
                controller: inner,
                focusNode: viewports[1],
                scrollDirection: axis,
                child: vertical
                    ? Column(children: content)
                    : Row(children: content),
              ),
            ),
          ),
        );
        tester.pumpWidget(
          FocusTraversalGroup(
            child: vertical
                ? Column(children: [view, control(footer, 'end')])
                : Row(children: [view, control(footer, 'end')]),
          ),
        );
        const size = CellSize(20, 6);
        tester.render(size: size);
        expect(inner.maxOffset, 0);
        expect(next.rect, isNull);
        tester.sendKey(
          KeyEvent(vertical ? KeyCode.arrowDown : KeyCode.arrowRight),
        );
        tester.render(size: size);
        expect(next.hasFocus, isTrue);
        expect(next.rect, isNotNull);
        expect(inner.offset, 0);
        expect(outer.offset, vertical ? 2 : 5);
      },
    );

    for (final position in [10]) {
      testWidgets(
        '${axis.name} arrows reject positioned targets beyond scroll limits at $position',
        (tester) {
          final scroll = ScrollController();
          final viewport = FocusNode(skipTraversal: true);
          final first = FocusNode();
          final hidden = FocusNode();
          addTearDown(scroll.dispose);
          for (final node in [viewport, first, hidden]) {
            addTearDown(node.dispose);
          }
          final vertical = axis == Axis.vertical;
          tester.pumpWidget(
            FocusTraversalGroup(
              child: SizedBox(
                width: vertical ? 20 : 6,
                height: vertical ? 3 : 4,
                child: ScrollView(
                  controller: scroll,
                  focusNode: viewport,
                  scrollDirection: axis,
                  child: Stack(
                    children: [
                      SizedBox(
                        width: vertical ? 20 : 6,
                        height: vertical ? 3 : 4,
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Focus(
                          focusNode: first,
                          autofocus: true,
                          child: const Text('one'),
                        ),
                      ),
                      Positioned(
                        left: vertical ? 0 : 1,
                        top: vertical ? 1 : 0,
                        width: vertical ? 20 : 12,
                        height: vertical ? 12 : 4,
                        child: vertical
                            ? Column(
                                children: [
                                  SizedBox(height: position - 1),
                                  Focus(
                                    focusNode: hidden,
                                    child: const Text('two'),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  SizedBox(width: position - 1),
                                  Focus(
                                    focusNode: hidden,
                                    child: const Text('two'),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          const size = CellSize(20, 6);
          tester.render(size: size);
          expect(hidden.rect, isNull);
          expect(scroll.maxOffset, 0);
          final key = vertical
              ? (position < 0 ? KeyCode.arrowUp : KeyCode.arrowDown)
              : (position < 0 ? KeyCode.arrowLeft : KeyCode.arrowRight);
          tester.sendKey(KeyEvent(key));
          tester.render(size: size);
          expect(first.hasFocus, isTrue);
          expect(
            hidden.hasFocus,
            isFalse,
            reason: 'controller clamps the requested reveal',
          );
          expect(scroll.offset, 0);
        },
      );
    }

    for (final clippedAxis in Axis.values) {
      testWidgets(
        '${axis.name} arrows reject ${clippedAxis.name} screen-clipped targets',
        (tester) {
          final scroll = ScrollController();
          final viewport = FocusNode(skipTraversal: true);
          final first = FocusNode();
          final hidden = FocusNode();
          addTearDown(scroll.dispose);
          for (final node in [viewport, first, hidden]) {
            addTearDown(node.dispose);
          }
          final horizontalClip = clippedAxis == Axis.horizontal;
          final children = [
            Focus(
              focusNode: first,
              autofocus: true,
              child: const SizedBox(width: 4, height: 1, child: Text('one')),
            ),
            SizedBox(
              width: horizontalClip ? 21 : 0,
              height: horizontalClip ? 0 : 5,
            ),
            Focus(
              focusNode: hidden,
              child: const SizedBox(width: 4, height: 1, child: Text('two')),
            ),
          ];
          tester.pumpWidget(
            FocusTraversalGroup(
              child: Stack(
                children: [
                  const SizedBox(width: 20, height: 4),
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 40,
                    height: 10,
                    child: ScrollView(
                      controller: scroll,
                      focusNode: viewport,
                      scrollDirection: axis,
                      child: horizontalClip
                          ? Row(children: children)
                          : Column(children: children),
                    ),
                  ),
                ],
              ),
            ),
          );
          const size = CellSize(20, 4);
          tester.render(size: size);
          expect(hidden.rect, isNull);
          tester.sendKey(
            KeyEvent(horizontalClip ? KeyCode.arrowRight : KeyCode.arrowDown),
          );
          tester.render(size: size);
          expect(
            first.hasFocus,
            isTrue,
            reason: 'scrolling cannot expose this target',
          );
          expect(hidden.hasFocus, isFalse);
          expect(scroll.offset, 0);
        },
      );
    }

    for (final edge in EdgeBehavior.values) {
      testWidgets(
        '${axis.name} arrows reveal controls with ${edge.name} edges',
        (tester) {
          final scroll = ScrollController();
          final viewport = FocusNode(skipTraversal: true);
          final first = FocusNode();
          final second = FocusNode();
          final done = FocusNode();
          addTearDown(scroll.dispose);
          for (final node in [viewport, first, second, done]) {
            addTearDown(node.dispose);
          }
          final vertical = axis == Axis.vertical;
          Widget control(FocusNode node, String label) => Focus(
            focusNode: node,
            child: SizedBox(width: 4, height: 2, child: Text(label)),
          );
          final children = [
            control(first, 'one'),
            SizedBox(width: vertical ? 0 : 3, height: vertical ? 2 : 0),
            control(second, 'two'),
          ];
          final view = SizedBox(
            width: vertical ? 10 : 6,
            height: vertical ? 3 : 2,
            child: ScrollView(
              controller: scroll,
              focusNode: viewport,
              scrollDirection: axis,
              edgeBehavior: edge,
              child: vertical
                  ? Column(children: children)
                  : Row(children: children),
            ),
          );
          tester.pumpWidget(
            FocusTraversalGroup(
              child: vertical
                  ? Column(children: [view, control(done, 'done')])
                  : Row(children: [view, control(done, 'done')]),
            ),
          );
          const size = CellSize(20, 6);
          tester.render(size: size);
          expect(tester.focusManager.focusedNode, isNull);
          expect(
            second.rect,
            isNull,
            reason: 'the next control is fully clipped',
          );
          tester.sendKey(const KeyEvent(KeyCode.tab));
          expect(first.hasFocus, isTrue);
          final forward = vertical ? KeyCode.arrowDown : KeyCode.arrowRight;
          final backward = vertical ? KeyCode.arrowUp : KeyCode.arrowLeft;
          tester.sendKey(KeyEvent(forward));
          tester.render(size: size);
          expect(second.hasFocus, isTrue);
          expect(scroll.offset, vertical ? 3 : 5);
          expect(second.rect, isNotNull);
          tester.sendKey(KeyEvent(backward));
          tester.render(size: size);
          expect(first.hasFocus, isTrue);
          expect(scroll.offset, 0);
          tester.sendKey(KeyEvent(forward));
          tester.render(size: size);
          tester.sendKey(KeyEvent(forward));
          expect(
            edge == EdgeBehavior.contain ? second.hasFocus : done.hasFocus,
            isTrue,
            reason: 'the viewport edge policy governs leaving its last control',
          );
        },
      );
    }
  }

  testWidgets(
    'nested descendant can reveal a control in its ancestor viewport',
    (tester) {
      final outer = ScrollController();
      final inner = ScrollController();
      final first = FocusNode();
      final next = FocusNode();
      final footer = FocusNode();
      final viewports = [
        FocusNode(skipTraversal: true),
        FocusNode(skipTraversal: true),
      ];
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      for (final node in [first, next, footer, ...viewports]) {
        addTearDown(node.dispose);
      }
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            children: [
              SizedBox(
                height: 3,
                child: ScrollView(
                  controller: outer,
                  focusNode: viewports[0],
                  child: Column(
                    children: [
                      SizedBox(
                        height: 2,
                        child: ScrollView(
                          controller: inner,
                          focusNode: viewports[1],
                          child: Focus(
                            focusNode: first,
                            autofocus: true,
                            child: const Text('first'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Focus(focusNode: next, child: const Text('next')),
                    ],
                  ),
                ),
              ),
              Focus(focusNode: footer, child: const Text('footer')),
            ],
          ),
        ),
      );
      const size = CellSize(20, 5);
      tester.render(size: size);
      expect(next.rect, isNull);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.render(size: size);
      expect(next.hasFocus, isTrue);
      expect(next.rect, isNotNull);
      expect(outer.offset, 2);

      // Explicit page scrolling may also hide the source's whole inner viewport.
      first.requestFocus();
      outer.scrollToStart();
      tester.render(size: size);
      tester.sendKey(const KeyEvent(KeyCode.pageDown));
      tester.render(size: size);
      expect(outer.offset, 2);
      expect(first.rect, isNull);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.render(size: size);
      expect(
        next.hasFocus,
        isTrue,
        reason: 'hidden source focus can still move out',
      );
    },
  );

  testWidgets('arrows do not enter clipped controls in another viewport', (
    tester,
  ) {
    final first = FocusNode();
    final hidden = FocusNode();
    final done = FocusNode();
    final viewports = [
      FocusNode(skipTraversal: true),
      FocusNode(skipTraversal: true),
    ];
    for (final node in [first, hidden, done, ...viewports]) {
      addTearDown(node.dispose);
    }
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          children: [
            SizedBox(
              height: 2,
              child: ScrollView(
                focusNode: viewports[0],
                child: Focus(
                  focusNode: first,
                  autofocus: true,
                  child: const Text('first'),
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: ScrollView(
                focusNode: viewports[1],
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    Focus(focusNode: hidden, child: const Text('hidden')),
                  ],
                ),
              ),
            ),
            Focus(focusNode: done, child: const Text('done')),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(20, 6));
    expect(hidden.rect, isNull);
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(done.hasFocus, isTrue);
    expect(hidden.hasFocus, isFalse);
  });

  testWidgets(
    'PageDown still scrolls descendants; arrows recover hidden focus',
    (tester) {
      final scroll = ScrollController();
      final first = FocusNode();
      final next = FocusNode();
      addTearDown(scroll.dispose);
      addTearDown(first.dispose);
      addTearDown(next.dispose);
      tester.pumpWidget(
        FocusTraversalGroup(
          child: ScrollView(
            controller: scroll,
            child: Column(
              children: [
                Focus(
                  focusNode: first,
                  autofocus: true,
                  child: const Text('first'),
                ),
                const SizedBox(height: 4),
                Focus(focusNode: next, child: const Text('next')),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));
      tester.sendKey(const KeyEvent(KeyCode.pageDown));
      tester.render(size: const CellSize(20, 3));
      expect(scroll.offset, 3);
      expect(first.hasFocus, isTrue);
      expect(first.rect, isNull);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.render(size: const CellSize(20, 3));
      expect(next.hasFocus, isTrue);
      expect(next.rect, isNotNull);
    },
  );

  testWidgets('descendant editor keeps cursor arrows before scroll traversal', (
    tester,
  ) {
    final scroll = ScrollController();
    final editing = TextEditingController(text: 'one\ntwo\nthree');
    final editor = FocusNode();
    final next = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(editing.dispose);
    addTearDown(editor.dispose);
    addTearDown(next.dispose);
    tester.pumpWidget(
      FocusTraversalGroup(
        child: ScrollView(
          controller: scroll,
          child: Column(
            children: [
              SizedBox(
                height: 3,
                child: TextArea(
                  controller: editing,
                  focusNode: editor,
                  autofocus: true,
                ),
              ),
              Focus(focusNode: next, child: const Text('next')),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    tester.render(size: const CellSize(20, 4));
    editing.selection = const TextSelection.collapsed(offset: 0);
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(editing.selection.extentOffset, 4);
    expect(editor.hasFocus, isTrue);
    expect(scroll.offset, 0);
  });

  testWidgets(
    'descendant list keeps selection and releases edge to next control',
    (tester) {
      final scroll = ScrollController();
      final list = ListController();
      final listFocus = FocusNode();
      final next = FocusNode();
      addTearDown(scroll.dispose);
      addTearDown(list.dispose);
      addTearDown(listFocus.dispose);
      addTearDown(next.dispose);
      tester.pumpWidget(
        FocusTraversalGroup(
          child: ScrollView(
            controller: scroll,
            child: Column(
              children: [
                SizedBox(
                  height: 2,
                  child: ListView.builder(
                    controller: list,
                    focusNode: listFocus,
                    autofocus: true,
                    edgeBehavior: EdgeBehavior.bubble,
                    itemCount: 2,
                    itemBuilder: (_, index, current) => Text('item $index'),
                  ),
                ),
                const SizedBox(height: 2),
                Focus(focusNode: next, child: const Text('next')),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(list.currentIndex, 1);
      expect(listFocus.hasFocus, isTrue);
      expect(scroll.offset, 0);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.render(size: const CellSize(20, 3));
      expect(next.hasFocus, isTrue);
      expect(scroll.offset, 2);
    },
  );
}
