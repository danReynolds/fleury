// The fleury README's test fence, from its first import to the end, verbatim:
// test/docs_accuracy_test.dart fails if the two differ. The README's counter
// reaches this package through ../example/counter_quickstart.dart.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../example/counter_quickstart.dart';

void main() {
  testWidgets('space increments the counter', (tester) {
    tester.pumpWidget(const CounterApp());
    tester.sendKey(const KeyEvent(KeyCode.char(' ')));
    tester.pump();
    expect(tester.renderToString(), contains('count: 1'));
  });
}
