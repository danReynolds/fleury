// Lock test: "no sticky owner" has two causes and they need opposite answers.
//
//   * The owner was taken away mid-composition (ExcludeFocus covered it, or it
//     dropped its claimant). Its commit is an ORPHAN — dropping it is the
//     point, so it cannot land on whoever holds focus now.
//   * No composition was ever owned. A candidate-selection IME commits with no
//     preceding update at all, and that text is the user's — it must arrive.
//
// Collapsing the two silently ate the second.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a commit with no preceding update reaches the field', (tester) {
    final c = TextEditingController();
    addTearDown(c.dispose);
    tester.pumpWidget(
      SizedBox(
        width: 20,
        height: 1,
        child: TextInput(controller: c, autofocus: true),
      ),
    );
    tester.render(size: const CellSize(20, 3));

    tester.dispatcher.dispatch(const TextCompositionEvent.commit('あ'));

    expect(
      c.text,
      'あ',
      reason: 'a direct commit is ordinary typed text, not an orphan',
    );
  });

  testWidgets('a second direct commit still arrives', (tester) {
    final c = TextEditingController();
    addTearDown(c.dispose);
    tester.pumpWidget(
      SizedBox(
        width: 20,
        height: 1,
        child: TextInput(controller: c, autofocus: true),
      ),
    );
    tester.render(size: const CellSize(20, 3));

    tester.dispatcher.dispatch(const TextCompositionEvent.commit('あ'));
    tester.dispatcher.dispatch(const TextCompositionEvent.commit('い'));

    expect(c.text, 'あい', reason: 'delivering one must not latch anything');
  });

  testWidgets('an update then commit still routes to the owner', (tester) {
    final c = TextEditingController();
    addTearDown(c.dispose);
    tester.pumpWidget(
      SizedBox(
        width: 20,
        height: 1,
        child: TextInput(controller: c, autofocus: true),
      ),
    );
    tester.render(size: const CellSize(20, 3));

    tester.dispatcher.dispatch(const TextCompositionEvent.update('あ'));
    tester.dispatcher.dispatch(const TextCompositionEvent.commit('阿'));

    expect(c.text, '阿');
  });
}
