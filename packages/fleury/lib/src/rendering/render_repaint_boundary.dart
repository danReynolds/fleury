import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_object.dart';

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
/// changes (e.g. a syntax-highlighted log pane); for cheap subtrees it is
/// at best neutral. Reach for it deliberately, not by default.
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

    if (needsPaint) {
      cache.clear();
      c.paint(cache, CellOffset.zero);
      // Tighten the next blit to just the non-empty cells. For dense
      // subtrees that's the full size (no penalty); for sparse subtrees
      // this avoids copying a buffer of mostly-empty cells.
      _cacheBounds = cache.boundingBoxOfNonEmpty();
      needsPaint = false;
    }

    final bounds = _cacheBounds;
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
