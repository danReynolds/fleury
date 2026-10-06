// A complete widget test: a small counter and two tests that drive it.
//
// With `fleury_test` and `test` in your dev_dependencies, run it with:
//
//   dart test example/fleury_test_example.dart

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

/// Shows a count and a button that increments it.
class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Count: $_count'),
      Button(text: 'Increment', onPressed: () => setState(() => _count++)),
    ],
  );
}

void main() {
  testWidgets('pressing Increment counts up', (tester) async {
    tester.pumpWidget(const Counter());
    expect(tester.renderToString(), contains('Count: 0'));

    // Find the control by its role and label, then activate it.
    await tester.button('Increment').press();

    expect(tester.renderToString(), contains('Count: 1'));
  });

  testWidgets('Enter activates the focused button', (tester) async {
    tester.pumpWidget(const Counter());
    final increment = tester.button('Increment');

    await increment.focus();
    expect(increment, isFocused);

    // Real key input travels the same path a terminal's does.
    tester.sendKey(const KeyEvent(KeyCode.enter));

    expect(tester.renderToString(), contains('Count: 1'));
  });
}
