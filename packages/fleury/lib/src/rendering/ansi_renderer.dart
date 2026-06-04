import '../terminal/capabilities.dart';
import 'cell.dart';
import 'cell_buffer.dart';

/// A destination for ANSI bytes. Production wiring sends them to stdout via
/// `IoSinkAnsiSink`; tests capture them with [StringAnsiSink].
abstract interface class AnsiSink {
  void write(String data);
  Future<void> flush();
}

/// Captures every byte written into an in-memory buffer. Used in tests to
/// assert on the exact ANSI emitted by [AnsiRenderer].
final class StringAnsiSink implements AnsiSink {
  final StringBuffer _buffer = StringBuffer();

  /// The full output written so far, including escape sequences.
  String get output => _buffer.toString();

  /// Clears the captured output without allocating a new sink.
  void clear() {
    _buffer.clear();
  }

  @override
  void write(String data) => _buffer.write(data);

  @override
  Future<void> flush() async {}
}

/// Emits the minimum ANSI byte sequence required to update the terminal
/// from [previous] state to [next] state.
///
/// Stateless: the caller owns the previous-frame buffer. Each frame:
///
///   1. Walk cell by cell, left to right, top to bottom.
///   2. Skip cells that are identical to the previous frame.
///   3. Skip continuation cells (they're emitted by their leading cell's
///      grapheme advancing the terminal cursor by 2 columns).
///   4. On a dirty cell, emit:
///        - A cursor position update if the terminal's cursor isn't
///          already at this cell.
///        - A style change (full reset + re-apply) if the style differs
///          from what was last emitted.
///        - The cell's grapheme (or a space for `CellRole.empty`).
///   5. After the last cell, if any style was emitted, reset back to
///      default with `\x1B[0m`.
///
/// Trust contract: this renderer writes cell graphemes verbatim. The
/// `CellBuffer` is the safety boundary; widget code must pass strings
/// through `sanitizeForDisplay` before they reach the buffer. The
/// renderer never inspects grapheme bytes for ESC or control characters.
final class AnsiRenderer {
  /// [colorMode] is the terminal's detected fidelity; colors that exceed
  /// it are downsampled per [quantizeColor] (truecolor → 256 → 16 →
  /// none). Defaults to [ColorMode.truecolor] (no downsampling).
  ///
  /// [synchronizedOutput] (default `true`) wraps each emitted frame in
  /// DEC mode 2026 begin/end markers (`ESC[?2026h` … `ESC[?2026l`) so
  /// the terminal buffers the diff and applies it atomically — no
  /// mid-frame tearing on structural updates. Universally supported by
  /// modern terminals (Kitty/Alacritty/WezTerm/iTerm2/Ghostty/Windows
  /// Terminal/tmux); terminals that don't recognize the escape ignore
  /// it, and modern terminals enforce a ~1-second safety timeout so a
  /// missing ESU can't lock the display. Set `false` only if you've
  /// seen flicker on a specific terminal that mis-implements the
  /// mode — the failure cost is low.
  const AnsiRenderer({
    this.colorMode = ColorMode.truecolor,
    this.synchronizedOutput = true,
  });

  final ColorMode colorMode;
  final bool synchronizedOutput;

  static const _beginSyncUpdate = '\x1B[?2026h';
  static const _endSyncUpdate = '\x1B[?2026l';

