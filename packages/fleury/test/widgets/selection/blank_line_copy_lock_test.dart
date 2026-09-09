// Lock test: a selected blank line survives the copy.
//
// `SelectionContainerDelegate.getSelectedText` joins the rows it is handed
// with `\n`, so a row that reports nothing disappears entirely — a blank line
// between two paragraphs would come back as a single newline instead of two.
// `selectedTextByScreenRow` therefore records an EMPTY fragment for a selected
// blank line rather than skipping it.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../../support/harness.dart';

MouseEvent _at(MouseEventKind kind, int col, int row) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row);

void main() {
  testWidgets('a blank line inside the selection is copied as a blank line', (
    tester,
  ) async {
    tester.pumpWidget(
      const SelectionArea(copyOnRelease: true, child: Text('a\n\nb')),
    );
    tester.render(size: const CellSize(12, 4));

    tester.sendMouse(_at(MouseEventKind.down, 0, 0));
    tester.sendMouse(_at(MouseEventKind.drag, 1, 2));
    tester.sendMouse(_at(MouseEventKind.up, 1, 2));
    await Future<void>.delayed(Duration.zero);

    expect(
      tester.clipboard.readInProcess(),
      'a\n\nb',
      reason: 'the empty row still separates the two paragraphs',
    );
  });

  testWidgets('trailing blank rows outside the selection are not added', (
    tester,
  ) async {
    tester.pumpWidget(
      const SelectionArea(copyOnRelease: true, child: Text('a\n\nb')),
    );
    tester.render(size: const CellSize(12, 4));

    // Stop at the end of the first line: the blank row below is not selected.
    tester.sendMouse(_at(MouseEventKind.down, 0, 0));
    tester.sendMouse(_at(MouseEventKind.drag, 1, 0));
    tester.sendMouse(_at(MouseEventKind.up, 1, 0));
    await Future<void>.delayed(Duration.zero);

    expect(tester.clipboard.readInProcess(), 'a');
  });
}
