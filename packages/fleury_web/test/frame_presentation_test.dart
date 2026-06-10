import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/cell_span_builder.dart';
import 'package:fleury_web/src/frame_presentation.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:test/test.dart';

void main() {
  const size = CellSize(6, 3);
  const planner = FramePresentationPlanner();

  group('FramePresentationPlanner', () {
    test('detects an upward scroll and builds only residual rows', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      const scrollSize = CellSize(6, 4);
      final first = loop.render(
        size: scrollSize,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'aaaa');
          buffer.writeText(const CellOffset(0, 1), 'bbbb');
          buffer.writeText(const CellOffset(0, 2), 'cccc');
          buffer.writeText(const CellOffset(0, 3), 'dddd');
        },
      )!;
      loop.commit(first);

      final second = loop.render(
        size: scrollSize,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'bbbb');
          buffer.writeText(const CellOffset(0, 1), 'cccc');
          buffer.writeText(const CellOffset(0, 2), 'dddd');
          buffer.writeText(const CellOffset(0, 3), 'eeee');
          damage.recordLayoutOrConservativePaint();
        },
      )!;

      final plan = planner.build(reason: 'scroll', frame: second);

      expect(plan.scrollUpRows, 1);
      // The TRUE damage stays full for semantic consumers...
      expect(plan.damage.dirtyRows.isFull, isTrue);
      // ...while the surface only rebuilds the entering row.
      expect(plan.dirtyRowModels.map((row) => row.row), [3]);
    });

    test('non-scroll full-diff frames keep full row models', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      const scrollSize = CellSize(6, 4);
      final first = loop.render(
        size: scrollSize,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'aaaa');
          buffer.writeText(const CellOffset(0, 1), 'bbbb');
        },
      )!;
      loop.commit(first);

      final second = loop.render(
        size: scrollSize,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'zzzz');
          buffer.writeText(const CellOffset(0, 1), 'yyyy');
          damage.recordLayoutOrConservativePaint();
        },
      )!;

      final plan = planner.build(reason: 'layout', frame: second);

      expect(plan.scrollUpRows, isNull);
      // The conservative per-row diff prunes unchanged rows even on
      // full-diff frames, so only the rewritten rows get models.
      expect(plan.dirtyRowModels.map((row) => row.row), [0, 1]);
    });

    test('first frame is a full repaint with all row models', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 1), 'hello'),
      )!;

      final plan = planner.build(reason: 'initial', frame: frame);

      expect(plan.reason, 'initial');
      expect(plan.fullRepaint, isTrue);
      expect(plan.size, size);
      expect(plan.damage.source, FrameDamageSource.fullRepaint);
      expect(plan.damage.dirtyRows.isFull, isTrue);
      expect(plan.dirtyRowModels.map((row) => row.row), [0, 1, 2]);
      expect(plan.dirtyRowDiffTime, Duration.zero);
      expect(plan.spanBuildTime.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('bounded paint damage builds only affected row models', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 1), 'hello'),
      )!;
      loop.commit(first);

      final second = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 1), 'hullo'),
      )!;

      final plan = planner.build(reason: 'paint', frame: second);

      expect(plan.fullRepaint, isFalse);
      expect(plan.damage.source, FrameDamageSource.paintDamage);
      expect(plan.damage.dirtyBounds, CellRect.fromLTWH(0, 1, 6, 1));
      expect(plan.damage.dirtyRows.isFull, isFalse);
      expect(plan.damage.dirtyRows.rows, [1]);
      expect(plan.dirtyRowModels, hasLength(1));
      expect(plan.dirtyRowModels.single.row, 1);
      expect(plan.dirtyRowModels.single.runs.first.text, 'hullo ');
      expect(plan.dirtyRowDiffTime, Duration.zero);
    });

    test('conservative damage uses buffer diff to select changed rows', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'zero');
          buffer.writeText(const CellOffset(0, 1), 'hello');
          buffer.writeText(const CellOffset(0, 2), 'two');
        },
      )!;
      loop.commit(first);

      final second = loop.render(
        size: size,
        paint: (buffer) {
          _copyRowsWithoutDamage(
            source: first.next,
            target: buffer,
            rows: const [0, 2],
          );
          buffer.writeText(const CellOffset(0, 1), 'hullo');
          damage.recordLayoutOrConservativePaint();
        },
      )!;

      final plan = planner.build(reason: 'layout', frame: second);

      expect(plan.damage.source, FrameDamageSource.conservativeFullDiff);
      expect(plan.damage.dirtyBounds, isNull);
      expect(plan.damage.dirtyRows.isFull, isFalse);
      expect(plan.damage.dirtyRows.rows, [1]);
      expect(plan.dirtyRowModels.map((row) => row.row), [1]);
      expect(plan.dirtyRowDiffTime.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('missing paint damage with unchanged buffers presents no rows', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(size: size, paint: (_) {})!;
      loop.commit(first);

      final second = loop.render(size: size, paint: (_) {})!;
      final plan = planner.build(reason: 'idle', frame: second);

      expect(plan.fullRepaint, isFalse);
      expect(plan.damage.source, FrameDamageSource.unboundedFallback);
      expect(plan.damage.dirtyBounds, isNull);
      expect(plan.damage.dirtyRows.isEmpty, isTrue);
      expect(plan.dirtyRowModels, isEmpty);
    });

    test('missing paint damage falls back to row diff oracle', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final first = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'zero');
          buffer.writeText(const CellOffset(0, 1), 'one');
          buffer.writeText(const CellOffset(0, 2), 'two');
        },
      )!;
      loop.commit(first);

      final second = loop.render(
        size: size,
        paint: (buffer) {
          buffer.withoutDamageTracking(() {
            buffer.copyRectFrom(
              first.next,
              CellRect.fromLTWH(0, 1, size.cols, 1),
              const CellOffset(0, 1),
            );
            buffer.writeText(const CellOffset(0, 0), 'ZERO');
            buffer.writeText(const CellOffset(0, 2), 'TWO');
          });
        },
      )!;
      final plan = planner.build(reason: 'oracle', frame: second);

      expect(plan.damage.source, FrameDamageSource.unboundedFallback);
      expect(plan.damage.dirtyRows.isFull, isFalse);
      expect(plan.damage.dirtyRows.ranges, hasLength(2));
      expect(plan.damage.dirtyRows.rows, [0, 2]);
      expect(plan.dirtyRowModels.map((row) => row.row), [0, 2]);
      expect(plan.dirtyRowDiffTime.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('metricsChanged is carried into the plan', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(size: size, paint: (_) {})!;

      final plan = planner.build(
        reason: 'metrics',
        frame: frame,
        metricsChanged: true,
      );

      expect(plan.metricsChanged, isTrue);
    });
  });

  group('WebSurfaceCapabilities', () {
    test('defaults match retained DOM surface assumptions', () {
      const capabilities = WebSurfaceCapabilities();

      expect(capabilities.supportsTrueColor, isTrue);
      expect(capabilities.supportsSemanticLinks, isFalse);
      expect(capabilities.inlineImages, InlineImageCapability.none);
      expect(capabilities.supportsGlyphOverlay, isFalse);
    });
  });

  group('FrameSurface', () {
    test('fake surface can consume a presentation plan', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(
        size: size,
        paint: (buffer) => buffer.writeText(const CellOffset(0, 0), 'ok'),
      )!;
      final plan = planner.build(reason: 'initial', frame: frame);
      final surface = _FakeFrameSurface(size);

      surface.present(frame.previous, frame.next, plan);

      expect(
        surface.presentedPlans.single.dirtyRowModels.first.runs.first.kind,
        CellRunKind.text,
      );
    });
  });
}

void _copyRowsWithoutDamage({
  required CellBuffer source,
  required CellBuffer target,
  required List<int> rows,
}) {
  target.withoutDamageTracking(() {
    for (final row in rows) {
      target.copyRectFrom(
        source,
        CellRect.fromLTWH(0, row, source.size.cols, 1),
        CellOffset(0, row),
      );
    }
  });
}

final class _FakeFrameSurface implements FrameSurface {
  _FakeFrameSurface(this.size);

  @override
  CellSize size;

  @override
  WebSurfaceCapabilities get capabilities => const WebSurfaceCapabilities();

  final presentedPlans = <FramePresentationPlan>[];

  @override
  FrameSurfacePresentationStats present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  ) {
    presentedPlans.add(plan);
    return const FrameSurfacePresentationStats(
      rowsReplaced: 0,
      domNodesCreated: 0,
    );
  }

  @override
  void resize(CellSize size, {MeasuredCellBox? metrics}) {
    this.size = size;
  }

  @override
  Future<void> dispose() async {}
}
