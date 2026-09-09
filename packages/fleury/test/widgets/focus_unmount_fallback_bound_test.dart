// The unmount fallback is captured, not computed on demand, and this pins how
// exact it is.
//
// It cannot be computed on demand: `Element._deactivateChild` clears the
// removed subtree root's `_parent` BEFORE `deactivate` runs, so by the time a
// focused node unregisters, the path to its ancestors is already cut. So the
// chain is captured on the ancestor walk the manager already does when focus
// moves — which means it reflects the tree as of the last focus change.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  group('unmount focus fallback', () {
    testWidgets('falls back to the enclosing Focus, not null', (tester) {
      final outer = FocusNode(debugLabel: 'outer');
      final leaf = FocusNode(debugLabel: 'leaf');
      addTearDown(() {
        outer.dispose();
        leaf.dispose();
      });

      var showLeaf = true;
      Widget build() => Focus(
        focusNode: outer,
        child: showLeaf
            ? Focus(focusNode: leaf, child: const Text('leaf'))
            : const Text('gone'),
      );

      tester.pumpWidget(build());
      leaf.requestFocus();
      tester.pumpWidget(build());
      expect(tester.focusManager.focusedNode, same(leaf));

      showLeaf = false;
      tester.pumpWidget(build());

      expect(
        tester.focusManager.focusedNode,
        same(outer),
        reason: 'keyboard ownership stays in the enclosing Focus',
      );
    });

    testWidgets('a Focus inserted after focus landed is not seen', (tester) {
      final outer = FocusNode(debugLabel: 'outer');
      final middle = FocusNode(debugLabel: 'middle');
      final leaf = FocusNode(debugLabel: 'leaf');
      addTearDown(() {
        outer.dispose();
        middle.dispose();
        leaf.dispose();
      });

      var withMiddle = false;
      var showLeaf = true;
      Widget build() {
        Widget inner = showLeaf
            ? Focus(focusNode: leaf, child: const Text('leaf'))
            : const Text('gone');
        if (withMiddle) inner = Focus(focusNode: middle, child: inner);
        return Focus(focusNode: outer, child: inner);
      }

      tester.pumpWidget(build());
      leaf.requestFocus();
      tester.pumpWidget(build());

      // A Focus appears between the focused leaf and its ancestor, without
      // focus moving — so nothing recaptures the chain.
      withMiddle = true;
      tester.pumpWidget(build());

      showLeaf = false;
      tester.pumpWidget(build());

      expect(
        tester.focusManager.focusedNode,
        same(outer),
        reason:
            'the captured chain predates `middle`, so the fallback lands one '
            'level further out than the nearest enclosing Focus. That is the '
            'documented bound: keyboard ownership is kept (the point of the '
            'fallback), just not at the closest possible node. Recapturing on '
            'every Focus attach would cost a walk per mount to buy only this.',
      );
    });
  });
}
