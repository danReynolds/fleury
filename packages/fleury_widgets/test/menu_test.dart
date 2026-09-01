import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester, {int cols = 16, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

/// A full left-click (press + release) at one cell. Render first so the
/// pointer router has the current paint-time rects.
void _clickAt(FleuryTester tester, {required int col, required int row}) {
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
  List<MenuItem> items(void Function(String) onRun) => [
    MenuItem(label: 'Cut', onSelect: () => onRun('cut')),
    MenuItem(label: 'Copy', onSelect: () => onRun('copy')),
    MenuItem(label: 'Paste', onSelect: () => onRun('paste')),
  ];

  testWidgets('closed by default — only the trigger shows', (tester) {
    tester.pumpWidget(
      Menu(trigger: const Text('Edit'), autofocus: true, items: items((_) {})),
    );
    final out = _screen(tester);
    expect(out.contains('Edit'), isTrue);
    expect(out.contains('Copy'), isFalse, reason: 'menu is closed');
  });

  testWidgets('Enter opens the menu anchored below the trigger', (tester) {
    tester.pumpWidget(
      Menu(trigger: const Text('Edit'), autofocus: true, items: items((_) {})),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter));
    final out = _screen(tester);
    expect(out.contains('Cut'), isTrue);
    expect(out.contains('Paste'), isTrue);
  });

  testWidgets('clicking the trigger opens the menu (pointer users)', (tester) {
    tester.pumpWidget(Menu(trigger: const Text('Edit'), items: items((_) {})));
    // Render so the pointer router has the trigger's paint-time rect, then
    // click the trigger glyphs at the top-left.
    tester.render(size: const CellSize(16, 8));
    expect(_screen(tester).contains('Copy'), isFalse, reason: 'closed first');
    _clickAt(tester, col: 1, row: 0);
    expect(
      _screen(tester).contains('Copy'),
      isTrue,
      reason: 'a tap on the trigger opens the menu',
    );
    // A second tap on the trigger closes it again.
    tester.render(size: const CellSize(16, 8));
    _clickAt(tester, col: 1, row: 0);
    expect(
      _screen(tester).contains('Copy'),
      isFalse,
      reason: 'tapping the trigger again closes the menu',
    );
    expect(
      tester.focusManager.focusedNode?.debugLabel,
      'menu-trigger',
      reason: 'the outer close path retires the trap before restoring focus',
    );
  });

  testWidgets('Down + Enter runs the selected item and closes', (tester) {
    String? ran;
    tester.pumpWidget(
      Menu(
        trigger: const Text('Edit'),
        autofocus: true,
        items: items((v) => ran = v),
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter)); // open
    tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Copy
    tester.sendKey(const KeyEvent(KeyCode.enter)); // run
    expect(ran, 'copy');
    expect(_screen(tester).contains('Paste'), isFalse, reason: 'menu closed');
  });

  testWidgets('clicking a menu item runs it and closes', (tester) {
    String? ran;
    tester.pumpWidget(
      Menu(
        trigger: const Text('Edit'),
        autofocus: true,
        items: items((v) => ran = v),
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter)); // open
    // The menu opens anchored below the trigger inside a border; 'Copy' is the
    // second item, at row 3, with its label past the left border at col 3.
    tester.render(size: const CellSize(16, 8));
    _clickAt(tester, col: 3, row: 3);
    expect(ran, 'copy', reason: 'click activated the item under the pointer');
    expect(_screen(tester).contains('Paste'), isFalse, reason: 'menu closed');
  });

  testWidgets('Esc closes without selecting', (tester) {
    var ran = false;
    tester.pumpWidget(
      Menu(
        trigger: const Text('Edit'),
        autofocus: true,
        items: [MenuItem(label: 'Delete', onSelect: () => ran = true)],
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter)); // open
    expect(_screen(tester).contains('Delete'), isTrue);
    tester.sendKey(const KeyEvent(KeyCode.escape)); // close
    expect(ran, isFalse);
    expect(_screen(tester).contains('Delete'), isFalse);
  });

  // The float pointer barrier. An open Menu paints over the app, so it must
  // own those cells for INPUT too — otherwise a click "on the menu's backdrop"
  // silently fires whatever is painted underneath. `Select` had this from the
  // start; `Menu` inserted a bare `BoundsAnchor` and did not.
  testWidgets('a click outside the open menu dismisses it and does not reach '
      'the app behind', (tester) {
    var fired = 0;
    Widget app() => Column(
      children: [
        Menu(trigger: const Text('Edit'), autofocus: true, items: items((_) {})),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: () => fired++,
          child: const Text('DANGER'),
        ),
      ],
    );

    tester.pumpWidget(app());
    tester.render(size: const CellSize(20, 10));
    _clickAt(tester, col: 2, row: 6);
    expect(fired, 1, reason: 'the button works with no menu open');

    tester.sendKey(const KeyEvent(KeyCode.enter)); // open the menu
    expect(_screen(tester, cols: 20, rows: 10).contains('Cut'), isTrue);
    tester.render(size: const CellSize(20, 10)); // register pointer regions

    _clickAt(tester, col: 2, row: 6); // outside the panel, over 'DANGER'
    expect(
      fired,
      1,
      reason: 'the barrier swallowed the click meant for the app behind',
    );
    expect(
      _screen(tester, cols: 20, rows: 10).contains('Cut'),
      isFalse,
      reason: 'clicking outside dismissed the menu',
    );
  });

  testWidgets('clicks on the open menu still reach its rows', (tester) {
    // The barrier is a floor, not a lid: regions inside the panel paint later
    // and keep winning.
    String? ran;
    tester.pumpWidget(
      Menu(
        trigger: const Text('Edit'),
        autofocus: true,
        items: items((v) => ran = v),
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter)); // open
    final out = _screen(tester, cols: 20, rows: 10);
    final row = out.split('\n').indexWhere((r) => r.contains('Copy'));
    tester.render(size: const CellSize(20, 10));
    _clickAt(tester, col: 3, row: row);
    expect(ran, 'copy');
  });

  testWidgets('focus returns to the trigger after close (reopens)', (tester) {
    tester.pumpWidget(
      Menu(trigger: const Text('Edit'), autofocus: true, items: items((_) {})),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter)); // open
    tester.sendKey(const KeyEvent(KeyCode.escape)); // close
    expect(_screen(tester).contains('Cut'), isFalse);
    // The trigger is focused again, so Enter reopens.
    tester.sendKey(const KeyEvent(KeyCode.enter));
    expect(
      _screen(tester).contains('Cut'),
      isTrue,
      reason: 'trigger refocused',
    );
  });

  group('separators & disabled items', () {
    testWidgets('a separator renders a rule and is skipped by Down', (tester) {
      String? ran;
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          autofocus: true,
          items: [
            MenuItem(label: 'Cut', onSelect: () => ran = 'cut'),
            const MenuSeparator(),
            MenuItem(label: 'Paste', onSelect: () => ran = 'paste'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open
      expect(_screen(tester).contains('─'), isTrue, reason: 'rule drawn');
      // One Down should skip the separator and land on Paste.
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(ran, 'paste');
    });

    testWidgets('a disabled item is skipped and not invokable', (tester) {
      String? ran;
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          autofocus: true,
          items: [
            MenuItem(label: 'Cut', onSelect: () => ran = 'cut'),
            MenuItem(
              label: 'Copy',
              enabled: false,
              onSelect: () => ran = 'copy',
            ),
            MenuItem(label: 'Paste', onSelect: () => ran = 'paste'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // skip Copy
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(ran, 'paste', reason: 'Down hopped over the disabled Copy');
    });

    testWidgets('selection starts on the first enabled item', (tester) {
      String? ran;
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          autofocus: true,
          items: [
            MenuItem(label: 'Off', enabled: false, onSelect: () => ran = 'off'),
            MenuItem(label: 'On', onSelect: () => ran = 'on'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open
      tester.sendKey(const KeyEvent(KeyCode.enter)); // activate
      expect(ran, 'on', reason: 'first selectable, not the disabled first row');
    });
  });

  group('submenus', () {
    Menu fileMenu(void Function(String) onRun) => Menu(
      trigger: const Text('File'),
      semanticLabel: 'File menu',
      autofocus: true,
      items: [
        MenuItem(label: 'New', onSelect: () => onRun('new')),
        SubMenu(
          label: 'Open',
          items: [
            MenuItem(label: 'Recent', onSelect: () => onRun('recent')),
            MenuItem(label: 'Browse', onSelect: () => onRun('browse')),
          ],
        ),
      ],
    );

    testWidgets('Right opens a submenu to the right', (tester) {
      tester.pumpWidget(fileMenu((_) {}));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open root
      final root = _screen(tester, cols: 30);
      expect(root.contains('Open'), isTrue);
      expect(root.contains('▸'), isTrue, reason: 'submenu cascade indicator');

      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // open submenu
      final out = _screen(tester, cols: 30);
      expect(out.contains('Recent'), isTrue, reason: 'submenu items visible');
      expect(out.contains('Browse'), isTrue);
    });

    testWidgets('choosing a submenu leaf runs it and closes everything', (
      tester,
    ) {
      String? ran;
      tester.pumpWidget(fileMenu((v) => ran = v));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open submenu
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Browse
      tester.sendKey(const KeyEvent(KeyCode.enter)); // run Browse
      expect(ran, 'browse');
      expect(
        _screen(tester, cols: 30).contains('Recent'),
        isFalse,
        reason: 'the whole menu closed',
      );
      expect(_screen(tester, cols: 30).contains('New'), isFalse);
    });

    testWidgets('Left steps back out of a submenu to the parent', (tester) {
      tester.pumpWidget(fileMenu((_) {}));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // open submenu
      expect(_screen(tester, cols: 30).contains('Recent'), isTrue);

      tester.sendKey(const KeyEvent(KeyCode.arrowLeft)); // back out
      final out = _screen(tester, cols: 30);
      expect(out.contains('Recent'), isFalse, reason: 'submenu closed');
      expect(out.contains('Open'), isTrue, reason: 'parent still open');
      expect(
        out.contains('▸'),
        isTrue,
        reason: 'cascade indicator still shown',
      );
    });

    // The root panel's barrier is the only one in the chain: submenu entries
    // paint above it, so their own rows keep winning, and an outside click
    // still lands on the root barrier and closes everything.
    testWidgets('a submenu leaf is still clickable with the root barrier '
        'down', (tester) {
      String? ran;
      tester.pumpWidget(fileMenu((v) => ran = v));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // open submenu
      final out = _screen(tester, cols: 30, rows: 10);
      final row = out.split('\n').indexWhere((r) => r.contains('Browse'));
      final col = out.split('\n')[row].indexOf('Browse');
      tester.render(size: const CellSize(30, 10));
      _clickAt(tester, col: col, row: row);
      expect(ran, 'browse', reason: 'the submenu row owns its own cells');
      expect(
        _screen(tester, cols: 30, rows: 10).contains('New'),
        isFalse,
        reason: 'the leaf selection closed the whole chain',
      );
      expect(
        tester.focusManager.focusedNode?.debugLabel,
        'menu-trigger',
        reason: 'each panel retired its focus trap on the way out',
      );
    });

    testWidgets('a click outside an open submenu closes the whole chain', (
      tester,
    ) {
      tester.pumpWidget(fileMenu((_) {}));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // open submenu
      expect(_screen(tester, cols: 30, rows: 10).contains('Recent'), isTrue);

      tester.render(size: const CellSize(30, 10));
      _clickAt(tester, col: 28, row: 9); // far from both panels
      final out = _screen(tester, cols: 30, rows: 10);
      expect(out.contains('Recent'), isFalse, reason: 'submenu gone');
      expect(out.contains('New'), isFalse, reason: 'root panel gone');
      expect(
        tester.focusManager.focusedNode?.debugLabel,
        'menu-trigger',
        reason: 'the outside click retired the trap and restored focus',
      );
    });

    testWidgets('moving between two adjacent submenu rows re-targets the '
        'anchor', (tester) {
      // Only the SELECTED submenu row is wrapped in the BoundsObserver that
      // anchors the child panel. Moving the selection between two adjacent
      // SubMenu rows therefore changed BOTH rows' widget type in one build
      // pass: the new observer's render object claimed the notifier while the
      // old row's element was still parked in `_inactiveElements` (finalized
      // only after the flush loop), so the single-writer assert fired with
      // "This BoundsNotifier already has a BoundsObserver".
      String? ran;
      tester.pumpWidget(
        Menu(
          trigger: const Text('Menu'),
          autofocus: true,
          items: [
            SubMenu(
              label: 'File',
              items: [MenuItem(label: 'New', onSelect: () => ran = 'new')],
            ),
            SubMenu(
              label: 'Edit',
              items: [MenuItem(label: 'Undo', onSelect: () => ran = 'undo')],
            ),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open, File selected
      tester.render(size: const CellSize(30, 10));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // File → Edit
      tester.render(size: const CellSize(30, 10));
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // open Edit's submenu

      final out = _screen(tester, cols: 30, rows: 10);
      expect(out.contains('Undo'), isTrue, reason: "Edit's submenu opened");
      expect(out.contains('New'), isFalse, reason: "not File's submenu");
      // Anchored to the Edit ROW (row 2 of the panel), not the panel corner.
      final lines = out.split('\n');
      expect(
        lines.indexWhere((l) => l.contains('Undo')),
        lines.indexWhere((l) => l.contains('Edit')),
        reason: 'the submenu is aligned with the row that opened it',
      );

      tester.sendKey(const KeyEvent(KeyCode.enter)); // run Undo
      expect(ran, 'undo');
    });

    testWidgets('closing the whole menu from outside the chain restores '
        'focus to the trigger', (tester) async {
      // Any close driven from OUTSIDE the panel chain — the semantic close
      // action here, the pointer barrier, a tap on the trigger — removes the
      // root overlay entry in one go, while the submenu's entry is only
      // unmounted on the next build flush. Its focus trap therefore had to be
      // released explicitly; without that the restore was refused and the
      // keyboard was left on no node at all.
      tester.pumpWidget(fileMenu((_) {}));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // open submenu
      tester.render(size: const CellSize(30, 10));

      await tester.invokeSemanticAction(
        SemanticAction.close,
        role: SemanticRole.button,
        label: 'File menu',
      );
      tester.pump();

      final out = _screen(tester, cols: 30, rows: 10);
      expect(out.contains('Recent'), isFalse, reason: 'submenu gone');
      expect(out.contains('New'), isFalse, reason: 'root panel gone');
      expect(
        tester.focusManager.focusedNode?.debugLabel,
        'menu-trigger',
        reason: 'the whole chain retired its traps before the restore',
      );
    });

    testWidgets('Esc from a submenu returns to the parent, not all the way', (
      tester,
    ) {
      tester.pumpWidget(fileMenu((_) {}));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // open submenu
      tester.sendKey(const KeyEvent(KeyCode.escape)); // close submenu
      final out = _screen(tester, cols: 30);
      expect(out.contains('Recent'), isFalse);
      expect(out.contains('New'), isTrue, reason: 'parent menu still open');
    });
  });

  group('semantics', () {
    testWidgets('trigger semantic action opens the menu', (tester) async {
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          semanticLabel: 'Edit menu',
          autofocus: true,
          items: items((_) {}),
        ),
      );

      final trigger = tester.semantics().single(
        role: SemanticRole.button,
        label: 'Edit menu',
        action: SemanticAction.open,
      );

      expect(trigger.focused, isTrue);
      expect(trigger.expanded, isFalse);
      expect(trigger.state.menuItemCount, 3);

      final result = await tester.invokeSemanticAction(
        SemanticAction.open,
        node: trigger,
      );

      expect(result.completed, isTrue);
      tester.render(size: const CellSize(30, 8));
      final tree = tester.semantics();
      final menu = tree.single(role: SemanticRole.menu, label: 'Edit menu');
      expect(menu.focused, isTrue);
      expect(menu.expanded, isTrue);
      expect(menu.state.menuItemCount, 3);
      expect(tree.byRole(SemanticRole.menuItem).map((node) => node.label), [
        'Cut',
        'Copy',
        'Paste',
      ]);
    });

    testWidgets('menu item semantic activate runs the item and closes', (
      tester,
    ) async {
      String? ran;
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          semanticLabel: 'Edit menu',
          autofocus: true,
          items: items((v) => ran = v),
        ),
      );

      await tester.invokeSemanticAction(
        SemanticAction.open,
        role: SemanticRole.button,
        label: 'Edit menu',
      );
      tester.render(size: const CellSize(30, 8));
      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.menuItem,
        label: 'Copy',
      );

      expect(result.completed, isTrue);
      expect(ran, 'copy');
      expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Edit menu')
            .expanded,
        isFalse,
      );
    });

    testWidgets('submenu semantic open exposes child menu semantics', (
      tester,
    ) async {
      tester.pumpWidget(
        Menu(
          trigger: const Text('File'),
          semanticLabel: 'File menu',
          autofocus: true,
          items: [
            MenuItem(label: 'New', onSelect: () {}),
            SubMenu(
              label: 'Open',
              items: [
                MenuItem(label: 'Recent', onSelect: () {}),
                MenuItem(label: 'Browse', onSelect: () {}),
              ],
            ),
          ],
        ),
      );
      await tester.invokeSemanticAction(
        SemanticAction.open,
        role: SemanticRole.button,
        label: 'File menu',
      );
      tester.render(size: const CellSize(40, 8));

      final result = await tester.invokeSemanticAction(
        SemanticAction.open,
        role: SemanticRole.menuItem,
        label: 'Open',
      );

      expect(result.completed, isTrue);
      tester.render(size: const CellSize(40, 8));
      final tree = tester.semantics();
      final submenu = tree.single(role: SemanticRole.menu, label: 'Open');
      expect(submenu.state.menuDepth, 1);
      expect(submenu.state.menuItemCount, 2);
      expect(
        tree.single(role: SemanticRole.menuItem, label: 'Recent'),
        isNotNull,
      );
      expect(
        tree.single(role: SemanticRole.menuItem, label: 'Open').expanded,
        isTrue,
      );
    });

    testWidgets('accessibility fallback summarizes menu item positions', (
      tester,
    ) async {
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          semanticLabel: 'Edit menu',
          autofocus: true,
          items: items((_) {}),
        ),
      );

      await tester.invokeSemanticAction(
        SemanticAction.open,
        role: SemanticRole.button,
        label: 'Edit menu',
      );
      tester.render(size: const CellSize(30, 8));

      final snapshot = tester.accessibilitySnapshot();
      final menu = snapshot.single(
        role: SemanticRole.menu,
        label: 'Edit menu',
        state: 'menu 3 items',
      );
      final cut = snapshot.single(
        role: SemanticRole.menuItem,
        label: 'Cut',
        selected: true,
        state: 'menu item 1 of 3',
      );

      expect(menu.announcement, contains('focused'));
      expect(cut.announcement, contains('actions: activate'));
    });
  });

  testWidgets('sanitizes unsafe item labels for display and semantics', (
    tester,
  ) {
    tester.pumpWidget(
      Menu(
        trigger: const Text('Edit'),
        autofocus: true,
        items: [
          MenuItem(label: 'Cut\x1b]52;c;secret\x07here', onSelect: () {}),
        ],
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.enter)); // open
    final out = _screen(tester, cols: 32);
    expect(out, isNot(contains('secret')));
    expect(out, contains(replacementCharacter));
    final row = tester.semantics().single(role: SemanticRole.menuItem);
    expect(row.label, contains(replacementCharacter));
    expect(row.label, isNot(contains('secret')));
  });
}
