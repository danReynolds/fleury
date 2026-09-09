// dart format width=60
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/lists/horizontal_content.dart';

void main() {
  testWidgets(
    'wide text keeps its lines and reveals the final columns',
    (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 36,
          height: 8,
          child: HorizontalContent(),
        ),
      );
      expect(tester.renderToString(), contains('NAME'));
      expect(tester.renderToString(), contains('START'));
      tester.press(KeySequence.end);
      tester.pump();
      expect(tester.renderToString(), contains('SUCCESS'));
      expect(tester.renderToString(), contains('END'));
      tester.press(KeySequence.home);
      tester.pump();
      expect(tester.renderToString(), contains('NAME'));
      expect(tester.renderToString(), contains('START'));
    },
  );
}
