import 'dart:convert';

import 'ansi_renderer.dart';

/// UTF-8 byte counts for emitted ANSI output, split by what the bytes were
/// spent on.
///
/// "Bytes on the wire" are measured as UTF-8 because that is what the terminal
/// (and any SSH/tmux transport) actually carries — escape sequences are ASCII
/// (one byte per character), but content graphemes can be multi-byte (CJK,
/// emoji). Counting UTF-16 code units would undercount real transport cost.
///
/// Categories map to what [AnsiRenderer] emits:
///   - [content]: printable graphemes (the actual information).
///   - [sgr]:     `CSI … m` — style set/reset (color, bold, inverse, …).
///   - [cursor]:  CSI cursor moves/positioning (`A`/`B`/`C`/`D`, `H`/`f`,
///                and related row/column positioning commands).
///   - [sync]:    `CSI ? 2026 h/l` — the per-frame synchronized-output
///                wrapper.
///   - [session]: session lifecycle private-mode toggles — alt screen
///                (1049), cursor visibility (25), bracketed paste (2004),
///                mouse modes (1000/1002/1003/1006), and Kitty keyboard
///                push/pop (`CSI > … u` / `CSI < u`). Paid once per
///                enter/suspend/restore, not per frame.
///   - [other]:   any other escape sequence (e.g. an image/protocol anchor
///                grapheme emitted verbatim, or an unrecognized CSI final).
class AnsiByteBreakdown {
  const AnsiByteBreakdown({
    this.content = 0,
    this.sgr = 0,
    this.cursor = 0,
    this.sync = 0,
    this.session = 0,
    this.other = 0,
  });

  final int content;
  final int sgr;
  final int cursor;
  final int sync;
  final int session;
  final int other;

  int get total => content + sgr + cursor + sync + session + other;

  /// Bytes that carry information (content) vs. control/formatting overhead
  /// spent per frame (everything except content and [session]). A high
  /// overhead fraction on update frames is the signal that byte-level
  /// encoding (e.g. incremental SGR) is worth tuning. Session lifecycle
  /// bytes are excluded: they are connection setup/teardown, paid once per
  /// terminal enter/restore, and would otherwise dominate the fraction on
  /// short runs without saying anything about frame encoding.
  int get overhead => sgr + cursor + sync + other;

  double get overheadFraction {
    final steady = total - session;
    return steady == 0 ? 0 : overhead / steady;
  }

  AnsiByteBreakdown operator +(AnsiByteBreakdown o) => AnsiByteBreakdown(
    content: content + o.content,
    sgr: sgr + o.sgr,
    cursor: cursor + o.cursor,
    sync: sync + o.sync,
    session: session + o.session,
    other: other + o.other,
  );

  /// Categorizes a single emitted ANSI string by UTF-8 byte count.
  ///
  /// Handles the CSI grammar [AnsiRenderer] emits: `ESC [` optionally followed
  /// by a `?` private marker, then parameter/intermediate bytes, then a final
  /// byte in `0x40..0x7E`. A bare `ESC` not starting a CSI is conservatively
  /// counted toward [other].
  factory AnsiByteBreakdown.analyze(String data) {
    var content = 0;
    var sgr = 0;
    var cursor = 0;
    var sync = 0;
    var session = 0;
    var other = 0;

    final contentRun = StringBuffer();
    void flushContent() {
      if (contentRun.isEmpty) return;
      content += utf8.encode(contentRun.toString()).length;
      contentRun.clear();
    }

    const esc = 0x1B;
    const csi = 0x5B; // '['
    const privateMarker = 0x3F; // '?'

    var i = 0;
    final n = data.length;
    while (i < n) {
      final cu = data.codeUnitAt(i);
      if (cu == 0x08 || cu == 0x0A || cu == 0x0D) {
        // BS, LF, and CR are printable-stream C0 controls that terminals use
        // as cursor movement. Fleury's sanitized cell content cannot contain
        // them, and peer captures use them for the same cursor-control role.
        flushContent();
        cursor += 1;
        i++;
        continue;
      }
      if (cu != esc) {
        contentRun.writeCharCode(cu);
        i++;
        continue;
      }

      flushContent();
      final start = i;
      i++; // consume ESC
      if (i >= n || data.codeUnitAt(i) != csi) {
        // Not a CSI; count the ESC alone as overhead and continue.
        other += 1;
        continue;
      }
      i++; // consume '['
      var private = false;
      var kittyMarker = false;
      if (i < n && data.codeUnitAt(i) == privateMarker) private = true;
      if (i < n) {
        final marker = data.codeUnitAt(i);
        // '>' (push) / '<' (pop) — the Kitty keyboard-protocol prefixes.
        if (marker == 0x3E || marker == 0x3C) kittyMarker = true;
      }
      final paramStart = i;
      var finalByte = 0;
      while (i < n) {
        final c = data.codeUnitAt(i);
        i++;
        if (c >= 0x40 && c <= 0x7E) {
          finalByte = c;
          break;
        }
      }
      final len = i - start; // CSI is ASCII: byte length == code-unit length
      if (private && (finalByte == 0x68 || finalByte == 0x6C)) {
        // DEC private mode set/reset: synchronized output (2026) is the
        // per-frame wrapper; every other private mode is session lifecycle.
        if (_paramsAreSynchronizedOutput(data, paramStart + 1, i - 1)) {
          sync += len;
        } else {
          session += len;
        }
      } else if (kittyMarker && finalByte == 0x75) {
        session += len; // u: Kitty keyboard push/pop
      } else if (_isCursorCsiFinal(finalByte)) {
        cursor += len;
      } else if (finalByte == 0x6D) {
        sgr += len; // m
      } else {
        other += len;
      }
    }
    flushContent();

    return AnsiByteBreakdown(
      content: content,
      sgr: sgr,
      cursor: cursor,
      sync: sync,
      session: session,
      other: other,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'total': total,
    'content': content,
    'sgr': sgr,
    'cursor': cursor,
    'sync': sync,
    'session': session,
    'other': other,
    'overheadFraction': overheadFraction,
  };

  @override
  String toString() =>
      'AnsiByteBreakdown(total: $total, content: $content, sgr: $sgr, '
      'cursor: $cursor, sync: $sync, session: $session, other: $other)';
}

/// True if the private-mode parameter list in `data[from..to)` is exactly
/// `2026` (synchronized output). Any other parameter — or a list — makes the
/// toggle session lifecycle, not a per-frame wrapper.
bool _paramsAreSynchronizedOutput(String data, int from, int to) {
  const expected = '2026';
  if (to - from != expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (data.codeUnitAt(from + i) != expected.codeUnitAt(i)) return false;
  }
  return true;
}

bool _isCursorCsiFinal(int finalByte) {
  return switch (finalByte) {
    0x41 || // A: CUU
    0x42 || // B: CUD
    0x43 || // C: CUF
    0x44 || // D: CUB
    0x45 || // E: CNL
    0x46 || // F: CPL
    0x47 || // G: CHA
    0x48 || // H: CUP
    0x61 || // a: HPR
    0x64 || // d: VPA
    0x65 || // e: VPR
    0x66 => true, // f: HVP
    _ => false,
  };
}

/// A simple transport model for turning a frame's byte count into an estimated
/// wire time, so byte-budget numbers can be reasoned about as latency.
///
/// `frameMs(bytes) = fixedOverheadMs + 1000 * bytes / bytesPerSecond`.
///
/// This is a deliberately simple first-order model: a one-way overhead (link
/// propagation / per-frame fixed cost) plus serialization time at the link's
/// throughput. It is NOT a substitute for measuring on real hardware — it
/// exists to show *where* byte count actually translates into latency. The
/// honest conclusion it surfaces: byte savings dominate on bandwidth-limited
/// links and are near-irrelevant on fast, RTT-dominated ones.
class TransportProfile {
  const TransportProfile(
    this.name, {
    required this.bytesPerSecond,
    required this.fixedOverheadMs,
  });