  /// Writes the diff between [previous] and [next] to [sink].
  ///
  /// Both buffers must have the same size; an assertion fires otherwise.
  ///
  /// All bytes for the frame are accumulated into an internal
  /// [StringBuffer] and flushed to [sink] in a single `write` call.
  /// This reduces per-frame `sink.write` calls (and the IOSink queue
  /// operations they trigger downstream) from O(dirty cells) to one.
  void renderDiff(
    CellBuffer previous,
    CellBuffer next,
    AnsiSink sink, {
    void Function(int col, int row)? onDirtyCell,
  }) {
    assert(
      previous.size == next.size,
      'AnsiRenderer.renderDiff: buffer sizes differ '
      '(previous=${previous.size}, next=${next.size}).',
    );

    final size = next.size;
    final buf = StringBuffer();
    if (synchronizedOutput) buf.write(_beginSyncUpdate);
    int? cursorRow;
    int? cursorCol;
    CellStyle? emittedStyle;
    var anyDirty = false;

    for (var row = 0; row < size.rows; row++) {
      for (var col = 0; col < size.cols; col++) {
        final newCell = next.atColRow(col, row);

        // Continuation cells emit nothing — the leading's grapheme
        // advances the terminal cursor across them.
        if (newCell.role == CellRole.continuation) continue;

        // protocolCovered cells are owned by an adjacent protocol
        // anchor — the terminal protocol has already painted them.
        // Don't emit a cursor move, don't emit content, don't emit a
        // clear.
        if (newCell.role == CellRole.protocolCovered) continue;

        final oldCell = previous.atColRow(col, row);
        if (newCell == oldCell) continue;

        anyDirty = true;
        // Surfaces "this cell got emitted" for tools that need a
        // dirty-cell list — paint-flashing overlay, etc. Null by
        // default so production pays nothing.
        onDirtyCell?.call(col, row);

        // Cursor positioning. Pick the shortest encoding that lands the
        // cursor at (row, col); see [_cursorMove]. Bytes-on-the-wire matter
        // more than CPU here, and cursor moves are the dominant frame
        // overhead on scroll/dashboard/sparse updates.
        if (cursorRow != row || cursorCol != col) {
          buf.write(_cursorMove(cursorRow, cursorCol, row, col));
          cursorRow = row;
          cursorCol = col;
        }

        // Protocol anchors are emitted verbatim: the grapheme IS the
        // escape sequence to send to the terminal. No SGR wrapping
        // (the protocol carries its own colors), no cursor advance
        // accounting (the protocol moves the cursor however it wants).
        if (newCell.role == CellRole.protocolAnchor) {
          buf.write(newCell.grapheme!);
          // The terminal may leave the cursor anywhere after the
          // protocol completes; invalidate our cached position so the
          // next dirty cell re-emits a cursor move.
          cursorRow = null;
          cursorCol = null;
          emittedStyle = null;
          continue;
        }

        // Style change. Full reset + re-apply on every non-empty
        // transition keeps the encoder simple and correct at the cost
        // of a few extra bytes per style boundary. Empty-style runs
        // only emit a reset when transitioning out of a previously-
        // emitted non-empty style — otherwise plain content stays
        // SGR-free.
        if (newCell.style != emittedStyle) {
          if (newCell.style == CellStyle.empty) {
            if (emittedStyle != null && emittedStyle != CellStyle.empty) {
              buf.write('\x1B[0m');
            }
          } else {
            buf.write(_encodeStyle(newCell.style));
          }
          emittedStyle = newCell.style;
        }

        // Emit the cell's content.
        final grapheme = newCell.role == CellRole.empty
            ? ' '
            : newCell.grapheme!;
        buf.write(grapheme);

        // Advance the cursor for next iteration. A leading cell with a
        // continuation to its right is wide (2 columns); otherwise 1.
        final isWide =
            newCell.role == CellRole.leading &&
            col + 1 < size.cols &&
            next.atColRow(col + 1, row).role == CellRole.continuation;
        cursorCol = col + (isWide ? 2 : 1);
      }
    }

    // If we ever changed style, leave the terminal in a known state.
    if (anyDirty && emittedStyle != null && emittedStyle != CellStyle.empty) {
      buf.write('\x1B[0m');
    }

    // ESU only when we actually emitted dirty cells; an empty frame
    // doesn't need a sync wrapper and emitting one would be a small
    // wasted round-trip on terminals that DON'T support 2026 (they
    // ignore the unknown escapes but still process the bytes).
    if (synchronizedOutput && anyDirty) buf.write(_endSyncUpdate);

    if (anyDirty) sink.write(buf.toString());
  }

  /// Renders [buffer] as a full frame (no previous state). Equivalent to
  /// diffing against an all-empty buffer of the same size.
  ///
  /// Use on first paint and after a resize. For ongoing updates, prefer
  /// `renderDiff` so unchanged regions cost zero bytes.
  void renderFull(CellBuffer buffer, AnsiSink sink) {
    final empty = CellBuffer(buffer.size);
    renderDiff(empty, buffer, sink);
  }

  // ---- Cursor encoding ---------------------------------------------------

  /// The shortest escape that moves the cursor from `(fromRow, fromCol)` to
  /// `(row, col)`. Every branch is byte-output-equivalent to the absolute
  /// `CSI row;col H` it replaces — it leaves the cursor in exactly the same
  /// place with no other visible effect:
  ///
  ///   - Same row: a relative `CSI n C` (forward) / `CSI n D` (back) is
  ///     usually shorter than an absolute reposition. CUF/CUB do not wrap or
  ///     change the row, and the target column is always on-screen, so the
  ///     landing position is identical. `n == 1` omits the parameter
  ///     (`CSI C` / `CSI D`), which defaults to 1.
  ///   - Otherwise (unknown previous position, or a different row): absolute,
  ///     with the column omitted when it is 1 (`CSI row H`) and both omitted
  ///     at home (`CSI H`).
  static String _cursorMove(int? fromRow, int? fromCol, int row, int col) {
    if (fromRow != null && fromCol != null && fromRow == row && fromCol != col) {
      final n = (col - fromCol).abs();
      final dir = col > fromCol ? 'C' : 'D';
      final relative = n == 1 ? '\x1B[$dir' : '\x1B[$n$dir';
      return _shorter(relative, _absolutePosition(row, col));
    }
    return _absolutePosition(row, col);
  }

