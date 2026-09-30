// Sizes docs example hosts to the exact grid they declare.
//
// A docs host promises `data-cols` × `data-rows` cells. Its CSS sizes it in ch
// and em units, the font's natural cell. The web host renders at that cell
// snapped to device pixels (DomCellMetrics), so wherever snapping rounds up
// the natural size no longer fits: at devicePixelRatio 1 a 17.5px row renders
// at 18px, and a five-row host shows four. Sizing the host from the snapped
// cell gives it exactly the declared grid at every ratio.
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

final _fitted = <web.HTMLElement>{};
var _watching = false;

/// Sizes [host] to its `data-cols` × `data-rows` grid, and again whenever
/// fonts finish loading or the device-pixel ratio changes. A host without
/// both attributes keeps its own size.
void fitToGrid(web.Element host) {
  if (host is! web.HTMLElement || _gridOf(host) == null) return;
  _fitted.add(host);
  _watch();
  _fit(host);
}

(int, int)? _gridOf(web.HTMLElement host) {
  final cols = int.tryParse(host.getAttribute('data-cols') ?? '');
  final rows = int.tryParse(host.getAttribute('data-rows') ?? '');
  return cols == null || rows == null || cols <= 0 || rows <= 0
      ? null
      : (cols, rows);
}

void _fit(web.HTMLElement host) {
  final grid = _gridOf(host);
  if (grid == null) return;
  final (cols, rows) = grid;
  // Measure as DomCellMetrics does: a probe in the host's font, whose box is
  // the natural cell, snapped onto the device-pixel grid.
  final style = web.window.getComputedStyle(host);
  final probe = web.document.createElement('span')
    ..textContent = 'MMMMMMMMMM'
    ..setAttribute(
      'style',
      'position:absolute;visibility:hidden;pointer-events:none;'
          'white-space:pre;left:-10000px;top:-10000px;'
          'font-family:${style.getPropertyValue('font-family')};'
          'font-size:${style.getPropertyValue('font-size')};'
          'font-weight:${style.getPropertyValue('font-weight')};'
          'font-style:${style.getPropertyValue('font-style')};'
          'line-height:${style.getPropertyValue('line-height')};',
    );
  web.document.body!.append(probe);
  final box = probe.getBoundingClientRect();
  probe.remove();
  final dpr = web.window.devicePixelRatio;
  double snap(double px) =>
      math.max(dpr > 0 ? (px * dpr).roundToDouble() / dpr : px, 1);
  // Half a pixel keeps floating-point division from dropping the last cell.
  host.style
    ..width = '${cols * snap(box.width / 10) + 0.5}px'
    ..height = '${rows * snap(box.height) + 0.5}px';
}

void _refitAll() {
  _fitted.removeWhere((host) => !host.isConnected);
  _fitted.forEach(_fit);
}

void _watch() {
  if (_watching) return;
  _watching = true;
  web.document.fonts.addEventListener(
    'loadingdone',
    ((web.Event _) => _refitAll()).toJS,
  );
  _watchResolution();
}

// Zooming, or moving the window to another display, changes the ratio.
void _watchResolution() {
  web.window
      .matchMedia('(resolution: ${web.window.devicePixelRatio}dppx)')
      .addEventListener(
        'change',
        ((web.Event _) {
          _refitAll();
          _watchResolution();
        }).toJS,
        web.AddEventListenerOptions(once: true),
      );
}
