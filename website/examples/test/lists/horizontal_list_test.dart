// dart format width=60
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/lists/horizontal_list.dart';

void main() {
  testWidgets(
    'browse horizontally, then select with Enter',
    (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 36,
          height: 6,
          child: HorizontalList(),
        ),
      );
      tester.press(KeySequence.end);
      tester.pump();
      expect(tester.renderToString(), contains('Outline'));
      expect(
        tester.renderToString(),
        contains('Selected: None'),
      );
      tester.press(KeySequence.enter);
      tester.pump();
      expect(
        tester.renderToString(),
        contains('Selected: Outline'),
      );
      tester.press(KeySequence.left);
      tester.pump();
      expect(
        tester.renderToString(),
        contains('Selected: Outline'),
      );
    },
  );
}
