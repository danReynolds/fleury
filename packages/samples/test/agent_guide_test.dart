import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('the guide workflow is complete through semantic controls', (
    tester,
  ) async {
    tester.viewportSize = const CellSize(46, 15);
    tester.pumpWidget(const AgentGuideApp());

    expect(tester.field('Release version'), hasValue('0.9.0'));
    expect(tester.checkbox('Tests passed'), isUnchecked);

    await tester.field('Release version').fill('1.0.0');
    await tester.checkbox('Tests passed').check();
    await tester.button('Prepare release').press();

    expect(tester.exists(text('Status: Ready to publish 1.0.0')), isTrue);
  });

  testWidgets('the guide makes a failed prerequisite visible', (tester) async {
    tester.pumpWidget(const AgentGuideApp());

    await tester.button('Prepare release').press();

    expect(tester.exists(text('Status: Blocked: mark tests passed')), isTrue);
  });
}
