@TestOn('browser')
library;

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
