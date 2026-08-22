import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

MouseEvent _at(
  MouseEventKind kind,
  int col,
  int row, {
  MouseButton button = MouseButton.left,
  Set<KeyModifier> modifiers = const <KeyModifier>{},
}) => MouseEvent(
  kind: kind,
  button: button,
  col: col,
  row: row,
  modifiers: modifiers,
);

PointerDownCallback _logPointerDown(List<String> log) => (details) {
  log.add(
    'details ${details.button.name} '
    '${details.col},${details.row} ${details.hasAlt}',
  );
};

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

    testWidgets(
      'onPointerDown reports coordinates, every button, and modifiers',
      (tester) {
        final details = <PointerDownDetails>[];
        tester.pumpWidget(
          GestureDetector(
            onPointerDown: details.add,
            child: const SizedBox(width: 8, height: 2, child: Text('target')),
          ),
        );
        tester.render(size: const CellSize(8, 2));

        final sourceModifiers = <KeyModifier>{
          KeyModifier.ctrl,
          KeyModifier.shift,
        };
        for (final button in <MouseButton>[
          MouseButton.left,
          MouseButton.right,
          MouseButton.middle,
        ]) {
          tester.sendMouse(
            _at(
              MouseEventKind.down,
              3,
              1,
              button: button,
              modifiers: sourceModifiers,
            ),
          );
          tester.sendMouse(_at(MouseEventKind.up, 3, 1, button: button));
        }

        expect(details, hasLength(3));
        expect(details.map((value) => value.button), <MouseButton>[
          MouseButton.left,
          MouseButton.right,
          MouseButton.middle,
        ]);
        for (final detail in details) {
          expect((detail.col, detail.row), (3, 1));
          expect(detail.modifiers, {KeyModifier.ctrl, KeyModifier.shift});
          expect(detail.hasCtrl, isTrue);
          expect(detail.hasShift, isTrue);
          expect(detail.hasAlt, isFalse);
        }

        sourceModifiers
          ..clear()
          ..add(KeyModifier.alt);
        expect(
          details.first.modifiers,
          {KeyModifier.ctrl, KeyModifier.shift},
          reason: 'details retain an immutable modifier snapshot',
        );
        expect(
          () => details.first.modifiers.add(KeyModifier.alt),
          throwsUnsupportedError,
        );
      },
    );

    testWidgets('new and legacy pointer-down callbacks coexist', (tester) {
      final log = <String>[];
      tester.pumpWidget(
        GestureDetector(
          onTapDown: (col, row) => log.add('position $col,$row'),
          onTapDownWithModifiers: (col, row, modifiers) {
            log.add(
              'modified $col,$row ${modifiers.contains(KeyModifier.alt)}',
            );
          },
          onPointerDown: _logPointerDown(log),
          child: const SizedBox(width: 5, height: 1, child: Text('A')),
        ),
      );
      tester.render(size: const CellSize(5, 1));

      tester.sendMouse(
        _at(
          MouseEventKind.down,
          2,
          0,
          button: MouseButton.right,
          modifiers: const <KeyModifier>{KeyModifier.alt},
        ),
      );

      expect(log, [
        'position 2,0',
        'modified 2,0 true',
        'details right 2,0 true',
      ]);
    });

    testWidgets('onPointerDown updates when GestureDetector rebuilds', (
      tester,
    ) {
      var oldCalls = 0;
      var newCalls = 0;
      const child = SizedBox(width: 5, height: 1, child: Text('A'));

      tester.pumpWidget(
        GestureDetector(onPointerDown: (_) => oldCalls++, child: child),
      );
      tester.render(size: const CellSize(5, 1));
      tester.sendMouse(_at(MouseEventKind.down, 1, 0));
      tester.sendMouse(_at(MouseEventKind.up, 1, 0));

      tester.pumpWidget(
        GestureDetector(onPointerDown: (_) => newCalls++, child: child),
      );
      tester.render(size: const CellSize(5, 1));
      tester.sendMouse(
        _at(MouseEventKind.down, 1, 0, button: MouseButton.middle),
      );
      tester.sendMouse(
        _at(MouseEventKind.up, 1, 0, button: MouseButton.middle),
      );

      expect(oldCalls, 1);
      expect(newCalls, 1);
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

    testWidgets('an absorb boundary handles outside taps but not descendants', (
      tester,
    ) {
      var underneathTaps = 0;
      var boundaryTaps = 0;
      var popupTaps = 0;
      tester.pumpWidget(
        Stack(
          children: <Widget>[
            GestureDetector(
              onTap: () => underneathTaps++,
              child: const SizedBox.expand(),
            ),
            AbsorbPointer(
              onTap: () => boundaryTaps++,
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: 1,
              top: 0,
              width: 3,
              height: 1,
              child: GestureDetector(
                onTap: () => popupTaps++,
                child: const Text('pop'),
              ),
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(8, 2));

      tester.sendMouse(_at(MouseEventKind.down, 6, 1));
      tester.sendMouse(_at(MouseEventKind.up, 6, 1));
      expect((underneathTaps, boundaryTaps, popupTaps), (0, 1, 0));

      tester.sendMouse(_at(MouseEventKind.down, 2, 0));
      tester.sendMouse(_at(MouseEventKind.up, 2, 0));
      expect((underneathTaps, boundaryTaps, popupTaps), (0, 1, 1));
    });
  });
}
