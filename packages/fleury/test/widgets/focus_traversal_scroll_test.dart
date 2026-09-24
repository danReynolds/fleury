// Tab through a form in a ScrollView that overflows. Tab order follows the
// content, not what happens to be scrolled into view, and each field Tab
// reaches is scrolled into view — the user never types into a field they
// cannot see.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  const size = CellSize(20, 6);
  late ScrollController controller;
  late List<FocusNode> fields;
  late FocusNode submit;

  setUp(() {
    controller = ScrollController();
    fields = [for (var i = 0; i < 8; i++) FocusNode(debugLabel: 'f$i')];
    submit = FocusNode(debugLabel: 'submit');
  });

  tearDown(() {
    controller.dispose();
    for (final node in [...fields, submit]) {
      node.dispose();
    }
  });

  Widget form() => FocusTraversalGroup(
    child: Column(
      children: [
        SizedBox(
          height: 4,
          child: ScrollView(
            controller: controller,
            child: Column(
              children: [
                for (var i = 0; i < 8; i++)
                  TextInput(
                    focusNode: fields[i],
                    autofocus: i == 0,
                    placeholder: 'field$i',
                  ),
              ],
            ),
          ),
        ),
        Focus(focusNode: submit, child: const Text('[ Submit ]')),
      ],
    ),
  );

  /// Presses [key] [times] times, rendering between presses as the app
  /// does, and records where focus lands and how far the form scrolled.
  List<String> press(FleuryTester tester, KeyEvent key, int times) {
    final landed = <String>[];
    for (var i = 0; i < times; i++) {
      tester.sendKey(key);
      tester.render(size: size);
      final focused = [
        ...fields,
        submit,
      ].where((node) => node.hasFocus).map((node) => node.debugLabel);
      landed.add('${focused.join()}@${controller.offset}');
    }
    return landed;
  }

  testWidgets('Tab visits every field in order, scrolling each into view', (
    tester,
  ) {
    tester.pumpWidget(form());
    tester.render(size: size);

    expect(press(tester, const KeyEvent(KeyCode.tab), 8), [
      'f1@0',
      'f2@0',
      'f3@0',
      'f4@1',
      'f5@2',
      'f6@3',
      'f7@4',
      'submit@4',
    ]);
  });

  testWidgets('Shift+Tab walks back up, scrolling up to each field', (tester) {
    tester.pumpWidget(form());
    tester.render(size: size);
    controller.jumpTo(4);
    fields[7].requestFocus();
    tester.render(size: size);

    expect(
      press(
        tester,
        const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
        7,
      ),
      ['f6@4', 'f5@4', 'f4@4', 'f3@3', 'f2@2', 'f1@1', 'f0@0'],
    );
  });

  testWidgets('an arrow onto a half-clipped control scrolls all of it in', (
    tester,
  ) {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    // A group inside the scroll view: arrows move between its controls
    // (outside one, they scroll the view).
    tester.pumpWidget(
      SizedBox(
        height: 3,
        child: ScrollView(
          controller: controller,
          child: FocusTraversalGroup(
            child: Column(
              children: [
                Focus(focusNode: a, autofocus: true, child: const Text('a')),
                const Text('-'),
                // Two rows, of which only the first is in view.
                Focus(focusNode: b, child: const Text('b1\nb2')),
              ],
            ),
          ),
        ),
      ),
    );
    tester.render(size: size);

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));

    expect(b.hasFocus, isTrue);
    expect(controller.offset, 1);
  });
}
