// Freeze-proofing guard for semantic-node identity.
//
// The semantic tree is collected on-demand today, but the public identity
// contract must already support the incremental/observable backend (and remote
// mirrors / durable test selectors) that will come later. That requires
// identity that is STABLE ACROSS REBUILDS for nodes that opt in via an explicit
// id or a Key. This test pins that contract so it can't silently regress before
// the API freezes.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('semantic node identity contract', () {
    testWidgets('explicit id is the node id verbatim', (tester) {
      tester.pumpWidget(
        const Semantics(
          id: SemanticNodeId('save-button'),
          role: SemanticRole.button,
          label: 'Save',
          child: Text('Save'),
        ),
      );
      final node = tester.semantics().single(role: SemanticRole.button);
      expect(node.id, const SemanticNodeId('save-button'));
    });

    testWidgets('a Key yields a stable, deterministic id (key:<key>)', (
      tester,
    ) {
      Widget build() => const Semantics(
        key: ValueKey('row-7'),
        role: SemanticRole.button,
        label: 'Row',
        child: Text('Row'),
      );

      tester.pumpWidget(build());
      final first = tester.semantics().single(role: SemanticRole.button).id;

      // Rebuild from scratch: a key-derived id must be identical, and it must
      // be deterministic (value-based), not an element hash.
      tester.pumpWidget(const SizedBox());
      tester.pumpWidget(build());
      final second = tester.semantics().single(role: SemanticRole.button).id;

      expect(first, second, reason: 'key identity must survive rebuilds');
      expect(first.value, 'key:ValueKey<String>(row-7)');
    });

    testWidgets('without id or key, the fallback is the documented unstable '
        'element-<hash> form', (tester) {
      tester.pumpWidget(
        const Semantics(
          role: SemanticRole.button,
          label: 'Anon',
          child: Text('Anon'),
        ),
      );
      final id = tester.semantics().single(role: SemanticRole.button).id;
      expect(
        id.value,
        startsWith('element-'),
        reason: 'unkeyed/unid\'d nodes get the snapshot-local fallback id',
      );
    });

    test('SemanticTree query surface works on a hand-built tree '
        '(producer-agnostic consumption)', () {
      // Proves consumption does not require fromElement: an incremental backend
      // can build the same queryable snapshot from a maintained root.
      const tree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('field:token'),
              role: SemanticRole.textField,
              label: 'Token',
            ),
          ],
        ),
      );
      expect(
        tree.nodeById(const SemanticNodeId('field:token'))?.label,
        'Token',
      );
      expect(tree.byRole(SemanticRole.textField), hasLength(1));
    });
  });
}
