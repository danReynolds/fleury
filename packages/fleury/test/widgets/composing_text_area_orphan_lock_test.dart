// Lock test: TextArea shares TextEditingController and the same onTextInput →
// insert path. Mid-composition type must cancel the preedit first.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'TextArea typed text mid-composition cancels the preedit, then inserts',
    (tester) {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 5,
          child: TextArea(controller: c, autofocus: true),
        ),
      );
      tester.render(size: const CellSize(40, 5));

      tester.dispatcher.dispatch(const TextCompositionEvent.update('che'));
      expect(c.text, 'git che');

      tester.type('X');

      expect(
        c.text,
        'git X',
        reason:
            'TextArea.onTextInput must cancel sticky composition before '
            'inserting, matching the paste-during-composition contract',
      );
      expect(c.composing, TextRange.empty);
    },
  );
}
