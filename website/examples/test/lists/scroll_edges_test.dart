// dart format width=60
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/lists/scroll_edges.dart';

void main() {
  testWidgets(
    'the numbered viewport reports top, middle, and bottom',
    (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 38,
          height: 16,
          child: ScrollEdges(),
        ),
      );
      tester.pump();
      expect(
        tester.exists(text('Rows 1–4 / 8 · TOP')),
        isTrue,
      );
      tester.press(KeySequence.down);
      expect(
        tester.exists(text('Rows 2–5 / 8 · MIDDLE')),
        isTrue,
      );
      tester.press(KeySequence.end);
      expect(
        tester.exists(text('Rows 5–8 / 8 · BOTTOM')),
        isTrue,
      );
      expect(
        tester.renderToString(),
        contains('8 ─── BOTTOM'),
      );
      tester.press(KeySequence.down);
      expect(tester.button('Next'), isFocused);
      expect(
        tester.exists(text('Focus: controls')),
        isTrue,
      );
      tester.press(KeySequence.enter);
      expect(
        tester.renderToString(),
        contains('Next selected'),
      );
    },
  );

  testWidgets(
    'contain keeps the edge arrow; Tab still leaves',
    (tester) async {
      tester.pumpWidget(
        const SizedBox(
          width: 38,
          height: 16,
          child: ScrollEdges(),
        ),
      );
      await tester.button('Edge behavior').focus();
      await tester.button('Edge behavior').press();
      tester.press(KeySequence.down);
      tester.press(KeySequence.enter);
      tester.pump();
      expect(
        tester.button('Edge behavior'),
        hasValue('Contain (stay in pane)'),
      );
      tester.press(KeySequence.tab);
      tester.press(KeySequence.end);
      tester.press(KeySequence.down);
      expect(
        tester.exists(text('Rows 5–8 / 8 · BOTTOM')),
        isTrue,
      );
      expect(
        tester.exists(text('Focus: scroll pane')),
        isTrue,
      );
      expect(tester.button('Next'), isNot(isFocused));
      tester.press(KeySequence.tab);
      expect(tester.button('Next'), isFocused);
    },
  );
}
