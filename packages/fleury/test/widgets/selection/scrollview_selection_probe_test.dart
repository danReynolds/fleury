// Selection inside a ScrollView — coverage probe.
//
// The first case (ScrollView at screen origin, no scroll offset) DOES
// work, because the scratch-buffer coordinates the children capture
// happen to match the on-screen coordinates the delegate hit-tests
// against. It's pinned here as a regression guard.
//
// The other two cases — a padded ScrollView, and a scrolled
// ScrollView — are skipped because they fail today. Documented gap:
// every descendant Selectable inside a ScrollView captures its
// `cellBounds` against the scratch buffer at (0, 0), so the
// delegate's hit-tests compare mouse screen-coords to scratch coords.
// The fix is in ScrollView's paint — translate child bounds from
// scratch-space to screen-space, accounting for the ScrollView's
// own offset and the current scroll position. Tracked as a known
// limitation; selection inside a non-origin or scrolled ScrollView
// will misroute drags until that lands.

import 'package:fleury/fleury.dart';
import '../../support/harness.dart';
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
  testWidgets('drag inside a ScrollView selects visible text', (tester) async {
    SelectedContent? captured;
    tester.pumpWidget(
      SelectionArea(
        onSelectionChanged: (sel) => captured = sel,
        child: const ScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text('line zero'), Text('line one'), Text('line two')],
          ),
        ),
      ),
    );
    tester.render(size: const CellSize(30, 3));

    // Drag across 'line ' on row 0.
    tester.sendMouse(_down(0, 0));
    tester.sendMouse(_drag(5, 0));
    tester.sendMouse(_up(5, 0));

    // If selection works, captured?.plainText == 'line '.
    // If it doesn't, captured will be null.
    expect(
      captured?.plainText,
      'line ',
      reason:
          'selection should hit-test against on-screen bounds, '
          'even when content was painted to a scratch buffer first',
    );
  });

  testWidgets('drag inside a Padded ScrollView selects visible text', (
    tester,
  ) async {
    SelectedContent? captured;
    tester.pumpWidget(
      SelectionArea(
        onSelectionChanged: (sel) => captured = sel,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: ScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Text('line zero'), Text('line one'), Text('line two')],
            ),
          ),
        ),
      ),
    );
    tester.render(size: const CellSize(30, 5));

    // After 1-row top padding + 2-col left padding, 'line zero' lives
    // at screen (2..10, 1). Drag from col 2 to col 7 on row 1 — should
    // select 'line '.
    tester.sendMouse(_down(2, 1));
    tester.sendMouse(_drag(7, 1));
    tester.sendMouse(_up(7, 1));

    expect(
      captured?.plainText,
      'line ',
      reason:
          'selection inside a non-origin ScrollView must hit-test '
          'against the on-screen position',
    );
  });

  testWidgets('drag inside a scrolled ScrollView picks visible content', (
    tester,
  ) async {
    // After scrolling, the visible row 0 is content row N. A drag at
    // screen row 0 must select that VISIBLE content, not whatever
    // content originally lived at screen row 0.
    final controller = ScrollController(offset: 2);
    SelectedContent? captured;
    tester.pumpWidget(
      SelectionArea(
        onSelectionChanged: (sel) => captured = sel,
        child: ScrollView(
          controller: controller,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('zero zero'),
              Text('one one'),
              Text('two two'),
              Text('three three'),
              Text('four four'),
            ],
          ),
        ),
      ),
    );
    tester.render(size: const CellSize(30, 3));

    // With offset=2, screen row 0 shows 'two two'.
    tester.sendMouse(_down(0, 0));
    tester.sendMouse(_drag(3, 0));
    tester.sendMouse(_up(3, 0));

    expect(
      captured?.plainText,
      'two',
      reason: 'after scroll, screen row 0 -> content row 2',
    );
  });
}
