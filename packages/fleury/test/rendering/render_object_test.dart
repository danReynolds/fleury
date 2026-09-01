import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:fleury/src/debug/debug_invalidation.dart';
import 'package:fleury/src/rendering/render_navigator.dart';
import 'package:test/test.dart';

/// Minimal stateful host for the invalidation-label tests: `bump()` is a
/// plain `setState`, the single hottest caller of `markNeedsBuild`.
class _Ticker extends StatefulWidget {
  const _Ticker({super.key});

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  int count = 0;
  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('$count');
}

class _CountingRenderObject extends RenderObject {
  _CountingRenderObject(this.nextSize);

  CellSize nextSize;
  int layoutCount = 0;

  void markPaintOnly() => markNeedsPaintOnly();

  @override
  CellSize performLayout(CellConstraints constraints) {
    layoutCount += 1;
    return constraints.constrain(nextSize);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {}
}

class _CountingParentRenderObject extends RenderObject
    implements RenderObjectWithSingleChild {
  _CountingParentRenderObject(RenderObject child) {
    this.child = child;
  }

  int layoutCount = 0;
  RenderObject? _child;

  @override
  RenderObject? get child => _child;

  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    final old = _child;
    if (old != null) dropChild(old);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    layoutCount += 1;
    return _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {}
}

void main() {
  group('RenderObject layout dirtiness', () {
    test('caches same-constraint layout until marked dirty', () {
      final render = _CountingRenderObject(const CellSize(3, 2));
      const constraints = CellConstraints(maxCols: 10, maxRows: 10);

      expect(render.layout(constraints), const CellSize(3, 2));
      expect(render.layout(constraints), const CellSize(3, 2));
      expect(render.layoutCount, 1);

      render.nextSize = const CellSize(4, 2);
      render.markNeedsLayout();

      expect(render.layout(constraints), const CellSize(4, 2));
      expect(render.layoutCount, 2);
    });

    test('constraint changes bypass the cached layout result', () {
      final render = _CountingRenderObject(const CellSize(8, 4));

      expect(
        render.layout(const CellConstraints(maxCols: 10, maxRows: 10)),
        const CellSize(8, 4),
      );
      expect(
        render.layout(const CellConstraints(maxCols: 5, maxRows: 10)),
        const CellSize(5, 4),
      );
      expect(render.layoutCount, 2);
    });

    test('child layout dirtiness bubbles to the parent', () {
      final child = _CountingRenderObject(const CellSize(3, 2));
      final parent = _CountingParentRenderObject(child);
      const constraints = CellConstraints(maxCols: 10, maxRows: 10);

      parent.layout(constraints);
      parent.layout(constraints);
      expect(parent.layoutCount, 1);
      expect(child.layoutCount, 1);

      child.nextSize = const CellSize(5, 2);
      child.markNeedsLayout();
      expect(parent.layout(constraints), const CellSize(5, 2));

      expect(parent.layoutCount, 2);
      expect(child.layoutCount, 2);
    });

    test('paint invalidation conservatively invalidates layout', () {
      final child = _CountingRenderObject(const CellSize(3, 2));
      final parent = _CountingParentRenderObject(child);
      const constraints = CellConstraints(maxCols: 10, maxRows: 10);

      parent.layout(constraints);
      parent.layout(constraints);
      expect(parent.layoutCount, 1);
      expect(child.layoutCount, 1);

      child.markNeedsPaint();
      parent.layout(constraints);

      expect(parent.layoutCount, 2);
      expect(child.layoutCount, 2);
    });

    test('paint-only invalidation preserves cached layout', () {
      final child = _CountingRenderObject(const CellSize(3, 2));
      final parent = _CountingParentRenderObject(child);
      const constraints = CellConstraints(maxCols: 10, maxRows: 10);

      parent.layout(constraints);
      parent.layout(constraints);
      expect(parent.layoutCount, 1);
      expect(child.layoutCount, 1);

      child.markPaintOnly();
      parent.layout(constraints);

      expect(parent.layoutCount, 1);
      expect(child.layoutCount, 1);
    });

    test('debug invalidation collector records layout sources', () {
      final subscription = DebugEvents.stream.listen((_) {});
      addTearDown(subscription.cancel);

      DebugInvalidations.reset();
      final render = _CountingRenderObject(const CellSize(3, 2))
        ..layout(const CellConstraints(maxCols: 10, maxRows: 10));

      DebugInvalidations.reset();
      render.markNeedsLayout();

      expect(
        DebugInvalidations.drain(),
        contains('layout:_CountingRenderObject'),
      );
    });

    test('debug invalidation collector records paint-only sources', () {
      final subscription = DebugEvents.stream.listen((_) {});
      addTearDown(subscription.cancel);

      DebugInvalidations.reset();
      final render = _CountingRenderObject(const CellSize(3, 2))
        ..layout(const CellConstraints(maxCols: 10, maxRows: 10));

      DebugInvalidations.reset();
      render.markPaintOnly();

      expect(
        DebugInvalidations.drain(),
        contains('paint:_CountingRenderObject'),
      );
    });

    test('no listener: a render-object invalidation builds no label', () {
      // The collector's contract (debug_invalidation.dart) is that the HOT
      // PATH checks `DebugEvents.hasListeners` before allocating a label.
      // `_record` checking after the fact is too late: the caller has already
      // paid for `runtimeType.toString()`, on every invalidation of every
      // render object in every frame.
      expect(DebugInvalidations.isRecording, isFalse, reason: 'precondition');
      final render = _CountingRenderObject(const CellSize(3, 2))
        ..layout(const CellConstraints(maxCols: 10, maxRows: 10));

      final before = DebugInvalidations.debugLabelsBuilt;
      for (var i = 0; i < 100; i++) {
        render.markNeedsLayout();
        render.markNeedsPaint();
        render.markPaintOnly();
      }
      expect(DebugInvalidations.debugLabelsBuilt, before);
    });

    test('with a listener: render-object labels are still built', () {
      final subscription = DebugEvents.stream.listen((_) {});
      addTearDown(subscription.cancel);

      DebugInvalidations.reset();
      final render = _CountingRenderObject(const CellSize(3, 2))
        ..layout(const CellConstraints(maxCols: 10, maxRows: 10));

      DebugInvalidations.reset();
      final before = DebugInvalidations.debugLabelsBuilt;
      render.markNeedsPaint();
      expect(DebugInvalidations.debugLabelsBuilt, before + 1);
      expect(
        DebugInvalidations.drain(),
        contains('paint:_CountingRenderObject'),
      );
    });

    testWidgets('no listener: setState builds no label', (tester) {
      expect(DebugInvalidations.isRecording, isFalse, reason: 'precondition');
      final key = GlobalKey<_TickerState>();
      tester.pumpWidget(_Ticker(key: key));

      final before = DebugInvalidations.debugLabelsBuilt;
      for (var i = 0; i < 100; i++) {
        key.currentState!.bump();
        tester.render(size: const CellSize(20, 1));
      }
      expect(DebugInvalidations.debugLabelsBuilt, before);
    });

    testWidgets('with a listener: the setState label names widget and state', (
      tester,
    ) {
      final subscription = DebugEvents.stream.listen((_) {});
      addTearDown(subscription.cancel);

      final key = GlobalKey<_TickerState>();
      tester.pumpWidget(_Ticker(key: key));

      DebugInvalidations.reset();
      final before = DebugInvalidations.debugLabelsBuilt;
      key.currentState!.bump();
      expect(DebugInvalidations.debugLabelsBuilt, greaterThan(before));
      expect(DebugInvalidations.drain(), contains('build:_Ticker/_TickerState'));
    });
  });

  group('RenderObjectWithChildren replacement dirtiness', () {
    test(
      'same ordered children are a layout no-op for core multi-child nodes',
      () {
        final factories = <RenderObjectWithChildren Function()>[
          () => RenderFlex(direction: Axis.horizontal),
          RenderStack.new,
          RenderIndexedStack.new,
          RenderWrap.new,
          RenderNavigatorStack.new,
        ];

        for (final factory in factories) {
          final parent = factory();
          final a = _CountingRenderObject(const CellSize(2, 1));
          final b = _CountingRenderObject(const CellSize(3, 1));
          parent.replaceAllChildren([a, b]);
          parent.layout(const CellConstraints(maxCols: 20, maxRows: 10));

          final parentRender = parent as RenderObject;
          parentRender.layout(const CellConstraints(maxCols: 20, maxRows: 10));
          expect(a.layoutCount, 1, reason: '${parent.runtimeType} setup');
          expect(b.layoutCount, 1, reason: '${parent.runtimeType} setup');

          parent.replaceAllChildren([a, b]);
          RenderLayoutDebugStats.beginFrame(enabled: true);
          parentRender.layout(const CellConstraints(maxCols: 20, maxRows: 10));
          final stats = RenderLayoutDebugStats.takeFrameStats();

          expect(
            a.layoutCount,
            1,
            reason: '${parent.runtimeType} should keep child A layout cached',
          );
          expect(
            b.layoutCount,
            1,
            reason: '${parent.runtimeType} should keep child B layout cached',
          );
          expect(
            stats.skippedCount,
            1,
            reason:
                '${parent.runtimeType} should skip cached parent layout after '
                'same ordered children are supplied',
          );
          expect(stats.performedCount, 0);
        }
      },
    );

    test('reordered children still invalidate layout', () {
      final parent = RenderFlex(direction: Axis.horizontal);
      final a = _CountingRenderObject(const CellSize(2, 1));
      final b = _CountingRenderObject(const CellSize(3, 1));
      const constraints = CellConstraints(maxCols: 20, maxRows: 10);

      parent.replaceAllChildren([a, b]);
      parent.layout(constraints);
      parent.layout(constraints);
      expect(a.layoutCount, 1);
      expect(b.layoutCount, 1);

      parent.replaceAllChildren([b, a]);
      RenderLayoutDebugStats.beginFrame(enabled: true);
      parent.layout(constraints);
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(stats.performedCount, 1);
      expect(stats.skippedCount, 2);
      expect(a.layoutCount, 1);
      expect(b.layoutCount, 1);
    });
  });
}
