// Cross-widget integration: widgets composed together and exercised
// through focus traversal + input, the way real screens use them.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _fruits = ['apple', 'apricot', 'banana', 'cherry'];

String _screen(FleuryTester tester, {int cols = 20, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  group('Autocomplete in a form', () {
    testWidgets('Tab moves between fields when the dropdown is closed', (
      tester,
    ) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Autocomplete(options: _fruits, focusNode: a, autofocus: true),
              TextInput(focusNode: b),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 4)); // record rects
      expect(a.hasFocus, isTrue);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));
      expect(b.hasFocus, isTrue, reason: 'Tab bubbled to the focus group');
    });

    testWidgets('Down navigates suggestions without moving focus when open', (
      tester,
    ) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Autocomplete(options: _fruits, focusNode: a, autofocus: true),
              TextInput(focusNode: b),
            ],
          ),
        ),
      );
      tester.type('ap'); // opens the dropdown
      expect(tester.overlay.entries.length, 2);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      expect(a.hasFocus, isTrue, reason: 'Down drove the list, not traversal');
      expect(tester.overlay.entries.length, 2, reason: 'dropdown still open');
    });

    testWidgets('a picked value does not re-suggest itself on refocus', (
      tester,
    ) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Autocomplete(options: _fruits, focusNode: a, autofocus: true),
              Focus(focusNode: b, child: const Text('next')),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 4));
      tester.type('ap'); // apple, apricot
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // pick apple
      expect(tester.overlay.entries.length, 1, reason: 'closed after pick');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab)); // → b
      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab)); // wraps back → a
      expect(a.hasFocus, isTrue);
      expect(
        tester.overlay.entries.length,
        1,
        reason: 'the picked value should not re-suggest itself',
      );
    });
  });

  group('Tooltip', () {
    testWidgets('only the focused widget shows its tooltip', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                message: 'tip A',
                child: Focus(
                  focusNode: a,
                  autofocus: true,
                  child: const Text('A'),
                ),
              ),
              Tooltip(
                message: 'tip B',
                child: Focus(focusNode: b, child: const Text('B')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 8)); // record rects
      var out = _screen(tester);
      expect(out.contains('tip A'), isTrue);
      expect(out.contains('tip B'), isFalse);
      expect(tester.overlay.entries.length, 2, reason: 'one tooltip layer');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab)); // → B
      expect(b.hasFocus, isTrue);
      out = _screen(tester);
      expect(out.contains('tip A'), isFalse, reason: 'A blurred');
      expect(out.contains('tip B'), isTrue);
    });
  });

  group('Toaster + Menu', () {
    testWidgets('a toast floats over an open menu', (tester) {
      late BuildContext ctx;
      tester.pumpWidget(
        Toaster(
          child: Menu(
            trigger: _Capture((c) => ctx = c, label: 'File'),
            autofocus: true,
            items: [MenuItem(label: 'Quit', onSelected: () {})],
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open menu
      expect(_screen(tester).contains('Quit'), isTrue);

      Toaster.show(ctx, 'busy');
      tester.pump();
      final out = _screen(tester);
      expect(out.contains('Quit'), isTrue, reason: 'menu still open');
      expect(out.contains('busy'), isTrue, reason: 'toast over the menu');
    });
  });
}

class _Capture extends StatelessWidget {
  const _Capture(this.sink, {required this.label});
  final void Function(BuildContext) sink;
  final String label;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return Text(label);
  }
}
