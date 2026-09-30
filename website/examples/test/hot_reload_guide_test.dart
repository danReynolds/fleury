@TestOn('vm')
library;

import 'package:fleury/fleury_core.dart';
import 'package:fleury_doc_examples/hot_reload_guide.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

// A new heading with the same key stands in for a reload: the tree keeps its
// State. A new key stands in for a restart: the State is created again.
Widget _notes(String heading, {int session = 0}) => Theme(
  data: ThemeData.dark(),
  child: HotReloadNotes(key: ValueKey(session), heading: heading),
);

void main() {
  testWidgets(
    'reload preserves drafts, note, focus and caret; restart resets state',
    (tester) async {
      tester.pumpWidget(_notes('Notes'));
      tester.press(KeySequence.down);
      tester.press(KeySequence.enter);
      expect(tester.renderToString(), contains('› Release notes'));
      tester.type('Ready.');
      tester.press(KeySequence.left);

      tester.pumpWidget(_notes('Release workspace'));
      expect(tester.renderToString(), contains('Release workspace'));
      expect(tester.renderToString(), contains('› Release notes'));
      expect(tester.field('Draft'), hasValue('Ready.'));
      expect(tester.field('Draft'), isFocused);
      tester.type(' today');
      expect(tester.field('Draft'), hasValue('Ready today.'));

      tester.press(KeySequence.shift.tab);
      tester.press(KeySequence.down);
      tester.press(KeySequence.enter);
      expect(tester.renderToString(), contains('› Ideas'));
      expect(tester.field('Draft'), hasValue(''));
      await tester.field('Draft').fill('Try a new layout.');
      tester.press(KeySequence.shift.tab);
      tester.press(KeySequence.up);
      tester.press(KeySequence.enter);
      expect(tester.field('Draft'), hasValue('Ready today.'));

      tester.pumpWidget(_notes('Release workspace', session: 1));
      expect(tester.renderToString(), contains('Release workspace'));
      expect(tester.renderToString(), contains('› Inbox'));
      expect(tester.field('Draft'), hasValue(''));
      tester.press(KeySequence.down);
      tester.press(KeySequence.enter);
      expect(tester.field('Draft'), hasValue(''));
      tester.press(KeySequence.shift.tab);
      tester.press(KeySequence.down);
      tester.press(KeySequence.enter);
      expect(tester.renderToString(), contains('› Ideas'));
      expect(tester.field('Draft'), hasValue(''));
    },
    viewportSize: const CellSize(54, 12),
  );
}
