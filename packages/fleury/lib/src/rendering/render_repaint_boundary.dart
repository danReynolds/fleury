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
  // Reused across repaints (cleared, not reallocated): a boundary repaint is
  // the steady-state hot path, and fresh capture lists per repaint were pure
  // per-frame churn. Private and only read internally, so sharing the
  // mutable instances is safe.
  final List<SemanticPaintBoundsRecord> _semanticBounds =
      <SemanticPaintBoundsRecord>[];
  final List<PointerRegionRecord> _pointerRegions = <PointerRegionRecord>[];
  final List<FocusGeometryRecord> _focusGeometry = <FocusGeometryRecord>[];
  final List<RetainedPaintGeometryRecord> _retainedPaintGeometry =
      <RetainedPaintGeometryRecord>[];

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
    } else {
      // Pass-through paint no longer replays this boundary's retained
      // callbacks. Retire them now so externally owned FocusNodes and
      // semantic elements cannot retain geometry from the last cached frame
      // if the subtree changes while caching is disengaged.
      _discardCapturedGeometry();
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
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final c = _child;
    if (c == null) {
      _discardCapturedGeometry();
      return;
    }
    if (!_cachingEnabled) {
      // Pass-through: no cache, no blit, no stats — indistinguishable from
      // the child painting bare.
      c.paint(
        buffer,
        offset,
        screenOffset: screenOffset ?? offset,
        clipRect: clipRect,
      );
      return;
    }
    final s = size;
    if (s.cols == 0 || s.rows == 0) {
      // A cache hit cannot walk the old subtree to clear its paint-owned
      // geometry. Explicitly retire the callbacks when layout collapses the
      // boundary, otherwise focus traversal and IME anchoring keep using the
      // last non-empty frame's rectangles.
      _discardCapturedGeometry();
      _cacheBounds = null;
      return;
    }

    final currentScreenOffset = screenOffset ?? offset;

    var cache = _cache;
    if (cache == null || cache.size != s) {
      cache = CellBuffer(s);
      _cache = cache;
      needsPaint = true;
    }

    // Snapshot the extent painted last frame BEFORE the repaint recomputes it:
    // cells inside the old box but outside the new one have been vacated, and
    // must be damaged (below) so the bounded presenter diff erases them.
    final previousBounds = _cacheBounds;
    var repainted = false;
    if (needsPaint) {
      final targetCache = cache;
      // Clear untracked, then arm the cache's own damage tracking around the
      // child's paint: the damage rect falls out of the writes themselves —
      // no post-paint full-grid scan.
      cache.withoutDamageTracking(targetCache.clear);
      cache.resetDamageTracking();
      _resetCapturedGeometryForRepaint();
      SemanticPaintBoundsCapture.collect(
        _semanticBounds,
        screenOrigin: currentScreenOffset,
        clipRect: clipRect,
        paint: () {
          PointerRegionCapture.collect(
            _pointerRegions,
            screenOrigin: currentScreenOffset,
            clipRect: clipRect,
            paint: () {
              FocusGeometryCapture.collect(
                _focusGeometry,
                screenOrigin: currentScreenOffset,
                clipRect: clipRect,
                paint: () {
                  RetainedPaintGeometryCapture.collect(
                    _retainedPaintGeometry,
                    screenOrigin: currentScreenOffset,
                    clipRect: clipRect,
                    paint: () {
                      c.paint(
                        targetCache,
                        CellOffset.zero,
                        screenOffset: currentScreenOffset,
                        clipRect: clipRect,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
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
    } else {
      _replaySemanticBounds(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
      _replayPointerRegions(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
      _replayFocusGeometry(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
      _replayRetainedPaintGeometry(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
    }

    final bounds = _cacheBounds;
    RepaintBoundaryDebugStats.recordPaint(
      repainted: repainted,
      copiedBounds: bounds,
    );
    if (repainted) {
      _publishSemanticBounds(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
      _publishPointerRegions(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
      _publishFocusGeometry(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
      _publishRetainedPaintGeometry(
        screenOffset: currentScreenOffset,
        clipRect: clipRect,
      );
    }
    // A repaint whose content shrank, moved, or disappeared leaves ghost cells:
    // the blit below damages only the NEW box, and diffBounds is a paint-only
    // superset, so cells the previous frame painted outside the new box are
    // never revisited. Damage the previous extent too whenever it differs (a
    // cache-hit can't change content, so restrict to repaints).
    if (repainted && previousBounds != null && previousBounds != bounds) {
      buffer.recordDamage(
        CellRect(
          offset: offset + previousBounds.offset,
          size: previousBounds.size,
        ),
      );
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

  void _publishSemanticBounds({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _semanticBounds) {
      record.publishToActiveCapture(
        screenOffset: screenOffset,
        clipRect: clipRect,
      );
    }
  }

  void _replaySemanticBounds({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _semanticBounds) {
      record.replay(screenOffset: screenOffset, clipRect: clipRect);
    }
  }

  void _publishPointerRegions({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _pointerRegions) {
      record.publishToActiveCapture(
        screenOffset: screenOffset,
        clipRect: clipRect,
      );
    }
  }

  void _replayPointerRegions({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _pointerRegions) {
      record.replay(screenOffset: screenOffset, clipRect: clipRect);
    }
  }

  void _publishFocusGeometry({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _focusGeometry) {
      record.publishToActiveCapture(
        screenOffset: screenOffset,
        clipRect: clipRect,
      );
    }
  }

  void _replayFocusGeometry({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _focusGeometry) {
      record.replay(screenOffset: screenOffset, clipRect: clipRect);
    }
  }

  void _publishRetainedPaintGeometry({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _retainedPaintGeometry) {
      record.publishToActiveCapture(
        screenOffset: screenOffset,
        clipRect: clipRect,
      );
    }
  }

  void _replayRetainedPaintGeometry({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    for (final record in _retainedPaintGeometry) {
      record.replay(screenOffset: screenOffset, clipRect: clipRect);
    }
  }

  void _discardCapturedGeometry() {
    for (final record in _semanticBounds) {
      record.onPaintBounds(null);
    }
    _semanticBounds.clear();
    _pointerRegions.clear();
    for (final record in _focusGeometry) {
      record.clear();
    }
    _focusGeometry.clear();
    for (final record in _retainedPaintGeometry) {
      record.clear();
    }
    _retainedPaintGeometry.clear();
  }

  void _resetCapturedGeometryForRepaint() {
    // A still-mounted semantic can be culled by the fresh paint and never
    // republish. Retire every previous callback first; the semantic dirty set
    // deduplicates the null -> current-bounds updates for nodes that do paint.
    for (final record in _semanticBounds) {
      record.onPaintBounds(null);
    }
    _semanticBounds.clear();
    _pointerRegions.clear();
    for (final record in _focusGeometry) {
      record.clear();
    }
    _focusGeometry.clear();
    for (final record in _retainedPaintGeometry) {
      record.clear();
    }
    _retainedPaintGeometry.clear();
  }
}
