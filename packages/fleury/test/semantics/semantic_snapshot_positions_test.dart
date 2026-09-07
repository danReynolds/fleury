import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _CountingColumn extends Column {
  const _CountingColumn({required super.children})
    : super(key: const ValueKey('scope'));

  @override
  MultiChildRenderObjectElement createElement() => _CountingElement(this);
}

class _CountingElement extends MultiChildRenderObjectElement {
  _CountingElement(super.widget);
  int childVisits = 0;

  @override
  void visitChildren(void Function(Element) visitor) {
    super.visitChildren((child) {
      childVisits++;
      visitor(child);
    });
  }
}

class _AnchorProbe extends ProxyWidget {
  const _AnchorProbe({super.key, this.onSnapshot})
    : super(child: const SizedBox());
  final void Function()? onSnapshot;

  @override
  Element createElement() => _AnchorElement(this);
}

class _AnchorElement extends ComponentElement implements SemanticContributor {
  _AnchorElement(_AnchorProbe super.widget);

  @override
  _AnchorProbe get widget => super.widget as _AnchorProbe;

  @override
  Widget buildChild() => widget.child;

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    final id = SemanticNodeId(semanticAnchorOf(this) ?? 'element-$hashCode');
    widget.onSnapshot?.call();
    return SemanticNode(id: id, role: SemanticRole.button, children: children);
  }
}

