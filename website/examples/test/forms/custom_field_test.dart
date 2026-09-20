// dart format width=60
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/forms/custom_field.dart';

void main() {
  testWidgets(
    'a composite field focuses its chosen control and refreshes',
    (tester) async {
      tester.pumpWidget(const CustomField());
      await tester.button('Save range').press();
      await tester.settle();
      final start = tester.target(
        role: SemanticRole.spinButton,
        label: 'Start',
      );
      final end = tester.target(
        role: SemanticRole.spinButton,
        label: 'End',
      );
      expect(start, isFocused);
      expect(
        tester.renderToString(),
        contains('End must be greater than start.'),
      );

      await end.setValue(8);
      await tester.settle();
      expect(
        tester.renderToString(),
        isNot(contains('End must be greater than start.')),
      );
      await tester.button('Save range').press();
      await tester.settle();
      expect(
        tester.renderToString(),
        contains('Saved range 5–8'),
      );
    },
    viewportSize: const CellSize(40, 12),
  );
}
