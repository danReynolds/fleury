import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

void main() {
  test('SemanticsOwner reports first snapshot as added nodes', () {
    final owner = SemanticsOwner();
    final update = owner.update(_tree(label: 'Save'));

    expect(update.previous, isNull);
    expect(update.next, same(owner.currentTree));
    expect(update.nextNodesById.keys, {
      const SemanticNodeId('root'),
      const SemanticNodeId('button'),
    });
    expect(update.previousNodesById, isEmpty);
    expect(update.added, {
      const SemanticNodeId('root'),
      const SemanticNodeId('button'),
    });
    expect(update.removed, isEmpty);
    expect(update.updated, isEmpty);
    expect(update.hasChanges, isTrue);
  });

  test('SemanticsOwner reports no changes for equivalent snapshots', () {
    final owner = SemanticsOwner();
    owner.update(_tree(label: 'Save'));

    final update = owner.update(_tree(label: 'Save'));

    expect(update.added, isEmpty);
    expect(update.removed, isEmpty);
    expect(update.updated, isEmpty);
    expect(update.hasChanges, isFalse);
  });

  test('SemanticsOwner compares nested state values without changes', () {
    final owner = SemanticsOwner();
    owner.update(
      _tree(
        label: 'Save',
        state: const SemanticState({
          'metadata': {
            'path': 'lib/main.dart',
            'ranges': [1, 2, 3],
          },
        }),
      ),
    );

    final update = owner.update(
      _tree(
        label: 'Save',
        state: const SemanticState({
          'metadata': {
            'path': 'lib/main.dart',
            'ranges': [1, 2, 3],
          },
        }),
      ),
    );

    expect(update.added, isEmpty);
    expect(update.removed, isEmpty);
    expect(update.updated, isEmpty);
    expect(update.hasChanges, isFalse);
  });

  test('SemanticsOwner reports updated, added, and removed ids', () {
    final owner = SemanticsOwner();
    owner.update(
      _tree(
        label: 'Save',
        children: const [
          SemanticNode(
            id: SemanticNodeId('status'),
            role: SemanticRole.status,
            label: 'Idle',
          ),
        ],
      ),
    );

    final update = owner.update(
      _tree(
        label: 'Run',
        bounds: CellRect.fromLTWH(1, 2, 3, 1),
        children: const [
          SemanticNode(
            id: SemanticNodeId('field'),
            role: SemanticRole.textField,
            label: 'Command',
            value: 'deploy',
          ),
        ],
      ),
    );

    expect(update.added, {const SemanticNodeId('field')});
    expect(update.removed, {const SemanticNodeId('status')});
    expect(update.updated, {
      const SemanticNodeId('root'),
      const SemanticNodeId('button'),
    });
    expect(update.hasChanges, isTrue);
  });

  test('SemanticsOwner reports retained node replacements incrementally', () {
    final owner = SemanticsOwner();
    owner.update(_tree(label: 'Save'));
    final replacement = const SemanticNode(
      id: SemanticNodeId('button'),
      role: SemanticRole.button,
      label: 'Run',
      actions: {SemanticAction.activate},
    );
    final next = owner.currentTree!.replaceNodes({
      const SemanticNodeId('button'): replacement,
    });

    final update = owner.updateRetainedNodes(
      next: next,
      replacements: {const SemanticNodeId('button'): replacement},
    );

    expect(update, isNotNull);
    expect(update!.added, isEmpty);
    expect(update.removed, isEmpty);
    expect(update.updated, {const SemanticNodeId('button')});
    expect(update.next, same(owner.currentTree));
    expect(
      update.nextNodesById[const SemanticNodeId('button')],
      same(replacement),
    );
    expect(update.hasChanges, isTrue);
  });

  test('SemanticsOwner dispose clears retained node index', () {
    final owner = SemanticsOwner();
    owner.update(_tree(label: 'Save'));

    owner.dispose();
    final update = owner.update(_tree(label: 'Save'));

    expect(update.previous, isNull);
    expect(update.added, {
      const SemanticNodeId('root'),
      const SemanticNodeId('button'),
    });
    expect(update.removed, isEmpty);
    expect(update.updated, isEmpty);
    expect(update.hasChanges, isTrue);
  });
}

SemanticTree _tree({
  required String label,
  CellRect? bounds,
  SemanticState state = SemanticState.empty,
  List<SemanticNode> children = const <SemanticNode>[],
}) {
  return SemanticTree(
    root: SemanticNode(
      id: const SemanticNodeId('root'),
      role: SemanticRole.app,
      children: [
        SemanticNode(
          id: const SemanticNodeId('button'),
          role: SemanticRole.button,
          label: label,
          bounds: bounds,
          actions: const {SemanticAction.activate},
          state: state,
        ),
        ...children,
      ],
    ),
  );
}
