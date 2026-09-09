// Lock test: the orphan latch must not outlive the composition it came from.
//
// `_compositionOrphaned` exists so a commit belonging to a composition whose
// owner was taken away is dropped rather than landing on whoever holds focus
// now. It is a bare bool with no session identity, so the danger is it
// latching and never clearing — after which the next DIRECT commit (a
// candidate-selection IME, no preceding update) is swallowed anywhere in the
// app, for a composition that has nothing to do with the orphaned one.
//
// Both variants below reach the same dispatcher precondition — no composition
// owner — and differ only in how they got there.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  void scenario(FleuryTester tester, {required bool deadUpdate}) {
    final aNode = FocusNode(debugLabel: 'a');
    final bNode = FocusNode(debugLabel: 'b-plain');
    final cNode = FocusNode(debugLabel: 'c');
    final a = TextEditingController();
    final c = TextEditingController();
    addTearDown(() {
      aNode.dispose();
      bNode.dispose();
      cNode.dispose();
      a.dispose();
      c.dispose();
    });

    Widget tree({required bool aEnabled}) => Column(
      children: [
        TextInput(controller: a, focusNode: aNode, enabled: aEnabled),
        Focus(focusNode: bNode, child: const Text('plain')),
        TextInput(controller: c, focusNode: cNode),
      ],
    );

    tester.pumpWidget(tree(aEnabled: true));
    tester.render(size: const CellSize(40, 5));
    aNode.requestFocus();
    tester.pump();
    tester.dispatcher.dispatch(const TextCompositionEvent.update('に'));
    expect(a.hasComposingRange, isTrue);

    if (deadUpdate) {
      // A drops its claimant, focus lands on a node that claims no text, and
      // an update arrives that nobody can take. Nothing is composing now.
      tester.pumpWidget(tree(aEnabled: false));
      tester.pump();
      bNode.requestFocus();
      tester.pump();
      tester.dispatcher.dispatch(const TextCompositionEvent.update('ほ'));
      // A is disabled and focus has moved twice, yet A still owns the
      // composition — `_syncClaimants` keeps a disabled field claiming while
      // `hasComposingRange` is true, which is what stops `enabled: false`
      // from cutting an IME mid-word. The commit below therefore lands in A.
      //
      // OPEN QUESTION, deliberately pinned rather than asserted as correct:
      // a disabled, unfocused field receiving committed text is defensible
      // (it is where the user composed it, and its preedit needs resolving)
      // but it also means `enabled` no longer means one thing. The durable
      // answer is a composition session owned by the claimant, not a sticky
      // pointer plus a bool in the dispatcher.
      expect(
        a.hasComposingRange,
        isTrue,
        reason: 'A is still the composition owner despite enabled: false',
      );
    } else {
      tester.dispatcher.dispatch(const TextCompositionEvent.commit('荷'));
      tester.pump();
    }

    cNode.requestFocus();
    tester.pump();
    expect(cNode.hasFocus, isTrue);
    tester.dispatcher.dispatch(const TextCompositionEvent.commit('日本'));
    tester.pump();

    if (deadUpdate) {
      // Routed to the still-composing owner, not swallowed and not given to
      // C. The property that matters here is that it is not LOST.
      expect(a.text, '日本');
      expect(c.text, isEmpty);
    } else {
      expect(
        c.text,
        '日本',
        reason:
            'A finished cleanly, so this commit is new news and belongs to '
            'the field the user is in now — it must not be eaten by a latch '
            'left over from a composition that already ended',
      );
    }
  }

  testWidgets(
    'a clean finish leaves a later direct commit deliverable',
    (tester) => scenario(tester, deadUpdate: false),
  );

  testWidgets(
    'an update nobody takes leaves a later direct commit '
    'deliverable',
    (tester) => scenario(tester, deadUpdate: true),
  );
}
