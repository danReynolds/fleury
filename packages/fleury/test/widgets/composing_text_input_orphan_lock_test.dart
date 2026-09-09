// Lock test (widget surface): TextInput.onTextInput / backspace while an IME
// composition is sticky must resolve the composition first. Split surfaces
// (DOM) and leftover text halves can deliver a TextInputEvent mid-preedit;
// backspace KeyEvents can likewise reach the field. Today both orphan the
// composition base the same way the controller-level applyEdit path does.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('typed text mid-composition cancels the preedit, then inserts', (
    tester,
  ) {
    final c = TextEditingController(text: 'git ');
    addTearDown(c.dispose);
    tester.pumpWidget(
      SizedBox(
        width: 40,
        height: 1,
        child: TextInput(controller: c, autofocus: true),
      ),
    );
    tester.render(size: const CellSize(40, 3));

    tester.dispatcher.dispatch(const TextCompositionEvent.update('che'));
    expect(c.text, 'git che');
    expect(c.composing, const TextRange(start: 4, end: 7));

    tester.type('X');

    expect(
      c.text,
      'git X',
      reason:
          'onTextInput mid-composition must cancel the sticky preedit '
          'before inserting — same contract paste already honors',
    );
    expect(c.composing, TextRange.empty);

    tester.dispatcher.dispatch(const TextCompositionEvent.cancel());
    expect(
      c.text,
      'git X',
      reason: 'a late peer cancel must not find an orphaned base to restore',
    );
  });

  testWidgets(
    'backspace mid-composition cancels the preedit instead of editing it',
    (tester) {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 1,
          child: TextInput(controller: c, autofocus: true),
        ),
      );
      tester.render(size: const CellSize(40, 3));

      tester.dispatcher.dispatch(const TextCompositionEvent.update('che'));
      tester.press(KeySequence.backspace);

      expect(
        c.text,
        'git ',
        reason:
            'Backspace during sticky composition must cancel (restore '
            'baseline), not delete into the interim preedit and drop the base',
      );
      expect(c.composing, TextRange.empty);

      tester.dispatcher.dispatch(const TextCompositionEvent.cancel());
      expect(c.text, 'git ');
    },
  );

  testWidgets(
    'stale peer commit after mid-composition type does not duplicate',
    (tester) {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 1,
          child: TextInput(controller: c, autofocus: true),
        ),
      );
      tester.render(size: const CellSize(40, 3));

      tester.dispatcher.dispatch(const TextCompositionEvent.update('che'));
      tester.type('X');
      tester.dispatcher.dispatch(const TextCompositionEvent.commit('checkout'));

      expect(
        c.text,
        'git checkout',
        reason:
            'after type resolved the preedit, a stale peer commit must not '
            'produce git cheXcheckout',
      );
    },
  );
}
