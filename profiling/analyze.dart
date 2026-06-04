// Analysis layer of the TUI profiling harness.
//
// Turns one or more PTY captures (from capture_pty.py) into comparable TUI
// axes, using the SAME AnsiByteBreakdown every framework is measured with — so
// the cross-language comparison is apples-to-apples on the output artifact
// (bytes on the wire), not on internal CPU timing (which is meaningless across
// languages). When given multiple labelled captures of the SAME scenario, it
// bands each against the best on each axis: leading / competitive / ballpark /
// way-off.
//
// Usage:
//   dart run analyze.dart <label>=<captureBasename> [<label>=<basename> ...]
//   (basename refers to <basename>.bin + <basename>.json from capture_pty.py)

import 'dart:convert';
import 'dart:io';

// Import the categorizer directly (not via fleury_test.dart, which pulls in the
// package:test-dependent harness this non-test tool doesn't need).
import 'package:fleury/src/rendering/ansi_byte_budget.dart' show AnsiByteBreakdown;

class _Axes {
  _Axes(this.label, this.bytes, this.frames, this.ttfbMs, this.durationMs);
  final String label;
  final AnsiByteBreakdown bytes;
  final int frames;
  final double? ttfbMs;
  final double? durationMs;

  double get bytesPerFrame => frames == 0 ? bytes.total.toDouble() : bytes.total / frames;
}

_Axes _load(String label, String base) {
  final raw = File('$base.bin').readAsBytesSync();
  final text = utf8.decode(raw, allowMalformed: true);
  final breakdown = AnsiByteBreakdown.analyze(text);

  // Frame count: number of synchronized-output frames (BSU markers). Falls back
  // to the number of distinct PTY read bursts when sync output isn't used.
  final bsu = '\x1B[?2026h'.allMatches(text).length;
  final meta = File('$base.json').existsSync()
      ? jsonDecode(File('$base.json').readAsStringSync()) as Map<String, dynamic>
      : const <String, dynamic>{};
  final reads = (meta['reads'] as List?)?.length ?? 0;
  final frames = bsu > 0 ? bsu : reads;

  return _Axes(
    label,
    breakdown,
    frames,
    (meta['ttfbMs'] as num?)?.toDouble(),
    (meta['durationMs'] as num?)?.toDouble(),
  );
}

// All axes are lower-is-better. Band each value vs the best (min) on that axis.
String _band(num value, num best) {
  if (best <= 0) return '—';
  final r = value / best;
  if (r <= 1.15) return 'leading';
  if (r <= 1.5) return 'competitive';
  if (r <= 3.0) return 'ballpark';
  return 'WAY OFF';
}

void _row(String name, List<_Axes> all, num Function(_Axes) pick, String fmt(num v)) {
  final vals = all.map(pick).toList();
  final best = vals.reduce((a, b) => a < b ? a : b);
  stdout.writeln('  $name');
  for (var i = 0; i < all.length; i++) {
    final v = vals[i];
    final band = all.length > 1 ? '  [${_band(v, best)}]' : '';
    stdout.writeln('    ${all[i].label.padRight(14)} ${fmt(v).padLeft(12)}$band');
  }
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run analyze.dart <label>=<captureBasename> ...');
    exit(64);
  }
  final all = <_Axes>[];
  for (final arg in args) {
    final i = arg.indexOf('=');
    if (i < 0) {
      stderr.writeln('bad arg "$arg" (expected label=basename)');
      exit(64);
    }
    all.add(_load(arg.substring(0, i), arg.substring(i + 1)));
  }

  stdout.writeln('TUI profiling — output-artifact axes (lower is better)\n');
  _row('bytes on the wire (total)', all, (a) => a.bytes.total, (v) => '$v B');
  _row('bytes / frame', all, (a) => a.bytesPerFrame, (v) => v.toStringAsFixed(0));
  _row('frames emitted', all, (a) => a.frames, (v) => '$v');
  _row('control overhead %', all, (a) => (a.bytes.overheadFraction * 100),
      (v) => '${v.toStringAsFixed(0)}%');
  if (all.every((a) => a.ttfbMs != null)) {
    _row('time-to-first-byte', all, (a) => a.ttfbMs!, (v) => '${v.toStringAsFixed(1)} ms');
  }

  stdout.writeln('\n  per-capture byte split (content/sgr/cursor/sync/other):');
  for (final a in all) {
    final b = a.bytes;
    stdout.writeln('    ${a.label.padRight(14)} '
        '${b.content}/${b.sgr}/${b.cursor}/${b.sync}/${b.other}');
  }
  if (all.length > 1) {
    stdout.writeln('\n  Bands are vs the best capture on each axis. "leading" '
        '≤1.15x, "competitive" ≤1.5x, "ballpark" ≤3x, else "WAY OFF".');
  }
}
