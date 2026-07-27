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
    required this.size,
    required this.damage,
    required this.dirtyRowModels,
    required this.metricsChanged,
    required this.dirtyRowDiffTime,
    required this.spanBuildTime,
    this.scrollUpRows,
  });

  final String reason;
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

  /// Whether the presenter must repaint everything.
  ///
  /// Derived from [damage], not stored alongside it. This fact used to live in
  /// three places at once — here, on the damage, and again as the damage's
  /// `source` — all three set from one decision at every construction site.
  /// Three copies of one fact is three chances to disagree, and one of them
  /// was already dead: written at all three sites, read by nothing.
  bool get fullRepaint => damage is PresentationFullRepaint;

  int get dirtyRowCount => damage.dirtyRows.dirtyRowCount;

  int get dirtyCellEstimate => dirtyRowCount * size.cols;

  int get spanCount =>
      dirtyRowModels.fold(0, (count, row) => count + row.runs.length);
}

/// Damage data normalized for surface presenters.
///
/// Sealed for ONE invariant that flags could not hold: a full repaint always
/// dirties every row. That pairing used to be restated by hand at every
/// construction site — and the type is exported host SPI, so a site that
/// paired "full repaint" with partial rows would present a partially stale
/// frame with no error anywhere. [PresentationFullRepaint] computes its rows
/// instead of accepting them, making the mismatch unrepresentable.
///
/// The carve deliberately differs from the loop-level `TuiFrameDamage` it is
/// built from. There, [dirtyBounds] being absent MEANS "nothing changed", so
/// the variants discriminate on it. Here a bound is an optional hint that the
/// wire simply does not carry — a remote frame has real [dirtyRows] and no
/// bounds — so bounds stay nullable INSIDE the changed variant and
/// [dirtyRows] is the authority. Copying the upstream shape literally would
/// have made "changed, rows known, bounds unknown" inexpressible.
sealed class FramePresentationDamage {
  const FramePresentationDamage();

  /// The rows a presenter must re-apply. Authoritative.
  TuiDirtyRows get dirtyRows;

  /// A bound a diffing presenter may restrict itself to, when one is known.
  ///
  /// Null means "no bound available", never "nothing changed".
  CellRect? get dirtyBounds;
}

/// Present everything: there was no comparable previous frame, or a host
/// resynced the surface from scratch.
final class PresentationFullRepaint extends FramePresentationDamage {
  const PresentationFullRepaint(this.size);

  final CellSize size;

  /// Computed, not accepted — a full repaint cannot be given partial rows.
  @override
  TuiDirtyRows get dirtyRows => TuiDirtyRows.full(size.rows);

  @override
  CellRect? get dirtyBounds => null;
}

/// Present [dirtyRows]; [dirtyBounds] narrows that further when known.
final class PresentationChanged extends FramePresentationDamage {
  const PresentationChanged({required this.dirtyRows, this.dirtyBounds});

  @override
  final TuiDirtyRows dirtyRows;

  @override
  final CellRect? dirtyBounds;
}

/// How a frame's damage was arrived at — a TELEMETRY vocabulary, not plan
/// state.
///
/// A plan no longer carries one: "is this a full repaint" is answered by the
/// damage's variant, so storing this alongside it would restore the second
/// copy this type was flattened to remove. Instrumentation keeps it because it
/// reports on frames a plan cannot describe (see [none]).
enum FrameDamageSource {
  /// The frame loop derived the exact changed set by comparing buffers.
  paintDamage,
  fullRepaint,

  /// The frame request skipped rendering: no frame work was pending and the
  /// committed front buffer was still exact. No plan is built for these.
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
    final damage = fullRepaint
        ? PresentationFullRepaint(frame.next.size)
        : PresentationChanged(
            dirtyRows: dirtyRows,
            dirtyBounds: runtimeDamage.diffBounds,
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
