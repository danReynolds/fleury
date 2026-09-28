// ListController.moveCursor places the cursor in the list an owner is
// rebuilding: the index clamps against the count the list is about to show,
// not the one it showed last.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

final class _Items with Notifier {
  List<String> _items = const ['a', 'b', 'c', 'd'];
  List<String> get items => _items;
  set items(List<String> value) {
    _items = value;
    notify();
  }
}

Widget _list(_Items items, ListController controller) => NotifierBuilder(
  notifier: items,
  builder: (_, items) => ListView.builder(
    controller: controller,
    autofocus: true,
    itemCount: items.items.length,
    itemBuilder: (_, i, _) => Text(items.items[i]),
  ),
);

void main() {
  testWidgets('moveCursor reaches past the count the list showed last', (
    tester,
  ) {
    final items = _Items();
    final controller = ListController(initialIndex: 1);
    tester.pumpWidget(_list(items, controller));
    tester.render(size: const CellSize(10, 8));

    // The owner inserts two items above 'd' and moves the cursor to it.
    items.items = const ['a', 'x', 'y', 'b', 'c', 'd'];
    controller.moveCursor(5, itemCount: 6);
    tester.pump();

    expect(controller.currentIndex, 5);
    expect(controller.itemCount, 6);
  });

  testWidgets('a move for a count the list never reaches is dropped', (tester) {
    final items = _Items();
    final controller = ListController(initialIndex: 1);
    tester.pumpWidget(_list(items, controller));
    tester.render(size: const CellSize(10, 8));

    controller.moveCursor(5, itemCount: 9);
    items.items = const ['a', 'b', 'c', 'd', 'e', 'f'];
    tester.pump();

    expect(controller.itemCount, 6);
    expect(controller.currentIndex, 1);
  });

  testWidgets('a move within the current count applies at once', (tester) {
    final items = _Items();
    final controller = ListController(initialIndex: 1);
    tester.pumpWidget(_list(items, controller));
    tester.render(size: const CellSize(10, 8));

    controller.moveCursor(3, itemCount: 4);

    expect(controller.currentIndex, 3);
  });

  testWidgets('a placement after a move supersedes it', (tester) {
    final items = _Items();
    final controller = ListController(initialIndex: 1);
    tester.pumpWidget(_list(items, controller));
    tester.render(size: const CellSize(10, 8));

    items.items = const ['a', 'x', 'y', 'b', 'c', 'd'];
    controller.moveCursor(5, itemCount: 6);
    controller.currentIndex = 0;
    tester.pump();

    expect(controller.currentIndex, 0);
  });

  testWidgets('cursorFor reads the move until the list shows it', (tester) {
    final items = _Items();
    final controller = ListController(initialIndex: 1);
    tester.pumpWidget(_list(items, controller));
    tester.render(size: const CellSize(10, 8));

    items.items = const ['a', 'x', 'y', 'b', 'c', 'd'];
    controller.moveCursor(5, itemCount: 6);

    expect(controller.cursorFor(itemCount: 6), 5);
    expect(controller.cursorFor(itemCount: 4), 1);
    tester.pump();
    expect(controller.cursorFor(itemCount: 6), 5);
    expect(controller.currentIndex, 5);
  });
}
