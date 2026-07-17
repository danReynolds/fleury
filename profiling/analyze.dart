// Analysis layer of the TUI profiling harness.
//
// Turns one or more PTY captures (from capture_pty.dart) into comparable TUI
// axes, using the SAME AnsiByteBreakdown every framework is measured with — so
// the cross-language comparison is apples-to-apples on the output artifact
// (bytes on the wire), not on internal CPU timing (which is meaningless across
// languages). When given multiple labelled captures of the SAME scenario, it
// bands each against the best on each axis: leading / competitive / ballpark /
// way-off.
//
// Usage:
//   dart run analyze.dart <label>=<captureBasename> [<label>=<basename> ...]
//   (basename refers to <basename>.bin + <basename>.json from capture_pty.dart)

import 'dart:convert';
import 'dart:io';

// Import the categorizer directly (not via fleury_test_support.dart, which
// exports harness utilities this non-test tool doesn't need).
import 'package:fleury/src/rendering/ansi_byte_budget.dart'
    show AnsiByteBreakdown;

class _Axes {
  _Axes(
    this.label,
    this.bytes,
    this.frames,
    this.ttfbMs,
    this.durationMs,
    this.maxRssBytes,
    this.cpuMs,
    this.uiMode,
    this.frameSource,
    this.runtimeMarkersMs,
  );

  final String label;
  final AnsiByteBreakdown bytes;
  final int frames;
  final double? ttfbMs;
  final double? durationMs;
  final int? maxRssBytes;
  final double? cpuMs;
  final String? uiMode;
  final String frameSource;
  final Map<String, double> runtimeMarkersMs;

  double get bytesPerFrame =>
      frames == 0 ? bytes.total.toDouble() : bytes.total / frames;
  double? get fps => (durationMs == null || durationMs! <= 0)
      ? null
      : frames * 1000 / durationMs!;
  double? get rssMiB =>
      maxRssBytes == null ? null : maxRssBytes! / (1024 * 1024);
  double? get cpuLoadPercent =>
      (cpuMs == null || durationMs == null || durationMs! <= 0)
          ? null
          : cpuMs! * 100 / durationMs!;
}

_Axes _load(String label, String base) {
  final raw = File('$base.bin').readAsBytesSync();
  final text = utf8.decode(raw, allowMalformed: true);
  final breakdown = AnsiByteBreakdown.analyze(text);

  final meta = File('$base.json').existsSync()
      ? jsonDecode(File('$base.json').readAsStringSync())
          as Map<String, dynamic>
      : const <String, dynamic>{};
  // Frame count: prefer the scenario-declared logical frame count. Fall back to
  // synchronized-output frames (BSU markers), then PTY reads as a proxy.
  final logicalFrames = (meta['logicalFrameCount'] as num?)?.toInt() ?? 0;
  final bsu = '\x1B[?2026h'.allMatches(text).length;
  final reads = (meta['reads'] as List?)?.length ?? 0;
  final frames = logicalFrames > 0 ? logicalFrames : (bsu > 0 ? bsu : reads);
  final frameSource = logicalFrames > 0
      ? 'scenario logical frames'
      : (bsu > 0 ? 'sync markers' : 'pty reads');

  return _Axes(
    label,
    breakdown,
    frames,
    (meta['ttfbMs'] as num?)?.toDouble(),
    (meta['durationMs'] as num?)?.toDouble(),
    (meta['maxRssBytes'] as num?)?.toInt(),
    (meta['cpuMs'] as num?)?.toDouble(),
    meta['uiMode'] as String?,
    frameSource,
    _runtimeMarkersMs(meta['runtimeMarkers']),
  );
}

Map<String, double> _runtimeMarkersMs(Object? value) {
  if (value is! List<Object?>) return const <String, double>{};
  final result = <String, double>{};
  for (final marker in value) {
    if (marker is! Map<String, Object?>) continue;
    final label = marker['label'];
    final offset = marker['captureOffsetMs'];
    if (label is String && offset is num) {
      result[label] = offset.toDouble();
    }
  }
  return result;
}

