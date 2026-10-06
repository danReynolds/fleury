import 'package:fleury/fleury.dart';
import 'package:fleury_doc_examples/testing/counter.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('adds one', (tester) async {
    tester.pumpWidget(const Counter());
    await tester.button('Add one').press();
    expect(tester.exists(text('Count: 1')), isTrue);
  });

  testWidgets('adds one using the keyboard', (tester) {
    tester.pumpWidget(const Counter());
    expect(tester.button('Add one'), isFocused);
    tester.press(KeySequence.enter);
    expect(tester.exists(text('Count: 1')), isTrue);
  });
}
