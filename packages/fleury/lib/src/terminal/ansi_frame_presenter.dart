// AnsiFramePresenter: the terminal write phase of the frame program —
// the full-repaint clear, the cell diff to ANSI bytes, the paint-flash
// debug overlay, and per-frame debug telemetry. Extracted verbatim from
// runApp's render closure; the ANSI byte golden
// (ansi_byte_parity_test) pins the output byte-for-byte.

import '../debug/debug_events.dart';
import '../debug/debug_invalidation.dart';
import '../debug/debug_state.dart';
import '../foundation/geometry.dart';
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
  }) : _sink = sink,
       _renderer = renderer,
       _debug = debug,
       _imageEncoder = imageEncoder;

  final AnsiSink _sink;
  final AnsiRenderer _renderer;
  final DebugController _debug;

  /// Emits inline-image placements as the terminal's graphics protocol,
  /// or null when the terminal has none (glyph art needs no encoder).
  final TerminalImageEncoder? _imageEncoder;

  var _frameCounter = 0;
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
    final prev = frame.previous;
    final next = frame.next;
    final debugWatching = info.debugWatching;

    if (frame.damage.fullRepaint) {
      // Clear screen + home so any stale content (from the alt-screen
      // switch, terminal scrollback, or a previous size) doesn't leak.
      _sink.write('\x1B[2J\x1B[H');
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
        _imageEncoder?.encodeFrame(
          next,
          fullRepaint: frame.damage.fullRepaint,
        ) ??
        '';
    _renderer.renderDiff(
      prev,
      next,
      _sink,
      dirtyBounds: frame.damage.diffBounds,
      onDirtyCell: debugWatching ? recordDirtyCell : null,
      trailer: imageTrailer,
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
      );
      _lastFlashedCells = _currentDirty;
    } else if (_lastFlashedCells.isNotEmpty) {
      // Flash got toggled off — clear any lingering tints from the last
      // on-frame so the terminal doesn't carry stale highlights.
      emitPaintFlash(
        sink: _sink,
        next: next,
        currentDirty: const [],
        lastFlashed: _lastFlashedCells,
      );
      _lastFlashedCells = const [];
    }
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {
    if (info.debugWatching) {
      _frameCounter++;
      final dirtySources = DebugInvalidations.drain();
      DebugEvents.emitFrame(
        FrameEvent(
          frameNumber: _frameCounter,
          reason: info.reason,
          build: info.phaseBuild,
          layout: info.phaseLayout,
          paint: info.phasePaint,
          diff: _phaseDiff,
          dirtyCells: _dirtyCellCount,
          dirtyBounds: _dirtyBounds,
          dirtySpans: DirtySpanFrameStats.fromFlatCells(
            _currentDirty,
            columns: frame.next.size.cols,
          ),
          dirtySources: dirtySources,
          layoutStats: info.layoutStats,
          repaintBoundaries: info.repaintBoundaryStats,
          bufferSize: frame.next.size,
        ),
      );
    } else {
      DebugInvalidations.reset();
    }
  }
}

/// Emits the paint-flash overlay bytes: un-tints last frame's flashed
/// cells that the diff didn't re-emit, then tints this frame's dirty
/// cells green. Moved verbatim from runApp.
void emitPaintFlash({
  required AnsiSink sink,
  required CellBuffer next,
  required List<int> currentDirty,
  required List<int> lastFlashed,
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
    buf.write('\x1B[${row + 1};${col + 1}H');
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
    buf.write('\x1B[${row + 1};${col + 1}H');
    buf.write('\x1B[42m'); // green background
    buf.write(cell.role == CellRole.empty ? ' ' : cell.grapheme!);
  }

  if (buf.isNotEmpty) {
    buf.write('\x1B[0m'); // leave terminal in a known style
    sink.write(buf.toString());
  }
}
