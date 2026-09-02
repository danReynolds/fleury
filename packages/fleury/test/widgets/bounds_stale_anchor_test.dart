// A float hides when its anchor stops painting while staying mounted.
//
// BoundsObserver published on every paint and retracted only on unmount, so
// an anchor that stayed mounted but stopped painting — the other IndexedStack
// tab, a route beneath an opaque one — kept its last bounds forever, and the
// float anchored to it hovered over whatever painted there next. Every root
// paint pass now ends by retracting observations no subtree refreshed
// (painted, or replayed by a cached repaint boundary).

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

const _size = CellSize(30, 6);

({int col, int row})? _find(FleuryTester tester, String glyph) {
  final buf = tester.render(size: _size);
  for (var r = 0; r < _size.rows; r++) {
    for (var c = 0; c < _size.cols; c++) {
      if (buf.atColRow(c, r).grapheme == glyph) return (col: c, row: r);
    }
  }
  return null;
}

void main() {
  testWidgets('switching an IndexedStack away from the anchor hides the '
      'float', (tester) {
    final chip = BoundsNotifier();
    final index = ValueNotifier<int>(0);
    tester.pumpWidget(
      ListenableBuilder(
        listenable: index,
        builder: (context, _) => Stack(
          children: [
            IndexedStack(
              index: index.value,
              children: [
                BoundsObserver(notifier: chip, child: const Text('tab-a')),
                const Text('tab-b'),
              ],
            ),
            BoundsAnchor(notifier: chip, child: const Text('¤')),
          ],
        ),
      ),
    );
    expect(_find(tester, '¤'), isNotNull, reason: 'anchor paints → float');

    index.value = 1;
    // The pass that first paints tab-b ends by retracting tab-a's bounds
    // (it neither painted nor replayed); the float repaints hidden on the
    // pass after — one frame, which the retraction itself schedules.
    tester.render(size: _size);
    expect(chip.visibleBounds, isNull, reason: 'retracted at end of pass');
    expect(_find(tester, '¤'), isNull, reason: 'nothing to attach to');

    index.value = 0;
    tester.render(size: _size);
    expect(_find(tester, '¤'), isNotNull, reason: 'anchor paints again');
  });

  testWidgets('an anchor inside a cached repaint boundary stays attached '
      'while an unrelated sibling repaints', (tester) {
    // The boundary replays its retained geometry on a cached paint, which
    // counts as refreshed — the sweep must not retract a clean subtree.
    final chip = BoundsNotifier();
    final counter = ValueNotifier<int>(0);
    tester.pumpWidget(
      Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RepaintBoundary(
                child: BoundsObserver(notifier: chip, child: const Text('ab')),
              ),
              ListenableBuilder(
                listenable: counter,
                builder: (context, _) => Text('tick ${counter.value}'),
              ),
            ],
          ),
          BoundsAnchor(notifier: chip, child: const Text('¤')),
        ],
      ),
    );
    expect(_find(tester, '¤'), isNotNull);
    for (var i = 1; i <= 3; i++) {
      counter.value = i;
      tester.render(size: _size);
      expect(chip.visibleBounds, isNotNull, reason: 'frame $i: still painted');
      expect(_find(tester, '¤'), isNotNull, reason: 'frame $i: float stays');
    }
  });
}
