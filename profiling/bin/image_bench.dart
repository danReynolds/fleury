// Inline-image pipeline bench + gate. Drives TerminalImageEncoder directly over
// a CellBuffer sequence and measures the image escape bytes/frame — now visible
// via the AnsiByteBreakdown `image` category (before, kitty/iterm2/sixel escapes
// were mis-counted as content/other) — plus encode µs. Covers the two invariants
// that had no byte-level gate: a STATIC image dedups (the encoder transmits +
// places once, then 0 bytes/frame), and an image-free frame on an image-capable
// terminal emits 0 (the zero-image fast path, PR #30). An ANIMATED image
// (content changes each frame) is the per-frame transmit cost.
//
//   dart run bin/image_bench.dart [--gate] [--frames=N]
//
// (Terminal encoder side. The browser/serve image wire rides G1's live harness;
// the embed InlineImageOverlay is DOM, not bytes — both are follow-ups.)

import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/ansi_byte_budget.dart';
import 'package:fleury/src/terminal/terminal_image_encoder.dart';

const _protocols = <({String name, ImageProtocol protocol})>[
  (name: 'kitty', protocol: ImageProtocol.kitty),
  (name: 'iterm2', protocol: ImageProtocol.iterm2),
];

/// A distinct fake image payload per [seed] — deterministic, ~256 bytes so the
/// encoder does real base64 + chunking work.
Uint8List _png(int seed) =>
    Uint8List.fromList(List<int>.generate(256, (i) => (i * 7 + seed * 31) & 0xFF));

CellBuffer _withImage(Uint8List bytes) {
  final buf = CellBuffer(const CellSize(40, 20));
  buf.writeImage(
    const CellOffset(0, 0),
    bytes,
    width: 8,
    height: 4,
    sourceWidth: 16,
    sourceHeight: 16,
  );
  return buf;
}

/// Image bytes emitted for a scenario, per frame. [animated] varies the payload
/// each frame (a re-transmit); otherwise the same image repeats (dedup).
List<int> _imageBytesPerFrame(
  ImageProtocol protocol,
  int frames, {
  required bool animated,
}) {
  final encoder = TerminalImageEncoder(protocol: protocol);
  final out = <int>[];
  for (var i = 0; i < frames; i++) {
    final buf = _withImage(_png(animated ? i : 0));
    final bytes = encoder.encodeFrame(buf, fullRepaint: i == 0);
    out.add(AnsiByteBreakdown.analyze(bytes).image);
  }
  return out;
}

int _zeroImageBytes(ImageProtocol protocol, int frames) {
  final encoder = TerminalImageEncoder(protocol: protocol);
  final empty = CellBuffer(const CellSize(40, 20));
  var total = 0;
  for (var i = 0; i < frames; i++) {
    // First frame full-repaint (setup); the rest are the steady image-free path.
    final bytes = encoder.encodeFrame(empty, fullRepaint: i == 0);
    total += AnsiByteBreakdown.analyze(bytes).image;
  }
  return total;
}

double _encodeUsPerFrame(ImageProtocol protocol, {required bool animated}) {
  final encoder = TerminalImageEncoder(protocol: protocol);
  encoder.encodeFrame(_withImage(_png(0)), fullRepaint: true); // prime
  const iters = 2000;
  for (var i = 0; i < 200; i++) {
    encoder.encodeFrame(_withImage(_png(animated ? i : 0)), fullRepaint: false);
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iters; i++) {
    encoder.encodeFrame(_withImage(_png(animated ? i : 0)), fullRepaint: false);
  }
  sw.stop();
  return sw.elapsedMicroseconds / iters;
}

void main(List<String> args) {
  var frames = 30;
  for (final a in args) {
    if (a.startsWith('--frames=')) {
      frames = int.tryParse(a.substring('--frames='.length)) ?? frames;
    }
  }
  if (args.contains('--gate')) {
    _gate(frames);
    return;
  }

  stdout.writeln('Inline-image encoder bench — image bytes/frame (via the '
      'AnsiByteBreakdown image category) + encode µs. $frames frames.');
  stdout.writeln('');
  stdout.writeln('${'protocol'.padRight(10)}  first-frame  '
      'static steady/f  animated/f  enc µs/f');
  stdout.writeln('-' * 60);
  for (final p in _protocols) {
    final staticB = _imageBytesPerFrame(p.protocol, frames, animated: false);
    final animB = _imageBytesPerFrame(p.protocol, frames, animated: true);
    final staticSteady = staticB.skip(1).fold<int>(0, (a, b) => a + b);
    final animSteady = animB.skip(1).fold<int>(0, (a, b) => a + b);
    final animPerFrame = frames > 1 ? animSteady / (frames - 1) : 0;
    stdout.writeln('${p.name.padRight(10)}  '
        '${staticB.first.toString().padLeft(11)}  '
        '${staticSteady.toString().padLeft(15)}  '
        '${animPerFrame.toStringAsFixed(0).padLeft(10)}  '
        '${_encodeUsPerFrame(p.protocol, animated: true).toStringAsFixed(1).padLeft(8)}');
  }
  stdout.writeln('');
  stdout.writeln('static steady/f == 0 means a still image dedups (transmit + '
      'place once). animated/f is the per-frame re-transmit cost.');
}

void _gate(int frames) {
  var failed = false;
  for (final p in _protocols) {
    // Dedup: a static image must cost 0 image bytes after the first frame.
    final staticSteady = _imageBytesPerFrame(p.protocol, frames, animated: false)
        .skip(1)
        .fold<int>(0, (a, b) => a + b);
    // Zero-image fast path: image-free frames must emit 0 image bytes.
    final zero = _zeroImageBytes(p.protocol, frames);
    final ok = staticSteady == 0 && zero == 0;
    stdout.writeln('${p.name}: static steady ${staticSteady} B, '
        'zero-image ${zero} B ${ok ? 'ok' : 'FAIL'}');
    if (!ok) failed = true;
  }
  if (failed) {
    stdout.writeln('\nimage bench gate: FAIL — a still image is re-transmitting '
        '(dedup regressed) or an image-free frame emits image bytes (the '
        'zero-image fast path regressed).');
    exitCode = 1;
  } else {
    stdout.writeln('\nimage bench gate: pass — still images dedup and image-free '
        'frames cost zero image bytes.');
  }
}
