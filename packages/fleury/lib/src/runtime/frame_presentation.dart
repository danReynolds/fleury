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
  // Not const: [dirtyRows] is resolved once, lazily, against this plan's size.
  FramePresentationPlan({
    required this.reason,
    required this.size,
    required this.damage,
    required this.dirtyRowModels,
    required this.metricsChanged,
    required this.dirtyRowDiffTime,
    required this.spanBuildTime,
  });

  final String reason;
  final CellSize size;
  final FramePresentationDamage damage;
  final List<RowSpanModel> dirtyRowModels;
  final bool metricsChanged;
  final Duration dirtyRowDiffTime;
  final Duration spanBuildTime;

  /// Whether the presenter must repaint everything.
  ///
  /// Derived from [damage], not stored alongside it. This fact used to live in
  /// three places at once — here, on the damage, and again as the damage's
  /// `source` — all three set from one decision at every construction site.
  /// Three copies of one fact is three chances to disagree, and one of them
  /// was already dead: written at all three sites, read by nothing.
  bool get fullRepaint => switch (damage) {
    PresentationFullRepaint() => true,
    PresentationChanged() || PresentationScrolled() => false,
  };

  /// The upward shift to apply before [dirtyRowModels], when the frame is a
  /// detected scroll.
  ///
  /// Derived, not stored: scroll used to be a nullable field here, which let a
  /// full repaint carry a shift — a pairing every presenter had to remember to
  /// ignore, held together by an assert. As a variant of [damage] the pairing
  /// cannot be written.
  int? get scrollUpRows => switch (damage) {
    PresentationScrolled(:final scrollUpRows) => scrollUpRows,
    PresentationFullRepaint() || PresentationChanged() => null,
  };

  /// The rows a presenter must re-apply, resolved against THIS plan's [size].
  ///
  /// Resolved here rather than stored on the damage: a full repaint means
  /// "every row of the frame being presented", and the frame's size is the
  /// plan's. Letting the damage carry its own copy of the size would put the
  /// same fact in two places again — with the damage's copy silently winning
  /// the row count.
  late final TuiDirtyRows dirtyRows = switch (damage) {
    // A full repaint means every row of THIS frame, so it expands here, where
    // the size lives. Letting the variant answer would mean handing it a size
    // — and a variant holding a size is the duplicate this type just shed.
    PresentationFullRepaint() => TuiDirtyRows.full(size.rows),
    // Already absolute, measured by whoever built the damage.
    PresentationChanged(:final dirtyRows) => dirtyRows,
    PresentationScrolled(:final dirtyRows) => dirtyRows,
  };

  int get dirtyRowCount => dirtyRows.dirtyRowCount;

  int get dirtyCellEstimate => dirtyRowCount * size.cols;

  int get spanCount =>
      dirtyRowModels.fold(0, (count, row) => count + row.runs.length);
}

/// Damage data normalized for surface presenters.
///
/// Sealed for ONE invariant that flags could not hold: a full repaint always
/// dirties every row. That pairing used to be restated by hand at every
/// construction site, and this type is exported host SPI, so the fourth site
/// was never going to be one of ours. [PresentationFullRepaint] has no rows to
/// pass — the plan expands them — so the mismatch cannot be written.
///
/// What that does and does not protect. [FramePresentationPlan.dirtyRows]
/// drives the wire's dirty-row hint and semantic coverage, so a full repaint
/// declaring partial rows used to desync a peer mirror or throw out of
/// coverage. Which rows a DOM surface actually paints comes from
/// `dirtyRowModels`, which this type has no say over — though the variant does
/// reach the DOM indirectly, since [FramePresentationPlan.fullRepaint] gates
/// its scroll path.
///
/// The carve deliberately differs from the loop-level `TuiFrameDamage` it is
/// built from. There, [dirtyBounds] being absent MEANS "nothing changed", so
/// the variants discriminate on it. Here a bound is an optional hint that the
/// wire simply does not carry — a remote frame has real dirty rows and no
/// bounds — so bounds stay nullable INSIDE the changed variant and the rows
/// are the authority. Copying the upstream shape literally would have made
/// "changed, rows known, bounds unknown" inexpressible.
sealed class FramePresentationDamage {
  const FramePresentationDamage();