  final String name;
  final double bytesPerSecond;
  final double fixedOverheadMs;

  double frameMs(int bytes) =>
      fixedOverheadMs + 1000.0 * bytes / bytesPerSecond;

  /// Local pty: throughput so high these byte counts are effectively free.
  static const local = TransportProfile(
    'local',
    bytesPerSecond: 20000000,
    fixedOverheadMs: 0.02,
  );

  /// SSH over a LAN: fast, low latency.
  static const sshLan = TransportProfile(
    'ssh-lan',
    bytesPerSecond: 5000000,
    fixedOverheadMs: 0.5,
  );

  /// SSH over a WAN: ample bandwidth but ~40 ms one-way — RTT-dominated, so
  /// byte savings barely move the needle here.
  static const sshWan = TransportProfile(
    'ssh-wan',
    bytesPerSecond: 1000000,
    fixedOverheadMs: 40,
  );

  /// A constrained link (≈9600 baud) where every byte costs ~0.83 ms —
  /// bandwidth-dominated, so byte savings translate directly to time.
  static const slow9600 = TransportProfile(
    'slow-9600',
    bytesPerSecond: 1200,
    fixedOverheadMs: 5,
  );

  static const defaults = <TransportProfile>[local, sshLan, sshWan, slow9600];
}

/// An [AnsiSink] that categorizes every write into an [AnsiByteBreakdown],
/// keeping both a running [total] and (optionally) a per-frame list.
///
/// [AnsiRenderer.renderDiff] flushes each frame to the sink in exactly one
/// `write` call (and only when the frame is non-empty), so each entry in
/// [frames] corresponds to one emitted frame's byte budget.
///
/// Optionally wraps an [inner] sink so the same bytes can still reach a real
/// destination — making this usable for live byte telemetry against a real
/// terminal, not just offline analysis.
class CountingAnsiSink implements AnsiSink {
  /// [keepFrames] retains a per-frame breakdown list (for offline analysis).
  /// Set it false for long-running production telemetry, where only the
  /// running [total] and [frameCount] are needed and an unbounded list would
  /// grow without limit.
  CountingAnsiSink([this.inner]) : keepFrames = true;
  CountingAnsiSink.aggregate([this.inner]) : keepFrames = false;

  final AnsiSink? inner;
  final bool keepFrames;

  final List<AnsiByteBreakdown> frames = <AnsiByteBreakdown>[];
  AnsiByteBreakdown total = const AnsiByteBreakdown();

  int _frameCount = 0;

  /// Number of non-empty frames written.
  int get frameCount => keepFrames ? frames.length : _frameCount;

  @override
  void write(String data) {
    final breakdown = AnsiByteBreakdown.analyze(data);
    if (keepFrames) {
      frames.add(breakdown);
    } else {
      _frameCount++;
    }
    total = total + breakdown;
    inner?.write(data);
  }

  @override
  Future<void> flush() async => inner?.flush();

  void reset() {
    frames.clear();
    _frameCount = 0;
    total = const AnsiByteBreakdown();
  }
}
