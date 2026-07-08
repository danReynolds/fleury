// present(): modal routes on the Navigator — a dialog/sheet over the
// page beneath, dismissed by pop/Esc, returning a typed result.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester, {required int cols, required int rows}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  testWidgets('a dialog shows over the page; the page stays visible', (
    tester,
  ) async {
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;

    nav.present<void>(const Text('OK'));
    tester.pump(const Duration(milliseconds: 300));
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    final out = _screen(tester, cols: 16, rows: 7);
    expect(out.contains('page'), isTrue, reason: 'page paints behind');
    expect(out.contains('OK'), isTrue, reason: 'dialog paints on top');
    expect(nav.depth, 2, reason: 'dialog is a route on the stack');
  });

  testWidgets('pop returns the dialog result', (tester) async {
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;

    final future = nav.present<int>(const Text('pick'));
    tester.pump(const Duration(milliseconds: 300));
    nav.pop(7);
    expect(await future, 7);

    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 1, reason: 'back to the page');
  });

  testWidgets('Esc dismisses the dialog', (tester) {
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;

    nav.present<void>(const Focus(autofocus: true, child: Text('dialog')));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 2);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 1, reason: 'Esc popped the modal');
  });

  testWidgets('a dialog dims nothing but traps input to itself', (tester) {
    // The dialog's TextInput receives typing; the page behind doesn't.
    final dialogInput = TextEditingController();
    final pageInput = TextEditingController();
    tester.pumpWidget(
      Navigator(home: TextInput(controller: pageInput, autofocus: true)),
    );
    final nav = tester.binding.rootNavigator!;
    tester.type('a');
    expect(pageInput.text, 'a');

    nav.present<void>(TextInput(controller: dialogInput, autofocus: true));
    tester.pump(const Duration(milliseconds: 300));
    tester.type('b');
    expect(dialogInput.text, 'b', reason: 'dialog captured focus');
    expect(pageInput.text, 'a', reason: 'page no longer receives input');
  });

  testWidgets('a presented modal traverses focus between its focusables with '
      'no group of its own', (tester) {
    // The Navigator gives every route (incl. a presented modal) its own
    // FocusTraversalGroup, so arrows move focus within the modal out of the box
    // — and, because the modal FocusScope traps, they can't escape to the page.
    final inA = FocusNode(debugLabel: 'inA');
    final inB = FocusNode(debugLabel: 'inB');
    tester.pumpWidget(
      Navigator(home: const Focus(autofocus: true, child: Text('page'))),
    );
    final nav = tester.binding.rootNavigator!;

    nav.present<void>(
      Column(
        children: [
          Focus(focusNode: inA, autofocus: true, child: const Text('A')),
          Focus(focusNode: inB, child: const Text('B')),
        ],
      ),
    );
    tester.pump(const Duration(milliseconds: 300));
    tester.render(size: const CellSize(20, 5));
    expect(inA.hasFocus, isTrue, reason: 'modal autofocuses its first field');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.render(size: const CellSize(20, 5));
    expect(
      inB.hasFocus,
      isTrue,
      reason: 'arrowDown traverses within the modal via its per-route group',
    );

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.render(size: const CellSize(20, 5));
    expect(
      inB.hasFocus,
      isTrue,
      reason: 'nothing below B and the modal traps focus — it stays on B',
    );
  });

  testWidgets('a sheet anchors to the bottom edge', (tester) async {
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;

    nav.present<void>(const Text('sheet'), alignment: Alignment.bottomCenter);
    tester.pump(const Duration(milliseconds: 400));
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    final rows = _screen(tester, cols: 16, rows: 8).split('\n');
    final sheetRow = rows.indexWhere((r) => r.contains('sheet'));
    expect(sheetRow, greaterThan(3), reason: 'rendered in the lower half');
  });

  testWidgets('a PopScope(canPop: false) dialog refuses Esc', (tester) {
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;

    nav.present<void>(
      const PopScope(
        canPop: false,
        child: Focus(autofocus: true, child: Text('locked')),
      ),
    );
    tester.pump(const Duration(milliseconds: 300));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 2, reason: 'PopScope vetoed the Esc dismissal');
  });

  testWidgets('focus returns to the page after the dialog closes', (tester) {
    final pageInput = TextEditingController();
    tester.pumpWidget(
      Navigator(home: TextInput(controller: pageInput, autofocus: true)),
    );
    final nav = tester.binding.rootNavigator!;
    tester.type('a');

    nav.present<void>(
      TextInput(controller: TextEditingController(), autofocus: true),
    );
    tester.pump(const Duration(milliseconds: 300));
    nav.pop();
    tester.pump(const Duration(milliseconds: 300));

    tester.type('b');
    expect(pageInput.text, 'ab', reason: 'focus restored to the page');
  });

  testWidgets('stacked dialogs: Esc dismisses only the top', (tester) {
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;

    nav.present<void>(const Focus(autofocus: true, child: Text('first')));
    tester.pump(const Duration(milliseconds: 300));
    nav.present<void>(const Focus(autofocus: true, child: Text('second')));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 3);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 2, reason: 'only the top dialog dismissed');
  });
}
