// Lock test (audit 8.g): when a focused descendant inside a lazy ListView
// item is virtualized away, focus must not drop to null. A scope-level
// fallback (ListView's own focus node, or the nearest surviving focusable)
// should keep keyboard ownership in the list.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'virtualizing away a focused row does not leave focusedNode null',
    (tester) {
      final controller = ListController();
      final listNode = FocusNode(debugLabel: 'list');
      addTearDown(listNode.dispose);
      final itemNodes = <int, FocusNode>{};
      addTearDown(() {
        for (final n in itemNodes.values) {
          n.dispose();
        }
      });

      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          focusNode: listNode,
          itemCount: 20,
          itemBuilder: (context, i, highlighted) {
            final node = itemNodes.putIfAbsent(
              i,
              () => FocusNode(debugLabel: 'item-$i'),
            );
            return Focus(focusNode: node, child: Text('item$i'));
          },
        ),
      );
      tester.render(size: const CellSize(20, 4));

      final n0 = itemNodes[0]!;
      n0.requestFocus();
      tester.pump();
      expect(n0.hasFocus, isTrue);

      controller.jumpToIndex(10);
      tester.render(size: const CellSize(20, 4));
      tester.pump();

      expect(
        tester.focusManager.focusedNode,
        isNotNull,
        reason:
            'unmounting the focused item must fall focus back to the list '
            '(or another surviving focusable), not null — current: '
            '${tester.focusManager.focusedNode?.debugLabel}',
      );
      expect(
        n0.hasFocus,
        isFalse,
        reason: 'the unmounted item itself cannot remain focused',
      );
    },
  );
}
