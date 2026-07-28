import 'package:fleury/fleury_host.dart';

/// Applies a decoded [plan] to the client's [CellBuffer] mirror and returns
/// the [FramePresentationPlan] the surface needs to repaint the touched
/// rows. The wire carries only changed cells; the mirror reconstructs the
/// full frame, and the dirty rows are rebuilt from it with the same span
/// builder the in-browser host uses — so the served frame renders
/// identically to a local one.
FramePresentationPlan applyRemotePlan(RemotePlan plan, CellBuffer mirror) {
  // The caller owns resizing: WireFrameSource reallocates the mirror at the
  // new size (and resizes the surface) BEFORE handing the plan here, so a
  // mismatch means the mirror was not prepared. Patches would then be clamped
  // into a wrongly-sized buffer and render silently wrong, which is why this
  // states the precondition instead of pretending to handle it.
  assert(
    plan.size == mirror.size,
    'mirror must be resized to the plan before applying it: '
    'plan ${plan.size.cols}x${plan.size.rows} vs '
    'mirror ${mirror.size.cols}x${mirror.size.rows}',
  );
  final touched = applyRemotePlanToBuffer(plan, mirror);
  final dirtyRows = plan.fullRepaint
      ? TuiDirtyRows.full(mirror.size.rows)
      : TuiDirtyRows.fromRows(touched, rowCount: mirror.size.rows);
  const builder = CellSpanBuilder();
  final rowModels = [
    for (final r in dirtyRows.rows)
      if (r >= 0 && r < mirror.size.rows) builder.buildRow(mirror, r),
  ];
  return FramePresentationPlan(
    reason: 'remote',
    size: mirror.size,
    // The wire carries rows, not bounds, so no variant here gets a bound —
    // legitimately absent, not "nothing changed". A scrolled frame's dirty
    // rows are conservative-full: the wire ships only the residual patches,
    // and a client cannot know which moved rows ended up identical, so it
    // reports all of them rather than mislabel the residue as the whole.
    damage: switch ((plan.fullRepaint, plan.scrollUpRows)) {
      (true, _) => const PresentationFullRepaint(),
      (false, final shift?) => PresentationScrolled(
        scrollUpRows: shift,
        dirtyRows: TuiDirtyRows.full(mirror.size.rows),
        dirtyBounds: null,
      ),
      (false, null) => PresentationChanged(
        dirtyRows: dirtyRows,
        dirtyBounds: null,
      ),
    },
    dirtyRowModels: rowModels,
    metricsChanged: false,
    spanBuildTime: Duration.zero,
  );
}
