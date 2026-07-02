@TestOn('browser')
library;

// Serve-path DOM divergence oracle. The transport-parity tests prove the
// client *mirror* (a CellBuffer) reproduces the server frame. This proves the
// next link: that the retained DOM the surface renders from that mirror also
// matches — driving the exact client pipeline (applyRemotePlan → present) over
// the overlay / region-scroll / mixed sequences the "screen clears" blank
// correlates with, reading the DOM rows back, and comparing to the server's
// buffer. A divergence here is the blank, reproduced deterministically.

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:fleury_web/src/remote_client/plan_adapter.dart';
import 'package:fleury_web/src/host/wire_frame_source.dart'
    show viewportSizeForMeasurement;
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

MeasuredCellBox _box(int cols, int rows) => MeasuredCellBox(
  cssCellWidth: 8,
  cssCellHeight: 16,
  cssCanvasWidth: cols * 8,
  cssCanvasHeight: rows * 16,
  devicePixelRatio: 1,
  cols: cols,
  rows: rows,
);

/// A full-repaint presentation plan rebuilt from [mirror] — the client's
/// resync path (rebuild every row from the authoritative mirror).
FramePresentationPlan _fullPlan(CellBuffer mirror) {
  const builder = CellSpanBuilder();
  return FramePresentationPlan(
    reason: 'resync',
    fullRepaint: true,
    size: mirror.size,
    damage: FramePresentationDamage(
      fullRepaint: true,
      requiresFullDiff: true,
      dirtyBounds: null,
      dirtyRows: TuiDirtyRows.full(mirror.size.rows),
      source: FrameDamageSource.fullRepaint,
    ),
    dirtyRowModels: [
      for (var r = 0; r < mirror.size.rows; r++) builder.buildRow(mirror, r),
    ],
    metricsChanged: false,
    dirtyRowDiffTime: Duration.zero,
    spanBuildTime: Duration.zero,
  );
}

List<String> _domRows(DomGridSurface s) => [
  for (final r in s.rowElements) r.textContent ?? '',
];

List<String> _bufRows(CellBuffer b) => [
  for (var r = 0; r < b.size.rows; r++)
    [
      for (var c = 0; c < b.size.cols; c++)
        switch (b.atColRow(c, r)) {
          Cell(role: CellRole.continuation) => '',
          final cell => cell.grapheme ?? ' ',
        },
    ].join(),
];

void _seed(CellBuffer from, CellBuffer to) {
  for (var r = 0; r < from.size.rows; r++) {
    for (var c = 0; c < from.size.cols; c++) {
      final cell = from.atColRow(c, r);
      if (cell.role == CellRole.leading && cell.grapheme != null) {
        to.writeText(CellOffset(c, r), cell.grapheme!, style: cell.style);
      }
    }
  }
}

/// One serve frame end-to-end: server builds the plan, it round-trips the
/// wire, the client applies it to [mirror] and presents the result into the
/// retained DOM [surface].
void _serveFrame(
  CellBuffer prev,
  CellBuffer next,
  CellBuffer mirror,
  DomGridSurface surface, {
  bool full = false,
}) {
  final plan = buildRemotePlan(prev, next, fullRepaint: full);
  final decoded = decodeRemotePlan(encodeRemotePlan(plan));
  final clientPlan = applyRemotePlan(decoded, mirror);
  surface.present(mirror, mirror, clientPlan);
}

CellBuffer _background(CellSize size, int phase) {
  final b = CellBuffer(size);
  for (var r = 0; r < size.rows; r++) {
    b.writeText(CellOffset(0, r), '| left ${(r + phase) % 40} ');
    b.writeText(CellOffset(size.cols ~/ 2, r), '| preview row $r ok |');
  }
  return b;
}

CellBuffer _withOverlay(
  CellBuffer base, {
  required int boxW,
  required int boxH,
}) {
  final out = CellBuffer(base.size);
  _seed(base, out);
  final left = (base.size.cols - boxW) ~/ 2;
  final top = (base.size.rows - boxH) ~/ 2;
  for (var r = 0; r < boxH; r++) {
    final row = top + r;
    if (row < 0 || row >= base.size.rows) continue;
    final isEdge = r == 0 || r == boxH - 1;
    final line = isEdge
        ? '+${'-' * (boxW - 2)}+'
        : '|${' cmd $r'.padRight(boxW - 2).substring(0, boxW - 2)}|';
    out.writeText(CellOffset(left, row), line);
  }
  return out;
}

