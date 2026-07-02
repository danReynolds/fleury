import 'package:fleury/fleury_host.dart';

import 'metrics/cell_metrics.dart';

// The presentation plan and its planner moved to fleury core
// (`src/runtime/frame_presentation.dart`) so the native serve host can
// build plans without a browser dependency. They are re-exported here so
// the visual surface code keeps a single import.
export 'package:fleury/fleury_host.dart'
    show
        FrameDamageSource,
        FramePresentationDamage,
        FramePresentationPlan,
        FramePresentationPlanner;

/// Visual frame surface implemented by browser renderers.
///
/// This is intentionally visual-only. Input, metrics, clipboard, semantics,
/// and scheduling stay in the host/runtime layer.
abstract interface class FrameSurface {
  CellSize get size;
  WebSurfaceCapabilities get capabilities;

  FrameSurfacePresentationStats present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  );

  void resize(CellSize size, {MeasuredCellBox? metrics});
  Future<void> dispose();
}

/// Capabilities of a web visual surface.
///
/// Inline images are deliberately absent: the surface is text/grid only,
/// and true-pixel image placements are rendered by the host-assembled
/// `InlineImageOverlay` layer above it.
final class WebSurfaceCapabilities {
  const WebSurfaceCapabilities({
    this.supportsTrueColor = true,
    this.supportsSemanticLinks = false,
    this.supportsGlyphOverlay = false,
  });

  final bool supportsTrueColor;
  final bool supportsSemanticLinks;
  final bool supportsGlyphOverlay;
}

/// Count data reported by a visual [FrameSurface] after one presentation.
final class FrameSurfacePresentationStats {
  const FrameSurfacePresentationStats({
    required this.rowsReplaced,
    required this.domNodesCreated,
    this.styleCacheHits = 0,
    this.styleCacheMisses = 0,
    this.widthCacheHits = 0,
    this.widthCacheMisses = 0,
  });

  static const none = FrameSurfacePresentationStats(
    rowsReplaced: 0,
    domNodesCreated: 0,
  );

  final int rowsReplaced;
  final int domNodesCreated;
  final int styleCacheHits;
  final int styleCacheMisses;
  final int widthCacheHits;
  final int widthCacheMisses;
}
