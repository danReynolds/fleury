@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:math' as math;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/metrics/dom_cell_metrics.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test(
    'DomCellMetrics measures a browser container and maps points to cells',
    () {
      final container = web.document.createElement('div');
      container.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:160px;height:48px;'
            'font-family:monospace;font-size:16px;line-height:16px;',
      );
      web.document.body!.appendChild(container);
      final metrics = DomCellMetrics(container: container);
      addTearDown(() {
        metrics.dispose();
        container.parentNode?.removeChild(container);
      });

      final box = metrics.measure();

      expect(box.cssCanvasWidth, closeTo(160, 0.5));
      expect(box.cssCanvasHeight, closeTo(48, 0.5));
      expect(box.cssCellWidth, greaterThan(0));
      expect(box.cssCellHeight, greaterThan(0));
      expect(box.cols, greaterThan(0));
      expect(box.rows, greaterThan(0));
      expect(box.size, CellSize(box.cols, box.rows));

      final point = metrics.cellForPoint(
        box.cssCellWidth * 1.25,
        box.cssCellHeight * 1.25,
      );
      expect(point.col, math.min(1, box.cols - 1));
      expect(point.row, math.min(1, box.rows - 1));
      expect(metrics.cellForPoint(-100, -100), CellOffset.zero);
      expect(
        metrics.cellForPoint(100000, 100000),
        CellOffset(box.cols - 1, box.rows - 1),
      );
    },
  );

  test('DomCellMetrics maps the content box inside host padding', () {
    // The serve/host surface renders into the host's *content* box, which a
    // padding inset pushes in from the element's outer rect. Measuring the
    // border box would offset every pointer hit-test by the padding (a
    // constant, full-pixel error) and over-report cols/rows that overflow the
    // visible area — clicks would land on the row/cell below the target.
    final container = web.document.createElement('div');
    container.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:200px;height:80px;'
          'box-sizing:border-box;padding:8px;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );
    web.document.body!.appendChild(container);
    final metrics = DomCellMetrics(container: container);
    addTearDown(() {
      metrics.dispose();
      container.parentNode?.removeChild(container);
    });

    final box = metrics.measure();

    // Origin and size are the content box: outer 200x80 minus 8px padding
    // on each edge → a 16px-narrower/shorter canvas offset by (8, 8).
    expect(box.cssCanvasLeft, closeTo(8, 0.5));
    expect(box.cssCanvasTop, closeTo(8, 0.5));
    expect(box.cssCanvasWidth, closeTo(184, 0.5));
    expect(box.cssCanvasHeight, closeTo(64, 0.5));

    // The grid is letter-spaced so text flows at the device-pixel-snapped cell
    // pitch (see DomGridSurface._rootStyle), so hit-testing maps against that
    // snapped pitch — a pointer in the centre of the last cell resolves there.
    expect(box.cssCellWidth, greaterThan(0));
    expect(box.cssCellHeight, greaterThan(0));
    expect(box.layoutCellWidth, greaterThan(0));
    expect(box.layoutCellHeight, greaterThan(0));
    final lastCol = box.cols - 1;
    final lastRow = box.rows - 1;
    expect(
      metrics.cellForPoint(
        box.cssCellWidth * lastCol + box.cssCellWidth * 0.5,
        box.cssCellHeight * lastRow + box.cssCellHeight * 0.5,
      ),
      CellOffset(lastCol, lastRow),
    );
  });

  test('DomCellMetrics maps viewport points after host movement', () {
    final container = web.document.createElement('div');
    container.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:160px;height:64px;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );
    web.document.body!.appendChild(container);
    final metrics = DomCellMetrics(container: container);
    addTearDown(() {
      metrics.dispose();
      container.parentNode?.removeChild(container);
    });

    final box = metrics.measure();
    container.setAttribute(
      'style',
      'position:absolute;left:40px;top:80px;width:160px;height:64px;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );
    final rect = container.getBoundingClientRect();

    expect(
      metrics.cellForViewportPoint(
        rect.left + box.cssCellWidth * 1.5,
        rect.top + box.cssCellHeight * 1.5,
      ),
      const CellOffset(1, 1),
    );
    expect(metrics.cachedMeasurement, same(box));
    expect(metrics.isDirty, isFalse);
  });

  test('DomCellMetrics maps viewport points through padding and border', () {
    final container = web.document.createElement('div');
    container.setAttribute(
      'style',
      'position:absolute;left:30px;top:50px;width:220px;height:96px;'
          'box-sizing:border-box;padding:6px;border:2px solid black;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );
    web.document.body!.appendChild(container);
    final metrics = DomCellMetrics(container: container);
    addTearDown(() {
      metrics.dispose();
      container.parentNode?.removeChild(container);
    });

    final box = metrics.measure();
    final rect = container.getBoundingClientRect();

    expect(
      metrics.cellForViewportPoint(
        rect.left + 8 + box.cssCellWidth * 2.5,
        rect.top + 8 + box.cssCellHeight * 1.5,
      ),
      const CellOffset(2, 1),
    );
  });

  test('DomCellMetrics maps viewport points after page scroll', () {
    final body = web.document.body!;
    final previousBodyStyle = body.getAttribute('style');
    web.window.scrollTo(0.toJS, 0);
    body.setAttribute('style', '${previousBodyStyle ?? ''};min-height:2400px;');
    final container = web.document.createElement('div');
    container.setAttribute(
      'style',
      'position:absolute;left:20px;top:1200px;width:160px;height:64px;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );
    web.document.body!.appendChild(container);
    final metrics = DomCellMetrics(container: container);
    addTearDown(() {
      metrics.dispose();
      container.parentNode?.removeChild(container);
      if (previousBodyStyle == null) {
        body.removeAttribute('style');
      } else {
        body.setAttribute('style', previousBodyStyle);
      }
      web.window.scrollTo(0.toJS, 0);
    });

    final box = metrics.measure();
    web.window.scrollTo(0.toJS, 900);
    final rect = container.getBoundingClientRect();

    expect(
      metrics.cellForViewportPoint(
        rect.left + box.cssCellWidth * 1.5,
        rect.top + box.cssCellHeight * 1.5,
      ),
      const CellOffset(1, 1),
    );
    expect(metrics.cachedMeasurement, same(box));
  });

  test('DomCellMetrics caches until explicitly marked dirty', () {
    final container = web.document.createElement('div');
    container.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:120px;height:40px;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );
    web.document.body!.appendChild(container);
    final metrics = DomCellMetrics(container: container);
    addTearDown(() {
      metrics.dispose();
      container.parentNode?.removeChild(container);
    });

    final before = metrics.measure();
    container.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:220px;height:40px;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );

    expect(metrics.measure(), same(before));

    metrics.markDirty();
    final after = metrics.measure();

    expect(after, isNot(same(before)));
    expect(after.cssCanvasWidth, closeTo(220, 0.5));
  });

  test(
    'DomCellMetrics maps points from cached measurement without reading',
    () {
      final container = web.document.createElement('div');
      container.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:120px;height:40px;'
            'font-family:monospace;font-size:16px;line-height:16px;',
      );
      web.document.body!.appendChild(container);
      final metrics = DomCellMetrics(container: container);
      addTearDown(() {
        metrics.dispose();
        container.parentNode?.removeChild(container);
      });

      final before = metrics.measure();
      container.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:240px;height:40px;'
            'font-family:monospace;font-size:16px;line-height:16px;',
      );
      metrics.markDirty();

      final point = metrics.cellForPoint(
        before.cssCellWidth * (before.cols + 10),
        before.cssCellHeight * (before.rows + 10),
      );

      expect(point, CellOffset(before.cols - 1, before.rows - 1));
      expect(metrics.isDirty, isTrue);
      expect(metrics.cachedMeasurement, same(before));
    },
  );

  test('DomCellMetrics invalidates on browser metrics signals', () {
    final container = web.document.createElement('div');
    container.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:120px;height:40px;'
          'font-family:monospace;font-size:16px;line-height:16px;',
    );
    web.document.body!.appendChild(container);
    final metrics = DomCellMetrics(container: container);
    addTearDown(() {
      metrics.dispose();
      container.parentNode?.removeChild(container);
    });

    final before = metrics.measure();
    var dirtyCount = 0;
    metrics.startObserving(() {
      dirtyCount += 1;
    });

    final beforeEventCount = dirtyCount;
    expect(metrics.cachedMeasurement, same(before));
    expect(metrics.isDirty, isFalse);

    web.document.fonts.dispatchEvent(web.Event('loadingdone'));

    expect(dirtyCount, beforeEventCount + 1);
    expect(metrics.isDirty, isTrue);
    expect(metrics.cachedMeasurement, same(before));

    metrics.measure();
    expect(metrics.isDirty, isFalse);

    final beforeResizeEventCount = dirtyCount;
    web.window.dispatchEvent(web.Event('resize'));

    expect(dirtyCount, beforeResizeEventCount + 1);
    expect(metrics.isDirty, isTrue);

    metrics.measure();
    expect(metrics.isDirty, isFalse);
    metrics.dispose();

    final beforeDisposedEventCount = dirtyCount;
    web.document.fonts.dispatchEvent(web.Event('loadingdone'));
    web.window.dispatchEvent(web.Event('resize'));
    expect(dirtyCount, beforeDisposedEventCount);
  });
}
