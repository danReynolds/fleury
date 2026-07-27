// Styled-component selection convention: interactive stock controls are NOT
// part of the ambient text selection — the terminal analogue of a browser
// making `<button>` text non-selectable (`user-select: none`). Plain Text
// stays selectable. See SelectionArea.disabled wiring in controls.dart.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

MouseEvent _d(int c, int r) => MouseEvent(
  kind: MouseEventKind.down,
  button: MouseButton.left,
  col: c,
  row: r,
);
MouseEvent _m(int c, int r) => MouseEvent(
  kind: MouseEventKind.drag,
  button: MouseButton.left,
  col: c,
  row: r,
);
MouseEvent _u(int c, int r) => MouseEvent(
  kind: MouseEventKind.up,
  button: MouseButton.left,
  col: c,
  row: r,
);

void _dragAcross(FleuryTester tester, int toCol) {
  tester.sendMouse(_d(0, 0));
  tester.sendMouse(_m(toCol, 0));
  tester.sendMouse(_u(toCol, 0));
}

void main() {
  testWidgets('an enabled Button is not selectable text', (tester) {
    tester.pumpWidget(Button(label: 'Save', onPressed: () {}));
    tester.render(size: const CellSize(20, 3));
    _dragAcross(tester, 9); // across "[ Save ]"
    tester.press(KeySequence.ctrl.c);
    expect(
      tester.clipboard.readInProcess(),
      isNull,
      reason: 'a styled control is not selectable text',
    );
  });

  testWidgets('a disabled Button is not selectable text', (tester) {
    tester.pumpWidget(const Button(label: 'Save', onPressed: null));
    tester.render(size: const CellSize(20, 3));
    _dragAcross(tester, 9);
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), isNull);
  });

  testWidgets('a plain Text IS still selectable', (tester) {
    tester.pumpWidget(const Text('hello world'));
    tester.render(size: const CellSize(20, 3));
    _dragAcross(tester, 11);
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), 'hello world');
  });
}
