// Exercises the minimal counter example: it mounts and its
// space-to-increment binding fires.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
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
