import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void main() {
  group('Stack.fit', () {
    CellConstraints? seen;
    Widget probe() => LayoutBuilder(
      builder: (context, constraints) {
        seen = constraints;
        return const Text('x');
      },
    );

    testWidgets('loose (default) drops the minimums', (tester) {
      seen = null;
      tester.pumpWidget(Stack(children: [probe()]));
      tester.render(size: const CellSize(20, 5));
      expect(seen!.minCols, 0);
      expect(seen!.minRows, 0);
      expect(seen!.maxCols, 20);
    });

    testWidgets("passthrough hands children the stack's own constraints", (
      tester,
    ) {
      // Whatever the stack receives, its children receive — a loose root's
      // loose constraints, a tight box's tight ones — so a child lays out
      // exactly as it would bare.
      seen = null;
      tester.pumpWidget(Stack(fit: StackFit.passthrough, children: [probe()]));
      tester.render(size: const CellSize(20, 5));
      expect(seen, CellConstraints.loose(const CellSize(20, 5)));

      seen = null;
      tester.pumpWidget(
        ConstrainedBox(
          minWidth: 20,
          maxWidth: 20,
          minHeight: 5,
          maxHeight: 5,
          child: Stack(fit: StackFit.passthrough, children: [probe()]),
        ),
      );
      tester.render(size: const CellSize(20, 5));
      expect(seen, CellConstraints.tight(const CellSize(20, 5)));
    });

    testWidgets('expand forces children to fill the envelope', (tester) {
      seen = null;
      tester.pumpWidget(Stack(fit: StackFit.expand, children: [probe()]));
      tester.render(size: const CellSize(20, 5));
      expect(seen, CellConstraints.tight(const CellSize(20, 5)));
    });

    testWidgets('a Positioned child never contributes to the size', (tester) {
      // Passthrough + Positioned is the layout-transparent overlay shape.
      seen = null;
      tester.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              fit: StackFit.passthrough,
              children: [
                const Text('ab'),
                Positioned(child: probe()),
              ],
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(20, 5));
      // The overlay is bounded by the stack's own (child-sized) box.
      expect(seen!.maxCols, 2);
      expect(seen!.maxRows, 1);
    });
  });
}
