// The verifier that guards repaint-boundary caches — and a test that the
// verifier itself still works.
//
// A boundary cache is the one place in the render path where an under-reported
// change is unrecoverable. Frame damage is DERIVED by comparing the two
// buffers, so nothing else can hide a change by failing to declare it; a stale
// blit defeats that, because by the time the diff runs the buffer genuinely
// matches what was painted. This mode asks the question the diff cannot.
@Tags(['unit'])
library;

import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/render_repaint_boundary.dart'
    show RepaintBoundaryCacheVerification;
import 'package:test/test.dart';

import '../support/harness.dart';

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  void bump() => setState(() => count += 1);
  @override
  Widget build(BuildContext context) => Text('count=$count');
}

void main() {
  group('repaint-boundary cache verification', () {
    setUp(RepaintBoundaryCacheVerification.reset);
    tearDown(() => RepaintBoundaryCacheVerification.enabled = false);

    testWidgets('a cache hit is actually reached, and verified clean', (
      tester,
    ) async {
      RepaintBoundaryCacheVerification.enabled = true;
      final inner = GlobalKey<_CounterState>();
      tester.pumpWidget(
        RepaintBoundary(
          child: RepaintBoundary(child: _Counter(key: inner)),
        ),
      );
      const size = CellSize(12, 1);
      tester.render(size: size);

      // Second frame with nothing dirty: the boundaries cache-hit, and each hit
      // is compared against a fresh repaint.
      tester.render(size: size);

      expect(
        RepaintBoundaryCacheVerification.checkedCount,
        greaterThan(0),
        reason: 'no cache hit was verified — the check would be vacuous',
      );
      expect(RepaintBoundaryCacheVerification.mismatches, isEmpty);
    });

    testWidgets('a change through nested boundaries stays consistent', (
      tester,
    ) async {
      RepaintBoundaryCacheVerification.enabled = true;
      final inner = GlobalKey<_CounterState>();
      tester.pumpWidget(
        RepaintBoundary(
          child: RepaintBoundary(child: _Counter(key: inner)),
        ),
      );
      const size = CellSize(12, 1);
      expect(tester.renderToString(size: size).trim(), 'count=0');

      inner.currentState!.bump();
      tester.pump();
      expect(tester.renderToString(size: size).trim(), 'count=1');
      tester.render(size: size); // settles into a verified cache hit

      expect(RepaintBoundaryCacheVerification.mismatches, isEmpty);
    });

    test('the mode is off by default', () {
      // It repaints every cache hit, which is the whole cost the cache exists
      // to avoid. CI opts in with FLEURY_VERIFY_REPAINT_CACHE=1.
      expect(RepaintBoundaryCacheVerification.enabled, isFalse);
    });
  });
}
