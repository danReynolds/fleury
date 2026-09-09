import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';

MouseEvent mouse(MouseEventKind kind, int col, int row) => MouseEvent(
  kind: kind,
  button: kind == MouseEventKind.scrollDown || kind == MouseEventKind.scrollUp
      ? MouseButton.none
      : MouseButton.left,
  col: col,
  row: row,
);

Widget list(
  ListController controller, {
  bool lazy = true,
  int count = 20,
  bool selectable = true,
  bool scrollbar = false,
  bool autofocus = false,
  String Function(int)? content,
  void Function(int)? select,
  void Function(int)? focusedItemChanged,
}) {
  Widget row(int i) => Text(content?.call(i) ?? 'Item $i');
  return lazy
      ? ListView.builder(
          controller: controller,
          itemCount: count,
          selectable: selectable,
          scrollbar: scrollbar,
          autofocus: autofocus,
          onSelect: select,
          onFocusedItemChanged: focusedItemChanged,
          itemBuilder: (_, i, highlighted) => row(i),
        )
      : ListView(
          controller: controller,
          children: List.generate(count, row),
          selectable: selectable,
          scrollbar: scrollbar,
          autofocus: autofocus,
          onSelect: select,
          onFocusedItemChanged: focusedItemChanged,
        );
}

void main() {
  testWidgets(
    'separated rows inherit the theme and retain explicit styles',
    (t) {
      final controller = ListController();
      Widget build(Color color) => Theme(
        data: ThemeData(selectionStyle: CellStyle(background: color)),
        child: ListView.separated(
          controller: controller,
          itemCount: 2,
          itemBuilder: (_, i, _) =>
              Text('Row $i', style: const CellStyle(foreground: AnsiColor(2))),
          separatorBuilder: (_, _) => const Text('---'),
        ),
      );
      t.pumpWidget(build(const AnsiColor(4)));
      expect(t.render().atColRow(0, 0).style.background, const AnsiColor(4));
      expect(t.render().atColRow(0, 0).style.foreground, const AnsiColor(2));
      expect(t.render().atColRow(0, 1).style.background, isNull);
      t.pumpWidget(build(const AnsiColor(5)));
      expect(t.render().atColRow(0, 0).style.background, const AnsiColor(5));
      controller.currentIndex = 1;
      t.pump();
      expect(t.render().atColRow(0, 0).style.background, isNull);
      expect(t.render().atColRow(0, 2).style.background, const AnsiColor(5));
    },
    viewportSize: const CellSize(20, 3),
  );
  for (final lazy in [false, true]) {
    group(lazy ? 'lazy viewport' : 'eager viewport', () {
      testWidgets(
        'plain rows get the theme highlight without builder styling',
        (t) {
          final controller = ListController();
          t.pumpWidget(list(controller, lazy: lazy, count: 3, autofocus: true));
          expect(t.render().atColRow(0, 0).style.inverse, isTrue);
          expect(t.render().atColRow(0, 1).style.inverse, isFalse);
          t.sendKey(KeyEvent(KeyCode.arrowDown));
          expect(t.render().atColRow(0, 0).style.inverse, isFalse);
          expect(t.render().atColRow(0, 1).style.inverse, isTrue);
          controller.currentIndex = null;
          t.pump();
          expect(t.render().atColRow(0, 1).style.inverse, isFalse);
          t.pumpWidget(
            list(controller, lazy: lazy, count: 3, selectable: false),
          );
          expect(t.render().atColRow(0, 0).style.inverse, isFalse);
        },
        viewportSize: const CellSize(20, 3),
      );

      testWidgets(
        'initial current index is visible without selecting or taking focus',
        (t) {
          final c = ListController(initialIndex: 24);
          final outside = FocusNode(debugLabel: 'outside');
          final events = <int>[];
          t.pumpWidget(
            Column(
              children: [
                Focus(
                  focusNode: outside,
                  autofocus: true,
                  child: const Text('Outside'),
                ),
                SizedBox(
                  height: 5,
                  child: list(
                    c,
                    lazy: lazy,
                    count: 100,
                    select: events.add,
                    focusedItemChanged: events.add,
                  ),
                ),
              ],
            ),
          );
          expect(c.currentIndex, 24);
          expect(c.visibleRange!.first, lessThanOrEqualTo(24));
          expect(c.visibleRange!.last, greaterThanOrEqualTo(24));
          expect(t.renderToString(), contains('Item 24'));
          expect(events, isEmpty);
          expect(outside.hasFocus, isTrue);
          final row = 1 + 24 - c.visibleRange!.first;
          expect(t.render().atColRow(0, row).style.inverse, isTrue);
          t.pumpWidget(const Text('Done'));
          outside.dispose();
          c.dispose();
        },
        viewportSize: const CellSize(20, 6),
      );

      testWidgets(
        'initial index clamps and an explicit initial viewport wins',
        (t) {
          final c = ListController(initialIndex: 200)..jumpToIndex(10);
          t.pumpWidget(list(c, lazy: lazy, count: 30));
          expect(c.currentIndex, 29);
          expect(c.visibleRange, (first: 10, last: 14));
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'browsing reports focus; repeated Enter and clicks select; writes stay quiet',
        (t) {
          final controller = ListController();
          final events = <String>[];
          t.pumpWidget(
            list(
              controller,
              lazy: lazy,
              autofocus: true,
              focusedItemChanged: (index) => events.add('browse $index'),
              select: (index) => events.add('select $index'),
            ),
          );
          t.sendKey(KeyEvent(KeyCode.arrowDown));
          expect(events, ['browse 1']);
          t.sendKey(KeyEvent(KeyCode.enter));
          t.sendKey(KeyEvent(KeyCode.enter));
          expect(events, ['browse 1', 'select 1', 'select 1']);
          t.sendMouse(mouse(MouseEventKind.down, 1, 1));
          expect(events, hasLength(3));
          t.sendMouse(mouse(MouseEventKind.up, 1, 1));
          expect(events.last, 'select 1');
          events.clear();
          controller.currentIndex = 2;
          t.pump();
          t.sendMouse(mouse(MouseEventKind.scrollDown, 1, 2));
          t.pump();
          expect(controller.currentIndex, 2);
          expect(events, isEmpty);
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'wheel scrolls without changing the cursor or focus',
        (t) {
          final c = ListController();
          final focusedItems = <int>[];
          t.pumpWidget(
            list(c, lazy: lazy, focusedItemChanged: focusedItems.add),
          );
          t.sendMouse(mouse(MouseEventKind.scrollDown, 1, 2));
          t.pump();
          expect(c.currentIndex, 0);
          expect(c.visibleRange, (first: 1, last: 5));
          expect(focusedItems, isEmpty);
          expect(t.renderToString(), contains('Item 5'));
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'jump survives rebuild and keyboard reveals the current item',
        (t) {
          final c = ListController();
          Widget app() => list(c, lazy: lazy, autofocus: true);
          t.pumpWidget(app());
          c.jumpToIndex(10);
          t.pump();
          t.pumpWidget(app());
          expect(c.visibleRange, (first: 10, last: 14));
          expect(c.currentIndex, 0);
          t.sendKey(KeyEvent(KeyCode.arrowDown));
          t.pump();
          expect(c.currentIndex, 1);
          expect(c.visibleRange, (first: 1, last: 5));
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'every line of a tall item is reachable and clipped',
        (t) {
          final c = ListController();
          t.pumpWidget(
            Column(
              children: [
                SizedBox(
                  height: 5,
                  child: list(
                    c,
                    lazy: lazy,
                    count: 2,
                    content: (i) => i == 0
                        ? List.generate(8, (j) => 'Line $j').join('\n')
                        : 'Next item',
                  ),
                ),
                const Text('Outside'),
              ],
            ),
          );
          expect(t.renderToString(), contains('Line 4'));
          expect(t.renderToString(), isNot(contains('Line 5')));
          c.scrollBy(3);
          t.pump();
          final frame = t.renderToString();
          for (var i = 3; i <= 7; i++) {
            expect(frame, contains('Line $i'));
          }
          expect(frame, contains('Outside'));
          expect(c.currentIndex, 0);
          expect(c.atBottom, isFalse);
          c.scrollBy(1);
          t.pump();
          expect(t.renderToString(), contains('Next item'));
          expect(c.atBottom, isTrue);
          c.scrollBy(-100);
          t.pump();
          expect(c.atTop, isTrue);
        },
        viewportSize: const CellSize(20, 6),
      );

      testWidgets(
        'passive list scrolls by keyboard without selecting',
        (t) {
          final c = ListController(initialIndex: 4);
          t.pumpWidget(list(c, lazy: lazy, selectable: false, autofocus: true));
          expect(c.currentIndex, isNull);
          t.sendMouse(mouse(MouseEventKind.down, 1, 2));
          t.sendMouse(mouse(MouseEventKind.up, 1, 2));
          c.currentIndex = 3;
          t.sendKey(KeyEvent(KeyCode.arrowDown));
          t.pump();
          expect(c.currentIndex, isNull);
          expect(c.visibleRange, (first: 1, last: 5));
          t.sendKey(KeyEvent(KeyCode.pageDown));
          t.pump();
          expect(c.visibleRange, (first: 6, last: 10));
          t.sendKey(KeyEvent(KeyCode.end));
          t.pump();
          expect(c.atBottom, isTrue);
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'scrollbar pauses follow and next append preserves history',
        (t) {
          final c = ListController(followTail: true);
          Widget app(int count) =>
              list(c, lazy: lazy, count: count, scrollbar: true);
          t.pumpWidget(app(20));
          expect(c.visibleRange, (first: 15, last: 19));
          t.sendMouse(mouse(MouseEventKind.down, 19, 0));
          t.pump();
          t.sendMouse(mouse(MouseEventKind.up, 19, 0));
          expect(c.atTop, isTrue);
          expect(c.atBottom, isFalse);
          expect(c.isFollowing, isFalse);
          expect(c.followTail, isTrue);
          t.pumpWidget(app(21));
          expect(c.visibleRange, (first: 0, last: 4));
          expect(c.unseenCount, 1);
          c.jumpToBottom();
          t.pump();
          expect(c.isFollowing, isTrue);
          expect(c.unseenCount, 0);
          expect(c.currentIndex, 0);
          t.pumpWidget(app(22));
          expect(c.visibleRange, (first: 17, last: 21));
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'single tall item has a usable scrollbar',
        (t) {
          final c = ListController();
          t.pumpWidget(
            list(
              c,
              lazy: lazy,
              count: 1,
              scrollbar: true,
              content: (_) => List.generate(20, (i) => 'Line $i').join('\n'),
            ),
          );
          expect(c.visibleFraction, 0.25);
          t.sendMouse(mouse(MouseEventKind.down, 19, 4));
          t.pump();
          t.sendMouse(mouse(MouseEventKind.up, 19, 4));
          expect(c.atBottom, isTrue);
          expect(c.scrollFraction, 1);
          expect(t.renderToString(), contains('Line 19'));
          c.jumpToFraction(0.5);
          t.pump();
          expect(c.atTop, isFalse);
          expect(c.atBottom, isFalse);
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'follow tracks growth within the last item',
        (t) {
          final c = ListController(followTail: true, initialIndex: null);
          Widget app(int lines) => list(
            c,
            lazy: lazy,
            count: 1,
            content: (_) => List.generate(lines, (i) => 'Line $i').join('\n'),
          );
          t.pumpWidget(app(8));
          expect(t.renderToString(), contains('Line 7'));
          t.pumpWidget(app(12));
          expect(t.renderToString(), contains('Line 11'));
          expect(c.atBottom, isTrue);
          c.scrollBy(-2);
          t.pump();
          final before = t.renderToString();
          t.pumpWidget(app(14));
          expect(t.renderToString(), before);
          expect(c.isFollowing, isFalse);
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'disabled following stays disabled after visiting end',
        (t) {
          final c = ListController(followTail: true);
          t.pumpWidget(list(c, lazy: lazy));
          c.followTail = false;
          c.jumpToIndex(2);
          t.pump();
          c.jumpToBottom();
          t.pump();
          expect(c.isFollowing, isFalse);
          t.pumpWidget(list(c, lazy: lazy, count: 22));
          expect(c.visibleRange, (first: 15, last: 19));
          expect(c.unseenCount, 2);
          c.followTail = true;
          t.pump();
          expect(c.visibleRange, (first: 17, last: 21));
          expect(c.isFollowing, isTrue);
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'clicking a partial tall row keeps it under the pointer',
        (t) {
          final c = ListController(initialIndex: 1);
          final selected = <int>[];
          t.pumpWidget(
            list(
              c,
              lazy: lazy,
              count: 2,
              select: selected.add,
              content: (i) => i == 0 ? 'a0\na1\na2\na3\na4\na5\na6\na7' : 'end',
            ),
          );
          c.jumpToIndex(0);
          c.scrollBy(2);
          t.pump();
          final before = t.renderToString();
          t.sendMouse(mouse(MouseEventKind.down, 1, 0));
          t.pump();
          expect(c.currentIndex, 0);
          expect(t.renderToString(), before);
          t.sendMouse(mouse(MouseEventKind.up, 1, 0));
          expect(selected, [0]);
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'nested buttons own the click in a clipped row',
        (t) {
          final c = ListController();
          final selected = <int>[];
          var clicks = 0;
          Widget row(int i) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var line = 0; line < 8; line++)
                GestureDetector(
                  onTap: () => clicks++,
                  child: Semantics(
                    role: SemanticRole.button,
                    label: 'Action $line',
                    child: Text('Action $line'),
                  ),
                ),
            ],
          );
          final items = lazy
              ? ListView.builder(
                  controller: c,
                  itemCount: 1,
                  onSelect: selected.add,
                  itemBuilder: (_, i, highlighted) => row(i),
                )
              : ListView(
                  controller: c,
                  onSelect: selected.add,
                  children: [row(0)],
                );
          t.pumpWidget(
            Column(
              children: [
                SizedBox(height: 3, child: items),
                const Text('Outside'),
              ],
            ),
          );
          c.scrollBy(2);
          t.pump();
          expect(
            t
                .semantics()
                .single(role: SemanticRole.button, label: 'Action 0')
                .bounds,
            isNull,
          );
          final action = t.semantics().single(
            role: SemanticRole.button,
            label: 'Action 2',
          );
          expect(action.bounds!.top, 0);
          t.sendMouse(mouse(MouseEventKind.down, 2, 0));
          t.pump();
          t.sendMouse(mouse(MouseEventKind.up, 2, 0));
          expect(clicks, 1);
          expect(selected, isEmpty);
          t.sendMouse(mouse(MouseEventKind.down, 2, 3));
          t.sendMouse(mouse(MouseEventKind.up, 2, 3));
          expect(
            clicks,
            1,
            reason: 'clipped buttons must not hit outside the list',
          );
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'temporarily collapsed viewport retains follow intent',
        (t) {
          final c = ListController(followTail: true);
          Widget app(int rows, int count) => SizedBox(
            height: rows,
            child: list(c, lazy: lazy, count: count),
          );
          t.pumpWidget(app(5, 20));
          t.pumpWidget(app(0, 20));
          t.pumpWidget(app(5, 22));
          expect(c.isFollowing, isTrue);
          expect(c.visibleRange, (first: 17, last: 21));
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'empty boundary items do not hide content or invent scrolling',
        (t) {
          final c = ListController(initialIndex: null);
          Widget row(int i) =>
              i == 1 ? const Text('Only content') : const SizedBox(height: 0);
          t.pumpWidget(
            lazy
                ? ListView.builder(
                    controller: c,
                    itemCount: 3,
                    itemBuilder: (_, i, highlighted) => row(i),
                  )
                : ListView(controller: c, children: List.generate(3, row)),
          );
          expect(c.atTop, isTrue);
          expect(c.atBottom, isTrue);
          expect(c.visibleFraction, 1);
          c.jumpToIndex(2);
          t.pump();
          expect(t.renderToString(), contains('Only content'));
          expect(c.atTop, isTrue);
          expect(c.atBottom, isTrue);
          c.scrollBy(10);
          t.pump();
          expect(t.renderToString(), contains('Only content'));
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'pre-mount jump wins over the initial cursor',
        (t) {
          final c = ListController()..jumpToIndex(10);
          t.pumpWidget(list(c, lazy: lazy));
          expect(c.visibleRange, (first: 10, last: 14));
          expect(c.currentIndex, 0);
        },
        viewportSize: const CellSize(20, 5),
      );

      testWidgets(
        'cursor movement precedes cancellable selection',
        (t) {
          final c = ListController();
          final selected = <int>[];
          Widget app() => SizedBox(
            width: 12,
            height: 3,
            child: list(c, lazy: lazy, count: 3, select: selected.add),
          );
          t.pumpWidget(app());
          t.sendMouse(mouse(MouseEventKind.down, 1, 1));
          expect(c.currentIndex, 1);
          expect(selected, isEmpty);
          t.pumpWidget(app());
          t.sendMouse(mouse(MouseEventKind.up, 1, 1));
          expect(selected, [1]);
          t.sendMouse(mouse(MouseEventKind.down, 1, 2));
          t.pump();
          t.sendMouse(mouse(MouseEventKind.up, 17, 4));
          expect(selected, [1]);
          t.sendMouse(mouse(MouseEventKind.down, 1, 0));
          t.sendMouse(mouse(MouseEventKind.cancel, 1, 0));
          t.sendMouse(mouse(MouseEventKind.up, 1, 0));
          expect(selected, [1]);
        },
        viewportSize: const CellSize(20, 5),
      );
    });
  }

  testWidgets(
    'explicit null cursor survives empty and nonempty updates',
    (t) {
      final c = ListController(initialIndex: null);
      t.pumpWidget(list(c));
      expect(c.currentIndex, isNull);
      t.pumpWidget(list(c, count: 0));
      t.pumpWidget(list(c));
      expect(c.currentIndex, isNull);
      t.sendMouse(mouse(MouseEventKind.down, 1, 2));
      expect(c.currentIndex, 2);
    },
    viewportSize: const CellSize(20, 5),
  );

  testWidgets(
    'viewport listeners receive final metrics once after a frame',
    (t) {
      final c = ListController();
      t.pumpWidget(list(c));
      final seen = <({int first, int last})?>[];
      c.addListener(() => seen.add(c.visibleRange));
      c.jumpToIndex(10);
      t.pump();
      expect(seen.last, (first: 10, last: 14));
      expect(seen.where((v) => v == (first: 10, last: 14)), hasLength(1));
      final notifications = seen.length;
      t.pump();
      expect(seen.length, notifications);
    },
    viewportSize: const CellSize(20, 5),
  );

  testWidgets(
    'plain scroll metrics notify after a content resize',
    (t) {
      final c = ScrollController();
      Widget app(String content) =>
          ScrollView(controller: c, child: Text(content));
      t.pumpWidget(app('one'));
      final seen = <int>[];
      c.addListener(() => seen.add(c.maxOffset));
      t.pumpWidget(app('a\nb\nc\nd\ne\nf\ng'));
      expect(seen, [2]);
      t.pump();
      expect(seen, [2]);
    },
    viewportSize: const CellSize(20, 5),
  );

  testWidgets(
    'keyed prepend retains partial first item and cancels removed press',
    (t) {
      final c = ListController();
      var items = ['a', 'b', 'c'];
      final selected = <String>[];
      Widget app() {
        return ListView.builder(
          controller: c,
          itemCount: items.length,
          itemKeyBuilder: (i) => items[i],
          onSelect: (i) => selected.add(items[i]),
          itemBuilder: (_, i, highlighted) =>
              Text('${items[i]}0\n${items[i]}1\n${items[i]}2\n${items[i]}3'),
        );
      }

      t.pumpWidget(app());
      c.scrollBy(2);
      t.pump();
      final before = t.renderToString();
      items = ['new', ...items];
      t.pumpWidget(app());
      expect(t.renderToString(), before);
      t.sendMouse(mouse(MouseEventKind.down, 1, 0));
      items = ['new', 'replacement', 'b', 'c'];
      t.pumpWidget(app());
      t.sendMouse(mouse(MouseEventKind.up, 1, 0));
      expect(selected, isEmpty);
    },
    viewportSize: const CellSize(20, 5),
  );
  testWidgets(
    'a keyed press resolves the current index after a reorder',
    (t) {
      final c = ListController();
      var items = ['a', 'b', 'c'];
      final selected = <String>[];
      Widget app() {
        return ListView.builder(
          controller: c,
          itemCount: items.length,
          itemKeyBuilder: (i) => items[i],
          onSelect: (i) => selected.add('$i:${items[i]}'),
          itemBuilder: (_, i, highlighted) => Text(items[i]),
        );
      }

      t.pumpWidget(app());
      t.sendMouse(mouse(MouseEventKind.down, 0, 1));
      items = ['b', 'a', 'c'];
      t.pumpWidget(app());
      t.sendMouse(mouse(MouseEventKind.up, 0, 0));
      expect(c.currentIndex, 0);
      expect(selected, ['0:b']);
    },
    viewportSize: const CellSize(20, 5),
  );
}
