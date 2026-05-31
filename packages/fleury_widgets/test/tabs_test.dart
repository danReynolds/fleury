import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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

void main() {
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

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    expect(c.index, 1);
    expect(_row(tester, 1), 'bbb', reason: 'content follows the selection');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
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
      tester.sendKey(const KeyEvent(char: '3', modifiers: {KeyModifier.alt}));
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
      tester.sendKey(const KeyEvent(char: '2', modifiers: {KeyModifier.alt}));
      expect(c.index, 1, reason: 'accelerator fired from inside the content');
      expect(_row(tester, 1), 'bbb');
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
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
        tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));
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
      if (e.keyCode == KeyCode.enter) {
        setState(() => _count++);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Text('count=$_count'),
  );
}
