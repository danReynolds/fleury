import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_object.dart';

/// Repaint-boundary activity observed while painting one frame.
final class RepaintBoundaryFrameStats {
  const RepaintBoundaryFrameStats({
    required this.boundaryCount,
    required this.repaintedCount,
    required this.cachedCount,
    required this.emptyCount,
    required this.copiedCellCount,
  });

  static const empty = RepaintBoundaryFrameStats(
    boundaryCount: 0,
    repaintedCount: 0,
    cachedCount: 0,
    emptyCount: 0,
    copiedCellCount: 0,
  );

  final int boundaryCount;
  final int repaintedCount;
  final int cachedCount;
  final int emptyCount;
  final int copiedCellCount;

  bool get hasBoundaries => boundaryCount > 0;
}

/// Debug-only collector for repaint-boundary activity.
///
/// The runtime enables this only when a debug surface is listening, so normal
/// application frames do not pay for per-boundary diagnostics.
final class RepaintBoundaryDebugStats {
  RepaintBoundaryDebugStats._();

  static bool _enabled = false;
  static int _boundaryCount = 0;
  static int _repaintedCount = 0;
  static int _cachedCount = 0;
  static int _emptyCount = 0;
  static int _copiedCellCount = 0;

  static void beginFrame({required bool enabled}) {
    _enabled = enabled;
    _resetCounters();
  }

  static RepaintBoundaryFrameStats takeFrameStats() {
    if (!_enabled) return RepaintBoundaryFrameStats.empty;
    final stats = RepaintBoundaryFrameStats(
      boundaryCount: _boundaryCount,
      repaintedCount: _repaintedCount,
      cachedCount: _cachedCount,
      emptyCount: _emptyCount,
      copiedCellCount: _copiedCellCount,
    );
    _resetCounters();
    return stats;
  }

  static void recordPaint({
    required bool repainted,
    required CellRect? copiedBounds,
  }) {
    if (!_enabled) return;
    _boundaryCount += 1;
    if (repainted) {
      _repaintedCount += 1;
    } else {
      _cachedCount += 1;
    }
    if (copiedBounds == null) {
      _emptyCount += 1;
    } else {
      _copiedCellCount += copiedBounds.size.cols * copiedBounds.size.rows;
    }
  }

  static void _resetCounters() {
    _boundaryCount = 0;
    _repaintedCount = 0;
    _cachedCount = 0;
    _emptyCount = 0;
    _copiedCellCount = 0;
  }
}

