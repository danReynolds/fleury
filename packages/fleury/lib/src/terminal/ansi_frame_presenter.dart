// AnsiFramePresenter: the terminal write phase of the frame program —
// the full-repaint clear, the cell diff to ANSI bytes, the paint-flash
// debug overlay, and per-frame debug telemetry. Extracted verbatim from
// runApp's render closure; the ANSI byte golden
// (ansi_byte_parity_test) pins the output byte-for-byte.

import '../debug/debug_events.dart';
import '../debug/debug_state.dart';
import '../foundation/geometry.dart';
import '../rendering/ansi_render_target.dart';
import '../rendering/ansi_renderer.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../runtime/frame_driver.dart';
import '../runtime/tui_frame_loop.dart';
import 'terminal_image_encoder.dart';

/// Presents rendered frames as diffed ANSI bytes on [sink].
final class AnsiFramePresenter implements FramePresenter {
  AnsiFramePresenter({
    required AnsiSink sink,
    required AnsiRenderer renderer,
    required DebugController debug,
    TerminalImageEncoder? imageEncoder,
    CellRect? Function()? readCaret,
    AnsiRenderTarget Function()? readTarget,
    void Function(CellOffset position)? onCursorPositioned,
  }) : _sink = sink,
       _renderer = renderer,
       _debug = debug,
       _imageEncoder = imageEncoder,
       _readCaret = readCaret,
       _readTarget = readTarget,
       _onCursorPositioned = onCursorPositioned;

  final AnsiSink _sink;
  final AnsiRenderer _renderer;
  final DebugController _debug;

  /// Emits inline-image placements as the terminal's graphics protocol,
  /// or null when the terminal has none (glyph art needs no encoder).
  final TerminalImageEncoder? _imageEncoder;

  /// Reads the focused editable's latest painted caret. The native terminal
  /// keeps the hardware cursor hidden, but its position still anchors OS IME
  /// candidate windows. Reposition it after every diff because rendering (and
  /// inline-image placement) can leave the cursor at an unrelated cell.
  final CellRect? Function()? _readCaret;

  /// The host's current reserved region. Read once per frame so cell, caret,
  /// and debug output share one origin. The host releases the old region;
  /// this presenter only clears and paints the current one.
  final AnsiRenderTarget Function()? _readTarget;
  final void Function(CellOffset position)? _onCursorPositioned;
  AnsiRenderTarget? _lastTarget;
  CellOffset? _lastCursor;

  // Cells we tinted green in the previous frame's paint-flash pass.
  // Empty when paint-flash is off; populated each frame the flash is
  // active. Kept as flat indices (row * cols + col) to avoid per-cell
  // tuple allocation.
  List<int> _lastFlashedCells = const [];

  // Captured during presentFrame for the post-commit telemetry emit.
  Duration _phaseDiff = Duration.zero;
  int _dirtyCellCount = 0;
  CellRect? _dirtyBounds;
  List<int> _currentDirty = const [];

