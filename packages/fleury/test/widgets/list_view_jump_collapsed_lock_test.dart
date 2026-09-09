// Lock test (audit 8.h): a jump issued while the viewport has zero rows
// (collapsed pane) — or while the list is empty — must not leave the
// selection stranded relative to the viewport once space/items return.
// Today the zero-row/empty layout path returns without applying OR clearing
// `_pendingJumpIndex`, so a deferred jump can move the scroll window away
// from `currentIndex` without any reveal of the cursor.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

Widget _list({
  required ListController controller,
  required int itemCount,
  required int rows,
}) {
  return SizedBox(
    height: rows,
    child: ListView.builder(
      controller: controller,
      itemCount: itemCount,
      itemBuilder: (context, index, highlighted) => Text('item-$index'),
    ),
  );
}

void main() {
  testWidgets(
    'jump while collapsed (0 rows) does not strand selection off-screen on expand',
    (tester) {
      final controller = ListController();
      addTearDown(controller.dispose);

      tester.pumpWidget(
        _list(controller: controller, itemCount: 20, rows: 5),
      );
      tester.render(size: const CellSize(20, 5));
      expect(controller.currentIndex, 0);

      // Collapse the pane to zero rows (split view / hidden panel).
      tester.pumpWidget(
        _list(controller: controller, itemCount: 20, rows: 0),
      );
      tester.render(size: const CellSize(20, 1));

      controller.jumpToIndex(12);
      expect(controller.currentIndex, 0, reason: 'jump does not move cursor');

      // Re-expand.
      tester.pumpWidget(
        _list(controller: controller, itemCount: 20, rows: 5),
      );
      tester.render(size: const CellSize(20, 5));

      final range = controller.visibleRange;
      expect(range, isNotNull);
      final current = controller.currentIndex;
      expect(current, isNotNull);
      expect(
        current! >= range!.first && current <= range.last,
        isTrue,
        reason:
            'after expand, either the deferred jump must move/reveal the '
            'selection with the viewport, or the stale jump must be dropped '
            'so the existing selection stays on screen — not scroll away '
            'and leave currentIndex stranded',
      );
    },
  );

  // Audit note: empty-list jump was the *claimed* 8.h trigger and is refuted —
  // clamp + restore keep selection on-screen. Kept as a regression guard so a
  // future "fix" does not break the harmless empty path while addressing the
  // real collapsed-pane stranding above.
  testWidgets(
    'jump stashed while empty does not strand restored selection after refill',
    (tester) {
      final controller = ListController();
      addTearDown(controller.dispose);

      tester.pumpWidget(
        _list(controller: controller, itemCount: 10, rows: 5),
      );
      tester.render(size: const CellSize(20, 5));
      controller.currentIndex = 4;
      tester.pump();

      // Filter / clear → empty. Selection cleared; restore flag set.
      tester.pumpWidget(
        _list(controller: controller, itemCount: 0, rows: 5),
      );
      tester.render(size: const CellSize(20, 5));
      expect(controller.currentIndex, isNull);

      controller.jumpToIndex(7);

      // Unfilter / refill.
      tester.pumpWidget(
        _list(controller: controller, itemCount: 10, rows: 5),
      );
      tester.render(size: const CellSize(20, 5));

      final range = controller.visibleRange;
      final current = controller.currentIndex;
      expect(current, isNotNull);
      expect(range, isNotNull);
      expect(
        current! >= range!.first && current <= range.last,
        isTrue,
        reason:
            'restored selection and deferred empty-list jump must not diverge: '
            'viewport at jump target with cursor restored to 0 strands the '
            'selection off-screen',
      );
    },
  );
}
