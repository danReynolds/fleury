import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// WS-0: the build-owner structure generation must bump on every tree-*shape*
/// change (add / remove / reparent / reorder) and **never** on a value-only
/// rebuild — the invariant the stale-reference guard relies on, and the one the
/// reverted id-memo got wrong.
void main() {
  group('BuildOwner.structureGeneration', () {
    testWidgets('does NOT bump on a value-only rebuild', (tester) {
      tester.pumpWidget(const Text('a'));
      final before = tester.owner.structureGeneration;
      tester.pumpWidget(const Text('b')); // same shape, new value
      expect(tester.owner.structureGeneration, before);
    });

    testWidgets('does NOT bump when an unkeyed same-type sibling changes value',
        (tester) {
      // Two unkeyed Texts "swapped" is reconciled as in-place value updates —
      // the elements don't move, so no positional id changes ownership.
      tester.pumpWidget(
        const Column(children: [Text('a'), Text('b')]),
      );
      final before = tester.owner.structureGeneration;
      tester.pumpWidget(
        const Column(children: [Text('b'), Text('a')]),
      );
      expect(tester.owner.structureGeneration, before);
    });

    testWidgets('bumps when a child is added', (tester) {
      tester.pumpWidget(const Column(children: [Text('a')]));
      final before = tester.owner.structureGeneration;
      tester.pumpWidget(const Column(children: [Text('a'), Text('b')]));
      expect(tester.owner.structureGeneration, greaterThan(before));
    });

    testWidgets('bumps when a child is removed', (tester) {
      tester.pumpWidget(const Column(children: [Text('a'), Text('b')]));
      final before = tester.owner.structureGeneration;
      tester.pumpWidget(const Column(children: [Text('a')]));
      expect(tester.owner.structureGeneration, greaterThan(before));
    });

    testWidgets('bumps when keyed children reorder in place', (tester) {
      tester.pumpWidget(
        const Column(
          children: [
            Text('a', key: ValueKey('a')),
            Text('b', key: ValueKey('b')),
          ],
        ),
      );
      final before = tester.owner.structureGeneration;
      tester.pumpWidget(
        const Column(
          children: [
            Text('b', key: ValueKey('b')),
            Text('a', key: ValueKey('a')),
          ],
        ),
      );
      expect(tester.owner.structureGeneration, greaterThan(before));
    });

    testWidgets('bumps when a NON-semantic sibling is added (shifts a slot)',
        (tester) {
      // The reverted-memo failure mode: a node that did not itself change can
      // still have its positional id shift because a sibling appeared. The
      // generation must catch it — and it does, because every element's mount
      // bumps, not just Semantics elements.
      tester.pumpWidget(
        const Column(children: [SizedBox(width: 1), Text('keep')]),
      );
      final before = tester.owner.structureGeneration;
      tester.pumpWidget(
        const Column(
          children: [SizedBox(width: 1), SizedBox(width: 1), Text('keep')],
        ),
      );
      expect(tester.owner.structureGeneration, greaterThan(before));
    });
  });
}
