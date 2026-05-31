import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

MouseEvent _at(
  MouseEventKind kind,
  int col,
  int row, {
  MouseButton button = MouseButton.left,
}) => MouseEvent(kind: kind, button: button, col: col, row: row);

void main() {
  group('GestureDetector', () {
    testWidgets('onTap fires on a press+release in the same region', (tester) {
      var taps = 0;
      tester.pumpWidget(
        Column(
          children: [
            GestureDetector(
              onTap: () => taps++,
              child: const SizedBox(width: 5, height: 1, child: Text('A')),
            ),
            const SizedBox(width: 5, height: 1, child: Text('B')),
          ],
        ),
      );
      tester.render(size: const CellSize(10, 2)); // register regions

      tester.sendMouse(_at(MouseEventKind.down, 2, 0));
      tester.sendMouse(_at(MouseEventKind.up, 2, 0));
      expect(taps, 1);
    });

    testWidgets('a press-in / release-out does not fire onTap', (tester) {
      var taps = 0;
      tester.pumpWidget(
        Column(
          children: [
            GestureDetector(
              onTap: () => taps++,
              child: const SizedBox(width: 5, height: 1, child: Text('A')),
            ),
            const SizedBox(width: 5, height: 1, child: Text('B')),
          ],
        ),
      );
      tester.render(size: const CellSize(10, 2));

      tester.sendMouse(_at(MouseEventKind.down, 2, 0)); // in A
      tester.sendMouse(_at(MouseEventKind.up, 2, 1)); // out (row 1)
      expect(taps, 0);
    });

    testWidgets('onSecondaryTap fires on a right click', (tester) {
      var secondary = 0;
      tester.pumpWidget(
        GestureDetector(
          onSecondaryTap: () => secondary++,
          child: const SizedBox(width: 5, height: 1, child: Text('A')),
        ),
      );
      tester.render(size: const CellSize(5, 1));
      tester.sendMouse(
        _at(MouseEventKind.down, 1, 0, button: MouseButton.right),
      );
      tester.sendMouse(_at(MouseEventKind.up, 1, 0, button: MouseButton.right));
      expect(secondary, 1);
    });
  });

  group('MouseRegion hover', () {
    testWidgets('enter/exit fire as the pointer crosses regions', (tester) {
      final log = <String>[];
      tester.pumpWidget(
        Column(
          children: [
            MouseRegion(
              onEnter: () => log.add('enterA'),
              onExit: () => log.add('exitA'),
              child: const SizedBox(width: 5, height: 1, child: Text('A')),
            ),
            MouseRegion(
              onEnter: () => log.add('enterB'),
              child: const SizedBox(width: 5, height: 1, child: Text('B')),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(10, 2));

      tester.sendMouse(
        _at(MouseEventKind.moved, 2, 0, button: MouseButton.none),
      );
      expect(log, ['enterA']);
      tester.sendMouse(
        _at(MouseEventKind.moved, 2, 1, button: MouseButton.none),
      );
      expect(log, ['enterA', 'exitA', 'enterB']);
    });

    testWidgets('onHover reports the moving position within the region', (
      tester,
    ) {
      final cols = <int>[];
      tester.pumpWidget(
        MouseRegion(
          onHover: (c, r) => cols.add(c),
          child: const SizedBox(width: 6, height: 1, child: Text('A')),
        ),
      );
      tester.render(size: const CellSize(6, 1));
      tester.sendMouse(
        _at(MouseEventKind.moved, 1, 0, button: MouseButton.none),
      );
      tester.sendMouse(
        _at(MouseEventKind.moved, 3, 0, button: MouseButton.none),
      );
      expect(cols, [1, 3]);
    });
  });

  group('scroll routing', () {
    testWidgets('the wheel scrolls the list under the pointer, unfocused', (
      tester,
    ) {
      final c = ListController(selectedIndex: 0);
      tester.pumpWidget(
        ListView(
          controller: c,
          // not autofocused — scrolling must work without focus
          children: const [Text('0'), Text('1'), Text('2'), Text('3')],
        ),
      );
      tester.render(size: const CellSize(10, 4));

      tester.sendMouse(
        _at(MouseEventKind.scrollDown, 1, 1, button: MouseButton.none),
      );
      expect(c.selectedIndex, 1);
      tester.sendMouse(
        _at(MouseEventKind.scrollDown, 1, 1, button: MouseButton.none),
      );
      expect(c.selectedIndex, 2);
      tester.sendMouse(
        _at(MouseEventKind.scrollUp, 1, 1, button: MouseButton.none),
      );
      expect(c.selectedIndex, 1);
    });

    testWidgets('the wheel scrolls a ScrollView viewport', (tester) {
      final c = ScrollController();
      tester.pumpWidget(
        ScrollView(
          controller: c,
          child: const Column(
            children: [
              Text('a'),
              Text('b'),
              Text('c'),
              Text('d'),
              Text('e'),
              Text('f'),
              Text('g'),
              Text('h'),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(10, 3)); // 8 rows of content in 3
      expect(c.offset, 0);
      tester.sendMouse(
        _at(MouseEventKind.scrollDown, 1, 1, button: MouseButton.none),
      );
      expect(c.offset, greaterThan(0));
    });
  });

  group('drag', () {
    testWidgets('start/update/end fire, and the drag is captured outside', (
      tester,
    ) {
      final log = <String>[];
      tester.pumpWidget(
        Column(
          children: [
            GestureDetector(
              onDragStart: (c, r) => log.add('start $c,$r'),
              onDragUpdate: (c, r) => log.add('update $c,$r'),
              onDragEnd: () => log.add('end'),
              child: const SizedBox(width: 5, height: 1, child: Text('A')),
            ),
            const SizedBox(width: 5, height: 1, child: Text('B')),
          ],
        ),
      );
      tester.render(size: const CellSize(10, 2));

      tester.sendMouse(_at(MouseEventKind.down, 1, 0));
      tester.sendMouse(_at(MouseEventKind.drag, 2, 0));
      // Pointer leaves A's row into B's — capture keeps it on A.
      tester.sendMouse(_at(MouseEventKind.drag, 2, 1));
      tester.sendMouse(_at(MouseEventKind.up, 2, 1));
      expect(log, ['start 2,0', 'update 2,1', 'end']);
    });

    testWidgets('a drag suppresses the tap', (tester) {
      var taps = 0;
      final drags = <String>[];
      tester.pumpWidget(
        GestureDetector(
          onTap: () => taps++,
          onDragStart: (c, r) => drags.add('start'),
          onDragEnd: () => drags.add('end'),
          child: const SizedBox(width: 6, height: 1, child: Text('A')),
        ),
      );
      tester.render(size: const CellSize(6, 1));
      tester.sendMouse(_at(MouseEventKind.down, 1, 0));
      tester.sendMouse(_at(MouseEventKind.drag, 3, 0));
      tester.sendMouse(_at(MouseEventKind.up, 3, 0));
      expect(taps, 0, reason: 'dragged, so no tap');
      expect(drags, ['start', 'end']);
    });
  });

  group('hit-test precedence', () {
    testWidgets('a tap skips an occluding hover-only region to reach onTap', (
      tester,
    ) {
      var taps = 0;
      // A MouseRegion (hover only) wrapping a GestureDetector: a tap must
      // still reach the inner onTap rather than being swallowed.
      tester.pumpWidget(
        MouseRegion(
          onHover: (col, row) {},
          child: GestureDetector(
            onTap: () => taps++,
            child: const SizedBox(width: 5, height: 1, child: Text('A')),
          ),
        ),
      );
      tester.render(size: const CellSize(5, 1));
      tester.sendMouse(_at(MouseEventKind.down, 2, 0));
      tester.sendMouse(_at(MouseEventKind.up, 2, 0));
      expect(taps, 1);
    });
  });
}
