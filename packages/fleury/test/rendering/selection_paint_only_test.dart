// Regression guard for the selection-geometry paint-only invalidation.
//
// A selection-range change moves which cells are highlighted but never the
// text's size or wrap, so it must NOT force a relayout. `_recomputeGeometry`
// in `SelectableTextMixin` therefore uses `markNeedsPaintOnly`; if it ever
// regresses back to `markNeedsLayout`/`markNeedsPaint`, the measured render
// below reports performed (non-cached) layouts and this fails.
//
// Mechanics: `sendMouse` flushes builds but does not run layout, so the
// invalidation set by the selection change survives until the next `render()`
// — the frame we measure. The test self-validates by asserting the selection
// text actually changed, so a no-op trigger can't make it vacuously pass.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
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
  group('selection-geometry paint-only invalidation', () {
    testWidgets('changing a selection reuses cached layout', (tester) {
      const size = CellSize(24, 1);
      SelectedContent? captured;
      tester.pumpWidget(
        SelectionArea(
          onSelectionChanged: (sel) => captured = sel,
          child: const Text('hello world from fleury'),
        ),
      );

      // Render first so painted bounds exist for hit-testing, then anchor a
      // selection with the mouse, then settle a frame so layout caches warm.
      tester.render(size: size);
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(5, 0));
      tester.sendMouse(_up(5, 0));
      tester.render(size: size);
      final first = captured?.plainText;
      expect(first, isNotNull);
      expect(first, isNotEmpty);

      // Extend the selection by one cell (no render in between, so the
      // invalidation survives to the measured frame).
      tester.sendKey(
        const KeyEvent(KeyCode.arrowRight, modifiers: {KeyModifier.shift}),
      );

      // Self-validation: the selection really changed, so the trigger fired.
      expect(
        captured?.plainText,
        isNot(equals(first)),
        reason: 'precondition: the selection must actually change',
      );

      // The measured frame must reuse cached layout — paint-only.
      RenderLayoutDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      final stats = RenderLayoutDebugStats.takeFrameStats();
      expect(
        stats.performedCount,
        0,
        reason: 'a selection change must not trigger relayout',
      );
      expect(stats.skippedCount, greaterThan(0));
    });
  });
}