  /// A bound a diffing presenter may restrict itself to, when one is known.
  ///
  /// Null means "no bound available", never "nothing changed".
  CellRect? get dirtyBounds;
}

/// Present everything: there was no comparable previous frame, or a host
/// resynced the surface from scratch.
final class PresentationFullRepaint extends FramePresentationDamage {
  const PresentationFullRepaint();

  /// Carries no rows at all: [FramePresentationPlan.dirtyRows] expands this to
  /// every row of the frame, so a full repaint cannot be handed partial ones.
  ///
  /// Degenerate at zero rows: `TuiDirtyRows.full(0)` is empty, so a
  /// zero-height frame would report a full repaint with nothing dirty. No plan
  /// is built for an empty size, so this is unreachable in-tree.
  @override
  CellRect? get dirtyBounds => null;
}

/// The frame is a detected upward scroll: shift the surface's first
/// [scrollUpRows] retained rows to the bottom, then apply the plan's
/// [FramePresentationPlan.dirtyRowModels] — which cover only the residue
/// (entering rows plus rows that changed beyond the shift).
///
/// [dirtyRows] is NOT the residue. It is the full set of rows a non-shifting
/// consumer must treat as changed — the wire's dirty-row hint and semantic
/// coverage read it, and handing them the residue would leave every moved row
/// unaccounted for. On the planner path this is the diff's exact set; a
/// client rebuilding from the wire cannot know exactness and reports every
/// row instead — conservative, never wrong. As with [PresentationChanged],
/// nothing checks the rows against the plan's size.
final class PresentationScrolled extends FramePresentationDamage {
  const PresentationScrolled({
    required this.scrollUpRows,
    required this.dirtyRows,
    required this.dirtyBounds,
  }) : assert(scrollUpRows > 0, 'a scroll by zero rows is not a scroll');

  final int scrollUpRows;

  final TuiDirtyRows dirtyRows;

  @override
  final CellRect? dirtyBounds;
}

/// Present the rows the producer measured; [dirtyBounds] narrows that further
/// when known.
final class PresentationChanged extends FramePresentationDamage {
  const PresentationChanged({
    required this.dirtyRows,
    required this.dirtyBounds,
  });

  /// The rows the producer measured, already absolute. Nothing checks them
  /// against the plan's size — a producer reporting rows beyond the frame is a
  /// bug at the producer, and the wire clamps rather than crashes.
  final TuiDirtyRows dirtyRows;

  /// Required, not defaulted: a site that means to supply a bound and forgets
  /// should not compile.
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
    // One construction per loop-damage variant, 1:1. The scroll decision is
    // the loop's — it had both buffers and the diff's counts in hand.
    // Re-deriving it here would rescan both buffers, and the old trigger
    // (`dirtyRows.isFull`) silently stopped firing once damage became exact,
    // because one unchanged row is enough to make a clean scroll not-full.
    final damage = switch (runtimeDamage) {
      FrameFullRepaint() => const PresentationFullRepaint(),
      FrameUnchanged() || FrameChanged() => PresentationChanged(
        dirtyRows: dirtyRows,
        dirtyBounds: runtimeDamage.diffBounds,
      ),
      FrameScrolled(:final scrollUpRows) => PresentationScrolled(
        scrollUpRows: scrollUpRows,
        dirtyRows: dirtyRows,
        dirtyBounds: runtimeDamage.diffBounds,
      ),
    };
    final rowsToBuild = switch (damage) {
      PresentationScrolled(:final scrollUpRows) => _residualScrollRows(
        frame.previous,
        frame.next,
        scrollUpRows,
      ),
      PresentationFullRepaint() || PresentationChanged() => dirtyRows,
    };

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
