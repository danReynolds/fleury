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
///   - [cursor]:  `CSI … H` / `CSI … f` — cursor positioning.
///   - [sync]:    `CSI ? … h` / `CSI ? … l` — private modes (synchronized
///                output 2026, and any other DEC private mode toggles).
///   - [other]:   any other escape sequence (e.g. an image/protocol anchor
///                grapheme emitted verbatim, or an unrecognized CSI final).
class AnsiByteBreakdown {
  const AnsiByteBreakdown({
    this.content = 0,
    this.sgr = 0,
    this.cursor = 0,
    this.sync = 0,
    this.other = 0,
  });

  final int content;
  final int sgr;
  final int cursor;
  final int sync;
  final int other;

  int get total => content + sgr + cursor + sync + other;

  /// Bytes that carry information (content) vs. control/formatting overhead
  /// (everything else). A high overhead fraction on update frames is the
  /// signal that byte-level encoding (e.g. incremental SGR) is worth tuning.
  int get overhead => sgr + cursor + sync + other;

  double get overheadFraction => total == 0 ? 0 : overhead / total;

  AnsiByteBreakdown operator +(AnsiByteBreakdown o) => AnsiByteBreakdown(
    content: content + o.content,
    sgr: sgr + o.sgr,
    cursor: cursor + o.cursor,
    sync: sync + o.sync,
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
      if (i < n && data.codeUnitAt(i) == privateMarker) private = true;
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
        sync += len; // h / l
      } else if (finalByte == 0x48 || finalByte == 0x66) {
        cursor += len; // H / f
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
      other: other,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'total': total,
    'content': content,
    'sgr': sgr,
    'cursor': cursor,
    'sync': sync,
    'other': other,
    'overheadFraction': overheadFraction,
  };

  @override
  String toString() =>
      'AnsiByteBreakdown(total: $total, content: $content, sgr: $sgr, '
      'cursor: $cursor, sync: $sync, other: $other)';
}

/// An [AnsiSink] that categorizes every write into an [AnsiByteBreakdown],
/// keeping both a running [total] and a per-frame list.
///
/// [AnsiRenderer.renderDiff] flushes each frame to the sink in exactly one
/// `write` call (and only when the frame is non-empty), so each entry in
/// [frames] corresponds to one emitted frame's byte budget.
///
/// Optionally wraps an [inner] sink so the same bytes can still reach a real
/// destination — making this usable for live byte telemetry against a real
/// terminal, not just offline analysis.
class CountingAnsiSink implements AnsiSink {
  CountingAnsiSink([this.inner]);

  final AnsiSink? inner;

  final List<AnsiByteBreakdown> frames = <AnsiByteBreakdown>[];
  AnsiByteBreakdown total = const AnsiByteBreakdown();

  /// Number of non-empty frames written.
  int get frameCount => frames.length;

  @override
  void write(String data) {
    final breakdown = AnsiByteBreakdown.analyze(data);
    frames.add(breakdown);
    total = total + breakdown;
    inner?.write(data);
  }

  @override
  Future<void> flush() async => inner?.flush();

  void reset() {
    frames.clear();
    total = const AnsiByteBreakdown();
  }
}
