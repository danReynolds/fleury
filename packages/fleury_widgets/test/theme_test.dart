// End-to-end: a custom Theme restyles widgets, both in-tree (Tree) and
// in overlay content threaded from the in-tree context (Menu).

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('Theme.selectionStyle restyles an in-tree Tree selection', (
    tester,
  ) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(selectionStyle: CellStyle(bold: true)),
        child: Tree<String>(autofocus: true, roots: [TreeNode<String>('a')]),
      ),
    );
    final buf = tester.render(size: const CellSize(8, 1));
    // Row 0 ('a') is selected; the marker cell should be bold (not inverse).
    expect(buf.atColRow(2, 0).style.bold, isTrue);
    expect(
      buf.atColRow(2, 0).style.inverse,
      isFalse,
      reason: 'theme overrode the default inverse selection',
    );
  });

  testWidgets('Theme threads selectionStyle into an overlay Menu', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(selectionStyle: CellStyle(underline: true)),
        child: Menu(
          trigger: const Text('File'),
          autofocus: true,
          items: [MenuItem(label: 'New', onSelect: () {})],
        ),
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter)); // open
    final buf = tester.render(size: const CellSize(20, 6));
    // Find the 'N' of the selected "New" row and check it's underlined.
    var found = false;
    for (var r = 0; r < 6 && !found; r++) {
      for (var c = 0; c < 20; c++) {
        if (buf.atColRow(c, r).grapheme == 'N') {
          expect(buf.atColRow(c, r).style.underline, isTrue);
          expect(buf.atColRow(c, r).style.inverse, isFalse);
          found = true;
          break;
        }
      }
    }
    expect(found, isTrue, reason: 'menu opened with the selected row');
  });

  testWidgets('Toaster severity colors come from the theme colorScheme', (
    tester,
  ) {
    late BuildContext ctx;
    tester.pumpWidget(
      Theme(
        data: const ThemeData(colorScheme: ColorScheme(error: AnsiColor(13))),
        child: Toaster(child: _Capture((c) => ctx = c)),
      ),
    );
    Toaster.show(ctx, 'boom', severity: ToastSeverity.error);
    tester.pump();
    final buf = tester.render(size: const CellSize(20, 8));
    // Severity color lands on the status dot (the message stays neutral).
    var found = false;
    for (var r = 0; r < 8 && !found; r++) {
      for (var c = 0; c < 20; c++) {
        if (buf.atColRow(c, r).grapheme == '●') {
          expect(buf.atColRow(c, r).style.foreground, const AnsiColor(13));
          found = true;
          break;
        }
      }
    }
    expect(found, isTrue);
  });
}

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('app');
  }
}