  /// Absolute cursor position (1-indexed), omitting defaults: `CSI H` at home,
  /// `CSI row H` when the column is 1.
  static String _absolutePosition(int row, int col) {
    if (row == 0 && col == 0) return '\x1B[H';
    if (col == 0) return '\x1B[${row + 1}H';
    return '\x1B[${row + 1};${col + 1}H';
  }

  static String _shorter(String a, String b) => b.length < a.length ? b : a;

  // ---- Style encoding ----------------------------------------------------

  String _encodeStyle(CellStyle style) {
    // Reset, then apply.
    final buf = StringBuffer('\x1B[0m');

    final fg = style.foreground;
    if (fg != null) buf.write(_encodeColor(fg, isBackground: false));

    final bg = style.background;
    if (bg != null) buf.write(_encodeColor(bg, isBackground: true));

    if (style.bold) buf.write('\x1B[1m');
    if (style.dim) buf.write('\x1B[2m');
    if (style.italic) buf.write('\x1B[3m');
    if (style.underline) buf.write('\x1B[4m');
    if (style.inverse) buf.write('\x1B[7m');
    if (style.strikethrough) buf.write('\x1B[9m');

    return buf.toString();
  }

  String _encodeColor(Color color, {required bool isBackground}) {
    final c = quantizeColor(color, colorMode);
    if (c == null) return ''; // ColorMode.none — drop the color, keep attrs
    return switch (c) {
      AnsiColor(:final index) when index < 8 =>
        '\x1B[${(isBackground ? 40 : 30) + index}m',
      AnsiColor(:final index) =>
        '\x1B[${(isBackground ? 100 : 90) + index - 8}m',
      IndexedColor(:final index) =>
        '\x1B[${isBackground ? 48 : 38};5;${index}m',
      RgbColor(:final r, :final g, :final b) =>
        '\x1B[${isBackground ? 48 : 38};2;$r;$g;${b}m',
    };
  }
}

// ---- Color downsampling ---------------------------------------------------

/// Downsamples [color] to the best match representable in [mode], or null
/// for [ColorMode.none]. Colors already within the mode's fidelity pass
/// through unchanged; only what exceeds it is matched down.
///
/// Matching uses the "redmean" weighted distance — a cheap perceptual
/// approximation that avoids the muddy results plain RGB Euclidean
/// distance gives (a long-standing gripe with naive 16-color matching).
Color? quantizeColor(Color color, ColorMode mode) {
  switch (mode) {
    case ColorMode.none:
      return null;
    case ColorMode.truecolor:
      return color;
    case ColorMode.indexed256:
      if (color is RgbColor) {
        return IndexedColor(_rgbToIndexed256(color.r, color.g, color.b));
      }
      return color; // AnsiColor / IndexedColor already representable
    case ColorMode.ansi16:
      switch (color) {
        case AnsiColor():
          return color;
        case IndexedColor(:final index):
          if (index < 16) return AnsiColor(index);
          final rgb = color.toRgb();
          return AnsiColor(_rgbToAnsi16(rgb.r, rgb.g, rgb.b));
        case RgbColor(:final r, :final g, :final b):
          return AnsiColor(_rgbToAnsi16(r, g, b));
      }
  }
}

/// Weighted RGB distance² (no sqrt — only relative ordering matters).
int _redmean(int r1, int g1, int b1, int r2, int g2, int b2) {
  final rm = (r1 + r2) >> 1;
  final dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
  return (((512 + rm) * dr * dr) >> 8) +
      4 * dg * dg +
      (((767 - rm) * db * db) >> 8);
}

int _channelToCube(int v) =>
    v < 48 ? 0 : (v < 115 ? 1 : ((v - 35) ~/ 40).clamp(0, 5));

int _rgbToIndexed256(int r, int g, int b) {
  final r6 = _channelToCube(r), g6 = _channelToCube(g), b6 = _channelToCube(b);
  final cubeIdx = 16 + 36 * r6 + 6 * g6 + b6;
  final cr = cube256Levels[r6], cg = cube256Levels[g6], cb = cube256Levels[b6];
  // Pure-ish grays match the dedicated grayscale ramp better than the cube.
  final avg = (r + g + b) ~/ 3;
  final grayIdx = avg > 238 ? 23 : ((avg - 3) ~/ 10).clamp(0, 23);
  final gray = 8 + 10 * grayIdx;
  final cubeDist = _redmean(cr, cg, cb, r, g, b);
  final grayDist = _redmean(gray, gray, gray, r, g, b);
  return grayDist < cubeDist ? 232 + grayIdx : cubeIdx;
}

int _rgbToAnsi16(int r, int g, int b) {
  var best = 0;
  var bestDist = 1 << 62;
  for (var i = 0; i < 16; i++) {
    final p = ansiPalette16[i];
    final d = _redmean(p[0], p[1], p[2], r, g, b);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}
