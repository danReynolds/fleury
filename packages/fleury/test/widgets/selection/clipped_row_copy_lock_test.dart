// Lock test: only rows a leaf actually PAINTS may be keyed into the row map.
//
// `SelectionContainerDelegate.getSelectedText` joins one fragment per screen
// row with no separator, so a fragment keyed to a row another widget owns is
// glued onto that widget's text. Line `i` sits at `bounds.offset.row + i`
// only inside the painted box — paint stops at `size.rows`, and a clip can
// cut it further — so an unpainted line has no row of its own to claim.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../../support/harness.dart';

MouseEvent _m(MouseEventKind kind, int col, int row) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row);

void main() {
  testWidgets('a clipped line does not merge into the widget below', (
    tester,
  ) async {
    tester.pumpWidget(
      const SelectionArea(
        copyOnRelease: true,
        child: Column(
          children: [
            // Two lines of content in one row of space: 'two' never paints.
            SizedBox(height: 1, child: Text('one\ntwo')),
            Text('BOTTOM'),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(12, 4));

    tester.sendMouse(_m(MouseEventKind.down, 0, 0));
    tester.sendMouse(_m(MouseEventKind.drag, 6, 1));
    tester.sendMouse(_m(MouseEventKind.up, 6, 1));
    await Future<void>.delayed(Duration.zero);

    expect(
      tester.clipboard.readInProcess(),
      'one\nBOTTOM',
      reason:
          'the unpainted line must not be keyed onto BOTTOM row and copied '
          'as `one\\ntwoBOTTOM`',
    );
  });
}
