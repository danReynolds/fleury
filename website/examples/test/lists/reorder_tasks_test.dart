import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/lists/reorder_tasks.dart';

void main() {
  testWidgets('reversing keeps the current task, not its old index', (
    tester,
  ) async {
    tester.pumpWidget(const SizedBox(width: 40, child: ReorderTasks()));
    final before = tester.renderToString().split('\n');
    expect(before[1], contains('› Build the prototype'));

    await tester.button('Reverse order').press();
    tester.pump();
    final after = tester.renderToString().split('\n');
    expect(after[2], contains('› Build the prototype'));
    expect(tester.exists(text('Current: Build the prototype')), isTrue);

    await tester.button('Reverse order').press();
    tester.pump();
    expect(
      tester.renderToString().split('\n')[1],
      contains('› Build the prototype'),
    );
  });
}
