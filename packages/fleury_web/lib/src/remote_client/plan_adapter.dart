import 'package:fleury/fleury_host.dart';


/// Applies a decoded [plan] to the client's [CellBuffer] mirror and returns
/// the [FramePresentationPlan] the surface needs to repaint the touched
/// rows. The wire carries only changed cells; the mirror reconstructs the
/// full frame, and the dirty rows are rebuilt from it with the same span
/// builder the in-browser host uses — so the served frame renders
/// identically to a local one.
FramePresentationPlan applyRemotePlan(RemotePlan plan, CellBuffer mirror) {
  if (plan.size != mirror.size) {
    // Caller resized the mirror; treat as a full repaint of the new size.
  }
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
    fullRepaint: plan.fullRepaint,
    size: mirror.size,
    damage: FramePresentationDamage(
      fullRepaint: plan.fullRepaint,
      requiresFullDiff: plan.fullRepaint,
      dirtyBounds: null,
      dirtyRows: dirtyRows,
      source: plan.fullRepaint
          ? FrameDamageSource.fullRepaint
          : FrameDamageSource.paintDamage,
    ),
    dirtyRowModels: rowModels,
    metricsChanged: false,
    dirtyRowDiffTime: Duration.zero,
    spanBuildTime: Duration.zero,
    scrollUpRows: plan.scrollUpRows,
  );
}
