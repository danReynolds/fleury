import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

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

List<String> _lines(FleuryTester tester, {int cols = 14, required int rows}) {
  final buf = tester.render(size: CellSize(cols, rows));
  return [
    for (var r = 0; r < rows; r++)
      [
        for (var c = 0; c < cols; c++)
          buf.atColRow(c, r).role == CellRole.leading
              ? buf.atColRow(c, r).grapheme!
              : ' ',
      ].join().trimRight(),
  ];
}

Tree<String> _tree({void Function(TreeNode<String>)? onSelect}) => Tree<String>(
  autofocus: true,
  onSelect: onSelect,
  roots: const [
    TreeNode<String>(
      'src',
      children: [TreeNode<String>('a.dart'), TreeNode<String>('b.dart')],
    ),
    TreeNode<String>('README'),
  ],
);

void main() {
  testWidgets('renders roots collapsed', (tester) {
    tester.pumpWidget(_tree());
    expect(_lines(tester, rows: 4), ['▸ src', '  README', '', '']);
  });

  testWidgets('Right expands a branch, Left collapses it', (tester) {
    tester.pumpWidget(_tree());

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    expect(_lines(tester, rows: 4), [
      '▾ src',
      '    a.dart',
      '    b.dart',
      '  README',
    ]);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
    expect(_lines(tester, rows: 4), ['▸ src', '  README', '', '']);
  });

  testWidgets('clicking a branch row toggles it', (tester) {
    tester.pumpWidget(_tree());
    tester.render(size: const CellSize(14, 4));
    // The 'src' branch sits on row 0; clicking the row expands it (the whole
    // row is the target, not just the ▸ glyph).
    _clickAt(tester, col: 2, row: 0);
    expect(_lines(tester, rows: 4), [
      '▾ src',
      '    a.dart',
      '    b.dart',
      '  README',
    ]);
    // Clicking the branch row again collapses it.
    _clickAt(tester, col: 2, row: 0);
    expect(_lines(tester, rows: 4), ['▸ src', '  README', '', '']);
  });

  testWidgets('typing jumps the selection to a matching node', (tester) {
    TreeNode<String>? selected;
    tester.pumpWidget(_tree(onSelect: (n) => selected = n));
    tester.render(size: const CellSize(14, 4));
    // 'r' moves the selection to README; Enter activates that leaf.
    tester.sendKey(const KeyEvent(char: 'r'));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(selected?.label, 'README');
  });

  testWidgets('Down + Enter toggles the focused branch', (tester) {
    tester.pumpWidget(_tree());
    // Move to README (a leaf) then back; expand src via Enter instead.
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // src is selected
    expect(_lines(tester, rows: 4).first, '▾ src');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // collapse again
    expect(_lines(tester, rows: 4).first, '▸ src');
  });

  testWidgets('Enter on a leaf fires onSelect', (tester) {
    String? activated;
    tester.pumpWidget(_tree(onSelect: (n) => activated = n.label));
    // Down to README (leaf), Enter activates it.
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(activated, 'README');
  });

  testWidgets('exposes semantic tree and tree-item state', (tester) {
    tester.pumpWidget(
      const Tree<String>(
        semanticLabel: 'Project tree',
        autofocus: true,
        roots: [
          TreeNode<String>(
            'src',
            children: [TreeNode<String>('a.dart'), TreeNode<String>('b.dart')],
          ),
          TreeNode<String>('README'),
        ],
      ),
    );

    tester.render(size: const CellSize(20, 4));
    var tree = tester.semantics().single(role: SemanticRole.tree);
    expect(tree.label, 'Project tree');
    expect(tree.state.collectionRowCount, 2);
    expect(tree.state['rootCount'], 2);
    expect(tree.state.selectedKey, '0');

    var src = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'src',
    );
    expect(src.selected, isTrue);
    expect(src.actions, contains(SemanticAction.open));
    expect(src.state['rowIndex'], 0);
    expect(src.state['rowKey'], '0');
    expect(src.state['depth'], 0);
    expect(src.state['isBranch'], isTrue);
    expect(src.state['expanded'], isFalse);
    expect(src.state['childCount'], 2);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.render(size: const CellSize(20, 4));

    tree = tester.semantics().single(role: SemanticRole.tree);
    expect(tree.state.collectionRowCount, 4);
    expect(tree.state['expandedCount'], 1);

    final child = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'a.dart',
    );
    expect(child.state['rowIndex'], 1);
    expect(child.state['rowKey'], '0.0');
    expect(child.state['depth'], 1);
    expect(child.actions, isNot(contains(SemanticAction.open)));
  });

  testWidgets('semantic focus, open, and activate drive tree behavior', (
    tester,
  ) async {
    String? activated;
    tester.pumpWidget(
      Tree<String>(
        semanticLabel: 'Project tree',
        roots: const [
          TreeNode<String>(
            'src',
            children: [TreeNode<String>('a.dart'), TreeNode<String>('b.dart')],
          ),
          TreeNode<String>('README'),
        ],
        onSelect: (node) => activated = node.label,
      ),
    );

    tester.render(size: const CellSize(20, 4));
    var result = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.tree,
      label: 'Project tree',
    );
    expect(result.completed, isTrue);
    expect(tester.semantics().single(role: SemanticRole.tree).focused, isTrue);

    result = await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.treeItem,
      label: 'src',
    );
    expect(result.completed, isTrue);
    tester.render(size: const CellSize(20, 4));
    expect(tester.semantics().single(label: 'a.dart'), isA<SemanticNode>());

    result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.treeItem,
      label: 'b.dart',
    );
    expect(result.completed, isTrue);
    expect(activated, 'b.dart');
  });

  testWidgets('semantic close collapses an expanded branch (symmetric with '
      'open)', (tester) async {
    tester.pumpWidget(_tree());
    tester.render(size: const CellSize(20, 4));

    await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.treeItem,
      label: 'src',
    );
    tester.render(size: const CellSize(20, 4));
    expect(tester.semantics().single(label: 'a.dart'), isA<SemanticNode>());

    // An expanded branch advertises close (not open) — the symmetric pair an
    // agent needs; collapsing used to be Left-arrow-only.
    final expanded = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'src',
    );
    expect(expanded.actions, contains(SemanticAction.close));
    expect(expanded.actions, isNot(contains(SemanticAction.open)));

    final result = await tester.invokeSemanticAction(
      SemanticAction.close,
      role: SemanticRole.treeItem,
      label: 'src',
    );
    expect(result.completed, isTrue);
    tester.render(size: const CellSize(20, 4));
    expect(
      tester.semantics().where(label: 'a.dart'),
      isEmpty,
      reason: 'collapsing removed the children from the tree',
    );
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.treeItem, label: 'src')
          .actions,
      contains(SemanticAction.open),
      reason: 'collapsed again ⇒ offers open',
    );
  });

  testWidgets('Left from a child steps out to its parent', (tester) {
    tester.pumpWidget(_tree());
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight)); // expand src
    tester.sendKey(
      const KeyEvent(keyCode: KeyCode.arrowRight),
    ); // step to a.dart
    // a.dart is a leaf; Left steps out to src (the parent).
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
    // Now on src (still expanded); Left again collapses it.
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
    expect(_lines(tester, rows: 4), ['▸ src', '  README', '', '']);
  });

  group('composition & edges', () {
    testWidgets('Right on a leaf bubbles to the focus chain', (tester) {
      var bubbled = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.key(KeyCode.arrowRight),
              onEvent: (_) => bubbled++,
            ),
          ],
          child: const Tree<String>(
            autofocus: true,
            roots: [TreeNode<String>('leaf')],
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(bubbled, 1, reason: 'a leaf has nothing to expand');
    });

    testWidgets('Left on a collapsed root bubbles to the focus chain', (
      tester,
    ) {
      var bubbled = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.key(KeyCode.arrowLeft),
              onEvent: (_) => bubbled++,
            ),
          ],
          child: const Tree<String>(
            autofocus: true,
            roots: [
              TreeNode<String>('dir', children: [TreeNode<String>('x')]),
            ],
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      expect(bubbled, 1, reason: 'collapsed root with no parent');
    });

    testWidgets('the selected row uses the selected style', (tester) {
      tester.pumpWidget(
        const Tree<String>(
          autofocus: true,
          selectedStyle: CellStyle(bold: true),
          roots: [TreeNode<String>('a'), TreeNode<String>('b')],
        ),
      );
      final buf = tester.render(size: const CellSize(8, 2));
      // Row 0 ('a') is selected → bold; row 1 ('b') is not.
      expect(buf.atColRow(2, 0).style.bold, isTrue);
      expect(buf.atColRow(2, 1).style.bold, isFalse);
    });

    testWidgets('Enter on a branch toggles it and does not fire onSelect', (
      tester,
    ) {
      var selected = 0;
      tester.pumpWidget(
        Tree<String>(
          autofocus: true,
          onSelect: (_) => selected++,
          roots: const [
            TreeNode<String>('dir', children: [TreeNode<String>('x')]),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(_lines(tester, rows: 2).first, '▾ dir', reason: 'expanded');
      expect(selected, 0, reason: 'onSelect is for leaves only');
    });

    testWidgets('expanding one root leaves siblings collapsed', (tester) {
      tester.pumpWidget(
        const Tree<String>(
          autofocus: true,
          roots: [
            TreeNode<String>('a', children: [TreeNode<String>('a1')]),
            TreeNode<String>('b', children: [TreeNode<String>('b1')]),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight)); // expand a
      expect(_lines(tester, rows: 3), ['▾ a', '    a1', '▸ b']);
    });

    testWidgets('onSelect hands back the leaf node and its value payload', (
      tester,
    ) {
      int? picked;
      tester.pumpWidget(
        Tree<int>(
          autofocus: true,
          onSelect: (n) => picked = n.value,
          roots: const [
            TreeNode<int>(
              'files',
              children: [
                TreeNode<int>('one', value: 1),
                TreeNode<int>('two', value: 2),
              ],
            ),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight)); // expand
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → one
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → two
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(picked, 2, reason: 'the typed value rode along on the node');
    });

    testWidgets('sanitizes unsafe labels for display and semantics', (tester) {
      tester.pumpWidget(
        const Tree<String>(
          roots: [TreeNode<String>('bad\x1b]52;c;secret\x07\nname')],
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(30, 2),
        emptyMark: ' ',
      );
      expect(output, contains('bad'));
      expect(output, contains('name'));
      expect(output, contains(replacementCharacter));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final row = tester.semantics().single(role: SemanticRole.treeItem);
      expect(row.label, contains(replacementCharacter));
      expect(row.label, isNot(contains('secret')));
      expect(row.state.outputSanitized, isTrue);
    });
  });
}