void main() {
  const size = CellSize(80, 24);

  group('serve DOM parity', () {
    test('overlay open then close renders identically to the server', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);
      final mirror = CellBuffer(size);

      final bg = _background(size, 0);
      _serveFrame(CellBuffer(size), bg, mirror, surface, full: true);
      expect(_domRows(surface), _bufRows(bg), reason: 'initial');

      final open = _withOverlay(bg, boxW: 30, boxH: 8);
      _serveFrame(bg, open, mirror, surface);
      expect(_domRows(surface), _bufRows(open), reason: 'overlay open');

      _serveFrame(open, bg, mirror, surface);
      expect(_domRows(surface), _bufRows(bg), reason: 'overlay closed');
    });

    test('a region scroll renders identically to the server', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);
      final mirror = CellBuffer(size);
      var prev = _background(size, 0);
      _serveFrame(CellBuffer(size), prev, mirror, surface, full: true);
      for (var i = 1; i < 30; i++) {
        final next = _background(size, i);
        _serveFrame(prev, next, mirror, surface);
        expect(_domRows(surface), _bufRows(next), reason: 'region scroll $i');
        prev = next;
      }
    });

    test('full-screen scroll renders identically to the server', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);
      final mirror = CellBuffer(size);
      // Whole-screen content so the scroll detector fires (every row shifts).
      CellBuffer screen(int top) {
        final b = CellBuffer(size);
        for (var r = 0; r < size.rows; r++) {
          b.writeText(
            CellOffset(0, r),
            'log line ${top + r} payload=${(top + r) * 7}',
          );
        }
        return b;
      }

      var prev = screen(0);
      _serveFrame(CellBuffer(size), prev, mirror, surface, full: true);
      for (var i = 1; i < 40; i++) {
        final next = screen(i);
        _serveFrame(prev, next, mirror, surface);
        expect(_domRows(surface), _bufRows(next), reason: 'scroll $i');
        prev = next;
      }
    });

    test('degenerate viewport measurements are rejected, not collapsed', () {
      // The blank's root cause: a transient bad measurement (mid-reflow, font
      // not ready, collapsed host) clamping to a 1-row grid. The guard rejects
      // anything below 2x2 so the session keeps its last good size.
      expect(viewportSizeForMeasurement(_box(0, 0)), isNull, reason: 'empty');
      expect(viewportSizeForMeasurement(_box(80, 1)), isNull, reason: '1 row');
      expect(viewportSizeForMeasurement(_box(1, 24)), isNull, reason: '1 col');
      expect(viewportSizeForMeasurement(_box(80, 24)), const CellSize(80, 24));
      // Sane reads pass through; absurd ones still clamp to the upper bound.
      expect(
        viewportSizeForMeasurement(_box(5000, 24)),
        const CellSize(1000, 24),
      );
    });

    test('a full repaint from the mirror restores a blanked grid', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);
      final mirror = CellBuffer(size);
      final content = _background(size, 0);
      _serveFrame(CellBuffer(size), content, mirror, surface, full: true);
      expect(_domRows(surface), _bufRows(content));

      // Simulate a frame that left the DOM broken (blanked rows).
      for (final r in surface.rowElements) {
        r.textContent = '';
      }
      expect(
        surface.rowElements.every((r) => (r.textContent ?? '').isEmpty),
        isTrue,
      );

      // The resync repaints every row from the (correct) mirror.
      surface.present(mirror, mirror, _fullPlan(mirror));
      expect(
        _domRows(surface),
        _bufRows(content),
        reason: 'restored from mirror',
      );
    });

    test('a mixed scroll + overlay sequence renders identically', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);
      final mirror = CellBuffer(size);
      var prev = _background(size, 0);
      _serveFrame(CellBuffer(size), prev, mirror, surface, full: true);
      var overlay = false;
      for (var i = 1; i < 120; i++) {
        final bg = _background(size, i);
        if (i % 5 == 0) overlay = !overlay;
        final next = overlay ? _withOverlay(bg, boxW: 28, boxH: 7) : bg;
        _serveFrame(prev, next, mirror, surface);
        expect(_domRows(surface), _bufRows(next), reason: 'mixed frame $i');
        prev = next;
      }
    });
  });
}
