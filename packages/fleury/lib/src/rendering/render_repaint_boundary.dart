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
  RenderRepaintBoundary({bool cachingEnabled = true})
    : _cachingEnabled = cachingEnabled;

  RenderObject? _child;
  CellBuffer? _cache;
  CellRect? _cacheBounds;

  /// Whether this boundary currently caches its subtree's paint.
  ///
  /// While false the node is a plain pass-through: [isRepaintBoundary]
  /// reports false so the invalidation walk ignores it, and [paint]
  /// delegates straight to the child. This lets an owner keep the boundary
  /// in the tree unconditionally (element-stable — flipping never reparents
  /// the subtree) and engage caching only while it can pay; [Overlay] does
  /// this per entry, engaging only while more than one entry is visible.
  ///
  /// Flipping mid-life is safe because nothing snapshots
  /// [isRepaintBoundary]: the invalidation walk reads it live, and enabling
  /// marks [needsPaint] — invalidations that happened while pass-through
  /// never marked this node, so the retained cache must not be trusted —
  /// and dirties every enclosing boundary (see the setter).
  bool get cachingEnabled => _cachingEnabled;
  bool _cachingEnabled;
  set cachingEnabled(bool value) {
    if (_cachingEnabled == value) return;
    _cachingEnabled = value;
    if (value) {
      needsPaint = true;
      // Restore "dirty boundary ⟹ dirty ancestors" locally: an enclosing
      // boundary's cache embeds this subtree's cells, and every LATER
      // invalidation from inside this subtree will short-circuit at this
      // (now dirty) boundary — ancestors would never hear about it and
      // would keep blitting stale cells.
      markAncestorRepaintBoundariesDirty();
    }
    // Disengaging keeps the cache buffer: engagement flaps with structure
    // (an overlay entry appearing and vanishing), and freeing would cost a
    // screen-sized realloc plus warm-up repaint on every re-engage. The
    // memory is bounded by live boundaries and reclaimed with the render
    // object.
  }

  @override
  bool get isRepaintBoundary => _cachingEnabled;

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
  void performPaint(CellBuffer buffer, CellOffset offset) {
    final c = _child;
    if (c == null) return;
    if (!_cachingEnabled) {
      // Pass-through: no cache, no blit, no stats — indistinguishable from
      // the child painting bare.
      c.paint(buffer, offset);
      return;
    }
    final s = size;
    if (s.cols == 0 || s.rows == 0) {
      _cacheBounds = null;
      return;
    }

    var cache = _cache;
    if (cache == null || cache.size != s) {
      cache = CellBuffer(s);
      _cache = cache;
      needsPaint = true;
    }

    var repainted = false;
    if (needsPaint) {
      final targetCache = cache;
      // Clear untracked, then arm the cache's own damage tracking around the
      // child's paint: the damage rect falls out of the writes themselves —
      // no post-paint full-grid scan.
      cache.withoutDamageTracking(targetCache.clear);
      cache.resetDamageTracking();
      // The subtree paints at a cache-local origin. Its position on screen is
      // derived from layout by whoever needs it, so a cache hit — which skips
      // this walk entirely — leaves nothing stale behind.
      c.paint(targetCache, CellOffset.zero);
      // Tighten the blit to just the non-empty cells, using the damage rect
      // as the scan window. Damage is a conservative superset (grapheme
      // writes pad the wide-cell guard columns), and tightness matters: the
      // blit is a raw rect copy painted OVER whatever sits beneath this
      // boundary (a floating entry above the app), so a padded rect would
      // stamp its empty halo columns onto that content.
      final damage = cache.takeDamageBounds();
      _cacheBounds = damage == null
          ? null
          : cache.boundingBoxOfNonEmptyWithin(damage);
      needsPaint = false;
      repainted = true;
    }

    final bounds = _cacheBounds;
    RepaintBoundaryDebugStats.recordPaint(
      repainted: repainted,
      copiedBounds: bounds,
    );
    // Content that shrank, moved or disappeared used to need its previous
    // extent re-damaged by hand here, because the frame's damage was only ever
    // as good as what paint declared. The frame loop now derives damage by
    // comparing the two buffers, so a vacated cell is found by construction —
    // for this boundary and for anything else that stops painting.
    if (bounds == null) return; // entirely empty cache — nothing to draw
    final cacheForCopy = cache;
    final destOffset = CellOffset(
      offset.col + bounds.offset.col,
      offset.row + bounds.offset.row,
    );
    // The blit records damage even on a cache hit. It used to be suppressed so
    // the presenter would not re-scan cells it knew were unchanged — but frame
    // damage is derived by comparing buffers now, so the frame buffer never
    // arms tracking and suppressing there does nothing. Where [buffer] IS
    // armed it is a PARENT boundary's cache, and that parent measures what was
    // painted into it from this damage: suppressing hid a nested cache-hit
    // child from its parent's bounds and blanked the row.
    buffer.copyRectFrom(cacheForCopy, bounds, destOffset);
  }
}
