// Lock test (audit 5.e): cross-widget copy must follow visual reading order
// (row by row), not whole-widget order. Two side-by-side multi-line Texts:
//
//   L1 R1
//   L2 R2
//
// Each Text is one Selectable. getSelectedText concatenates whole widgets
// sorted by top-left, so select-all yields L1\\nL2R1\\nR2 — R1 appears after
// L2. Visual reading order requires R1 before L2. Separator between columns
// on the same row is a product call; this lock only asserts row-wise order.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../../support/harness.dart';

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
  testWidgets(
    'side-by-side multi-line Texts copy in visual row order (5.e)',
    (tester) {
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Row(
            children: [
              Text('L1\nL2'),
              Text('R1\nR2'),
            ],
          ),
        ),
      );
      // Each column is 2 cells wide + newline → 2 rows. Row packs left|right.
      tester.render(size: const CellSize(8, 2));

      // Drag across the whole area so both Selectables are fully selected.
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(5, 1));
      tester.sendMouse(_up(5, 1));

      final text = captured?.plainText ?? '';
      final r1 = text.indexOf('R1');
      final l2 = text.indexOf('L2');
      expect(r1, isNonNegative, reason: 'copied text must include R1: $text');
      expect(l2, isNonNegative, reason: 'copied text must include L2: $text');
      expect(
        r1 < l2,
        isTrue,
        reason:
            'visual row order puts R1 (row 0 right) before L2 (row 1 left); '
            'widget-order join puts all of the left Text first, so L2 '
            'precedes R1. got: $text',
      );
    },
  );
}
