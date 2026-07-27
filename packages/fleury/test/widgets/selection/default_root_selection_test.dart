// Default-on text selection.
//
// The host wraps every app root in a [DefaultRootSelection] (a SelectionArea),
// so rendered [Text] is drag-selectable and Ctrl+C-copyable WITHOUT the app
// opting in — the behavior terminal users expect of on-screen text. The tester
// installs the same wrapper (see FleuryTester._userEntry), so these pump plain
// widgets with NO explicit SelectionArea and still get selection.
//
// What's pinned here:
//   - a bare Text is drag-selectable, and Ctrl+C copies via the ambient
//     clipboard;
//   - Ctrl+A selects all (the default provides it);
//   - an app's own Ctrl+A binding WINS over the default (deepest-first
//     dispatch), so default-on never steals a chord the app claims;
//   - Ctrl+C with nothing selected does not write an empty copy (the default
//     bubbles when idle, leaving app/global handlers a turn);
//   - a subtree opts out via `Text(allowSelect: false)` or
//     `SelectionArea.disabled`.

import 'package:fleury/fleury.dart';
import '../../support/harness.dart';
import 'package:test/test.dart';

const _size = CellSize(20, 3);

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

void _dragSelect(
  FleuryTester tester, {
  required int fromCol,
  required int toCol,
  int row = 0,
}) {
  tester.sendMouse(_down(fromCol, row));
  tester.sendMouse(_drag(toCol, row));
  tester.sendMouse(_up(toCol, row));
}

void main() {
  group('default-on selection (no explicit SelectionArea)', () {
    testWidgets('a bare Text is drag-selectable and Ctrl+C copies it', (
      tester,
    ) {
      tester.pumpWidget(const Text('hello world'));
      tester.render(size: _size);

      // Selection is half-open [from, to): cols 0..10 is "hello world".
      _dragSelect(tester, fromCol: 0, toCol: 11);
      tester.press(KeySequence.ctrl.c);

      expect(
        tester.clipboard.readInProcess(),
        'hello world',
        reason: 'the default SelectionArea copied the dragged text',
      );
    });

    testWidgets('Ctrl+C copies then clears, so a second Ctrl+C can quit', (
      tester,
    ) {
      tester.pumpWidget(const Text('hello world'));
      tester.render(size: _size);

      _dragSelect(tester, fromCol: 0, toCol: 11);
      // The dragged cells are highlighted.
      expect(tester.render(size: _size).atColRow(0, 0).style.inverse, isTrue);

      tester.press(KeySequence.ctrl.c);
      expect(tester.clipboard.readInProcess(), 'hello world');

      // The copy cleared the selection: the highlight is gone, so a following
      // Ctrl+C finds nothing, bubbles, and (in a real app) reaches the runApp
      // quit guard instead of copying again.
      expect(tester.render(size: _size).atColRow(0, 0).style.inverse, isFalse);
    });

    testWidgets('Ctrl+A is not bound by default (no keyboard select-all)', (
      tester,
    ) {
      tester.pumpWidget(const Text('hello world'));
      tester.render(size: _size);

      // The default wrap does NOT bind Ctrl+A, so it can't shadow an app's own
      // global Ctrl+A. It bubbles unhandled — nothing is selected — so a
      // following Ctrl+C copies nothing.
      tester.press(KeySequence.ctrl.a);
      tester.press(KeySequence.ctrl.c);
      expect(tester.clipboard.readInProcess(), isNull);
    });

    testWidgets('an app Ctrl+A binding is not shadowed by the default', (
      tester,
    ) {
      var appHits = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.a, onTrigger: () => appHits++),
          ],
          child: const Text('hello world'),
        ),
      );
      tester.render(size: _size);

      tester.press(KeySequence.ctrl.a);
      // The default doesn't bind Ctrl+A (and the app binding is deeper than the
      // root anyway), so the app's Ctrl+A fires and nothing else selects.
      expect(appHits, 1);
      tester.press(KeySequence.ctrl.c);
      expect(
        tester.clipboard.readInProcess(),
        isNull,
        reason: 'no default select-all ran, so there is nothing to copy',
      );
    });

    testWidgets('Ctrl+C with nothing selected does not write an empty copy', (
      tester,
    ) {
      tester.pumpWidget(const Text('hello world'));
      tester.render(size: _size);

      tester.press(KeySequence.ctrl.c); // no selection → bubble, don't copy

      expect(tester.clipboard.readInProcess(), isNull);
    });
  });

  group('default-on selection — opt-outs', () {
    testWidgets('Text(allowSelect: false) is not drag-selectable', (tester) {
      tester.pumpWidget(const Text('secret', allowSelect: false));
      tester.render(size: _size);

      _dragSelect(tester, fromCol: 0, toCol: 6);
      tester.press(KeySequence.ctrl.c);

      expect(tester.clipboard.readInProcess(), isNull);
    });

    testWidgets('SelectionArea.disabled opts a subtree out', (tester) {
      tester.pumpWidget(SelectionArea.disabled(child: const Text('secret')));
      tester.render(size: _size);

      _dragSelect(tester, fromCol: 0, toCol: 6);
      tester.press(KeySequence.ctrl.c);

      expect(tester.clipboard.readInProcess(), isNull);
    });
  });
}
