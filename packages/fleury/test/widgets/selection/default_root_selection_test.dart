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
      expect(tester.render(size: _size).atColRow(0, 0).style.reverse, isTrue);

      tester.press(KeySequence.ctrl.c);
      expect(tester.clipboard.readInProcess(), 'hello world');

      // The copy cleared the selection: the highlight is gone, so a following
      // Ctrl+C finds nothing, bubbles, and (in a real app) reaches the runApp
      // quit guard instead of copying again.
      expect(tester.render(size: _size).atColRow(0, 0).style.reverse, isFalse);
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
            KeyBinding(KeySequence.ctrl.a, onTrigger: (_) => appHits++),
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
  group('modal routes get their own selection scope', () {
    // A presented route installs a key-binding boundary, which cuts the
    // background out of the active chain — taking the app-root selection
    // scope's Ctrl+C with it. Without a selection scope of its own, the
    // dialog's text highlighted but never copied.
    testWidgets('text presented in a modal route can be selected AND copied', (
      tester,
    ) {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _CaptureContext(
            sink: (context) => home = context,
            child: const Focus(autofocus: true, child: Text('app behind')),
          ),
        ),
      );
      tester.render(size: _modalSize);

      home!.present<void>(
        const Text('error: exit code 517'),
        transition: RouteTransition.none,
      );
      tester.pump();

      final at = _find(tester, 'error:');
      expect(at, isNotNull, reason: 'the route is up');
      _dragSelect(tester, fromCol: at!.col, toCol: at.col + 20, row: at.row);
      expect(
        tester.render(size: _modalSize).atColRow(at.col, at.row).style.reverse,
        isTrue,
        reason: 'the drag highlighted it',
      );

      tester.press(KeySequence.ctrl.c);
      expect(tester.clipboard.readInProcess(), 'error: exit code 517');
    });

    testWidgets('Esc clears a held selection first, then dismisses', (tester) {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _CaptureContext(
            sink: (context) => home = context,
            child: const Focus(autofocus: true, child: Text('app behind')),
          ),
        ),
      );
      tester.render(size: _modalSize);
      home!.present<void>(
        const Text('error: exit code 517'),
        transition: RouteTransition.none,
      );
      tester.pump();

      final at = _find(tester, 'error:')!;
      _dragSelect(tester, fromCol: at.col, toCol: at.col + 8, row: at.row);

      // First Esc clears the selection (the innermost thing Esc can back out
      // of) and consumes the key; the route stays. The second finds nothing
      // selected, bubbles, and pops — the same two-step contract Ctrl+C uses.
      tester.press(KeySequence.escape);
      tester.pump();
      expect(
        _find(tester, 'error:'),
        isNotNull,
        reason: 'the first Esc cleared the selection, not the route',
      );
      expect(
        tester.render(size: _modalSize).atColRow(at.col, at.row).style.reverse,
        isFalse,
        reason: 'the selection is gone',
      );

      tester.press(KeySequence.escape);
      tester.pump();
      expect(_find(tester, 'error:'), isNull, reason: 'the second Esc popped');
    });
  });
}

const _modalSize = CellSize(44, 8);

/// First (col,row) where [needle] starts in the rendered buffer, or null.
({int col, int row})? _find(FleuryTester tester, String needle) {
  final buf = tester.render(size: _modalSize);
  for (var r = 0; r < _modalSize.rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < _modalSize.cols; c++) {
      sb.write(buf.atColRow(c, r).grapheme ?? ' ');
    }
    final i = sb.toString().indexOf(needle);
    if (i >= 0) return (col: i, row: r);
  }
  return null;
}

class _CaptureContext extends StatelessWidget {
  const _CaptureContext({required this.sink, required this.child});

  final void Function(BuildContext) sink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    sink(context);
    return child;
  }
}
