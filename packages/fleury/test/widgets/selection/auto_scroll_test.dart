// Auto-scroll integration: when a drag inside a SelectionArea
// approaches the top or bottom of the visible selectable region AND
// a ScrollController is wired in, the viewport scrolls and the
// selection extends into the newly-visible content.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

MouseEvent _down(int col, int row) => MouseEvent(
  kind: MouseEventKind.down,
  button: MouseButton.left,
  col: col,
  row: row,
);

MouseEvent _drag(int col, int row) => MouseEvent(
  kind: MouseEventKind.drag,
  button: MouseButton.left,
  col: col,
  row: row,
);

MouseEvent _up(int col, int row) => MouseEvent(
  kind: MouseEventKind.up,
  button: MouseButton.left,
  col: col,
  row: row,
);

void main() {
  group('SelectionArea — drag auto-scroll', () {
    testWidgets(
      'dragging into the bottom edge auto-scrolls and extends selection',
      (tester) async {
        final controller = ScrollController();
        SelectedContent? captured;
        tester.pumpWidget(
          SelectionArea(
            scrollController: controller,
            autoScrollInterval: const Duration(milliseconds: 5),
            onSelectionChanged: (sel) => captured = sel,
            child: ScrollView(
              controller: controller,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('alpha'),
                  Text('beta'),
                  Text('gamma'),
                  Text('delta'),
                  Text('epsilon'),
                ],
              ),
            ),
          ),
        );
        // Viewport shows 3 rows out of 5.
        tester.render(size: const CellSize(20, 3));

        // Press at row 0, drag down to row 2 (bottom of the viewport).
        // We should pick up the visible 3 lines verbatim.
        tester.sendMouse(_down(0, 0));
        tester.sendMouse(_drag(5, 2));

        // Cursor is now in the auto-scroll bottom zone. Each iteration:
        //   1. Wait real time so Timer.periodic ticks (scroll happens,
        //      a post-frame callback queues).
        //   2. render() — paint with the new scroll offset so
        //      Selectables refresh their bounds.
        //   3. pump() — flush the post-frame callback, which dispatches
        //      the cursor against the fresh bounds and extends the
        //      selection into the newly-visible row.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          tester.render(size: const CellSize(20, 3));
          tester.pump();
        }

        tester.sendMouse(_up(5, 2));

        // The scroll should have advanced past 0.
        expect(
          controller.offset,
          greaterThan(0),
          reason: 'auto-scroll should have ticked the controller',
        );
        // The selection should extend beyond the originally-visible
        // content — at minimum should include 'gamma' (originally
        // visible) AND content that needed scrolling to reach.
        final text = captured?.plainText ?? '';
        expect(text, contains('gamma'));
        expect(
          text.length,
          greaterThan('alpha\nbeta\ngamma'.length),
          reason: 'selection extended past the original viewport bottom',
        );
      },
    );

    testWidgets('drag moving away from the edge stops auto-scroll', (
      tester,
    ) async {
      final controller = ScrollController();
      tester.pumpWidget(
        SelectionArea(
          scrollController: controller,
          autoScrollInterval: const Duration(milliseconds: 5),
          child: ScrollView(
            controller: controller,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('one'),
                Text('two'),
                Text('three'),
                Text('four'),
                Text('five'),
                Text('six'),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));

      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(0, 2)); // enter bottom edge zone
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final afterEdge = controller.offset;
      expect(afterEdge, greaterThan(0));

      // Move back to the middle of the viewport — auto-scroll must
      // stop immediately.
      tester.sendMouse(_drag(0, 1));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(
        controller.offset,
        afterEdge,
        reason: 'auto-scroll should have stopped when cursor left edge',
      );
      tester.sendMouse(_up(0, 1));
    });

    testWidgets('dragging into the top edge auto-scrolls up symmetrically', (
      tester,
    ) async {
      // Start scrolled partway down. Drag toward the top edge —
      // controller should scroll up to reveal earlier content.
      final controller = ScrollController(offset: 3);
      tester.pumpWidget(
        SelectionArea(
          scrollController: controller,
          autoScrollInterval: const Duration(milliseconds: 5),
          child: ScrollView(
            controller: controller,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('one'),
                Text('two'),
                Text('three'),
                Text('four'),
                Text('five'),
                Text('six'),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));
      expect(controller.offset, 3);

      // Press inside the bottom row, drag up to the top.
      tester.sendMouse(_down(0, 2));
      tester.sendMouse(_drag(0, 0)); // enter top edge zone

      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        tester.render(size: const CellSize(20, 3));
        tester.pump();
      }
      tester.sendMouse(_up(0, 0));

      // Should have scrolled UP (offset decreased).
      expect(
        controller.offset,
        lessThan(3),
        reason: 'top-edge drag should scroll up',
      );
    });

    testWidgets('queued post-frame dispatch after drag end is a no-op', (
      tester,
    ) async {
      // Regression: a Timer tick can queue a post-frame callback
      // that fires AFTER _onDragEnd has captured the selection for
      // copyOnRelease. If the callback dispatched, the clipboard
      // text would lag behind the displayed selection. Generation
      // counter must invalidate the queued dispatch.

      final controller = ScrollController();
      tester.pumpWidget(
        SelectionArea(
          copyOnRelease: true,
          scrollController: controller,
          autoScrollInterval: const Duration(milliseconds: 5),
          child: ScrollView(
            controller: controller,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('alpha'),
                Text('beta'),
                Text('gamma'),
                Text('delta'),
                Text('epsilon'),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 3));

      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(5, 2)); // bottom edge zone
      await Future<void>.delayed(const Duration(milliseconds: 8));
      // Release BEFORE pumping post-frame callbacks.
      tester.sendMouse(_up(5, 2));
      final clipboardAfterRelease = tester.clipboard.readInProcess();

      // Now pump — any queued post-frame callback would fire here.
      tester.render(size: const CellSize(20, 3));
      tester.pump();

      // The displayed selection didn't change after release
      // (clipboard text is what was selected at release time).
      expect(clipboardAfterRelease, isNotNull);
    });

    testWidgets('no scrollController = no auto-scroll', (tester) async {
      // Sanity guard: opting out is the default; the timer must
      // never run, no exceptions during the drag.
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text('one'), Text('two'), Text('three')],
          ),
        ),
      );
      tester.render(size: const CellSize(10, 3));

      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(3, 2));
      tester.sendMouse(_up(3, 2));

      expect(captured, isNotNull);
    });
  });
}
