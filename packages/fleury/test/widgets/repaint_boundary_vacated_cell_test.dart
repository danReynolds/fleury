// The vacated-cell contract as a real widget tree driven through the real
// double-buffered frame loop.
//
// `repaint_boundary_test.dart` covers the boundary's OWN half — a boundary that
// repaints re-damages the extent it shrank out of. This covers the half no
// boundary can: when a cached boundary is unmounted, the cells it occupied are
// abandoned by a frame that never painted them and never recorded damage for
// them. Nothing in the boundary is left to notice.
//
// It needs the genuine loop, not a hand-managed buffer: the signal only exists
// as a difference between the shown buffer and the new one.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  void bump() => setState(() => count++);
  @override
  Widget build(BuildContext context) => Text('c=$count');
}

void main() {
  testWidgets('an unmounted cached boundary does not leave ghost cells', (
    tester,
  ) {
    const size = CellSize(12, 4);
    final sibling = GlobalKey<_CounterState>();

    // The tall child occupies rows 0-2; the short one only row 0. An
    // IndexedStack flip is markNeedsPaintOnly, so the frame stays bounded —
    // exactly the case a bounded presenter must be told about.
    Widget tree(int index) => Column(
      children: [
        IndexedStack(
          index: index,
          children: const [
            RepaintBoundary(
              child: Column(
                children: [Text('AAAA'), Text('BBBB'), Text('CCCC')],
              ),
            ),
            RepaintBoundary(child: Text('x')),
          ],
        ),
        _Counter(key: sibling),
      ],
    );

    final loop = TuiFrameLoop(renderDamage: tester.owner.renderDamageTracker);
    TuiRenderedFrame frame() {
      final rendered = loop.render(
        size: size,
        paint: (buffer) => tester.owner.renderFrame(tester.root!, buffer),
      )!;
      loop.commit(rendered);
      return rendered;
    }

    // Frame 1: full repaint settles the boundary cache on the tall child.
    tester.pumpWidget(tree(0));
    frame();

    // Frame 2: only the sibling changes, so the boundary is a CACHE HIT and
    // blits its three rows in without recording any damage for them. This is
    // the frame that makes the bug invisible to paint-damage bookkeeping.
    sibling.currentState!.bump();
    final cached = frame();
    expect(
      cached.damage.dirtyRowsFor(size).rows,
      isNot(contains(2)),
      reason: 'precondition: row 2 is rebuilt by a cache hit, not repainted',
    );

    // Frame 3: flip to the short child. The tall boundary is gone, so rows 1-2
    // are abandoned by a frame that never touched them.
    tester.pumpWidget(tree(1));
    final flipped = frame();

    expect(
      flipped.next.atColRow(0, 2).grapheme ?? '',
      '',
      reason: 'the model buffer is clean — the ghost is in the damage',
    );
    expect(
      flipped.damage.dirtyRowsFor(size).rows,
      containsAll(<int>[1, 2]),
      reason:
          'rows the unmounted boundary vacated must be damaged; a retained '
          'presenter keeps BBBB/CCCC on screen otherwise',
    );
  });
}
