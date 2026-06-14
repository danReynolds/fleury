import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import 'cell_metrics.dart';

/// DOM implementation of [CellMetrics].
///
/// This is the only component in the web host that reads layout geometry.
/// ResizeObserver callbacks only mark the cache dirty and ask the host to
/// schedule a frame; measurement happens during the host read phase.
final class DomCellMetrics implements CellMetrics {
  DomCellMetrics({
    required web.Element container,
    web.Document? document,
    web.Window? window,
    double minimumCellWidth = 1,
    double minimumCellHeight = 1,
  }) : _container = container,
       _document = document ?? web.document,
       _window = window ?? web.window,
       _minimumCellWidth = minimumCellWidth,
       _minimumCellHeight = minimumCellHeight {
    _probe = _document.createElement('span');
    _probe.textContent = _probeText;
    _probe.setAttribute(
      'style',
      'position:absolute;visibility:hidden;pointer-events:none;'
          'white-space:pre;left:-10000px;top:-10000px;'
          'contain:layout style;',
    );
    (_document.body ?? _container).appendChild(_probe);
  }

  static const _probeText = 'MMMMMMMMMM';

  final web.Element _container;
  final web.Document _document;
  final web.Window _window;
  final double _minimumCellWidth;
  final double _minimumCellHeight;
  late final web.Element _probe;
  web.ResizeObserver? _resizeObserver;
  void Function()? _onMetricsDirty;
  JSFunction? _fontLoadListener;
  JSFunction? _windowResizeListener;
  MeasuredCellBox? _cached;
  var _dirty = true;
  var _fontObserverGeneration = 0;

  bool get isDirty => _dirty;

  @override
  MeasuredCellBox? get cachedMeasurement => _cached;

  @override
  MeasuredCellBox measure() {
    if (!_dirty) {
      final cached = _cached;
      if (cached != null) return cached;
    }

    final containerRect = _container.getBoundingClientRect();
    _syncProbeFont();
    final probeRect = _probe.getBoundingClientRect();
    // Snap the cell box to whole device pixels. Each grid row is laid out at
    // `cssCellHeight`, so a fractional height — a 13px font at line-height
    // 1.2 measures ~15.6px — never lands on an exact device pixel. The rows
    // drift, and vertical box-drawing glyphs ('│', and rounded corners
    // '╭╰') pick up a 1px gap every few rows: borders look dashed and the
    // corners detach from their edges. Rounding width and height onto the
    // device-pixel grid makes every cell identical so the glyphs tile
    // seamlessly. (The glyphs themselves fill their natural line box, so the
    // line-height stays as-is — tightening it would clip box-drawing.)
    final dpr = _window.devicePixelRatio;
    double snapToDevicePixels(double cssPx) =>
        dpr > 0 ? (cssPx * dpr).roundToDouble() / dpr : cssPx;
    final cssCellWidth = math.max(
      snapToDevicePixels(probeRect.width / _probeText.length),
      _minimumCellWidth,
    );
    final cssCellHeight = math.max(
      snapToDevicePixels(probeRect.height),
      _minimumCellHeight,
    );
    final cssCanvasWidth = math.max(containerRect.width.toDouble(), 0.0);
    final cssCanvasHeight = math.max(containerRect.height.toDouble(), 0.0);
    final cols = cssCellWidth <= 0
        ? 0
        : (cssCanvasWidth / cssCellWidth).floor();
    final rows = cssCellHeight <= 0
        ? 0
        : (cssCanvasHeight / cssCellHeight).floor();

    final result = MeasuredCellBox(
      cssCellWidth: cssCellWidth,
      cssCellHeight: cssCellHeight,
      cssCanvasWidth: cssCanvasWidth,
      cssCanvasHeight: cssCanvasHeight,
      cssCanvasLeft: containerRect.left.toDouble(),
      cssCanvasTop: containerRect.top.toDouble(),
      devicePixelRatio: _window.devicePixelRatio,
      cols: cols,
      rows: rows,
    );
    _cached = result;
    _dirty = false;
    return result;
  }

  @override
  void startObserving(void Function() onMetricsDirty) {
    _resizeObserver?.disconnect();
    _removeFontListeners();
    _removeWindowResizeListener();
    _onMetricsDirty = onMetricsDirty;
    _resizeObserver = web.ResizeObserver(
      ((JSArray<web.ResizeObserverEntry> _, web.ResizeObserver __) {
        _notifyMetricsDirty();
      }).toJS,
    )..observe(_container);
    _observeWindowResize();
    _observeFontReadiness();
  }

  @override
  void markDirty() {
    _dirty = true;
  }

  @override
  CellOffset cellForPoint(double x, double y) {
    final box = _cached;
    if (box == null) return CellOffset.zero;
    if (box.cols <= 0 || box.rows <= 0) return CellOffset.zero;
    final col = _clampCellIndex(x / box.cssCellWidth, box.cols);
    final row = _clampCellIndex(y / box.cssCellHeight, box.rows);
    return CellOffset(col, row);
  }

  @override
  void dispose() {
    _fontObserverGeneration += 1;
    _onMetricsDirty = null;
    _removeFontListeners();
    _removeWindowResizeListener();
    _resizeObserver?.disconnect();
    _resizeObserver = null;
    final parent = _probe.parentNode;
    if (parent != null) parent.removeChild(_probe);
  }

  void _observeFontReadiness() {
    final generation = _fontObserverGeneration + 1;
    _fontObserverGeneration = generation;
    final fonts = _document.fonts;
    final fontLoadListener = ((web.Event _) {
      _notifyMetricsDirty();
    }).toJS;
    _fontLoadListener = fontLoadListener;
    fonts.addEventListener('loadingdone', fontLoadListener);
    fonts.addEventListener('loadingerror', fontLoadListener);
    unawaited(
      fonts.ready.toDart.then<void>((_) {
        if (generation != _fontObserverGeneration) return;
        _notifyMetricsDirty();
      }, onError: (_) {}),
    );
  }

  void _removeFontListeners() {
    final listener = _fontLoadListener;
    if (listener == null) return;
    final fonts = _document.fonts;
    fonts.removeEventListener('loadingdone', listener);
    fonts.removeEventListener('loadingerror', listener);
    _fontLoadListener = null;
  }

  void _observeWindowResize() {
    final listener = ((web.Event _) {
      _notifyMetricsDirty();
    }).toJS;
    _windowResizeListener = listener;
    _window.addEventListener('resize', listener);
  }

  void _removeWindowResizeListener() {
    final listener = _windowResizeListener;
    if (listener == null) return;
    _window.removeEventListener('resize', listener);
    _windowResizeListener = null;
  }

  void _notifyMetricsDirty() {
    final callback = _onMetricsDirty;
    if (callback == null) return;
    markDirty();
    callback();
  }

  void _syncProbeFont() {
    final style = _window.getComputedStyle(_container);
    final css = StringBuffer()
      ..write('position:absolute;visibility:hidden;pointer-events:none;')
      ..write('white-space:pre;left:-10000px;top:-10000px;')
      ..write('contain:layout style;')
      ..write('font-family:${style.getPropertyValue('font-family')};')
      ..write('font-size:${style.getPropertyValue('font-size')};')
      ..write('font-weight:${style.getPropertyValue('font-weight')};')
      ..write('font-style:${style.getPropertyValue('font-style')};')
      ..write('line-height:${style.getPropertyValue('line-height')};');
    _probe.setAttribute('style', css.toString());
  }

  int _clampCellIndex(double value, int extent) =>
      value.floor().clamp(0, extent - 1).toInt();
}
