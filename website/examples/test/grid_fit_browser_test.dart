@TestOn('browser')
library;

import 'package:fleury/fleury_core.dart';
import 'package:fleury_doc_examples/grid_fit.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

final class _FakeFlush {
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
    _pending = null;
    flush?.call();
  }
}

/// A line height that the web host rounds up to the device-pixel grid. The
/// host measures its cell with a block probe, so the cell height is the line
/// height: the docs' 14px at 1.25 is 17.5px, which becomes 18px at
/// devicePixelRatio 1.
double _roundingUpLineHeight() {
  final dpr = web.window.devicePixelRatio;
  return ((17.5 * dpr).floorToDouble() + 0.5) / dpr;
}

/// Mounts an empty app into a host that declares [cols] × [rows] and starts at
/// that many natural cells, as FleuryExample sizes it. Returns the grid shown.
Future<({int cols, int rows})> _grid(
  double lineHeight,
  int cols,
  int rows, {
  required bool fitted,
}) async {
  final host = web.document.createElement('div')
    ..setAttribute('data-cols', '$cols')
    ..setAttribute('data-rows', '$rows')
    ..setAttribute(
      'style',
      'position:absolute;left:0;top:0;font-family:monospace;'
          'font-size:14px;line-height:${lineHeight}px;'
          'width:${cols}ch;height:${rows * lineHeight}px;',
    );
  web.document.body!.append(host);
  if (fitted) fitToGrid(host);
  final flush = _FakeFlush();
  final app = await mountApp(
    () => const SizedBox.shrink(),
    into: host,
    flushScheduler: flush.schedule,
  );
  for (var i = 0; i < 4 && flush.pending; i++) {
    flush.fire();
  }
  final lines = host.querySelectorAll('.fleury-row');
  final grid = (
    cols: lines.length == 0 ? 0 : lines.item(0)!.textContent!.length,
    rows: lines.length,
  );
  await app.dispose();
  host.remove();
  return grid;
}

void main() {
  test('a docs host fitted to its grid shows every declared row', () async {
    final lineHeight = _roundingUpLineHeight();
    // The bug this guards: sized at the natural cell, the last row is lost.
    final unfitted = await _grid(lineHeight, 24, 5, fitted: false);
    expect(unfitted.rows, lessThan(5));

    expect(await _grid(lineHeight, 24, 5, fitted: true), (cols: 24, rows: 5));
    expect(await _grid(lineHeight, 60, 30, fitted: true), (cols: 60, rows: 30));
  });

  test('a host without a declared grid keeps its own size', () {
    final host = web.document.createElement('div')
      ..setAttribute('style', 'width:123px;height:45px;');
    web.document.body!.append(host);
    fitToGrid(host);
    expect((host as web.HTMLElement).style.width, '123px');
    expect(host.style.height, '45px');
    host.remove();
  });
}
