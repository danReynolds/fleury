// Locks the README "Quick start" snippet: the example compiles, mounts,
// and the space-to-increment binding actually fires. If this breaks, the
// front-door docs are wrong — fix the example and the README together.

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
