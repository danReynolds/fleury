// Tests for the PaintContext / clip-rect model that powers selection
// inside scrollables:
//
//   - `cellBounds` reports the full paint rect (including off-screen
//     portions) so reading-order stays meaningful across scroll.
//   - `visibleBounds` reports the intersected, currently-visible rect.
//   - A partially-clipped multi-row Text still maps clicks to the
//     correct content line via the paint anchor.
//   - Auto-scroll keeps going when the cursor drags WAY past the
//     viewport edge (not just into the edge-row).

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
  testWidgets(
    'partial visibility — multi-row Text half-scrolled still maps clicks correctly',
    (tester) async {
      // A Text with explicit newlines lays out as 4 rows of 4 chars.
      // ScrollView shows 2 of them with a scroll offset of 2 (rows
      // 0..1 hidden, 2..3 visible). Clicking inside the visible top
      // row must resolve to the THIRD content line, not the first —
      // that's the whole point of anchoring grapheme math against
      // the FULL paint rect.
      SelectedContent? captured;
      final controller = ScrollController(offset: 2);
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: ScrollView(
            controller: controller,
            child: const Text('aaaa\nbbbb\ncccc\ndddd'),
          ),
        ),
      );
      tester.render(size: const CellSize(5, 2));

      // Drag across the visible top row — should pick 'cccc'.
      // Cursor at col 4 lands at the end-of-line offset (exclusive end
      // of 'cccc'), so the selection is exactly 'cccc'.
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(4, 0));
      tester.sendMouse(_up(4, 0));

      expect(
        captured?.plainText,
        'cccc',
        reason:
            'screen row 0 maps to content row 2 (cccc), because '
            'the grapheme anchor walks from the paint rect',
      );
    },
  );

  testWidgets(
    'cellBounds vs visibleBounds — off-screen has bounds but no visible',
    (tester) async {
      // Selection inside a scrolled ScrollView. Off-screen Selectables
      // should expose cellBounds (so they sort to the right position in
      // reading order) but null visibleBounds (so auto-scroll doesn't
      // include them in its viewport-region union).
      final controller = ScrollController(offset: 2);

      SelectionRegistrar? registrar;
      tester.pumpWidget(
        SelectionArea(
          child: ScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('A'),
                const Text('B'),
                const Text('C'),
                const Text('D'),
                _CaptureRegistrar(
                  onCapture: (r) => registrar = r,
                  child: const Text('E'),
                ),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(5, 3));

      expect(registrar, isNotNull);
      final delegate = registrar! as SelectionContainerDelegate;

      final visibleCount = delegate.selectables
          .where((s) => s.visibleBounds != null)
          .length;
      final fullyOffScreenCount = delegate.selectables
          .where((s) => s.visibleBounds == null)
          .length;
      final paintedCount = delegate.selectables
          .where((s) => s.cellBounds != null)
          .length;

      // 5 Texts, scroll=2, viewport=3 → 3 visible (C, D, E), 2 hidden (A, B).
      expect(visibleCount, 3, reason: 'three visible Texts');
      expect(fullyOffScreenCount, 2, reason: 'A and B are scrolled off');
      expect(
        paintedCount,
        5,
        reason: 'cellBounds is the full paint anchor — all 5 reported',
      );
    },
  );

  testWidgets(
    'drag past end-of-row resolves to end-of-line, not after-Selectable',
    (tester) async {
      // Multi-line Text. User drags from start of row 0 to col 100 of
      // row 0 (way past the last char). The drag should select the
      // FIRST row only — NOT all rows (which would happen if we
      // resolved to "after the whole Selectable").
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('aaaa\nbbbb\ncccc'),
        ),
      );
      tester.render(size: const CellSize(20, 3));

      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(100, 0)); // way past row 0's content
      tester.sendMouse(_up(100, 0));

      // Should pick 'aaaa' (one row), NOT 'aaaa\nbbbb\ncccc'.
      expect(
        captured?.plainText,
        'aaaa',
        reason:
            'horizontal overflow on a row lands at end-of-row, '
            'not after the whole Selectable',
      );
    },
  );

  testWidgets(
    'auto-scroll continues when cursor is dragged WAY past the edge',
    (tester) async {
      // The user yanks the mouse far below the viewport. The edge zone
      // has no upper bound — anything at or below `bottom - edge`
      // triggers auto-scroll while there's more content to reach.
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
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(10, 3));

      tester.sendMouse(_down(0, 0));
      // Drag to row 50 — far below the viewport (rows 0..2).
      tester.sendMouse(_drag(0, 50));

      // Let the timer fire a few times.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        tester.render(size: const CellSize(10, 3));
        tester.pump();
      }
      tester.sendMouse(_up(0, 50));

      expect(
        controller.offset,
        controller.maxOffset,
        reason: 'a drag far below the viewport scrolls all the way down',
      );
    },
  );
}

/// Reads SelectionScope.maybeOf at build time and forwards the
/// registrar to the caller — test-only helper since the codebase
/// has no Builder widget.
class _CaptureRegistrar extends StatelessWidget {
  const _CaptureRegistrar({required this.onCapture, required this.child});

  final void Function(SelectionRegistrar?) onCapture;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onCapture(SelectionScope.maybeOf(context));
    return child;
  }
}
