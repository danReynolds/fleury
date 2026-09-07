import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/render_navigator.dart';
import 'package:test/test.dart';

class _Leaf extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(1, 1));
  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {}
}

class _Data extends ParentData {
  int detachCount = 0;
  @override
  void detach() {
    detachCount++;
    super.detach();
  }
}

void main() {
  for (final (name, create) in <(String, RenderObjectWithChildren Function())>[
    ('flex', () => RenderFlex()),
    ('stack', () => RenderStack()),
    ('indexed stack', () => RenderIndexedStack()),
    ('wrap', () => RenderWrap()),
    ('navigator', () => RenderNavigatorStack()),
  ]) {
    for (final removedIndex in [0, 1, 2]) {
      test(
        '$name removes child $removedIndex and immediately permits reparenting',
        () {
          final parent = create();
          final children = List.generate(3, (_) => _Leaf());
          parent.replaceAllChildren(children);
          final data = List.generate(children.length, (_) => _Data());
          for (var i = 0; i < children.length; i++) {
            children[i].parentData = data[i];
          }
          parent.layout(const CellConstraints(maxCols: 10, maxRows: 5));
          final removed = children[removedIndex];
          final retained = [...children]..removeAt(removedIndex);
          parent.replaceAllChildren(retained);
          expect(parent.children, orderedEquals(retained));
          expect(removed.parent, isNull);
          expect(removed.parentData, isNull);
          expect(data[removedIndex].detachCount, 1);
          for (final child in retained) {
            expect(child.parent, same(parent));
            final ownData = data[children.indexOf(child)];
            expect(child.parentData, same(ownData));
            expect(ownData.detachCount, 0);
          }
          final newParent = RenderStack()..replaceAllChildren([removed]);
          parent.layout(const CellConstraints(maxCols: 10, maxRows: 5));
          parent.replaceAllChildren(retained.reversed.toList());
          expect(parent.children, orderedEquals(retained.reversed));
          parent.replaceAllChildren([]);
          expect(removed.parent, same(newParent));
          expect(data[removedIndex].detachCount, 1);
          newParent.replaceAllChildren([]);
        },
      );
    }
    test('$name handles a removal combined with sibling reordering', () {
      final parent = create();
      final a = _Leaf(), b = _Leaf(), c = _Leaf();
      parent.replaceAllChildren([a, b, c]);
      parent.replaceAllChildren([c, a]);
      expect(parent.children, orderedEquals([c, a]));
      expect(b.parent, isNull);
      expect(a.parent, same(parent));
      expect(c.parent, same(parent));
      parent.replaceAllChildren([]);
    });
  }
}
