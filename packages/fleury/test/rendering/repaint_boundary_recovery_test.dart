import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

class _TransientPaint extends RenderObject {
  bool fail = false;
  bool partialWrite = false;
  int paints = 0;

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(2, 1));

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    paints++;
    if (fail) {
      fail = false;
      if (partialWrite) buffer.writeText(offset, 'X');
      throw StateError('transient paint failure');
    }
    buffer.writeText(offset, 'OK');
  }
}

class _PaintWidget extends LeafRenderObjectWidget {
  const _PaintWidget(this.render);
  final RenderObject render;

  @override
  RenderObject createRenderObject(BuildContext context) => render;
}

class _Presenter implements FramePresenter {
  final frames = <String>[];

  @override
  bool get wantsPresentationPlan => false;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {
    frames.add(
      frame.next.textInRange(
        CellRect(offset: CellOffset.zero, size: frame.next.size),
      ),
    );
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {}

  @override
  FrameDiffStats? frameDiffStats(
    TuiRenderedFrame frame,
    FramePresentInfo info,
  ) => null;
}

void main() {
  for (final nested in [false, true]) {
    for (final partialWrite in [false, true]) {
      test(
        'failed cache repaints on retry: nested=$nested, partial=$partialWrite',
        () {
          final leaf = _TransientPaint()..partialWrite = partialWrite;
          final inner = RenderRepaintBoundary()..child = leaf;
          final outer = nested
              ? (RenderRepaintBoundary()..child = inner)
              : inner;
          const size = CellSize(2, 1);
          outer.layout(const CellConstraints(maxCols: 2, maxRows: 1));
          outer.paint(CellBuffer(size), CellOffset.zero);

          leaf.fail = true;
          leaf.markNeedsLayout();
          outer.layout(const CellConstraints(maxCols: 2, maxRows: 1));
          expect(
            () => outer.paint(CellBuffer(size), CellOffset.zero),
            throwsStateError,
          );

          // No new invalidation: failure itself must invalidate the incomplete
          // cache, including all enclosing caches that embed its output.
          final retry = CellBuffer(size);
          outer.paint(retry, CellOffset.zero);
          expect(
            retry.textInRange(CellRect(offset: CellOffset.zero, size: size)),
            'OK',
          );
          expect(leaf.paints, 3);
          outer.paint(CellBuffer(size), CellOffset.zero);
          expect(
            leaf.paints,
            3,
            reason: 'successful retry becomes cacheable again',
          );
        },
      );
    }
  }

  test('root backstop recovers a cache on an unrelated sibling repaint', () {
    final leaf = _TransientPaint()..partialWrite = true;
    final sibling = _TransientPaint();
    final runtime = TuiRuntime();
    final presenter = _Presenter();
    final errors = <Object>[];
    final driver = FrameDriver(
      runtime: runtime,
      frameLoop: TuiFrameLoop(renderDamage: runtime.renderDamageTracker),
      readViewport: () => const FrameViewportSnapshot(CellSize(24, 4)),
      presenter: presenter,
      onBackstopError: (error, stack) => errors.add(error),
    );
    addTearDown(driver.dispose);
    driver.mountRoot(
      () => Column(
        children: [
          RepaintBoundary(child: RepaintBoundary(child: _PaintWidget(leaf))),
          _PaintWidget(sibling),
        ],
      ),
    );
    driver.renderNow('initial');
    leaf.fail = true;
    leaf.markNeedsLayout();
    driver.renderNow('failure');
    expect(errors, hasLength(1));
    expect(presenter.frames.last, contains('transient'));
    expect(driver.renderUnrecoverable, isFalse);

    // Do not rebuild or re-invalidate the failed subtree as part of recovery.
    sibling.markNeedsLayout();
    driver.renderNow('sibling');
    expect(presenter.frames.last.split('\n').first.trim(), 'OK');
    expect(leaf.paints, 3);
    expect(errors, hasLength(1));
  });
}
