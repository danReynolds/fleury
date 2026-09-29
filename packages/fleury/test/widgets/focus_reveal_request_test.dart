import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  for (final autofocus in [false, true]) {
    testWidgets('focus request reveals after layout, autofocus=$autofocus', (
      tester,
    ) {
      final scroll = ScrollController();
      final node = FocusNode();
      addTearDown(scroll.dispose);
      addTearDown(node.dispose);
      tester.pumpWidget(
        SizedBox(
          height: 4,
          child: ScrollView(
            controller: scroll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Focus(
                  focusNode: node,
                  autofocus: autofocus,
                  child: const Text('TARGET'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
      tester.render();
      if (!autofocus) node.requestFocus();
      tester.pump();
      tester.pump();
      expect(node.hasFocus, isTrue);
      expect(scroll.offset, 5);
      expect(tester.renderToString(), contains('TARGET'));
    });
  }

  testWidgets('pointer focus does not move partially visible content', (
    tester,
  ) {
    final scroll = ScrollController();
    final node = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(node.dispose);
    tester.pumpWidget(
      SizedBox(
        height: 4,
        child: ScrollView(
          controller: scroll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 3),
              TextArea(focusNode: node, minLines: 3, maxLines: 3),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    tester.render();
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 0,
        row: 3,
      ),
    );
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 0,
        row: 3,
      ),
    );
    tester.pump();
    tester.pump();
    expect(node.hasFocus, isTrue);
    expect(scroll.offset, 0);
  });

  for (final lazy in [false, true]) {
    testWidgets('Tab reveals a partially visible list item, lazy=$lazy', (
      tester,
    ) {
      final nodes = [FocusNode(), FocusNode()];
      for (final node in nodes) {
        addTearDown(node.dispose);
      }
      Widget item(int index) => Focus(
        focusNode: nodes[index],
        child: SizedBox(height: 3, child: Text('ITEM $index')),
      );
      tester.pumpWidget(
        SizedBox(
          height: 4,
          child: lazy
              ? ListView.builder(
                  selectable: false,
                  itemCount: 2,
                  itemBuilder: (_, index, _) => item(index),
                )
              : ListView(selectable: false, children: [item(0), item(1)]),
        ),
      );
      tester.render();
      nodes.first.requestFocus();
      tester.pump();
      tester.focusManager.focusNext();
      tester.pump();
      tester.pump();
      expect(nodes.last.hasFocus, isTrue);
      expect(nodes.last.rect!.top, 1);
      expect(nodes.last.rect!.bottom, 4);
    });
  }
}
