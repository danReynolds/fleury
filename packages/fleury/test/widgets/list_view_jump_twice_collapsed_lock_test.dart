// Lock test: refusing a jump must not destroy the one already stashed.
//
// `jumpToIndex` drops a jump aimed at a collapsed pane that has items — it
// can show nothing. But it cleared the pending-request state BEFORE deciding
// that, so a second jump while collapsed wiped the first one's stash and then
// recorded nothing of its own, and the expand rendered from row 0.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a refused second jump leaves the first one stashed', (tester) {
    final controller = ListController();
    addTearDown(controller.dispose);
    final items = <String>[for (var i = 0; i < 60; i++) 'row $i'];
    var height = 0;
    Widget build() => SizedBox(
      width: 12,
      height: height,
      child: ListView.builder(
        controller: controller,
        itemCount: items.length,
        itemBuilder: (context, i, highlighted) => Text(items[i]),
      ),
    );

    // Stashed before any layout, so it is legitimate and must survive.
    controller.jumpToIndex(50);
    tester.pumpWidget(build());
    tester.render(size: const CellSize(12, 6));

    // Aimed at the collapsed pane: correctly refused — and must take nothing
    // with it.
    controller.jumpToIndex(55);

    height = 5;
    tester.pumpWidget(build());
    tester.render(size: const CellSize(12, 6));

    expect(
      controller.visibleRange?.first,
      50,
      reason: 'the refused jump destroyed the stash the first one left',
    );
  });
}
