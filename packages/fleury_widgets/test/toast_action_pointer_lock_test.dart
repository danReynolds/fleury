// Lock test (widget-interaction audit §6): ToastAction paints an accented
// label but installs no GestureDetector / pointer handler. Only the global
// shortcut and SemanticAction.activate invoke onPressed. Clicking the visible
// action must dismiss the toast and run the same handler.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('app');
  }
}

void main() {
  testWidgets(
    'clicking the toast action label invokes onPressed and dismisses',
    (tester) {
      late BuildContext ctx;
      var undone = 0;
      tester.pumpWidget(
        Toaster(child: Focus(autofocus: true, child: _Capture((c) => ctx = c))),
      );
      tester.render(size: const CellSize(40, 8));
      Toaster.show(
        ctx,
        'Deleted',
        action: ToastAction(
          label: 'Undo',
          key: KeySequence.alt.u,
          onPressed: () => undone++,
        ),
      );
      tester.pump();

      final buf = tester.render(size: const CellSize(40, 8));
      // Find the 'U' of 'Undo' in the painted toast.
      var undoCol = -1;
      var undoRow = -1;
      for (var r = 0; r < 8 && undoCol < 0; r++) {
        for (var c = 0; c < 36; c++) {
          if (buf.atColRow(c, r).grapheme == 'U' &&
              buf.atColRow(c + 1, r).grapheme == 'n' &&
              buf.atColRow(c + 2, r).grapheme == 'd' &&
              buf.atColRow(c + 3, r).grapheme == 'o') {
            undoCol = c;
            undoRow = r;
            break;
          }
        }
      }
      expect(undoCol, isNonNegative, reason: 'Undo label must be painted');

      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: undoCol,
          row: undoRow,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: undoCol,
          row: undoRow,
        ),
      );
      tester.pump();

      expect(
        undone,
        1,
        reason:
            'clicking the visible action label must invoke onPressed; today '
            'only the Alt+U binding and semantic activate do',
      );
      final after = tester.renderToString(
        size: const CellSize(40, 8),
        emptyMark: ' ',
      );
      expect(
        after.contains('Undo'),
        isFalse,
        reason: 'toast must dismiss after the action runs',
      );
    },
  );
}
