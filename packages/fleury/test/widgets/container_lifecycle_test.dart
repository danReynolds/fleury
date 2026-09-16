import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('color transitions preserve an internally owned editor', (
    tester,
  ) {
    Widget editor(Color? color) => Container(
      color: color,
      child: const TextInput(semanticLabel: 'Draft', autofocus: true),
    );
    tester.pumpWidget(editor(null));
    tester.type('draft');
    tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
    for (final color in <Color?>[Colors.green, null, Colors.blue, null]) {
      tester.pumpWidget(editor(color));
      tester.pump();
      final node = tester.semantics().single(label: 'Draft');
      expect(node.value, 'draft');
      expect(node.focused, isTrue);
    }
    tester.type('!');
    expect(tester.semantics().single(label: 'Draft').value, 'draf!t');
  });

  testWidgets('color transitions preserve external selection and focus', (
    tester,
  ) {
    final controller = TextEditingController(text: 'draft');
    final focus = FocusNode();
    Widget editor(Color? color) => Container(
      color: color,
      child: TextInput(
        controller: controller,
        focusNode: focus,
        autofocus: true,
      ),
    );
    tester.pumpWidget(editor(Colors.green));
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    tester.pump();
    tester.pumpWidget(editor(null));
    tester.pump();
    expect(controller.text, 'draft');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 4),
    );
    expect(focus.hasFocus, isTrue);
    tester.type('!');
    expect(controller.text, 'd!t');
    tester.pumpWidget(const EmptyBox());
    controller.dispose();
    focus.dispose();
  });

  testWidgets('color transitions preserve list position and keyboard focus', (
    tester,
  ) {
    Widget list(Color? color) => SizedBox(
      width: 20,
      height: 3,
      child: Container(
        color: color,
        child: ListView.builder(
          autofocus: true,
          itemCount: 20,
          itemBuilder: (_, i, _) => Text('item $i'),
        ),
      ),
    );
    tester.pumpWidget(list(Colors.green));
    tester.render(size: const CellSize(20, 3));
    for (var i = 0; i < 12; i++) {
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    }
    tester.pump();
    expect(tester.renderToString(), contains('item 12'));
    tester.pumpWidget(list(null));
    tester.pump();
    expect(tester.renderToString(), contains('item 12'));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.pump();
    expect(tester.renderToString(), contains('item 13'));
  });

  testWidgets(
    'removing fill exposes the parent background without stale cells',
    (tester) {
      Widget surface(Color? color) => Container(
        color: Colors.blue,
        width: 12,
        height: 3,
        child: Container(color: color, child: const Text('draft')),
      );
      for (final color in <Color?>[null, Colors.green, null]) {
        tester.pumpWidget(surface(color));
        tester.pump();
        final buffer = tester.render(size: const CellSize(12, 3));
        expect(buffer.atColRow(0, 0).style.background, color ?? Colors.blue);
        expect(buffer.atColRow(11, 2).style.background, color ?? Colors.blue);
      }
    },
  );

  testWidgets('unfilled empty containers keep zero intrinsic size', (tester) {
    tester.pumpWidget(
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text('a'), Container(), Text('b')],
      ),
    );
    expect(tester.renderToString(size: const CellSize(10, 2)), contains('ab'));
  });
}
