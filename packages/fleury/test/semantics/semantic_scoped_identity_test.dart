import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'repeated row keys in unkeyed branches have independent targets',
    (tester) async {
      final calls = <String>[];
      Widget branch(String name) => Column(
        children: [
          Container(
            key: const ValueKey('a.txt'),
            child: Semantics(
              role: SemanticRole.button,
              label: name,
              actions: const {SemanticAction.activate},
              onAction: (_) => calls.add(name),
              child: Text(name),
            ),
          ),
        ],
      );
      tester.pumpWidget(Row(children: [branch('Recent'), branch('All')]));
      final tree = tester.semantics();
      final recent = tree.single(role: SemanticRole.button, label: 'Recent');
      final all = tree.single(role: SemanticRole.button, label: 'All');
      expect(recent.id, isNot(all.id));
      expect(tree.nodes.map((n) => n.id).toSet(), hasLength(tree.nodeCount));
      expect(SemanticsWireEncoder().encodeTree(tree), isNotNull);
      expect(
        (await tester.invokeSemanticAction(
          SemanticAction.activate,
          id: all.id,
        )).completed,
        isTrue,
      );
      expect(calls, ['All']);
    },
  );

  testWidgets('typed value keys cannot alias in derived semantic ids', (
    tester,
  ) {
    tester.pumpWidget(
      Column(
        children: [
          for (final key in <Key>[
            const ValueKey<int>(1),
            const ValueKey<String>('1'),
          ])
            Container(
              key: key,
              child: const Semantics(
                role: SemanticRole.button,
                child: Text('Row'),
              ),
            ),
        ],
      ),
    );
    final tree = tester.semantics();
    expect(
      tree.where(role: SemanticRole.button).map((n) => n.id).toSet(),
      hasLength(2),
    );
    expect(SemanticsWireEncoder().encodeTree(tree), isNotNull);
  });

  testWidgets('generic value keys retain the value kind', (tester) {
    tester.pumpWidget(
      Column(
        children: [
          for (final key in <Key>[
            const ValueKey<Object>(1),
            const ValueKey<Object>('1'),
          ])
            Container(
              key: key,
              child: const Semantics(
                role: SemanticRole.button,
                child: Text('Row'),
              ),
            ),
        ],
      ),
    );
    final tree = tester.semantics();
    expect(
      tree.where(role: SemanticRole.button).map((n) => n.id).toSet(),
      hasLength(2),
    );
    expect(SemanticsWireEncoder().encodeTree(tree), isNotNull);
  });

  test('positions above the first key distinguish bare owner branches', () {
    final owner = BuildOwner();
    Widget branch() => Column(
      children: [
        Container(
          key: const ValueKey('same'),
          child: const Semantics(role: SemanticRole.button, child: Text('Row')),
        ),
      ],
    );
    final root = owner.mountRoot(Row(children: [branch(), branch()]));
    addTearDown(root.unmount);
    final tree = SemanticTree.fromElement(root);
    expect(
      tree.where(role: SemanticRole.button).map((n) => n.id).toSet(),
      hasLength(2),
    );
  });
}
