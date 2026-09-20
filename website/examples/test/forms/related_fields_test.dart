// dart format width=60
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/forms/related_fields.dart';

void main() {
  testWidgets(
    'Check preserves focus; Confirm focuses the error',
    (tester) async {
      tester.pumpWidget(const RelatedFields());
      await tester.field('Password').fill('made-up-one');
      await tester
          .field('Confirm password')
          .fill('made-up-two');
      await tester.button('Check').focus();
      await tester.button('Check').press();
      await tester.settle();
      expect(tester.button('Check'), isFocused);
      expect(
        tester.renderToString(),
        contains('Passwords must match.'),
      );

      await tester.button('Confirm').press();
      await tester.settle();
      expect(tester.field('Confirm password'), isFocused);
      await tester
          .field('Confirm password')
          .fill('made-up-one');
      await tester.settle();
      expect(
        tester.renderToString(),
        isNot(contains('Passwords must match.')),
      );

      // Changing the other field also refreshes the revealed comparison.
      await tester.field('Password').fill('made-up-three');
      await tester.settle();
      expect(
        tester.renderToString(),
        contains('Passwords must match.'),
      );
      expect(tester.field('Password'), isFocused);
      await tester
          .field('Confirm password')
          .fill('made-up-three');
      await tester.button('Confirm').press();
      await tester.settle();
      expect(
        tester.renderToString(),
        contains('Confirmed'),
      );
    },
    viewportSize: const CellSize(40, 18),
  );
}
