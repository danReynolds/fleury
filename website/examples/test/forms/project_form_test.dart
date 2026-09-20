// dart format width=60
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/forms/project_form.dart';

void main() {
  testWidgets(
    'submit, correct the errors, then submit with Enter',
    (tester) async {
      tester.pumpWidget(const ProjectForm());
      await tester.button('Create').press();
      await tester.settle();
      expect(tester.field('Name'), isFocused);
      expect(
        tester.renderToString(),
        contains('Enter a project name.'),
      );
      expect(
        tester.renderToString(),
        isNot(contains('Created')),
      );

      await tester.field('Name').fill('Fleury');
      await tester.field('Slug').fill('fleury-app');
      await tester.settle();
      expect(tester.field('Slug'), isFocused);
      expect(
        tester.renderToString(),
        isNot(contains('Enter a project name.')),
      );
      tester.press(KeySequence.enter);
      await tester.settle();
      expect(
        tester.renderToString(),
        contains('Created Fleury (fleury-app)'),
      );
    },
    viewportSize: const CellSize(40, 18),
  );
}
