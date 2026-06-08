import '../foundation/geometry.dart';
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
///        - A style delta if the style differs from what was last emitted.
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
    final screenStats = _screenDiffStats(previous, next);
    if (screenStats.dirtyCells == 0) return;

    final size = next.size;
    final scrollUpRows = _detectBeneficialScrollUp(previous, next, screenStats);
    if (scrollUpRows != null) {
      final scrolledPrevious = CellBuffer(size);
      scrolledPrevious.copyRectFrom(
        previous,
        CellRect(
          offset: CellOffset(0, scrollUpRows),
          size: CellSize(size.cols, size.rows - scrollUpRows),
        ),
        const CellOffset(0, 0),
      );
      final buf = StringBuffer();
      if (synchronizedOutput) buf.write(_beginSyncUpdate);
      buf.write(_scrollUp(scrollUpRows));
      _appendCellDiff(scrolledPrevious, next, buf, onDirtyCell: onDirtyCell);
      if (synchronizedOutput) buf.write(_endSyncUpdate);
      sink.write(buf.toString());
      return;
    }

    final buf = StringBuffer();
    final anyDirty = _appendCellDiff(
      previous,
      next,
      buf,
      onDirtyCell: onDirtyCell,
    );
    if (!anyDirty) return;
    final output = StringBuffer();
    if (synchronizedOutput) output.write(_beginSyncUpdate);
    output.write(buf);
    if (synchronizedOutput) output.write(_endSyncUpdate);
    sink.write(output.toString());
  }

  bool _appendCellDiff(
    CellBuffer previous,
    CellBuffer next,
    StringBuffer buf, {
    void Function(int col, int row)? onDirtyCell,
  }) {
    final size = next.size;
    int? cursorRow;
    int? cursorCol;
    CellStyle? emittedStyle;
    var styleResetRequired = false;
    var styleBytesEmitted = false;
    var anyDirty = false;

    void appendCell(int col, int row) {
      final newCell = next.atColRow(col, row);

      // Continuation cells emit nothing — the leading's grapheme
      // advances the terminal cursor across them.
      if (newCell.role == CellRole.continuation) return;

      // protocolCovered cells are owned by an adjacent protocol
      // anchor — the terminal protocol has already painted them.
      // Don't emit a cursor move, don't emit content, don't emit a
      // clear.
      if (newCell.role == CellRole.protocolCovered) return;

      final oldCell = previous.atColRow(col, row);
      if (newCell == oldCell) return;

      anyDirty = true;
      // Surfaces "this cell got emitted" for tools that need a
      // dirty-cell list — paint-flashing overlay, etc. Null by
      // default so production pays nothing.
      onDirtyCell?.call(col, row);

      // Cursor positioning. Pick the shortest encoding that lands the
      // cursor at (row, col); see [_cursorMove]. Bytes-on-the-wire matter
      // more than CPU here, and cursor moves are the dominant frame
      // overhead on scroll/dashboard/sparse updates.
      final fromCol = cursorCol;
      if (cursorRow == row && fromCol != null && fromCol < col) {
        final gap = _plainAsciiGap(
          previous,
          next,
          row,
          fromCol,
          col,
          emittedStyle,
        );
        if (gap != null) {
          final move = _cursorMove(cursorRow, cursorCol, row, col);
          if (gap.length < move.length) {
            buf.write(gap);
            cursorCol = col;
          }
        }
      }
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
        // protocol completes; invalidate our cached position/style so
        // the next dirty cell re-emits a cursor move and resets SGR.
        cursorRow = null;
        cursorCol = null;
        emittedStyle = null;
        styleResetRequired = true;
        return;
      }

      // Style change. Emit a combined SGR delta where the terminal state is
      // known; fall back to reset+set when a protocol anchor invalidated the
      // cache. Empty-style runs only emit a reset when transitioning out of
      // a previously emitted non-empty style, or after an invalidating
      // protocol anchor.
      if (newCell.style != emittedStyle) {
        if (newCell.style == CellStyle.empty) {
          if (styleResetRequired ||
              (emittedStyle != null && emittedStyle != CellStyle.empty)) {
            buf.write('\x1B[0m');
            styleBytesEmitted = true;
            styleResetRequired = false;
          }
        } else {
          final encoded = _encodeStyleTransition(
            emittedStyle,
            newCell.style,
            resetFirst: styleResetRequired,
          );
          if (encoded.isNotEmpty) {
            buf.write(encoded);
            styleBytesEmitted = true;
          }
          styleResetRequired = false;
        }
        emittedStyle = newCell.style;
      }

      // Emit the cell's content.
      final grapheme = newCell.role == CellRole.empty ? ' ' : newCell.grapheme!;
      buf.write(grapheme);

      // Advance the cursor for next iteration. A leading cell with a
      // continuation to its right is wide (2 columns); otherwise 1.
      final isWide =
          newCell.role == CellRole.leading &&
          col + 1 < size.cols &&
          next.atColRow(col + 1, row).role == CellRole.continuation;
      cursorCol = col + (isWide ? 2 : 1);
    }

    for (var row = 0; row < size.rows; row++) {
      for (var col = 0; col < size.cols; col++) {
        appendCell(col, row);
      }
    }

    // If we ever changed style, leave the terminal in a known state.
    if (anyDirty &&
        styleBytesEmitted &&
        emittedStyle != null &&
        emittedStyle != CellStyle.empty) {
      buf.write('\x1B[0m');
    }

    // ESU only when we actually emitted dirty cells; an empty frame
    // doesn't need a sync wrapper and emitting one would be a small
    // wasted round-trip on terminals that DON'T support 2026 (they
    // ignore the unknown escapes but still process the bytes).
    return anyDirty;
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
  ///   - Same column: a relative `CSI n B` / `CSI n A` is usually shorter
  ///     than an absolute reposition and preserves the column.
  ///   - Different row, target column 0: CNL/CPL (`CSI n E` / `CSI n F`) can
  ///     move vertically and return to line start in one escape.
  ///   - One row down: LF and CRLF are shorter equivalents for same-column and
  ///     line-start moves; CRLF can also beat CNL plus a horizontal move for
  ///     indented next-line targets. Because the target row is in-bounds, LF
  ///     cannot scroll the screen here.
  ///   - Otherwise: try a vertical relative move plus a horizontal relative
  ///     move, and fall back to absolute if that is shorter.
  ///
  /// Absolute positions omit defaults: `CSI H` at home, and `CSI row H` when
  /// the column is 1.
  static String _cursorMove(int? fromRow, int? fromCol, int row, int col) {
    var shortest = _absolutePosition(row, col);
    if (fromRow != null && fromCol != null) {
      if (fromRow == row) {
        shortest = _shorter(shortest, _horizontalMove(fromCol, col));
      } else {
        if (row == fromRow + 1) {
          if (fromCol == col) {
            shortest = _shorter(shortest, '\n');
          }
          if (col == 0) {
            shortest = _shorter(shortest, fromCol == 0 ? '\n' : '\r\n');
          } else {
            shortest = _shorter(shortest, '\r\n${_horizontalMove(0, col)}');
          }
        }
        if (fromCol == col) {
          shortest = _shorter(shortest, _verticalMove(fromRow, row));
        }
        if (col == 0) {
          shortest = _shorter(shortest, _lineMove(fromRow, row));
        }
        if (fromCol != col) {
          shortest = _shorter(
            shortest,
            _verticalMove(fromRow, row) + _horizontalMove(fromCol, col),
          );
          if (col > 0) {
            shortest = _shorter(
              shortest,
              _lineMove(fromRow, row) + _horizontalMove(0, col),
            );
          }
        }
      }
    }
    return shortest;
  }

  /// Absolute cursor position (1-indexed), omitting defaults: `CSI H` at home,
  /// `CSI row H` when the column is 1.
  static String _absolutePosition(int row, int col) {
    if (row == 0 && col == 0) return '\x1B[H';
    if (col == 0) return '\x1B[${row + 1}H';
    return '\x1B[${row + 1};${col + 1}H';
  }

  static String _shorter(String a, String b) => b.length < a.length ? b : a;

  static String _horizontalMove(int fromCol, int col) {
    if (fromCol == col) return '';
    final n = (col - fromCol).abs();
    final dir = col > fromCol ? 'C' : 'D';
    return n == 1 ? '\x1B[$dir' : '\x1B[$n$dir';
  }

  static String _verticalMove(int fromRow, int row) {
    if (fromRow == row) return '';
    final n = (row - fromRow).abs();
    final dir = row > fromRow ? 'B' : 'A';
    return n == 1 ? '\x1B[$dir' : '\x1B[$n$dir';
  }

  static String _lineMove(int fromRow, int row) {
    if (fromRow == row) return '';
    final n = (row - fromRow).abs();
    final dir = row > fromRow ? 'E' : 'F';
    return n == 1 ? '\x1B[$dir' : '\x1B[$n$dir';
  }

  static String _scrollUp(int rows) => rows == 1 ? '\x1B[S' : '\x1B[${rows}S';

  static String? _plainAsciiGap(
    CellBuffer previous,
    CellBuffer next,
    int row,
    int fromCol,
    int toCol,
    CellStyle? emittedStyle,
  ) {
    if (fromCol >= toCol) return null;
    if (emittedStyle != null && emittedStyle != CellStyle.empty) return null;
    final out = StringBuffer();
    for (var col = fromCol; col < toCol; col++) {
      final cell = next.atColRow(col, row);
      if (previous.atColRow(col, row) != cell) return null;
      if (cell.style != CellStyle.empty) return null;
      switch (cell.role) {
        case CellRole.empty:
          out.write(' ');
        case CellRole.leading:
          final grapheme = cell.grapheme!;
          if (!_isAscii(grapheme)) return null;
          final isWide =
              col + 1 < next.size.cols &&
              next.atColRow(col + 1, row).role == CellRole.continuation;
          if (isWide) return null;
          out.write(grapheme);
        case CellRole.continuation:
        case CellRole.protocolAnchor:
        case CellRole.protocolCovered:
          return null;
      }
    }
    return out.toString();
  }

  static bool _isAscii(String text) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) > 0x7F) return false;
    }
    return true;
  }

  static int? _detectBeneficialScrollUp(
    CellBuffer previous,
    CellBuffer next,
    ({int dirtyCells, bool hasProtocolCells}) stats,
  ) {
    final size = previous.size;
    if (size != next.size || size.rows < 2) return null;

    if (stats.hasProtocolCells) return null;
    final normalDirty = stats.dirtyCells;
    var bestShift = 0;
    var bestDirty = normalDirty;
    for (var shift = 1; shift < size.rows; shift++) {
      final retainedNonEmpty = _rowHasNonEmpty(previous, shift);
      if (!retainedNonEmpty) continue;
      if (!_rowsEqual(previous, shift, next, 0)) continue;
      var shiftedDirty = 0;
      var abandoned = false;
      for (var row = 1; row < size.rows - shift; row++) {
        for (var col = 0; col < size.cols; col++) {
          final oldCell = previous.atColRow(col, row + shift);
          final newCell = next.atColRow(col, row);
          if (oldCell != newCell) {
            shiftedDirty++;
            if (shiftedDirty >= bestDirty) {
              abandoned = true;
              break;
            }
          }
        }
        if (abandoned) break;
      }
      if (abandoned) continue;
      for (var row = size.rows - shift; row < size.rows; row++) {
        for (var col = 0; col < size.cols; col++) {
          if (next.atColRow(col, row) != const Cell.empty()) {
            shiftedDirty++;
            if (shiftedDirty >= bestDirty) {
              abandoned = true;
              break;
            }
          }
        }
        if (abandoned) break;
      }
      if (!abandoned && shiftedDirty < bestDirty) {
        bestShift = shift;
        bestDirty = shiftedDirty;
      }
    }
    return bestShift == 0 ? null : bestShift;
  }

  static ({int dirtyCells, bool hasProtocolCells}) _screenDiffStats(
    CellBuffer previous,
    CellBuffer next,
  ) {
    final size = previous.size;
    var dirty = 0;
    var hasProtocolCells = false;
    for (var row = 0; row < size.rows; row++) {
      for (var col = 0; col < size.cols; col++) {
        final previousCell = previous.atColRow(col, row);
        final nextCell = next.atColRow(col, row);
        if (previousCell != nextCell) dirty++;
        hasProtocolCells =
            hasProtocolCells ||
            previousCell.role == CellRole.protocolAnchor ||
            previousCell.role == CellRole.protocolCovered ||
            nextCell.role == CellRole.protocolAnchor ||
            nextCell.role == CellRole.protocolCovered;
      }
    }
    return (dirtyCells: dirty, hasProtocolCells: hasProtocolCells);
  }

  static bool _rowsEqual(
    CellBuffer previous,
    int previousRow,
    CellBuffer next,
    int nextRow,
  ) {
    final size = previous.size;
    for (var col = 0; col < size.cols; col++) {
      if (previous.atColRow(col, previousRow) != next.atColRow(col, nextRow)) {
        return false;
      }
    }
    return true;
  }

  static bool _rowHasNonEmpty(CellBuffer buffer, int row) {
    final size = buffer.size;
    for (var col = 0; col < size.cols; col++) {
      if (buffer.atColRow(col, row).role != CellRole.empty) return true;
    }
    return false;
  }

  // ---- Style encoding ----------------------------------------------------

  String _encodeStyleTransition(
    CellStyle? from,
    CellStyle to, {
    required bool resetFirst,
  }) {
    if (resetFirst || from == null || from == CellStyle.empty) {
      return _encodeStyle(to, resetFirst: resetFirst);
    }

    final params = <String>[];
    _appendColorDelta(
      params,
      from.foreground,
      to.foreground,
      isBackground: false,
    );
    _appendColorDelta(
      params,
      from.background,
      to.background,
      isBackground: true,
    );
    _appendIntensityDelta(params, from, to);
    _appendBoolAttrDelta(
      params,
      from.italic,
      to.italic,
      setCode: '3',
      resetCode: '23',
    );
    _appendBoolAttrDelta(
      params,
      from.underline,
      to.underline,
      setCode: '4',
      resetCode: '24',
    );
    _appendBoolAttrDelta(
      params,
      from.inverse,
      to.inverse,
      setCode: '7',
      resetCode: '27',
    );
    _appendBoolAttrDelta(
      params,
      from.strikethrough,
      to.strikethrough,
      setCode: '9',
      resetCode: '29',
    );
    return _sgr(params);
  }

  String _encodeStyle(CellStyle style, {required bool resetFirst}) {
    final params = <String>[];
    if (resetFirst) params.add('0');
    _appendStyleSetParams(params, style);
    return _sgr(params);
  }

  void _appendStyleSetParams(List<String> params, CellStyle style) {
    _appendColorSet(params, style.foreground, isBackground: false);
    _appendColorSet(params, style.background, isBackground: true);
    if (style.bold) params.add('1');
    if (style.dim) params.add('2');
    if (style.italic) params.add('3');
    if (style.underline) params.add('4');
    if (style.inverse) params.add('7');
    if (style.strikethrough) params.add('9');
  }

  void _appendColorDelta(
    List<String> params,
    Color? from,
    Color? to, {
    required bool isBackground,
  }) {
    final fromColor = from == null ? null : quantizeColor(from, colorMode);
    final toColor = to == null ? null : quantizeColor(to, colorMode);
    if (fromColor == toColor) return;
    if (toColor == null) {
      params.add(isBackground ? '49' : '39');
    } else {
      _appendEncodedColor(params, toColor, isBackground: isBackground);
    }
  }

  void _appendColorSet(
    List<String> params,
    Color? color, {
    required bool isBackground,
  }) {
    if (color == null) return;
    final effective = quantizeColor(color, colorMode);
    if (effective == null) return; // ColorMode.none: drop color, keep attrs.
    _appendEncodedColor(params, effective, isBackground: isBackground);
  }

  void _appendEncodedColor(
    List<String> params,
    Color color, {
    required bool isBackground,
  }) {
    switch (color) {
      case AnsiColor(:final index) when index < 8:
        params.add('${(isBackground ? 40 : 30) + index}');
      case AnsiColor(:final index):
        params.add('${(isBackground ? 100 : 90) + index - 8}');
      case IndexedColor(:final index):
        params.add('${isBackground ? 48 : 38};5;$index');
      case RgbColor(:final r, :final g, :final b):
        params.add('${isBackground ? 48 : 38};2;$r;$g;$b');
    }
  }

  void _appendIntensityDelta(
    List<String> params,
    CellStyle from,
    CellStyle to,
  ) {
    if (from.bold == to.bold && from.dim == to.dim) return;
    if ((from.bold && !to.bold) || (from.dim && !to.dim)) {
      params.add('22');
      if (to.bold) params.add('1');
      if (to.dim) params.add('2');
      return;
    }
    if (!from.bold && to.bold) params.add('1');
    if (!from.dim && to.dim) params.add('2');
  }

  void _appendBoolAttrDelta(
    List<String> params,
    bool from,
    bool to, {
    required String setCode,
    required String resetCode,
  }) {
    if (from == to) return;
    params.add(to ? setCode : resetCode);
  }

  static String _sgr(List<String> params) {
    if (params.isEmpty) return '';
    return '\x1B[${params.join(';')}m';
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
