import '../foundation/geometry.dart';
import '../terminal/capabilities.dart';
import 'cell.dart';
import 'cell_buffer.dart';
import 'scroll_detection.dart';

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
  /// [ambiguousCharsAreWide] controls the defensive per-cell repositioning for
  /// ambiguous-width glyphs (box drawing, block elements, arrows — UAX #11
  /// "Ambiguous"). When `true` (the safe default), each such glyph is pinned
  /// with an absolute reposition so the row can't desync on a terminal/font
  /// that renders it two columns wide (the "Warp garble"). When a startup probe
  /// confirms the terminal renders ambiguous glyphs one column wide — the common
  /// case — the driver passes `false`, and the renderer emits compact contiguous
  /// runs instead (no per-cell cursor moves). See [AmbiguousCharWidth].
  const AnsiRenderer({
    this.colorMode = ColorMode.truecolor,
    this.synchronizedOutput = true,
    this.ambiguousCharsAreWide = true,
  });

  final ColorMode colorMode;
  final bool synchronizedOutput;
  final bool ambiguousCharsAreWide;

  static const _beginSyncUpdate = '\x1B[?2026h';
  static const _endSyncUpdate = '\x1B[?2026l';

  /// Diffs at or below this many bytes skip the BSU/ESU wrapper.
  ///
  /// Synchronized output exists to stop the terminal rendering a partially
  /// applied frame; a payload this small arrives (and paints) in one read,
  /// so the 16-byte wrapper is a third of the frame for nothing. Wire
  /// transcripts showed sync overhead at 3-5x peers on sparse-update
  /// scenarios.
  static const _syncSkipThresholdBytes = 48;

  /// Wraps [payload] in synchronized-output markers when warranted.
  String _wrapSync(String payload) {
    if (!synchronizedOutput || payload.length <= _syncSkipThresholdBytes) {
      return payload;
    }
    return '$_beginSyncUpdate$payload$_endSyncUpdate';
  }

  /// Writes the diff between [previous] and [next] to [sink].
  ///
  /// Both buffers must have the same size; an assertion fires otherwise.
  ///
  /// All bytes for the frame are accumulated into an internal
  /// [StringBuffer] and flushed to [sink] in a single `write` call.
  /// This reduces per-frame `sink.write` calls (and the IOSink queue
  /// operations they trigger downstream) from O(dirty cells) to one.
  /// [dirtyBounds], when provided, must conservatively contain every cell that
  /// can differ between [previous] and [next]. The renderer then scans only
  /// that rectangle and skips whole-screen passes (diff stats, scroll
  /// detection). Pass null whenever layout, removal, scrolling, or any other
  /// unsafe mutation can change cells outside the known painted region.
  ///
  /// [trailer] is appended verbatim after the cell diff, inside the same
  /// synchronized-output frame — the terminal image encoder's escape bytes
  /// ride here so pixels and text land atomically. A non-empty trailer is
  /// written even when no cell changed (an animation frame can swap image
  /// content without touching a single cell).
  void renderDiff(
    CellBuffer previous,
    CellBuffer next,
    AnsiSink sink, {
    CellRect? dirtyBounds,
    void Function(int col, int row)? onDirtyCell,
    String trailer = '',
  }) {
    assert(
      previous.size == next.size,
      'AnsiRenderer.renderDiff: buffer sizes differ '
      '(previous=${previous.size}, next=${next.size}).',
    );
    final diffBounds = dirtyBounds?.intersect(
      CellRect(offset: CellOffset.zero, size: next.size),
    );
    if (dirtyBounds != null && diffBounds == null) {
      if (trailer.isNotEmpty) sink.write(_wrapSync(trailer));
      return;
    }
    if (diffBounds != null) {
      final buf = StringBuffer();
      final anyDirty = _appendCellDiff(
        previous,
        next,
        buf,
        bounds: diffBounds,
        onDirtyCell: onDirtyCell,
      );
      if (!anyDirty && trailer.isEmpty) return;
      buf.write(trailer);
      sink.write(_wrapSync(buf.toString()));
      return;
    }
    final screenStats = screenDiffStats(previous, next);
    if (screenStats.dirtyCells == 0) {
      if (trailer.isNotEmpty) sink.write(_wrapSync(trailer));
      return;
    }

    final size = next.size;
    final scrollUpRows = detectBeneficialScrollUp(previous, next, screenStats);
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
      buf.write(_scrollUp(scrollUpRows));
      _appendCellDiff(scrolledPrevious, next, buf, onDirtyCell: onDirtyCell);
      buf.write(trailer);
      sink.write(_wrapSync(buf.toString()));
      return;
    }

    final buf = StringBuffer();
    final anyDirty = _appendCellDiff(
      previous,
      next,
      buf,
      onDirtyCell: onDirtyCell,
    );
    if (!anyDirty && trailer.isEmpty) return;
    buf.write(trailer);
    sink.write(_wrapSync(buf.toString()));
  }

  bool _appendCellDiff(
    CellBuffer previous,
    CellBuffer next,
    StringBuffer buf, {
    CellRect? bounds,
    void Function(int col, int row)? onDirtyCell,
  }) {
    final size = next.size;
    final top = bounds?.top ?? 0;
    final bottom = bounds?.bottom ?? size.rows;
    final left = bounds?.left ?? 0;
    final right = bounds?.right ?? size.cols;
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

      final oldCell = previous.atColRow(col, row);

      // Overlay cells are owned by an inline-image placement: the
      // presenter's image encoder paints pixels over the region
      // out-of-band. The cell itself is still CLEARED to a blank here, so
      // stale text/styled content can't survive in the image's letterbox
      // bars (which the encoder leaves unpainted) — the encoder's escapes
      // ride the frame trailer and draw on top. But an overlay over an
      // already-blank cell (empty, or a prior overlay from a static image)
      // needs nothing, so an unchanging image costs zero bytes.
      if (newCell.role == CellRole.overlay &&
          (oldCell.role == CellRole.empty ||
              oldCell.role == CellRole.overlay)) {
        return;
      }
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
      if (cursorRow == row &&
          fromCol != null &&
          fromCol < col &&
          !styleResetRequired) {
        final gap = _gapRewrite(
          previous,
          next,
          row,
          fromCol,
          col,
          emittedStyle,
        );
        if (gap != null) {
          final move = _cursorMove(cursorRow, cursorCol, row, col);
          if (gap.bytes.length < move.length) {
            buf.write(gap.bytes);
            cursorCol = col;
            if (gap.emittedSgr) {
              emittedStyle = gap.endStyle;
              styleBytesEmitted = true;
            }
          }
        }
      }
      if (cursorRow != row || cursorCol != col) {
        buf.write(_cursorMove(cursorRow, cursorCol, row, col));
        cursorRow = row;
        cursorCol = col;
      }

      // Style change. Emit a combined SGR delta where the terminal state
      // is known; fall back to reset+set where it is not. Empty-style
      // runs only emit a reset when transitioning out of a previously
      // emitted non-empty style.
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

      // Emit the cell's content. Empty and overlay cells both render as a
      // blank in the text layer (overlay pixels are painted over it by the
      // encoder trailer).
      final grapheme =
          (newCell.role == CellRole.empty || newCell.role == CellRole.overlay)
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

      // Invalidate the tracked cursor — forcing the next dirty cell to
      // reposition with an absolute CUP — whenever the cursor's resting column
      // is terminal-defined rather than known:
      //
      //  * A write to the last column: terminals without the `xenl`/pending-wrap
      //    quirk (e.g. Warp) wrap to the next line immediately, so a following
      //    `\r\n`/relative move would over-advance and cascade-corrupt the rows
      //    below. Always invalidated — the risk is independent of glyph width.
      //  * A grapheme whose DISPLAY WIDTH the terminal may disagree on, but ONLY
      //    when [ambiguousCharsAreWide]. Every non-ASCII glyph fleury emits for
      //    box drawing / bullets / arrows is East-Asian "Ambiguous"; a terminal
      //    (or font) that renders those two columns wide advances the cursor
      //    further than our one-column model, so the row desyncs. An absolute
      //    reposition for each following cell overwrites the overflow and pins
      //    every cell to its column regardless of how the terminal sizes them.
      //    On a terminal a startup probe confirmed renders them one column wide
      //    (the common case), this pinning is pure waste — a 48-cell block-fill
      //    run costs 48 cursor moves instead of one — so it's gated off and the
      //    run stays a compact contiguous write. ASCII runs are always exact.
      final isAscii = grapheme.length == 1 && grapheme.codeUnitAt(0) < 0x80;
      // Ambiguous-width: a non-ASCII glyph fleury lays out as one column that
      // isn't a known wide (CJK) char — a terminal/font may still render it two
      // columns wide. Wide chars (`isWide`) are unambiguous (both sides agree on
      // 2) and ASCII is unambiguous (1), so neither needs pinning; the rest do
      // only when the terminal is (or is assumed) ambiguous-as-wide.
      final needsWidthPin = ambiguousCharsAreWide && !isWide && !isAscii;
      if ((cursorCol != null && cursorCol! >= size.cols) || needsWidthPin) {
        cursorRow = null;
        cursorCol = null;
      }
    }

    for (var row = top; row < bottom; row++) {
      for (var col = left; col < right; col++) {
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
    final absolute = _absolutePosition(row, col);
    // Same-row moves are column-relative (CUF/CUB) and safe: the tracked column
    // is kept exact (last-column and ambiguous-width writes invalidate it, so a
    // following move re-pins absolutely). CROSS-ROW relative moves (`\r\n`, CNL,
    // CUU/CUD), however, are row-RELATIVE — they step from the terminal's
    // current row. If our tracked row ever drifts from the terminal's actual
    // row (a write that wrapped, an LF that scrolled at the bottom margin, an
    // ambiguous-width glyph the terminal advanced differently), every following
    // row move lands one row off and cascades: a shrunk row's new content gets
    // written a row away, stranding the previous row's tail on screen — the
    // fast-scroll "stale tail" garble (`NumberInput  ller`, `…oller`). An
    // absolute CUP for any row change re-pins the row and cannot drift; the cost
    // is ~1 byte/row over `\r\n`+CUF, and only on row transitions.
    if (fromRow != null && fromCol != null && fromRow == row) {
      return _shorter(absolute, _horizontalMove(fromCol, col));
    }
    return absolute;
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

  static String _scrollUp(int rows) => rows == 1 ? '\x1B[S' : '\x1B[${rows}S';

  /// ASCII text (with any required SGR transitions) that can be rewritten in
  /// place of a cursor move across an unchanged gap.
  ///
  /// Unlike a same-style-only rewrite, style boundaries inside the gap are
  /// allowed: the SGR delta bytes are included in the returned payload, and
  /// the caller compares total bytes against the cursor move. Wire
  /// transcripts show forward cursor moves are fleury's dominant overhead;
  /// peers win these scenarios by rewriting through lines rather than
  /// hopping precisely between dirty cells.
  ({String bytes, CellStyle endStyle, bool emittedSgr})? _gapRewrite(
    CellBuffer previous,
    CellBuffer next,
    int row,
    int fromCol,
    int toCol,
    CellStyle? emittedStyle,
  ) {
    if (fromCol >= toCol) return null;
    var currentStyle = emittedStyle ?? CellStyle.empty;
    var emittedSgr = false;
    final out = StringBuffer();
    for (var col = fromCol; col < toCol; col++) {
      final cell = next.atColRow(col, row);
      if (previous.atColRow(col, row) != cell) return null;
      switch (cell.role) {
        case CellRole.empty:
          // Rewriting an empty cell as a space is only exact when the
          // current style's background/inverse matches the cell's (empty)
          // style; require an exact style match like content cells.
          if (cell.style != currentStyle) {
            final encoded = _styleDelta(currentStyle, cell.style);
            if (encoded == null) return null;
            out.write(encoded);
            currentStyle = cell.style;
            emittedSgr = true;
          }
          out.write(' ');
        case CellRole.leading:
          final grapheme = cell.grapheme!;
          if (!_isAscii(grapheme)) return null;
          final isWide =
              col + 1 < next.size.cols &&
              next.atColRow(col + 1, row).role == CellRole.continuation;
          if (isWide) return null;
          if (cell.style != currentStyle) {
            final encoded = _styleDelta(currentStyle, cell.style);
            if (encoded == null) return null;
            out.write(encoded);
            currentStyle = cell.style;
            emittedSgr = true;
          }
          out.write(grapheme);
        case CellRole.continuation:
        case CellRole.overlay:
          return null;
      }
    }
    return (
      bytes: out.toString(),
      endStyle: currentStyle,
      emittedSgr: emittedSgr,
    );
  }

  /// SGR delta from [from] to [to] without a reset, or null when [to] is the
  /// empty style and a reset would be required (resets inside a gap rewrite
  /// would interact with [_appendCellDiff]'s reset bookkeeping).
  String? _styleDelta(CellStyle from, CellStyle to) {
    if (to == CellStyle.empty) {
      if (from == CellStyle.empty) return '';
      // Transitioning to empty needs a reset; keep gap rewrites reset-free.
      return null;
    }
    final encoded = _encodeStyleTransition(from, to, resetFirst: false);
    return encoded;
  }

  static bool _isAscii(String text) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) > 0x7F) return false;
    }
    return true;
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