  @override
  bool get wantsPresentationPlan => false;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {
    final next = frame.next;
    final debugWatching = info.debugWatching;
    final target = _readTarget?.call() ?? const AnsiRenderTarget.fullScreen();
    if (target.isInline && _imageEncoder != null) {
      throw UnsupportedError(
        'Inline ANSI regions require glyph image rendering. Native image '
        'placement does not yet support a terminal row offset.',
      );
    }

    // One switch decides everything this frame needs from its damage, so a new
    // variant cannot be silently ignored the way an optional field could be.
    final damage = frame.damage;
    final targetChanged = _lastTarget != null && target != _lastTarget;
    final isFullRepaint = damage is FrameFullRepaint || targetChanged;
    // A moved region has no visible previous frame, even if the widget tree
    // and its buffers are unchanged. Do not mutate the loop's shared buffer.
    final prev = targetChanged && damage is! FrameFullRepaint
        ? CellBuffer(next.size)
        : frame.previous;
    final scrollUpRows = switch (damage) {
      FrameScrolled(:final scrollUpRows) => scrollUpRows,
      FrameFullRepaint() || FrameUnchanged() || FrameChanged() => null,
    };
    final hasChanges = isFullRepaint || damage is! FrameUnchanged;

    if (isFullRepaint) {
      _sink.write(target.clearSequence(next.size));
      _lastFlashedCells = const [];
    }
    // renderDiff against an all-empty prev (post-clear) produces the same
    // byte output as renderFull, so the same path handles first frame and
    // resize without a separate branch.
    final diffSw = debugWatching ? (Stopwatch()..start()) : null;
    // Debug mode captures every cell the diff emits. Paint flash uses the
    // same stream to overlay a tint, while captures/panels use it for
    // dirty-shape diagnostics.
    final currentDirty = debugWatching ? <int>[] : null;
    var dirtyCellCount = 0;
    int? dirtyMinCol;
    int? dirtyMinRow;
    int? dirtyMaxCol;
    int? dirtyMaxRow;

    void recordDirtyCell(int col, int row) {
      dirtyCellCount += 1;
      if (dirtyMinCol == null || col < dirtyMinCol!) dirtyMinCol = col;
      if (dirtyMaxCol == null || col > dirtyMaxCol!) dirtyMaxCol = col;
      if (dirtyMinRow == null || row < dirtyMinRow!) dirtyMinRow = row;
      if (dirtyMaxRow == null || row > dirtyMaxRow!) dirtyMaxRow = row;
      currentDirty?.add(row * next.size.cols + col);
    }

    // Image escapes ride the diff's trailer so text and pixels land in
    // one synchronized-output frame; the encoder diffs placements itself,
    // so an unchanged image contributes zero bytes.
    final imageTrailer =
        _imageEncoder?.encodeFrame(next, fullRepaint: isFullRepaint) ?? '';
    final cursor = _cursorPosition(_readCaret?.call(), next.size, target);
    final positionCursor =
        cursor != null &&
        (!target.isInline ||
            hasChanges ||
            cursor != _lastCursor ||
            _debug.paintFlash ||
            _lastFlashedCells.isNotEmpty);
    final caretTrailer = !positionCursor
        ? ''
        : '\x1B[${target.top + cursor.row + 1};${cursor.col + 1}H';
    _renderer.renderDiff(
      prev,
      next,
      _sink,
      dirtyBounds: isFullRepaint ? null : damage.diffBounds,
      scrollUpRows: isFullRepaint ? null : scrollUpRows,
      hasChanges: hasChanges,
      onDirtyCell: debugWatching ? recordDirtyCell : null,
      // Caret positioning must be last: graphics protocols can move the
      // terminal cursor while placing an image. Both trailers remain inside
      // the renderer's synchronized-output wrapper.
      trailer: '$imageTrailer$caretTrailer',
      target: target,
    );
    _phaseDiff = diffSw?.elapsed ?? Duration.zero;
    _dirtyCellCount = dirtyCellCount;
    _dirtyBounds = dirtyCellCount == 0
        ? null
        : CellRect.fromLTWH(
            dirtyMinCol!,
            dirtyMinRow!,
            dirtyMaxCol! - dirtyMinCol! + 1,
            dirtyMaxRow! - dirtyMinRow! + 1,
          );
    _currentDirty = currentDirty ?? const [];

    // Paint-flash overlay: emit ANSI directly to the sink (not into the
    // buffer) so the buffer state stays "the app's truth" and the diff
    // doesn't get confused next frame. Two phases:
    //   1. UN-tint cells from last frame's flash that didn't re-emit this
    //      frame — restores them to their real style.
    //   2. Tint this frame's dirty cells green.
    if (_debug.paintFlash) {
      emitPaintFlash(
        sink: _sink,
        next: next,
        currentDirty: _currentDirty,
        lastFlashed: _lastFlashedCells,
        target: target,
      );
      _lastFlashedCells = _currentDirty;
      // Paint flash writes directly after the synchronized frame and moves
      // the cursor. Preserve the IME anchor in debug mode too.
      if (caretTrailer.isNotEmpty) _sink.write(caretTrailer);
    } else if (_lastFlashedCells.isNotEmpty) {
      // Flash got toggled off — clear any lingering tints from the last
      // on-frame so the terminal doesn't carry stale highlights.
      emitPaintFlash(
        sink: _sink,
        next: next,
        currentDirty: const [],
        lastFlashed: _lastFlashedCells,
        target: target,
      );
      _lastFlashedCells = const [];
      if (caretTrailer.isNotEmpty) _sink.write(caretTrailer);
    }
    _lastTarget = target;
    _lastCursor = cursor;
    if (cursor != null) _onCursorPositioned?.call(cursor);
  }

