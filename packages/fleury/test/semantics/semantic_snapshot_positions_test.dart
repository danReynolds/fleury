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
    final id = SemanticNodeId(semanticAnchorOf(this)!);
    widget.onSnapshot?.call();
    return SemanticNode(id: id, role: SemanticRole.button, children: children);
  }
}

void main() {
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
}
