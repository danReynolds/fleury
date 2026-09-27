// The end of each paint pass re-derives the screen geometry of every mounted
// Semantics node, so a scroll or relayout reaches a semantics consumer as a
// leaf update. While a full rebuild is already pending — always, in a
// terminal-only app, where nothing consumes semantics — that walk is wasted:
// the rebuild re-derives every node anyway.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// Sits directly above a Semantics node and counts how often that node's
/// screen geometry is resolved: resolving a child asks its parent where the
/// child sits.
final class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required Widget super.child});

  static final List<_RenderProbe> all = [];

  @override
  RenderObject createRenderObject(BuildContext context) {
    final probe = _RenderProbe();
    all.add(probe);
    return probe;
  }
}

final class _RenderProbe extends RenderObject
    implements RenderObjectWithSingleChild {
  var geometryReads = 0;
  RenderObject? _child;

  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    _child?.paint(buffer, offset);
  }

  @override
  CellOffset childOffsetOf(RenderObject child) {
    geometryReads++;
    return super.childOffsetOf(child);
  }
}

final class _Clock with Notifier {
  var tick = 0;
  void advance() {
    tick++;
    notify();
  }
}

int _reads() => _Probe.all.fold(0, (sum, probe) => sum + probe.geometryReads);

/// A ticking clock above 20 Semantics nodes behind a RepaintBoundary, so a
/// tick repaints the clock and leaves the nodes' paint cached; [gap] moves
/// the nodes without rebuilding them.
Widget _app(_Clock clock, ValueNotifier<int> gap) => Column(
  children: [
    NotifierBuilder(
      notifier: clock,
      builder: (_, clock) => Text('tick ${clock.tick}'),
    ),
    NotifierBuilder(
      notifier: gap,
      builder: (_, gap) => SizedBox(height: gap.value),
    ),
    RepaintBoundary(
      child: Column(
        children: [
          for (var i = 0; i < 20; i++)
            _Probe(
              child: Semantics(
                role: SemanticRole.text,
                label: 'row $i',
                child: Text('row $i'),
              ),
            ),
        ],
      ),
    ),
  ],
);

void main() {
  setUp(_Probe.all.clear);

  testWidgets('no consumer: a paint pass does not walk the semantics', (
    tester,
  ) {
    final clock = _Clock();
    tester.pumpWidget(_app(clock, ValueNotifier(0)));
    tester.render(size: const CellSize(20, 30));
    expect(tester.owner.semanticDirtyTracker.hasDirt, isTrue);

    final before = _reads();
    for (var i = 0; i < 5; i++) {
      clock.advance();
      tester.pump();
    }

    expect(_reads(), before);
  });

  testWidgets('with a consumer: a node that moves is reported', (tester) {
    final gap = ValueNotifier(0);
    tester.pumpWidget(_app(_Clock(), gap));
    tester.render(size: const CellSize(20, 30));
    // A semantics consumer takes the pending full rebuild.
    tester.owner.semanticDirtyTracker.takeDirtySnapshot();
    expect(tester.owner.semanticDirtyTracker.hasDirt, isFalse);

    gap.value = 2;
    tester.pump();

    expect(tester.owner.semanticDirtyTracker.hasDirt, isTrue);
  });
}
