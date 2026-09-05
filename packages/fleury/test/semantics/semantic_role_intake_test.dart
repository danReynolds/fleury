// A declared role's name is embedded in positional semantic ids and is the
// whole identity on the wire, so two rules are enforced where a node is
// collected: the name is an identifier, and it does not shadow a core name.
@TestOn('vm')
library;

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

const shadow = SemanticRole('status', base: SemanticRole.region);
const spaced = SemanticRole('kanban card', base: SemanticRole.listItem);
const fine = SemanticRole('kanbanCard', base: SemanticRole.listItem);

void main() {
  testWidgets('a declared role that shadows a core name is rejected', (
    tester,
  ) async {
    expect(() {
      tester.pumpWidget(
        const Semantics(role: shadow, label: 'Build 42', child: Text('x')),
      );
      tester.semantics();
    }, throwsA(isA<AssertionError>()));
  });

  testWidgets('a role name that is not an identifier is rejected', (
    tester,
  ) async {
    expect(() {
      tester.pumpWidget(
        const Semantics(role: spaced, label: 'Fix login', child: Text('x')),
      );
      tester.semantics();
    }, throwsA(isA<AssertionError>()));
  });

  testWidgets('a well-formed declared role collects with a derived id', (
    tester,
  ) async {
    tester.pumpWidget(
      const Semantics(
        key: ValueKey('board'),
        role: SemanticRole.region,
        child: Semantics(role: fine, label: 'Fix login', child: Text('x')),
      ),
    );
    final node = tester.semantics().byRole(fine).single;
    // The role name is the final id segment, verbatim: escaping is a no-op
    // for a well-formed name. (The slot itself is positional — the inner
    // Semantics has no key — which is the framework's ordinary contract.)
    expect(node.id.value.split('/').last, 'kanbanCard');
  });
}
