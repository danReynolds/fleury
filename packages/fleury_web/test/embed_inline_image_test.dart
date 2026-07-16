// The embed pixel path: a widget places a neutral inline image; the host
// feeds the frame buffer's placements straight into the shared
// InlineImageOverlay — the same layer the serve client drives from the
// wire plan. This is the anti-drift oracle for images: embed and serve
// render placements through one component.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/dom_grid/inline_image_overlay.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:fleury_web/src/run_tui_surface.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

class _FakeFlush {
  void Function()? _pending;

  bool get pending => _pending != null;

  void Function() schedule(Duration delay, void Function() flush) {
    _pending = flush;
    return () {
      if (identical(_pending, flush)) _pending = null;
    };
  }

  void fire() {
    final flush = _pending;
    if (flush == null) throw StateError('No pending frame flush.');
    _pending = null;
    flush();
  }
}

class _FakeMetrics implements CellMetrics {
  _FakeMetrics(this.box);

  MeasuredCellBox box;

  @override
  MeasuredCellBox measure() => box;

  @override
  MeasuredCellBox? get cachedMeasurement => box;

  @override
  void startObserving(void Function() onMetricsDirty) {}

  @override
  void markDirty() {}

  @override
  CellOffset cellForPoint(double x, double y) => CellOffset.zero;

  @override
  CellOffset? cellForViewportPoint(double clientX, double clientY) =>
      CellOffset.zero;

  @override
  void dispose() {}
}

MeasuredCellBox _box({required int cols, required int rows}) => MeasuredCellBox(
  cssCellWidth: 10,
  cssCellHeight: 20,
  cssCanvasWidth: cols * 10.0,
  cssCanvasHeight: rows * 20.0,
  devicePixelRatio: 1,
  cols: cols,
  rows: rows,
);

/// Places [bytes] as an inline image over its whole box, or paints 'G'
/// when the surface reports no placement support — a minimal stand-in
/// for the Image widget's dispatch (fleury_web cannot depend on
/// fleury_widgets).
class _ProbeImage extends LeafRenderObjectWidget {
  const _ProbeImage(this.bytes);

  final Uint8List bytes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProbeImage(bytes, MediaQuery.imagesOf(context));
}

class _RenderProbeImage extends RenderObject {
  _RenderProbeImage(this.bytes, this.images);

  final Uint8List bytes;
  final InlineImageSupport images;

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(4, 2));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (images == InlineImageSupport.placements) {
      buffer.writeImage(offset, bytes, width: 4, height: 2);
    } else {
      buffer.writeText(offset, 'GGGG');
    }
  }
}

void main() {
  test('embed frames feed buffer placements into the <img> overlay', () async {
    final hostElement = web.document.createElement('div') as web.HTMLElement;
    final gridRoot = web.document.createElement('div');
    hostElement.appendChild(gridRoot);
    final surface = DomGridSurface(root: gridRoot, size: CellSize.zero);
    final overlay = InlineImageOverlay(hostElement);
    final metrics = _FakeMetrics(_box(cols: 10, rows: 4));
    final flush = _FakeFlush();
    final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i));

    final host = await runTuiSurface(
      () => _ProbeImage(bytes),
      surface: surface,
      cellMetrics: metrics,
      imageOverlay: overlay,
      flushScheduler: flush.schedule,
      // The real assembly disposes the overlay via removeGeneratedRoots;
      // mirror that wiring here.
      disposeHostResources: overlay.dispose,
    );
    flush.fire();
    await host.awaitSemanticIdle();

    expect(
      overlay.imageElementCount,
      1,
      reason: 'the frame placement reconciled into one <img>',
    );
    final img = hostElement.querySelector('img')! as web.HTMLImageElement;
    expect(img.style.getPropertyValue('width'), '40px');
    expect(img.style.getPropertyValue('height'), '40px');
    expect(img.style.getPropertyValue('object-fit'), 'contain');
    expect(img.src, startsWith('blob:'));
    expect(
      gridRoot.textContent!.trim(),
      isEmpty,
      reason: 'the grid under the overlay is blank cells, not glyph art',
    );

    await host.dispose();
    expect(
      overlay.imageElementCount,
      0,
      reason: 'disposing the host tears the overlay down',
    );
  });

  test('a host without an overlay keeps the glyph-art path', () async {
    final gridRoot = web.document.createElement('div');
    final surface = DomGridSurface(root: gridRoot, size: CellSize.zero);
    final metrics = _FakeMetrics(_box(cols: 10, rows: 4));
    final flush = _FakeFlush();

    final host = await runTuiSurface(
      () => _ProbeImage(Uint8List.fromList([1, 2, 3])),
      surface: surface,
      cellMetrics: metrics,
      flushScheduler: flush.schedule,
    );
    flush.fire();
    await host.awaitSemanticIdle();

    expect(
      gridRoot.textContent,
      contains('GGGG'),
      reason: 'MediaQuery reports images: none → widgets paint glyphs',
    );

    await host.dispose();
  });
}