void main() {
  for (final keyedRoot in [false, true]) {
    test(
      'snapshot prefixes match live identity rules (keyed root: $keyedRoot)',
      () {
        final owner = BuildOwner();
        final global = GlobalKey();
        final root = owner.mountRoot(
          Column(
            key: keyedRoot ? const ValueKey('outer/~%') : null,
            children: [
              const _AnchorProbe(),
              Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const _AnchorProbe(),
                    Column(
                      key: const ValueKey('inner/~%'),
                      children: [
                        _AnchorProbe(key: global),
                        const _AnchorProbe(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        addTearDown(root.unmount);
        final expected = <String>[];
        void visit(Element element) {
          if (element is _AnchorElement) {
            // Outside snapshot collection this is the original live parent
            // walk, independent of the snapshot prefix-sharing algorithm.
            expected.add(
              semanticAnchorOf(element) ?? 'element-${element.hashCode}',
            );
          }
          element.visitChildren(visit);
        }

        visit(root);
        final tree = SemanticTree.fromElement(root);
        expect(tree.root.children.map((n) => n.id.value), expected);
        expect(
          semanticAnchorOf(global.currentContext! as Element),
          '${keyedRoot ? 'auto:outer%2F%7E%25/' : 'auto:'}inner%2F%7E%25/~0',
        );
      },
    );
  }

  test(
    'pending full rebuild skips positional work and resumes leaf tracking',
    () {
      const count = 100;
      final owner = BuildOwner();
      Widget scene(String label) => _CountingColumn(
        children: [
          for (var i = 0; i < count; i++)
            Semantics(
              role: SemanticRole.status,
              label: '$label-$i',
              includeChildren: false,
              child: const SizedBox(),
            ),
        ],
      );
      final root = owner.mountRoot(scene('before')) as _CountingElement;
      addTearDown(root.unmount);
      final tracker = owner.semanticDirtyTracker;
      root.childVisits = 0;
      owner.updateRoot(root, scene('after'));
      expect(root.childVisits, lessThanOrEqualTo(count * 3));
      expect(tracker.takeDirtySnapshot().requiresFullRebuild, isTrue);
      final full = SemanticTree.fromElement(root);
      expect(
        full.root.children.map((node) => node.label),
        orderedEquals(List.generate(count, (i) => 'after-$i')),
      );

      owner.updateRoot(root, scene('retained'));
      final next = tracker.takeDirtySnapshot();
      expect(next.requiresFullRebuild, isFalse);
      expect(next.leafUpdates.length, count);
      expect(
        next.leafUpdates.keys.toSet(),
        full.root.children.map((node) => node.id).toSet(),
      );
      expect(
        next.leafUpdates.values.map((node) => node.label),
        orderedEquals(List.generate(count, (i) => 'retained-$i')),
      );
    },
  );

  test(
    'pending full rebuild still validates explicit reserved ids on update',
    () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Semantics(role: SemanticRole.status, child: SizedBox()),
      );
      addTearDown(root.unmount);
      expect(
        () => owner.updateRoot(
          root,
          const Semantics(
            id: SemanticNodeId('element-reserved'),
            role: SemanticRole.status,
            child: SizedBox(),
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('wide snapshot traversal stays linear across nested snapshots', () {
    final innerOwner = BuildOwner();
    final inner = innerOwner.mountRoot(
      const Column(
        key: ValueKey('inner'),
        children: [_AnchorProbe(), _AnchorProbe()],
      ),
    );
    addTearDown(inner.unmount);
    final owner = BuildOwner();
    const count = 200;
    final root =
        owner.mountRoot(
              _CountingColumn(
                children: [
                  _AnchorProbe(
                    onSnapshot: () {
                      expect(SemanticTree.fromElement(inner).nodeCount, 3);
                    },
                  ),
                  for (var i = 1; i < count; i++) const _AnchorProbe(),
                ],
              ),
            )
            as _CountingElement;
    addTearDown(root.unmount);
    root.childVisits = 0;
    final tree = SemanticTree.fromElement(root);
    expect(tree.nodeCount, count + 1);
    expect(root.childVisits, lessThanOrEqualTo(count * 3));
    for (var i = 0; i < count; i++) {
      expect(tree.root.children[i].id.value, 'auto:scope/~$i');
      expect(tree.elementById(tree.root.children[i].id), isA<_AnchorElement>());
    }
  });

  for (final fail in [false, true]) {
    test(
      'positions stay fresh after ${fail ? 'failed' : 'successful'} snapshot',
      () {
        final owner = BuildOwner();
        final key = GlobalKey();
        var shouldThrow = fail;
        final first = _AnchorProbe(key: key);
        final second = _AnchorProbe(
          onSnapshot: () {
            if (shouldThrow) throw StateError('snapshot failure');
          },
        );
        Widget scene(bool shifted) => Column(
          key: const ValueKey('scope'),
          children: [if (shifted) const SizedBox(), first, second],
        );
        final root = owner.mountRoot(scene(false));
        addTearDown(root.unmount);
        final element = key.currentContext! as Element;
        expect(semanticAnchorOf(element), 'auto:scope/~0');
        if (fail) {
          expect(() => SemanticTree.fromElement(root), throwsStateError);
        } else {
          expect(SemanticTree.fromElement(root).nodeCount, 3);
        }
        shouldThrow = false;
        owner.updateRoot(root, scene(true));
        expect(identical(key.currentContext, element), isTrue);
        // Read outside collection first: no prior snapshot may leave indices
        // behind for action dispatch or a retained-leaf update to consume.
        expect(semanticAnchorOf(element), 'auto:scope/~1');
        final next = SemanticTree.fromElement(root);
        expect(next.root.children.first.id.value, 'auto:scope/~1');
        expect(next.elementById(next.root.children.first.id), same(element));
      },
    );
  }

  test(
    'a reparented GlobalKey gets its new keyed scope on the next snapshot',
    () {
      final owner = BuildOwner();
      final key = GlobalKey();
      final child = _AnchorProbe(key: key);
      Widget scene(bool moved) => Column(
        children: [
          Column(key: const ValueKey('a'), children: [if (!moved) child]),
          Column(key: const ValueKey('b'), children: [if (moved) child]),
        ],
      );
      final root = owner.mountRoot(scene(false));
      addTearDown(root.unmount);
      final element = key.currentContext;
      final before = SemanticTree.fromElement(root);
      expect(before.root.children.single.id.value, 'auto:a/~0');
      owner.updateRoot(root, scene(true));
      expect(key.currentContext, same(element));
      final after = SemanticTree.fromElement(root);
      expect(after.root.children.single.id.value, 'auto:b/~0');
      expect(
        after.elementById(const SemanticNodeId('auto:b/~0')),
        same(element),
      );
      expect(after.elementById(const SemanticNodeId('auto:a/~0')), isNull);
      expect(before.root.children.single.id.value, 'auto:a/~0');
    },
  );
}
