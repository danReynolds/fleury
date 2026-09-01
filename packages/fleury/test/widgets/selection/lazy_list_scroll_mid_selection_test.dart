// A selectable that mounts mid-selection joins it (5.f).
//
// Drag across a lazy list, then scroll it: the item that mounts under the
// selection's end edge must be part of the selection (and the copied text).

import 'package:fleury/fleury.dart';
import '../../support/harness.dart';
import 'package:test/test.dart';

const _size = CellSize(20, 4);

MouseEvent _mouse(MouseEventKind kind, int col, int row) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row);

void main() {
  testWidgets('an item mounted by a scroll under the selection joins it', (
    tester,
  ) {
    final controller = ListController();
    Widget list() => ListView.builder(
      controller: controller,
      itemCount: 10,
      itemBuilder: (context, i, _) => Text('item$i'),
    );
    tester.pumpWidget(list());
    tester.render(size: _size);

    // Drag from the first row to the last visible row (items 0..3).
    tester.sendMouse(_mouse(MouseEventKind.down, 0, 0));
    tester.sendMouse(_mouse(MouseEventKind.drag, 5, 3));
    tester.render(size: _size);

    // Scroll by one: item4 mounts at the bottom row, item0 leaves.
    controller.jumpToIndex(1);
    tester.render(size: _size);
    tester.render(size: _size);

    tester.sendMouse(_mouse(MouseEventKind.up, 5, 3));
    tester.press(KeySequence.ctrl.c);
    final copied = tester.clipboard.readInProcess() ?? '';
    expect(
      copied,
      contains('item4'),
      reason: 'mounted under the end edge:\n$copied',
    );
    expect(copied, contains('item1'));
    expect(
      copied,
      isNot(contains('item0')),
      reason: 'unmounted by the scroll — no longer part of the selection',
    );
  });
}
