// Text under a tap-handling widget is still selectable.
//
// Tap-down went only to the topmost TAP region, while the drag was armed on
// the topmost DRAG region separately. A tap-only widget (a GestureDetector —
// every ListView item is one) sitting over a SelectionArea therefore starved
// the area of its anchor: the drag that followed had nothing to extend from,
// so list content, logs and transcripts could not be selected at all.

import 'package:fleury/fleury.dart';
import '../../support/harness.dart';
import 'package:test/test.dart';

const _size = CellSize(20, 4);

MouseEvent _mouse(MouseEventKind kind, int col, int row) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row);

void _dragSelect(
  FleuryTester tester, {
  required (int, int) from,
  required (int, int) to,
}) {
  tester.sendMouse(_mouse(MouseEventKind.down, from.$1, from.$2));
  tester.sendMouse(_mouse(MouseEventKind.drag, to.$1, to.$2));
  tester.sendMouse(_mouse(MouseEventKind.up, to.$1, to.$2));
}

void main() {
  testWidgets('text inside a GestureDetector is drag-selectable', (tester) {
    var taps = 0;
    tester.pumpWidget(
      GestureDetector(onTap: () => taps++, child: const Text('hello world')),
    );
    tester.render(size: _size);

    _dragSelect(tester, from: (0, 0), to: (5, 0));
    tester.press(KeySequence.ctrl.c);

    expect(tester.clipboard.readInProcess(), 'hello');
    expect(taps, 0, reason: 'a completed drag is not a tap');
  });

  testWidgets('a plain click on it still taps', (tester) {
    var taps = 0;
    tester.pumpWidget(
      GestureDetector(onTap: () => taps++, child: const Text('hello world')),
    );
    tester.render(size: _size);

    tester.sendMouse(_mouse(MouseEventKind.down, 2, 0));
    tester.sendMouse(_mouse(MouseEventKind.up, 2, 0));
    expect(taps, 1);
  });

  testWidgets('ListView items are selectable across rows', (tester) {
    tester.pumpWidget(
      ListView(children: const [Text('alpha'), Text('beta'), Text('gamma')]),
    );
    tester.render(size: _size);

    _dragSelect(tester, from: (0, 0), to: (4, 1));
    tester.press(KeySequence.ctrl.c);

    final copied = tester.clipboard.readInProcess() ?? '';
    expect(copied, contains('alpha'));
    expect(copied, contains('beta'));
    expect(copied, isNot(contains('gamma')));
  });
}
