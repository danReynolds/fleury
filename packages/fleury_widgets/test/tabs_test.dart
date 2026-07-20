import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _row(FleuryTester tester, int row, {int cols = 20, int rows = 2}) {
  final buf = tester.render(size: CellSize(cols, rows));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    final cell = buf.atColRow(c, row);
    sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
  }
  return sb.toString().trimRight();
}

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

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('TabController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = TabController(initialIndex: 2);

      controller.dispose();
      controller.dispose();

      expect(controller.index, 2);
      expect(controller.length, 0);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = TabController()..dispose();

      const message = 'TabController has been disposed.';
      expect(() => controller.index = 1, _stateError(message));
      expect(controller.next, _stateError(message));
      expect(controller.previous, _stateError(message));
    });
  });

  testWidgets('shows the active tab content below the strip', (tester) {
    tester.pumpWidget(
      const Tabs(
        tabs: [
          TabItem(label: 'One', content: Text('first')),
          TabItem(label: 'Two', content: Text('second')),
        ],
      ),
    );
    expect(_row(tester, 0).contains('One'), isTrue, reason: 'strip on row 0');
    expect(_row(tester, 1), 'first', reason: 'active content on row 1');
  });

  testWidgets('clamps an out-of-range initial index when first attached', (
    tester,
  ) {
    final controller = TabController(initialIndex: 99);
    tester.pumpWidget(
      Tabs(
        controller: controller,
        tabs: const [
          TabItem(label: 'One', content: Text('first')),
          TabItem(label: 'Two', content: Text('second')),
        ],
      ),
    );

    expect(controller.length, 2);
    expect(controller.index, 1);
    expect(_row(tester, 1), 'second');
  });

  testWidgets('clicking a tab label switches to it', (tester) {
    final controller = TabController();
    addTearDown(controller.dispose);
    tester.pumpWidget(
      Tabs(
        controller: controller,
        tabs: const [
          TabItem(label: 'One', content: Text('first')),
          TabItem(label: 'Two', content: Text('second')),
        ],
      ),
    );
    tester.render(size: const CellSize(20, 2));
    // Strip on row 0: ' One ' at cols 0-4, ' Two ' at cols 5-9.
    _clickAt(tester, col: 6, row: 0);
    expect(controller.index, 1);
    expect(_row(tester, 1), 'second', reason: 'second tab content now shows');
  });

  testWidgets('the active label uses the active style', (tester) {
    final buf =
        (tester..pumpWidget(
              const Tabs(
                activeStyle: CellStyle(bold: true),
                tabs: [
                  TabItem(label: 'A', content: Text('a')),
                  TabItem(label: 'B', content: Text('b')),
                ],
              ),
            ))
            .render(size: const CellSize(20, 2));
    // Strip renders " A  B " → 'A' at col 1 (active), 'B' at col 4.
    expect(buf.atColRow(1, 0).style.bold, isTrue);
    expect(buf.atColRow(4, 0).style.bold, isFalse);
  });

  testWidgets('Left/Right switch tabs when focused, wrapping', (tester) {
    final c = TabController();
    tester.pumpWidget(
      Tabs(
        controller: c,
        autofocus: true,
        tabs: const [
          TabItem(label: 'A', content: Text('aaa')),
          TabItem(label: 'B', content: Text('bbb')),
          TabItem(label: 'C', content: Text('ccc')),
        ],
      ),
    );
    tester.render(size: const CellSize(20, 2));
    expect(c.index, 0);

    tester.sendKey(const KeyEvent(KeyCode.arrowRight));
    expect(c.index, 1);
    expect(_row(tester, 1), 'bbb', reason: 'content follows the selection');

    tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
    tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
    expect(c.index, 2, reason: 'wrapped past 0 to the last tab');
    expect(_row(tester, 1), 'ccc');
  });

  testWidgets('the controller drives switching programmatically', (tester) {
    final c = TabController();
    tester.pumpWidget(
      Tabs(
        controller: c,
        tabs: const [
          TabItem(label: 'A', content: Text('aaa')),
          TabItem(label: 'B', content: Text('bbb')),
        ],
      ),
    );
    tester.render(size: const CellSize(20, 2));

    c.index = 1;
    expect(_row(tester, 1), 'bbb');
  });

  group('lifecycle & edges', () {
    testWidgets('an external controller survives unmount (not disposed)', (
      tester,
    ) {
      final c = TabController();
      tester.pumpWidget(
        Tabs(
          controller: c,
          tabs: const [
            TabItem(label: 'A', content: Text('a')),
            TabItem(label: 'B', content: Text('b')),
          ],
        ),
      );
      tester.pumpWidget(const Text('gone'));
      // A disposed ChangeNotifier throws on addListener — assert ours
      // wasn't disposed because the widget didn't own it.
      expect(() => c.addListener(() {}), returnsNormally);
    });

    testWidgets('swapping controllers re-wires; the old one detaches', (
      tester,
    ) {
      final a = TabController();
      final b = TabController();
      const tabs = [
        TabItem(label: 'A', content: Text('aaa')),
        TabItem(label: 'B', content: Text('bbb')),
      ];
      tester.pumpWidget(Tabs(controller: a, tabs: tabs));
      tester.render(size: const CellSize(20, 2));

      tester.pumpWidget(Tabs(controller: b, tabs: tabs));
      tester.render(size: const CellSize(20, 2));
      a.index = 1; // old controller no longer drives the view
      expect(_row(tester, 1), 'aaa', reason: 'still on b.index 0');
      b.index = 1;
      expect(_row(tester, 1), 'bbb', reason: 'new controller drives');
    });

    testWidgets('a shrunk tab list pulls the selection back in range', (
      tester,
    ) {
      final c = TabController(initialIndex: 2);
      tester.pumpWidget(
        Tabs(
          controller: c,
          tabs: const [
            TabItem(label: 'A', content: Text('aaa')),
            TabItem(label: 'B', content: Text('bbb')),
            TabItem(label: 'C', content: Text('ccc')),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 2));
      expect(c.index, 2);

      tester.pumpWidget(
        Tabs(
          controller: c,
          tabs: const [
            TabItem(label: 'A', content: Text('aaa')),
            TabItem(label: 'B', content: Text('bbb')),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 2));
      expect(c.index, 1, reason: 'clamped from 2 to last valid index');
      expect(_row(tester, 1), 'bbb');
    });

    testWidgets('empty tab list renders nothing without crashing', (tester) {
      tester.pumpWidget(const Tabs(tabs: []));
      expect(_row(tester, 0), '');
    });

    testWidgets('chords do not switch tabs unless the strip is focused', (
      tester,
    ) {
      final c = TabController();
      tester.pumpWidget(
        Tabs(
          controller: c,
          // autofocus is false → the strip never takes focus.
          tabs: const [
            TabItem(label: 'A', content: Text('aaa')),
            TabItem(label: 'B', content: Text('bbb')),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 2));
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      expect(c.index, 0, reason: 'unfocused strip ignores arrows');
    });
  });

  group('Alt+digit accelerators', () {
    testWidgets('Alt+N jumps straight to tab N', (tester) {
      final c = TabController();
      tester.pumpWidget(
        Tabs(
          controller: c,
          autofocus: true,
          tabs: const [
            TabItem(label: 'A', content: Text('aaa')),
            TabItem(label: 'B', content: Text('bbb')),
            TabItem(label: 'C', content: Text('ccc')),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 2));
      tester.sendKey(
        const KeyEvent(KeyCode.char('3'), modifiers: {KeyModifier.alt}),
      );
      expect(c.index, 2);
      expect(_row(tester, 1), 'ccc');
    });

    testWidgets('Alt+N works while focus is inside the active tab', (tester) {
      final c = TabController();
      final inner = FocusNode(debugLabel: 'inner');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Tabs(
            controller: c,
            tabs: [
              TabItem(
                label: 'A',
                content: Focus(
                  focusNode: inner,
                  autofocus: true,
                  child: const Text('aaa'),
                ),
              ),
              const TabItem(label: 'B', content: Text('bbb')),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));
      expect(inner.hasFocus, isTrue);
      tester.sendKey(
        const KeyEvent(KeyCode.char('2'), modifiers: {KeyModifier.alt}),
      );
      expect(c.index, 1, reason: 'accelerator fired from inside the content');
      expect(_row(tester, 1), 'bbb');
    });
  });

  group('semantics', () {
    testWidgets('exposes tab nodes with selection, focus, and shortcuts', (
      tester,
    ) {
      final c = TabController(initialIndex: 1);
      tester.pumpWidget(
        Tabs(
          controller: c,
          autofocus: true,
          tabs: const [
            TabItem(label: 'Files', content: Text('files')),
            TabItem(label: 'Search', content: Text('search')),
            TabItem(label: 'Run', content: Text('run')),
          ],
        ),
      );

      final tree = tester.semantics();
      final tabs = tree.byRole(SemanticRole.tab).toList(growable: false);

      expect(tabs.map((node) => node.label), ['Files', 'Search', 'Run']);
      final selected = tree.single(
        role: SemanticRole.tab,
        label: 'Search',
        selected: true,
        focused: true,
      );
      expect(
        selected.actions,
        containsAll(<SemanticAction>[
          SemanticAction.focus,
          SemanticAction.select,
          SemanticAction.activate,
        ]),
      );
      expect(selected.state.tabIndex, 1);
      expect(selected.state.tabPosition, 2);
      expect(selected.state.tabCount, 3);
      expect(selected.state.shortcut, 'Alt+2');
    });

    testWidgets('semantic select switches tabs and focuses the tab strip', (
      tester,
    ) async {
      final c = TabController();
      tester.pumpWidget(
        Tabs(
          controller: c,
          tabs: const [
            TabItem(label: 'Files', content: Text('files')),
            TabItem(label: 'Search', content: Text('search')),
            TabItem(label: 'Run', content: Text('run')),
          ],
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.select,
        role: SemanticRole.tab,
        label: 'Run',
      );

      expect(result.completed, isTrue);
      expect(c.index, 2);
      expect(_row(tester, 1), 'run');
      final selected = tester.semantics().single(
        role: SemanticRole.tab,
        label: 'Run',
        selected: true,
        focused: true,
      );
      expect(selected.state.tabPosition, 3);
    });

    testWidgets('inactive tab content is hidden from semantic snapshots', (
      tester,
    ) {
      final c = TabController(initialIndex: 1);
      tester.pumpWidget(
        Tabs(
          controller: c,
          tabs: const [
            TabItem(
              label: 'Hidden',
              content: Semantics(
                role: SemanticRole.button,
                label: 'Hidden action',
                actions: {SemanticAction.activate},
                child: Text('hidden'),
              ),
            ),
            TabItem(
              label: 'Visible',
              content: Semantics(
                role: SemanticRole.button,
                label: 'Visible action',
                actions: {SemanticAction.activate},
                child: Text('visible'),
              ),
            ),
          ],
        ),
      );

      final tree = tester.semantics();

      expect(
        tree.where(role: SemanticRole.button, label: 'Hidden action'),
        isEmpty,
      );
      expect(
        tree.single(role: SemanticRole.button, label: 'Visible action'),
        isNotNull,
      );
    });

    testWidgets('accessibility fallback includes tab position and shortcut', (
      tester,
    ) {
      tester.pumpWidget(
        const Tabs(
          tabs: [
            TabItem(label: 'Files', content: Text('files')),
            TabItem(label: 'Search', content: Text('search')),
          ],
        ),
      );

      final node = tester.accessibilitySnapshot().single(
        role: SemanticRole.tab,
        label: 'Files',
        selected: true,
        state: 'tab 1 of 2, shortcut Alt+1',
      );

      expect(node.announcement, contains('selected'));
      expect(node.announcement, contains('actions: activate, focus, select'));
    });
  });

  group('keep-alive', () {
    testWidgets("an inactive tab's state survives switching away and back", (
      tester,
    ) {
      final c = TabController();
      final counter = FocusNode(debugLabel: 'counter');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Tabs(
            controller: c,
            tabs: [
              TabItem(
                label: 'A',
                content: _Counter(focusNode: counter),
              ),
              const TabItem(label: 'B', content: Text('other')),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));

      counter.requestFocus();
      tester.sendKey(const KeyEvent(KeyCode.enter));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(_row(tester, 1), 'count=2');

      c.index = 1; // hide tab A
      expect(_row(tester, 1), 'other');
      c.index = 0; // back to A
      expect(
        _row(tester, 1),
        'count=2',
        reason: 'the counter element stayed mounted, so its state held',
      );
    });

    testWidgets('a hidden tab is excluded from focus traversal', (tester) {
      final c = TabController();
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Tabs(
            controller: c,
            tabs: [
              TabItem(
                label: 'A',
                content: Focus(focusNode: a, child: const Text('a')),
              ),
              TabItem(
                label: 'B',
                content: Focus(focusNode: b, child: const Text('b')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));

      a.requestFocus();
      // Cycle: only the strip and tab A's node are traversable; B is hidden.
      for (var i = 0; i < 4; i++) {
        tester.sendKey(const KeyEvent(KeyCode.tab));
        expect(
          b.hasFocus,
          isFalse,
          reason: "Tab must never land on the hidden tab's node",
        );
      }
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({required this.focusNode});
  final FocusNode focusNode;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.focusNode,
    onKey: (e) {
      if (e.code == KeyCode.enter) {
        setState(() => _count++);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Text('count=$_count'),
  );
}
