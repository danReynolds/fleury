// Freeze-proofing guard for semantic-node identity.
//
// The semantic tree is collected on-demand today, but the public identity
// contract must already support the incremental/observable backend (and remote
// mirrors / durable test selectors) that will come later. That requires
// identity that is STABLE ACROSS REBUILDS for nodes that opt in via an explicit
// id or a Key. This test pins that contract so it can't silently regress before
// the API freezes.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
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
      // The key renders compactly (just its value), not the verbose
      // `ValueKey<String>(row-7)` — that wrapper is pure token cost.
      expect(first.value, 'key:row-7');
    });

    testWidgets('without an explicit id or key, the id is derived from the '
        'keyed-ancestor chain (auto:…), not an element hash', (tester) {
      tester.pumpWidget(
        const Semantics(
          role: SemanticRole.button,
          label: 'Anon',
          child: Text('Anon'),
        ),
      );
      final id = tester.semantics().where(role: SemanticRole.button).single.id;
      // A realistic tree always has a keyed ancestor (here the Overlay entry),
      // so an unkeyed node anchors to it with a ~positional tail: value-derived
      // and stable within the session, unlike the old element-<hash>. The `~`
      // marks it version-fragile for the stale guard. (The bare element-<hash>
      // form remains only as a deep fallback for a node with no keyed ancestor
      // at all — not reachable through the normal runtime/overlay root.)
      expect(id.value, startsWith('auto:'));
      expect(id.value, contains('~'));
      expect(id.value, isNot(startsWith('element-')));
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

  group('derived identity from keyed ancestors (RFC A1/A2)', () {
    // A keyed list row wrapping an unkeyed leaf — the shape Fleury's data
    // widgets produce (rows carry a Key; the cells inside do not).
    Widget row(String k) => Semantics(
      key: ValueKey('row-$k'),
      role: SemanticRole.listItem,
      child: Semantics(role: SemanticRole.button, label: k, child: Text(k)),
    );
    Widget build(List<String> ks) =>
        Column(children: <Widget>[for (final k in ks) row(k)]);

    testWidgets('an unkeyed node folds its keyed ancestor into a stable '
        'auto: id', (tester) {
      tester.pumpWidget(build(<String>['a']));
      final id = tester.semantics().where(role: SemanticRole.button).single.id;

      expect(id.value, startsWith('auto:'));
      expect(
        id.value,
        contains('/row-a/'),
        reason: 'the keyed ancestor (rendered compactly) anchors the id',
      );
      expect(id.value, isNot(contains('element-')));
    });

    testWidgets('the keyed-anchored id is reorder-proof', (tester) {
      tester.pumpWidget(build(<String>['a', 'b']));
      final aId = tester
          .semantics()
          .where(role: SemanticRole.button, label: 'a')
          .single
          .id;
      final bId = tester
          .semantics()
          .where(role: SemanticRole.button, label: 'b')
          .single
          .id;
      expect(aId, isNot(bId));

      // Swap the rows. Each row keeps its Key, so its descendant keeps its id
      // wherever the row now sits — the property element-$hashCode never had.
      tester.pumpWidget(build(<String>['b', 'a']));
      final aId2 = tester
          .semantics()
          .where(role: SemanticRole.button, label: 'a')
          .single
          .id;
      final bId2 = tester
          .semantics()
          .where(role: SemanticRole.button, label: 'b')
          .single
          .id;
      expect(aId2, aId, reason: 'row a moved but its node id is unchanged');
      expect(bId2, bId, reason: 'row b moved but its node id is unchanged');
    });

    testWidgets('two unkeyed same-role siblings under one key get distinct '
        'ids (positional tail)', (tester) {
      tester.pumpWidget(
        Semantics(
          key: const ValueKey('scope'),
          role: SemanticRole.list,
          child: Column(
            children: const <Widget>[
              Semantics(
                role: SemanticRole.button,
                label: 'x',
                child: Text('x'),
              ),
              Semantics(
                role: SemanticRole.button,
                label: 'y',
                child: Text('y'),
              ),
            ],
          ),
        ),
      );
      final ids = tester
          .semantics()
          .where(role: SemanticRole.button)
          .map((n) => n.id)
          .toSet();
      expect(ids, hasLength(2), reason: 'the ~positional tail disambiguates');
      expect(
        ids.every((id) => id.value.contains('~')),
        isTrue,
        reason: 'positional ids carry the ~ fragility marker',
      );
    });

    testWidgets('a positional id reflects the node\'s current position after a '
        'sibling insert shifts it', (tester) {
      Widget build({required bool withLeader}) => Semantics(
        key: const ValueKey('scope'),
        role: SemanticRole.list,
        child: Column(
          children: <Widget>[
            if (withLeader)
              const Semantics(
                role: SemanticRole.text,
                label: 'lead',
                child: Text('lead'),
              ),
            // const ⇒ this element is reused (no update()) across the insert; the
            // derivation must still report its new ~index, since _nodeId is
            // computed fresh from the live tree rather than cached.
            const Semantics(
              role: SemanticRole.button,
              label: 'x',
              child: Text('x'),
            ),
          ],
        ),
      );

      tester.pumpWidget(build(withLeader: false));
      final before = tester
          .semantics()
          .where(role: SemanticRole.button)
          .single
          .id
          .value;

      tester.pumpWidget(build(withLeader: true));
      final after = tester
          .semantics()
          .where(role: SemanticRole.button)
          .single
          .id
          .value;

      expect(
        after,
        isNot(before),
        reason:
            'the ~positional segment shifted; a stale memo would not change',
      );
    });

    test(
      'escapeSemanticIdSegment neutralizes the / separator and ~ marker',
      () {
        expect(escapeSemanticIdSegment('plain'), 'plain');
        expect(escapeSemanticIdSegment('a/b'), 'a%2Fb');
        expect(escapeSemanticIdSegment('a~b'), 'a%7Eb');
        expect(escapeSemanticIdSegment('a%b'), 'a%25b');
        // % escaped first, so the escape is unambiguous/reversible.
        expect(escapeSemanticIdSegment('~/%'), '%7E%2F%25');
      },
    );

    testWidgets('a folded ancestor key containing / or ~ is escaped, so it '
        'cannot inject a segment or be misread as positional', (tester) {
      tester.pumpWidget(
        const Semantics(
          key: ValueKey('a/b~c'),
          role: SemanticRole.list,
          child: Semantics(
            role: SemanticRole.button,
            label: 'x',
            child: Text('x'),
          ),
        ),
      );
      final id = tester
          .semantics()
          .where(role: SemanticRole.button)
          .single
          .id
          .value;
      expect(id, contains('a%2Fb%7Ec'), reason: 'the key is folded in escaped');
      expect(id, isNot(contains('a/b~c')), reason: 'raw key form is absent');
    });

    testWidgets('a positional id survives a from-scratch rebuild at the same '
        'position', (tester) {
      tester.pumpWidget(build(<String>['a']));
      final first = tester
          .semantics()
          .where(role: SemanticRole.button)
          .single
          .id;
      tester.pumpWidget(const SizedBox());
      tester.pumpWidget(build(<String>['a']));
      final second = tester
          .semantics()
          .where(role: SemanticRole.button)
          .single
          .id;
      expect(
        second,
        first,
        reason: 'derived ids are value-based, not element-instance-based',
      );
    });
  });
}
