// Exercises the compiled counterpart to the README "Quick start": the example
// mounts and its space-to-increment binding fires. Keep the example and README
// snippet aligned when either changes.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

import '../../example/counter_quickstart.dart';

void main() {
  testWidgets('starts at zero', (tester) {
    tester.pumpWidget(const CounterApp());
    expect(tester.renderToString(), contains('count: 0'));
  });

  testWidgets('space increments the counter', (tester) {
    tester.pumpWidget(const CounterApp());
    tester.sendKey(const KeyEvent(char: ' '));
    tester.pump();
    expect(tester.renderToString(), contains('count: 1'));
  });
}
