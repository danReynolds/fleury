// Lock test: a jump issued before the list has data survives a collapsed
// first layout.
//
// The collapsed-pane rule drops a jump that cannot be realized — right, but
// only once there are items to jump among. `jumpToIndex` already draws that
// line (`_itemCount > 0`); the layout side did not, so a list that first laid
// out at zero extent while still loading lost the jump before the data it was
// waiting for ever arrived.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a jump issued before the collapse survives it', (tester) {
    final controller = ListController();
    addTearDown(controller.dispose);

    final items = <String>[for (var i = 0; i < 100; i++) 'row $i'];
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

    // The jump is issued first, before anything has been laid out.
    controller.jumpToIndex(50);

    // It then lays out once inside a collapsed pane...
    tester.pumpWidget(build());
    tester.render(size: const CellSize(12, 6));

    // ...and the pane opens.
    height = 3;
    tester.pumpWidget(build());
    tester.render(size: const CellSize(12, 6));

    expect(
      tester.renderToString(),
      contains('row 50'),
      reason:
          'jumpToIndex already refuses a jump aimed AT a collapsed pane; a '
          'jump issued before the collapse is a different thing and must '
          'survive it',
    );
  });
}
