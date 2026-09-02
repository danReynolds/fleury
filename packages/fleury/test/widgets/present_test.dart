// present(): modal routes on the Navigator — a dialog/sheet over the
// page beneath, dismissed by pop/Esc, returning a typed result.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester, {required int cols, required int rows}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void _clickAt(FleuryTester tester, int col, int row) {
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.down,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.up,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
}

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

    tester.sendKey(const KeyEvent(KeyCode.escape));
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
    // — and, because the route enables trapFocus, they can't escape to the page.
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

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.render(size: const CellSize(20, 5));
    expect(
      inB.hasFocus,
      isTrue,
      reason: 'arrowDown traverses within the modal via its per-route group',
    );

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
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
    tester.sendKey(const KeyEvent(KeyCode.escape));
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

  // ---------------------------------------------------------------------
  // The modal barrier: a presented route owns EVERY cell of its slot for
  // input, not just the cells it paints.
  //
  // `present()` already blocked keys (KeyBindings(modal: true)) and focus
  // (FocusScope(trapFocus:)) — but nothing blocked the pointer. A modal route
  // never flips `opaque`, so the covered route keeps its pointer regions
  // registered, and `barrierColor` painted a surround without absorbing over
  // it: the user saw a solid barrier, clicked it, and fired an invisible
  // button on the screen behind.
  // ---------------------------------------------------------------------

  testWidgets('a click on the surround does not reach the screen behind', (
    tester,
  ) {
    var fired = 0;
    tester.pumpWidget(
      Navigator(
        home: GestureDetector(
          onTap: () => fired++,
          child: const Text('DANGER'),
        ),
      ),
    );
    final nav = tester.binding.rootNavigator!;
    tester.render(size: const CellSize(20, 7));
    _clickAt(tester, 2, 0);
    expect(fired, 1, reason: 'the button works with no modal up');

    nav.present<void>(
      const SizedBox(width: 6, height: 3, child: Text('modal')),
    );
    tester.pump(const Duration(milliseconds: 300));
    tester.render(size: const CellSize(20, 7)); // register pointer regions

    _clickAt(tester, 2, 0); // over 'DANGER', outside the modal box
    expect(
      fired,
      1,
      reason: 'the modal barrier swallowed the click on the covered screen',
    );
  });

  testWidgets('a barrierColor modal absorbs clicks over its painted '
      'surround', (tester) {
    var fired = 0;
    tester.pumpWidget(
      Navigator(
        home: GestureDetector(
          onTap: () => fired++,
          child: const Text('DANGER'),
        ),
      ),
    );
    final nav = tester.binding.rootNavigator!;
    nav.present<void>(
      const SizedBox(width: 6, height: 3, child: Text('modal')),
      barrierColor: Colors.black,
    );
    tester.pump(const Duration(milliseconds: 300));
    tester.render(size: const CellSize(20, 7));

    _clickAt(tester, 2, 0);
    expect(fired, 0, reason: 'a painted barrier must absorb, not just paint');
  });

  testWidgets('clicks inside the modal still reach its own controls', (tester) {
    var inner = 0;
    var outer = 0;
    tester.pumpWidget(
      Navigator(
        home: GestureDetector(
          onTap: () => outer++,
          child: const Text('DANGER'),
        ),
      ),
    );
    final nav = tester.binding.rootNavigator!;
    nav.present<void>(
      GestureDetector(
        onTap: () => inner++,
        child: const SizedBox(width: 6, height: 1, child: Text('press')),
      ),
    );
    tester.pump(const Duration(milliseconds: 300));
    final out = _screen(tester, cols: 20, rows: 7);
    final row = out.split('\n').indexWhere((r) => r.contains('press'));
    final col = out.split('\n')[row].indexOf('press');
    tester.render(size: const CellSize(20, 7));

    _clickAt(tester, col + 1, row);
    expect(inner, 1, reason: 'the modal owns clicks on its own content');
    expect(outer, 0, reason: 'nothing leaked to the covered screen');
  });

  testWidgets('a click on the surround does not move focus behind the '
      'modal', (tester) {
    // Click-to-focus is a separate dispatcher pass from tap routing, so the
    // barrier has to block that too (`PointerRouter.focusAbsorbedAt`).
    final page = FocusNode(debugLabel: 'page');
    final modal = FocusNode(debugLabel: 'modal');
    tester.pumpWidget(
      Navigator(
        home: Focus(
          focusNode: page,
          child: const SizedBox(width: 10, height: 1, child: Text('page')),
        ),
      ),
    );
    final nav = tester.binding.rootNavigator!;
    nav.present<void>(
      Focus(
        focusNode: modal,
        autofocus: true,
        child: const SizedBox(width: 6, height: 1, child: Text('modal')),
      ),
    );
    tester.pump(const Duration(milliseconds: 300));
    tester.render(size: const CellSize(20, 7));
    expect(modal.hasFocus, isTrue, reason: 'the modal autofocused');

    _clickAt(tester, 1, 0); // over the page's focusable, outside the modal
    tester.render(size: const CellSize(20, 7));
    expect(
      page.hasFocus,
      isFalse,
      reason: 'click-to-focus must not reach behind the barrier',
    );
    expect(modal.hasFocus, isTrue, reason: 'focus stayed in the modal');
  });

  testWidgets('the barrier does not dismiss on click (Esc still does)', (
    tester,
  ) {
    // Click-outside-to-dismiss is deliberately NOT wired: `barrierDismissible`
    // is documented as Esc-only. The barrier is an input floor, not a
    // dismiss affordance — pinned so adding the barrier didn't quietly
    // change the contract.
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;
    nav.present<void>(const Focus(autofocus: true, child: Text('dialog')));
    tester.pump(const Duration(milliseconds: 300));
    tester.render(size: const CellSize(20, 7));
    expect(nav.depth, 2);

    _clickAt(tester, 0, 0);
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 2, reason: 'a click on the surround is a no-op');

    tester.sendKey(const KeyEvent(KeyCode.escape));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 1, reason: 'Esc still dismisses');
  });

  testWidgets('stacked dialogs: Esc dismisses only the top', (tester) {
    tester.pumpWidget(Navigator(home: const Text('page')));
    final nav = tester.binding.rootNavigator!;

    nav.present<void>(const Focus(autofocus: true, child: Text('first')));
    tester.pump(const Duration(milliseconds: 300));
    nav.present<void>(const Focus(autofocus: true, child: Text('second')));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 3);

    tester.sendKey(const KeyEvent(KeyCode.escape));
    tester.pump(const Duration(milliseconds: 300));
    expect(nav.depth, 2, reason: 'only the top dialog dismissed');
  });
}
