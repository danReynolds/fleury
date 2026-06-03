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
/// repaint the way a GPU layer does. Two important limits: layout still
/// runs for the whole tree every frame (this caches paint only), and the
/// `AnsiRenderer` still diffs every cell every frame (the blit just
/// repopulates the cells the diff then re-examines). So the win is real
/// only for subtrees whose *paint* is genuinely expensive and rarely
/// changes (e.g. a syntax-highlighted log pane); layout dirtiness is tracked
/// separately and can skip same-constraint subtrees even when no boundary is
/// present. For cheap subtrees repaint boundaries are at best neutral, so
/// reach for them deliberately, not by default.
///
/// The boundary is opaque to its caller: parents call `paint(buffer, offset)`
/// as usual; the cache discipline is internal. Use the [RepaintBoundary]
/// widget to wrap subtrees that are expensive to paint and change rarely.
class RenderRepaintBoundary extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderObject? _child;
  CellBuffer? _cache;
  CellRect? _cacheBounds;

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
      cache.clear();
      c.paint(cache, CellOffset.zero);
      // Tighten the next blit to just the non-empty cells. For dense
      // subtrees that's the full size (no penalty); for sparse subtrees
      // this avoids copying a buffer of mostly-empty cells.
      _cacheBounds = cache.boundingBoxOfNonEmpty();
      needsPaint = false;
      repainted = true;
    }

    final bounds = _cacheBounds;
    RepaintBoundaryDebugStats.recordPaint(
      repainted: repainted,
      copiedBounds: bounds,
    );
    if (bounds == null) return; // entirely empty cache — nothing to draw
    buffer.copyRectFrom(
      cache,
      bounds,
      CellOffset(
        offset.col + bounds.offset.col,
        offset.row + bounds.offset.row,
      ),
    );
  }
}
