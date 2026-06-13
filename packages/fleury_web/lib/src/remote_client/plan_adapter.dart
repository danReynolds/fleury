import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_codec.dart' show RemotePlan;

import '../frame_presentation.dart';

/// Adapts a wire [RemotePlan] into the [FramePresentationPlan] that a
/// [FrameSurface] consumes.
///
/// The surface's `present` reads only the plan (size, dirty rows,
/// scroll-up, full-repaint) — never the previous/next buffers — so a
/// client that receives plans off the wire can drive the exact same DOM
/// surface the in-browser host uses. The diagnostic fields (timings) are
/// zero; the damage is reconstructed from the row models the plan carries.
FramePresentationPlan remotePlanToPresentation(RemotePlan plan) {
  final rowIndices = plan.rows.map((r) => r.row);
  final dirtyRows = plan.fullRepaint
      ? TuiDirtyRows.full(plan.size.rows)
      : TuiDirtyRows.fromRows(rowIndices, rowCount: plan.size.rows);
  return FramePresentationPlan(
    reason: 'remote',
    fullRepaint: plan.fullRepaint,
    size: plan.size,
    damage: FramePresentationDamage(
      fullRepaint: plan.fullRepaint,
      requiresFullDiff: plan.fullRepaint,
      dirtyBounds: null,
      dirtyRows: dirtyRows,
      source: plan.fullRepaint
          ? FrameDamageSource.fullRepaint
          : FrameDamageSource.paintDamage,
    ),
    dirtyRowModels: plan.rows,
    metricsChanged: false,
    dirtyRowDiffTime: Duration.zero,
    spanBuildTime: Duration.zero,
    scrollUpRows: plan.scrollUpRows,
  );
}

/// A reusable empty buffer to pass as the surface's `previous`/`next` —
/// the surface ignores them, but the signature requires a [CellBuffer].
CellBuffer emptyClientBuffer(CellSize size) => CellBuffer(size);