  @override
  FrameDiffStats frameDiffStats(TuiRenderedFrame frame, FramePresentInfo info) {
    // The ANSI diff runs internally in presentFrame; report its measured cell
    // change set. The driver owns the rest of the FrameEvent.
    return FrameDiffStats(
      diff: _phaseDiff,
      dirtyCells: _dirtyCellCount,
      dirtyBounds: _dirtyBounds,
      dirtySpans: DirtySpanFrameStats.fromFlatCells(
        _currentDirty,
        columns: frame.next.size.cols,
      ),
    );
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {}
}

CellOffset? _cursorPosition(
  CellRect? caret,
  CellSize viewport,
  AnsiRenderTarget target,
) {
  if (viewport.isEmpty) return null;
  if (caret == null) {
    // A stable resting cursor gives the host an anchor after resize. An
    // editable's IME caret takes precedence and is tracked in the same way.
    return target.isInline ? CellOffset(0, viewport.rows - 1) : null;
  }
  final col = caret.left.clamp(0, viewport.cols - 1);
  final row = caret.top.clamp(0, viewport.rows - 1);
  return CellOffset(col, row);
}

/// Emits the paint-flash overlay bytes: un-tints last frame's flashed
/// cells that the diff didn't re-emit, then tints this frame's dirty
/// cells green. Moved verbatim from runApp.
void emitPaintFlash({
  required AnsiSink sink,
  required CellBuffer next,
  required List<int> currentDirty,
  required List<int> lastFlashed,
  AnsiRenderTarget target = const AnsiRenderTarget.fullScreen(),
}) {
  if (lastFlashed.isEmpty && currentDirty.isEmpty) return;
  final cols = next.size.cols;
  final dirtySet = currentDirty.toSet();
  final buf = StringBuffer();

  // Untint pass — restore underlying cell for previously-flashed cells
  // that the diff didn't re-emit (and so we couldn't re-tint cleanly).
  for (final idx in lastFlashed) {
    if (dirtySet.contains(idx)) continue;
    final col = idx % cols;
    final row = idx ~/ cols;
    if (row >= next.size.rows) continue;
    final cell = next.atColRow(col, row);
    if (cell.role == CellRole.continuation || cell.role == CellRole.overlay) {
      continue;
    }
    buf.write('\x1B[${target.top + row + 1};${col + 1}H');
    // Reset to clear any lingering bg, then emit the cell's real style.
    buf.write('\x1B[0m');
    final fg = cell.style.foreground;
    if (fg != null) {
      if (fg is RgbColor) {
        buf.write('\x1B[38;2;${fg.r};${fg.g};${fg.b}m');
      }
    }
    final bg = cell.style.background;
    if (bg != null) {
      if (bg is RgbColor) {
        buf.write('\x1B[48;2;${bg.r};${bg.g};${bg.b}m');
      }
    }
    buf.write(cell.role == CellRole.empty ? ' ' : cell.grapheme!);
  }

  // Tint pass — overlay green-bg on this frame's dirty cells.
  for (final idx in currentDirty) {
    final col = idx % cols;
    final row = idx ~/ cols;
    if (row >= next.size.rows) continue;
    final cell = next.atColRow(col, row);
    if (cell.role == CellRole.continuation || cell.role == CellRole.overlay) {
      continue;
    }
    buf.write('\x1B[${target.top + row + 1};${col + 1}H');
    buf.write('\x1B[42m'); // green background
    buf.write(cell.role == CellRole.empty ? ' ' : cell.grapheme!);
  }

  if (buf.isNotEmpty) {
    buf.write('\x1B[0m'); // leave terminal in a known style
    sink.write(buf.toString());
  }
}
