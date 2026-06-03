import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester, {int cols = 16, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  List<MenuItem> items(void Function(String) onRun) => [
    MenuItem(label: 'Cut', onSelected: () => onRun('cut')),
    MenuItem(label: 'Copy', onSelected: () => onRun('copy')),
    MenuItem(label: 'Paste', onSelected: () => onRun('paste')),
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
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    final out = _screen(tester);
    expect(out.contains('Cut'), isTrue);
    expect(out.contains('Paste'), isTrue);
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
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Copy
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // run
    expect(ran, 'copy');
    expect(_screen(tester).contains('Paste'), isFalse, reason: 'menu closed');
  });

  testWidgets('Esc closes without selecting', (tester) {
    var ran = false;
    tester.pumpWidget(
      Menu(
        trigger: const Text('Edit'),
        autofocus: true,
        items: [MenuItem(label: 'Delete', onSelected: () => ran = true)],
      ),
    );
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
    expect(_screen(tester).contains('Delete'), isTrue);
    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape)); // close
    expect(ran, isFalse);
    expect(_screen(tester).contains('Delete'), isFalse);
  });

  testWidgets('focus returns to the trigger after close (reopens)', (tester) {
    tester.pumpWidget(
      Menu(trigger: const Text('Edit'), autofocus: true, items: items((_) {})),
    );
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape)); // close
    expect(_screen(tester).contains('Cut'), isFalse);
    // The trigger is focused again, so Enter reopens.
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
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
            MenuItem(label: 'Cut', onSelected: () => ran = 'cut'),
            const MenuSeparator(),
            MenuItem(label: 'Paste', onSelected: () => ran = 'paste'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
      expect(_screen(tester).contains('─'), isTrue, reason: 'rule drawn');
      // One Down should skip the separator and land on Paste.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(ran, 'paste');
    });

    testWidgets('a disabled item is skipped and not invokable', (tester) {
      String? ran;
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          autofocus: true,
          items: [
            MenuItem(label: 'Cut', onSelected: () => ran = 'cut'),
            MenuItem(
              label: 'Copy',
              enabled: false,
              onSelected: () => ran = 'copy',
            ),
            MenuItem(label: 'Paste', onSelected: () => ran = 'paste'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // skip Copy
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(ran, 'paste', reason: 'Down hopped over the disabled Copy');
    });

    testWidgets('selection starts on the first enabled item', (tester) {
      String? ran;
      tester.pumpWidget(
        Menu(
          trigger: const Text('Edit'),
          autofocus: true,
          items: [
            MenuItem(
              label: 'Off',
              enabled: false,
              onSelected: () => ran = 'off',
            ),
            MenuItem(label: 'On', onSelected: () => ran = 'on'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // activate
      expect(ran, 'on', reason: 'first selectable, not the disabled first row');
    });
  });

  group('submenus', () {
    Menu fileMenu(void Function(String) onRun) => Menu(
      trigger: const Text('File'),
      semanticLabel: 'File menu',
      autofocus: true,
      items: [
        MenuItem(label: 'New', onSelected: () => onRun('new')),
        SubMenu(
          label: 'Open',
          items: [
            MenuItem(label: 'Recent', onSelected: () => onRun('recent')),
            MenuItem(label: 'Browse', onSelected: () => onRun('browse')),
          ],
        ),
      ],
    );

    testWidgets('Right opens a submenu to the right', (tester) {
      tester.pumpWidget(fileMenu((_) {}));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open root
      expect(_screen(tester, cols: 30).contains('Open ▸'), isTrue);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Open
      tester.sendKey(
        const KeyEvent(keyCode: KeyCode.arrowRight),
      ); // open submenu
      final out = _screen(tester, cols: 30);
      expect(out.contains('Recent'), isTrue, reason: 'submenu items visible');
      expect(out.contains('Browse'), isTrue);
    });

    testWidgets('choosing a submenu leaf runs it and closes everything', (
      tester,
    ) {
      String? ran;
      tester.pumpWidget(fileMenu((v) => ran = v));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Open
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open submenu
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Browse
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // run Browse
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Open
      tester.sendKey(
        const KeyEvent(keyCode: KeyCode.arrowRight),
      ); // open submenu
      expect(_screen(tester, cols: 30).contains('Recent'), isTrue);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft)); // back out
      final out = _screen(tester, cols: 30);
      expect(out.contains('Recent'), isFalse, reason: 'submenu closed');
      expect(out.contains('Open ▸'), isTrue, reason: 'parent still open');
    });

    testWidgets('Esc from a submenu returns to the parent, not all the way', (
      tester,
    ) {
      tester.pumpWidget(fileMenu((_) {}));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open root
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Open
      tester.sendKey(
        const KeyEvent(keyCode: KeyCode.arrowRight),
      ); // open submenu
      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape)); // close submenu
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
            MenuItem(label: 'New', onSelected: () {}),
            SubMenu(
              label: 'Open',
              items: [
                MenuItem(label: 'Recent', onSelected: () {}),
                MenuItem(label: 'Browse', onSelected: () {}),
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
}
