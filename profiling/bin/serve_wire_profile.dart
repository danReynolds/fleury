// Profiles the serve wire: the real V3 PLAN encoding vs the ANSI bytes a
// peer (ttyd/gotty/textual-web → xterm) would send for the same frame
// sequence. ANSI is the competitive baseline — peers relay it and it
// works over WAN. Both are then measured under whole-stream deflate
// (permessage-deflate with context takeover, the realistic socket).
//
// Run: dart run bin/serve_wire_profile.dart

import 'dart:io';

import 'package:fleury/fleury.dart';

class _CountingSink implements AnsiSink {
  final List<int> raw = [];
  @override
  void write(String data) => raw.addAll(data.codeUnits);
  @override
  Future<void> flush() async {}
}

List<int> _ansiFrame(CellBuffer prev, CellBuffer next) {
  final sink = _CountingSink();
  AnsiRenderer(colorMode: ColorMode.truecolor)
      .renderDiff(prev, next, sink, dirtyBounds: null);
  return sink.raw;
}

List<int> _planFrame(CellBuffer prev, CellBuffer next, {bool full = false}) =>
    encodeRemotePlan(buildRemotePlan(prev, next, fullRepaint: full));

typedef Scenario = ({String name, int cols, int rows, List<void Function(CellBuffer)> frames});

void main() {
  final scenarios = <Scenario>[
    _counter(), _typing(), _logStream(), _dashboard(), _fullPaint(),
    _bigChurn(),
  ];
  final z = ZLibCodec(raw: true, level: 6);
  print('ANSI = bytes a peer (ttyd/gotty/textual-web) relays to xterm.');
  print('PLAN = fleury V3 cell-patch encoding. z = whole-stream deflate.');
  print('');
  print('${'scenario'.padRight(20)} ANSIraw PLANraw rawx |  ANSIz  PLANz   zx');
  print('-' * 70);
  var tAz = 0, tPz = 0;
  for (final s in scenarios) {
    var prev = CellBuffer(CellSize(s.cols, s.rows));
    final ansiStream = <int>[], planStream = <int>[];
    for (var i = 0; i < s.frames.length; i++) {
      final next = CellBuffer(CellSize(s.cols, s.rows));
      _copy(prev, next);
      s.frames[i](next);
      final full = i == 0;
      ansiStream.addAll(
          _ansiFrame(full ? CellBuffer(CellSize(s.cols, s.rows)) : prev, next));
      planStream.addAll(_planFrame(prev, next, full: full));
      prev = next;
    }
    final az = z.encode(ansiStream).length;
    final pz = z.encode(planStream).length;
    tAz += az; tPz += pz;
    print('${s.name.padRight(20)} '
        '${ansiStream.length.toString().padLeft(7)} '
        '${planStream.length.toString().padLeft(7)} '
        '${(planStream.length / ansiStream.length).toStringAsFixed(0).padLeft(3)}x | '
        '${az.toString().padLeft(6)} ${pz.toString().padLeft(6)} '
        '${(pz / az).toStringAsFixed(2).padLeft(5)}x');
  }
  print('-' * 70);
  print('${'TOTAL (deflated)'.padRight(20)} ${''.padLeft(15)} | '
      '${tAz.toString().padLeft(6)} ${tPz.toString().padLeft(6)} '
      '${(tPz / tAz).toStringAsFixed(2).padLeft(5)}x');
  print('');
  print('zx <= 1.0 means fleury beats the peer wire after compression.');
}

void _copy(CellBuffer from, CellBuffer to) {
  for (var r = 0; r < from.size.rows; r++) {
    for (var c = 0; c < from.size.cols; c++) {
      final cell = from.atColRow(c, r);
      if (cell.role == CellRole.leading && cell.grapheme != null) {
        to.writeText(CellOffset(c, r), cell.grapheme!, style: cell.style);
      }
    }
  }
}

Scenario _counter() => (name: 'counter (1 field)', cols: 40, rows: 12, frames: [
      for (var i = 0; i < 100; i++)
        (b) => b.writeText(const CellOffset(2, 2), 'Count: ${i % 10}'),
    ]);
Scenario _typing() => (name: 'typing (1 row)', cols: 80, rows: 24, frames: [
      for (var i = 0; i < 100; i++)
        (b) => b.writeText(const CellOffset(0, 10), 'x' * (i % 70 + 1)),
    ]);
Scenario _logStream() => (name: 'log tail (scroll)', cols: 100, rows: 30, frames: [
      for (var i = 0; i < 100; i++)
        (b) {
          // Realistic varied lines so each scrolls (distinct content per
          // line), not near-identical lines where cell-diff already wins.
          for (var r = 0; r < 30; r++) {
            final n = i + r;
            const words = ['connect', 'GET /api/v2/users', 'cache miss',
              'retry backoff', 'flush wal', 'commit txn', 'timeout',
              'parse json', 'spawn worker', 'gc pause', 'queue drain'];
            b.writeText(CellOffset(0, r),
                '${n.toString().padLeft(6)} ${(n * 31) % 99999} '
                '${words[(n * 7) % words.length]} shard=${n % 64} '
                'lat=${(n * 13) % 900}ms');
          }
        },
    ]);
Scenario _dashboard() => (name: 'dashboard (10 rows)', cols: 80, rows: 24, frames: [
      for (var i = 0; i < 100; i++)
        (b) {
          for (var r = 0; r < 10; r++) {
            b.writeText(CellOffset(0, r * 2),
                'metric $r: ${(i * 7 + r) % 100}% ${'=' * ((i + r) % 40)}');
          }
        },
    ]);
Scenario _fullPaint() => (name: 'full paint (first)', cols: 80, rows: 24, frames: [
      (b) {
        for (var r = 0; r < 24; r++) {
          b.writeText(CellOffset(0, r), 'row $r ${'content ' * 8}');
        }
      },
    ]);
// Worst case for *both* wires: a large grid where every cell changes every
// frame (200x60 = 12k cells, ~36 KiB raw/frame — past DEFLATE's 32 KiB window).
// Neither cell-diffing (fleury) nor ANSI relay (peers) can exploit cross-frame
// redundancy here, so this is the apples-to-apples test that the "competitive
// with ANSI" claim still holds when context takeover stops helping anyone.
Scenario _bigChurn() => (name: 'big churn 200x60', cols: 200, rows: 60, frames: [
      for (var i = 0; i < 60; i++)
        (b) {
          const glyphs = 'abcdefghijklmnopqrstuvwxyz0123456789 .,#@/\\|-+';
          for (var r = 0; r < 60; r++) {
            final sb = StringBuffer();
            for (var c = 0; c < 200; c++) {
              sb.writeCharCode(
                  glyphs.codeUnitAt((i * 7 + r * 13 + c * 3) % glyphs.length));
            }
            b.writeText(CellOffset(0, r), sb.toString());
          }
        },
    ]);
