// Mirrors the "Read it, drive it — in code" section of
// docs/agents-and-semantics.md. These are the real semantic-graph testing APIs
// (read the tree, assert on meaning, invoke a SemanticAction); `dart analyze
// doc_snippets` keeps the prose on that page from drifting away from them.
library;

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('Save advertises an activate action', (tester) {
    tester.pumpWidget(const Semantics(
      id: SemanticNodeId('save'),
      role: SemanticRole.button,
      label: 'Save',
      actions: {SemanticAction.activate},
      child: Text('Save'),
    ));

    final save = tester.semantics().single(
        role: SemanticRole.button, label: 'Save');
    expect(save.actions, contains(SemanticAction.activate));
  });

  testWidgets('activating Save runs its handler', (tester) async {
    var saved = 0;
    tester.pumpWidget(Semantics(
      role: SemanticRole.button,
      label: 'Save',
      actions: const {SemanticAction.activate},
      onAction: (_) => saved++, // the app's handler
      child: const Text('Save'),
    ));

    final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Save');

    expect(result.completed, isTrue);
    expect(saved, 1); // the UI actually changed
  });
}