/// A render object that owns a [CellBuffer] cache for its subtree's paint.
///
/// On the first frame (and any frame after something inside it changed), the
/// boundary repaints its subtree into the cache and clears [_needsPaint]. On
/// subsequent frames it skips the subtree walk entirely and blits the cache
/// into the destination — a single bulk copy instead of a recursive paint
/// chain.
///
/// This is a CPU paint-memoization, NOT Flutter's GPU compositing layer —
/// there is no layer tree here, and it does not isolate the subtree from
/// repaint the way a GPU layer does. Two limits to keep in mind: layout still
/// runs for the whole tree every frame (this caches paint only), and the
/// `AnsiRenderer` still diffs every cell every frame (the blit just
/// repopulates the cells the diff then re-examines).
///
/// The win is the skipped paint *walk*: on a localized update, a boundary'd
/// subtree blits its cache instead of re-running its paint chain. Measured on
/// the paint-walk probe this is ~3x even for trivially cheap rows and 6-16x for
/// styled ones — the walk over N siblings costs more than blitting N-1 caches
/// regardless of per-row cost, so the historical "neutral for cheap subtrees"
/// guidance held only for a SINGLE boundary in isolation, not for the
/// one-of-many-changes shape [ListView] auto-wraps. The cost is one reused
/// cache buffer per boundary (bounded by what's on screen). Reach for a direct
/// boundary when a subtree's neighbour churns and it doesn't; the list case is
/// handled for you.
///
/// The boundary is opaque to its caller: parents call `paint(buffer, offset)`
/// as usual; the cache discipline is internal. Use the [RepaintBoundary]
/// widget to wrap subtrees that are expensive to paint and change rarely.
class RenderRepaintBoundary extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderObject? _child;
  CellBuffer? _cache;
  CellRect? _cacheBounds;
  List<SemanticPaintBoundsRecord> _semanticBounds =
      const <SemanticPaintBoundsRecord>[];
  List<PointerRegionRecord> _pointerRegions = const <PointerRegionRecord>[];

  @override
  bool get isRepaintBoundary => true;

  @override
  RenderObject? get child => _child;

  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    final old = _child;
    if (old != null) dropChild(old);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(const CellSize(0, 0));
    return c.layout(constraints);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final c = _child;
    if (c == null) return;
    final s = size;
    if (s.cols == 0 || s.rows == 0) return;

    var cache = _cache;
    if (cache == null || cache.size != s) {
      cache = CellBuffer(s);
      _cache = cache;
      needsPaint = true;
    }

    var repainted = false;
    if (needsPaint) {
      final targetCache = cache;
      final capturedSemanticBounds = <SemanticPaintBoundsRecord>[];
      final capturedPointerRegions = <PointerRegionRecord>[];
      cache.withoutDamageTracking(() {
        targetCache.clear();
        SemanticPaintBoundsCapture.collect(capturedSemanticBounds, () {
          PointerRegionCapture.collect(capturedPointerRegions, () {
            c.paint(
              targetCache,
              CellOffset.zero,
              screenOffset: screenOffset ?? offset,
              clipRect: clipRect,
            );
          });
        });
      });
      _semanticBounds = List<SemanticPaintBoundsRecord>.unmodifiable(
        capturedSemanticBounds,
      );
      _pointerRegions = List<PointerRegionRecord>.unmodifiable(
        capturedPointerRegions,
      );
      // Tighten the next blit to just the non-empty cells. For dense
      // subtrees that's the full size (no penalty); for sparse subtrees
      // this avoids copying a buffer of mostly-empty cells.
      _cacheBounds = cache.boundingBoxOfNonEmpty();
      needsPaint = false;
      repainted = true;
    } else {
      _replaySemanticBounds(
        paintOffset: offset,
        screenOffset: screenOffset ?? offset,
        clipRect: clipRect,
      );
      _replayPointerRegions(
        paintOffset: offset,
        screenOffset: screenOffset ?? offset,
      );
    }

    final bounds = _cacheBounds;
    RepaintBoundaryDebugStats.recordPaint(
      repainted: repainted,
      copiedBounds: bounds,
    );
    if (repainted) {
      _publishSemanticBounds(paintOffset: offset);
      _publishPointerRegions(paintOffset: offset);
    }
    if (bounds == null) return; // entirely empty cache — nothing to draw
    final cacheForCopy = cache;
    final destOffset = CellOffset(
      offset.col + bounds.offset.col,
      offset.row + bounds.offset.row,
    );
    if (repainted) {
      buffer.copyRectFrom(cacheForCopy, bounds, destOffset);
    } else {
      buffer.withoutDamageTracking(
        () => buffer.copyRectFrom(cacheForCopy, bounds, destOffset),
      );
    }
  }

  void _publishSemanticBounds({required CellOffset paintOffset}) {
    for (final record in _semanticBounds) {
      record.publishToActiveCapture(paintOffset);
    }
  }

  void _replaySemanticBounds({
    required CellOffset paintOffset,
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _semanticBounds) {
      record.replay(
        paintOffset: paintOffset,
        screenOffset: screenOffset,
        clipRect: clipRect,
      );
    }
  }

  void _publishPointerRegions({required CellOffset paintOffset}) {
    for (final record in _pointerRegions) {
      record.publishToActiveCapture(paintOffset);
    }
  }

  void _replayPointerRegions({
    required CellOffset paintOffset,
    required CellOffset screenOffset,
  }) {
    for (final record in _pointerRegions) {
      record.replay(paintOffset: paintOffset, screenOffset: screenOffset);
    }
  }
}
