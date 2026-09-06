import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _CountingColumn extends MultiChildRenderObjectWidget {
  const _CountingColumn({required super.children});

  @override
  RenderFlex createRenderObject(BuildContext context) => _CountingFlex();
}

class _CountingFlex extends RenderFlex {
  _CountingFlex() : super(direction: Axis.vertical);
  int installedChildren = 0;

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    installedChildren += newChildren.length;
    super.replaceAllChildren(newChildren);
  }
}

class _Switch extends StatefulWidget {
  const _Switch({super.key});
  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> {
  bool nested = false;
  void swap() => setState(() => nested = !nested);
  @override
  Widget build(BuildContext context) => nested
      ? const Padding(padding: EdgeInsets.only(left: 1), child: SizedBox())
      : const SizedBox();
}

class _FailMount extends LeafRenderObjectWidget {
  const _FailMount();
  @override
  RenderObject createRenderObject(BuildContext context) =>
      throw StateError('mount');
}

void main() {
  test('mounting siblings installs a linear number of render children', () {
    final owner = BuildOwner();
    final root =
        owner.mountRoot(
              _CountingColumn(
                children: List.generate(200, (_) => const SizedBox()),
              ),
            )
            as MultiChildRenderObjectElement;
    try {
      final render = root.renderObject as _CountingFlex;
      expect(render.children.length, 200);
      expect(render.installedChildren, lessThanOrEqualTo(400));
      expect(
        render.children,
        orderedEquals(
          root.childElements.map(
            (element) => (element as RenderObjectElement).renderObject,
          ),
        ),
      );
      expect(
        render.children.every((child) => identical(child.parent, render)),
        isTrue,
      );
    } finally {
      root.unmount();
    }
  });
  test('failed parent reconciliation restores descendant-only attachment', () {
    final owner = BuildOwner();
    final key = GlobalKey<_SwitchState>();
    final child = _Switch(key: key);
    final root =
        owner.mountRoot(_CountingColumn(children: [child]))
            as MultiChildRenderObjectElement;
    try {
      expect(
        () => owner.updateRoot(
          root,
          _CountingColumn(
            children: [child, const SizedBox(), const _FailMount()],
          ),
        ),
        throwsStateError,
      );
      owner.updateRoot(root, _CountingColumn(children: [child]));
      final render = root.renderObject as _CountingFlex;
      final original = render.children.single;
      key.currentState!.swap();
      owner.flushBuild();
      expect(render.children, hasLength(1));
      expect(render.children.single, isNot(same(original)));
      expect(render.children.single.parent, same(render));
      expect(original.parent, isNull);
    } finally {
      root.unmount();
    }
  });
}
