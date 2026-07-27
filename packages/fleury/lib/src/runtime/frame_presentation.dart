// Presentation-plan computation, shared by every retained surface host.
//
// A plan reduces one rendered frame to "what the surface must apply":
// the dirty rows as span models, plus full-repaint and scroll-up hints.
// It is browser-agnostic — operating only on CellBuffers and the runtime
// frame — so the web DOM host and the native serve host build plans the
// same way. The visual `FrameSurface` that consumes a plan lives with the
// renderer (fleury_web); the plan and its planner live here.

import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/cell_span.dart';
import '../rendering/scroll_detection.dart';
import 'tui_frame_loop.dart';

/// Presenter-ready frame data computed once by the host.
final class FramePresentationPlan {
  const FramePresentationPlan({
    required this.reason,
    required this.fullRepaint,
    required this.size,
    required this.damage,
    required this.dirtyRowModels,
    required this.metricsChanged,
    required this.dirtyRowDiffTime,
    required this.spanBuildTime,
    this.scrollUpRows,
  });

  final String reason;
  final bool fullRepaint;
  final CellSize size;
  final FramePresentationDamage damage;
  final List<RowSpanModel> dirtyRowModels;
  final bool metricsChanged;
  final Duration dirtyRowDiffTime;
  final Duration spanBuildTime;

  /// When non-null, the frame is a detected upward scroll: the surface moves
  /// its first [scrollUpRows] retained row elements to the bottom and then
  /// applies [dirtyRowModels], which cover only the residual rows (entering
  /// rows plus rows that changed beyond the shift).
  ///
  /// [damage] stays the TRUE dirty set (everything moved), so semantic
  /// coverage and diff consumers remain exact.
  final int? scrollUpRows;

  int get dirtyRowCount => damage.dirtyRows.dirtyRowCount;

  int get dirtyCellEstimate => dirtyRowCount * size.cols;

  int get spanCount =>
      dirtyRowModels.fold(0, (count, row) => count + row.runs.length);
}

/// Damage data normalized for surface presenters.
final class FramePresentationDamage {
  const FramePresentationDamage({
    required this.fullRepaint,
    required this.dirtyBounds,
    required this.dirtyRows,
    required this.source,
  });

  final bool fullRepaint;
  final CellRect? dirtyBounds;
  final TuiDirtyRows dirtyRows;
  final FrameDamageSource source;
}

enum FrameDamageSource {
  /// The frame loop derived the exact changed set by comparing buffers.
  paintDamage,
  fullRepaint,

  /// The frame request skipped rendering: no frame work was pending and the
  /// committed front buffer was still exact.
  none,
}

/// Builds [FramePresentationPlan]s from shared runtime frame output.
final class FramePresentationPlanner {
  const FramePresentationPlanner({this.spanBuilder = const CellSpanBuilder()});

  final CellSpanBuilder spanBuilder;

  FramePresentationPlan build({
    required String reason,
    required TuiRenderedFrame frame,
    bool metricsChanged = false,
  }) {
    final runtimeDamage = frame.damage;
    final dirtyRowsResult = _dirtyRowsForFrame(frame);
    final dirtyRows = dirtyRowsResult.rows;
    final fullRepaint = runtimeDamage is FrameFullRepaint;
    final damage = FramePresentationDamage(
      fullRepaint: fullRepaint,
      dirtyBounds: runtimeDamage.diffBounds,
      dirtyRows: dirtyRows,
      source: fullRepaint
          ? FrameDamageSource.fullRepaint
          : FrameDamageSource.paintDamage,
    );

    // The frame loop already decided whether this is a beneficial scroll, using
    // the counts its diff produced. Re-deriving it here would rescan both
    // buffers — and the old trigger (`dirtyRows.isFull`) silently stopped
    // firing once damage became exact, because one unchanged row is enough to
    // make a clean scroll not-full.
    final scrollUpRows = switch (runtimeDamage) {
      FrameScrolled(:final scrollUpRows) => scrollUpRows,
      FrameFullRepaint() || FrameUnchanged() || FrameChanged() => null,
    };
    final rowsToBuild = scrollUpRows == null
        ? dirtyRows
        : _residualScrollRows(frame.previous, frame.next, scrollUpRows);

    final spanBuildStopwatch = Stopwatch()..start();
    final dirtyRowModels = spanBuilder.buildDirtyRows(frame.next, rowsToBuild);
    spanBuildStopwatch.stop();

    return FramePresentationPlan(
      reason: reason,
      fullRepaint: fullRepaint,
      size: frame.next.size,
      damage: damage,
      dirtyRowModels: dirtyRowModels,
      metricsChanged: metricsChanged,
      dirtyRowDiffTime: dirtyRowsResult.diffTime,
      spanBuildTime: spanBuildStopwatch.elapsed,
      scrollUpRows: scrollUpRows,
    );
  }

  /// Rows that still need their spans rebuilt after scrolling up by [shift]:
  /// every entering row at the bottom (the moved elements carry stale spans)
  /// plus any retained row whose content changed beyond the shift.
  TuiDirtyRows _residualScrollRows(
    CellBuffer previous,
    CellBuffer next,
    int shift,
  ) {
    final rows = next.size.rows;
    final residual = <int>[];
    for (var row = 0; row < rows - shift; row++) {
      if (!rowsEqual(previous, row + shift, next, row)) residual.add(row);
    }
    for (var row = rows - shift; row < rows; row++) {
      residual.add(row);
    }
    return TuiDirtyRows.fromRows(residual, rowCount: rows);
  }

  _DirtyRowsResult _dirtyRowsForFrame(TuiRenderedFrame frame) {
    // The frame loop derives the exact changed set while it still has both
    // buffers hot, so there is nothing left to discover here.
    return _DirtyRowsResult(
      rows: frame.damage.dirtyRowsFor(frame.next.size),
      diffTime: Duration.zero,
    );
  }
}

final class _DirtyRowsResult {
  const _DirtyRowsResult({required this.rows, required this.diffTime});

  final TuiDirtyRows rows;
  final Duration diffTime;
}