// Band each value vs the best on that axis.
String _band(num value, num best, {bool higherIsBetter = false}) {
  if (best <= 0 || value <= 0) return '-';
  final r = higherIsBetter ? best / value : value / best;
  if (r <= 1.15) return 'leading';
  if (r <= 1.5) return 'competitive';
  if (r <= 3.0) return 'ballpark';
  return 'WAY OFF';
}

void _row(
  String name,
  List<_Axes> all,
  num? Function(_Axes) pick,
  String Function(num v) fmt, {
  bool higherIsBetter = false,
}) {
  final vals = all.map(pick).toList();
  if (vals.any((v) => v == null)) return;
  final present = vals.cast<num>().toList();
  final best = present.reduce(
    (a, b) => higherIsBetter ? (a > b ? a : b) : (a < b ? a : b),
  );
  stdout.writeln('  $name');
  for (var i = 0; i < all.length; i++) {
    final v = present[i];
    final band = all.length > 1
        ? '  [${_band(v, best, higherIsBetter: higherIsBetter)}]'
        : '';
    stdout
        .writeln('    ${all[i].label.padRight(14)} ${fmt(v).padLeft(12)}$band');
  }
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr
        .writeln('usage: dart run analyze.dart <label>=<captureBasename> ...');
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

  stdout.writeln('TUI profiling — output-artifact axes\n');
  final modes = all.map((a) => a.uiMode).whereType<String>().toSet();
  if (modes.length == 1) {
    stdout.writeln('  ui mode: ${modes.single}\n');
  } else if (modes.length > 1) {
    stdout.writeln(
      '  WARNING: mixed ui modes (${modes.join(', ')}); compare/band within the same mode.\n',
    );
  }
  final frameSources = all.map((a) => a.frameSource).toSet();
  if (frameSources.length == 1) {
    stdout.writeln('  frame source: ${frameSources.single}\n');
  } else {
    stdout.writeln(
      '  WARNING: mixed frame sources (${frameSources.join(', ')}); PTY reads are a proxy, not exact UI frames.\n',
    );
  }
  _row('bytes on the wire (total)', all, (a) => a.bytes.total, (v) => '$v B');
  _row('bytes / frame', all, (a) => a.bytesPerFrame,
      (v) => v.toStringAsFixed(0));
  _row('frames emitted', all, (a) => a.frames, (v) => '$v');
  _row('control overhead %', all, (a) => (a.bytes.overheadFraction * 100),
      (v) => '${v.toStringAsFixed(0)}%');
  _row('time-to-first-byte', all, (a) => a.ttfbMs,
      (v) => '${v.toStringAsFixed(1)} ms');
  _row('RSS max (runtime-confounded)', all, (a) => a.rssMiB,
      (v) => '${v.toStringAsFixed(1)} MiB');
  _row('CPU load during capture', all, (a) => a.cpuLoadPercent,
      (v) => '${v.toStringAsFixed(0)}%');
  _row('sustained frame rate', all, (a) => a.fps,
      (v) => '${v.toStringAsFixed(1)} fps',
      higherIsBetter: true);

  stdout.writeln(
      '\n  per-capture byte split '
      '(content/sgr/cursor/sync/session/other):');
  for (final a in all) {
    final b = a.bytes;
    stdout.writeln('    ${a.label.padRight(14)} '
        '${b.content}/${b.sgr}/${b.cursor}/${b.sync}/${b.session}/${b.other}');
  }
  final markerCaptures =
      all.where((capture) => capture.runtimeMarkersMs.isNotEmpty).toList();
  if (markerCaptures.isNotEmpty) {
    stdout.writeln('\n  runtime markers (capture offset):');
    final labels = <String>{
      for (final capture in markerCaptures) ...capture.runtimeMarkersMs.keys,
    }.toList()
      ..sort();
    for (final capture in markerCaptures) {
      stdout.writeln('    ${capture.label}:');
      for (final label in labels) {
        final value = capture.runtimeMarkersMs[label];
        if (value != null) {
          stdout.writeln('      ${label.padRight(24)} '
              '${value.toStringAsFixed(1)} ms');
        }
      }
    }
  }
  if (all.length > 1) {
    stdout.writeln('\n  Bands are vs the best capture on each axis. "leading" '
        '≤1.15x, "competitive" ≤1.5x, "ballpark" ≤3x, else "WAY OFF".');
  }
}
