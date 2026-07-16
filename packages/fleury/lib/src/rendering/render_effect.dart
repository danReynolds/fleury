// RenderCellEffect: the compositing primitive behind every animated
// effect (fade, slide, flash, reveal, tint, shimmer, …).
//
// On a cell grid there's no alpha or pixel buffer, so effects can't
// recolor or move arbitrary child content in place. Instead this
// render object paints its child into a scratch CellBuffer, then
// composites each painted cell into the real buffer through a
// per-cell function. That function can:
//
//   - recolor / restyle the cell    (fade, tint, flash, shimmer)
//   - move it                       (slide, shake)
//   - drop it                       (reveal / clip)
//
// Layout is transparent: the effect reports its child's size, so it
// never disturbs surrounding layout — only paint changes.

import '../foundation/geometry.dart';
import 'cell.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_object.dart';

/// Where (and how) a painted child cell lands in the output buffer.
/// Returned by a [CellComposite]; `null` drops the cell (a clip).
class CellPlacement {
  const CellPlacement(this.col, this.row, this.style);

  /// Target column/row, relative to the effect's own origin.
  final int col;
  final int row;

  /// Style to paint the cell with (recolored, etc.).
  final CellStyle style;
}

/// Maps a painted child cell at (`col`, `row`) — within a child of
/// [size] — to its output placement, or null to drop it.
typedef CellComposite =
    CellPlacement? Function(int col, int row, Cell cell, CellSize size);

/// Paints [child] to a scratch buffer, then composites its cells via
/// [composite]. Layout-transparent (reports the child's size).
///
/// A composite is deliberately paint-only: focus, caret, semantic, and pointer
/// geometry stays at the child's stable layout position while inherited clips
/// still apply. Use [RenderClip] when interaction geometry must be clipped with
/// the visible region; an arbitrary per-cell transform has no general inverse
/// that could safely remap descendant interaction regions.
class RenderCellEffect extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderCellEffect(
    this._composite, {
    bool passthrough = false,
    RenderObject? child,
  }) : _passthrough = passthrough {
    if (child != null) this.child = child;
  }

  CellComposite _composite;
  set composite(CellComposite value) {
    if (identical(_composite, value)) return;
    _composite = value;
    markNeedsPaintOnly();
  }

  /// When true, painting delegates straight to the child — no scratch
  /// buffer, no per-cell composite. Used for an effect at rest (a route's
  /// enter effect at full progress): the wrapper element stays mounted (so
  /// the subtree keeps its State), but paint costs nothing and, crucially,
  /// non-text cells survive — the composite path copies only leading text
  /// cells, so protocol cells (terminal images) would be dropped, and it
  /// paints the child at a scratch-local origin, so recorded focus/pointer
  /// rects would go stale.
  bool _passthrough;
  set passthrough(bool value) {
    if (_passthrough == value) return;
    _passthrough = value;
    markNeedsPaintOnly();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
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
    if (_passthrough) {
      c.paint(
        buffer,
        offset,
        screenOffset: screenOffset ?? offset,
        clipRect: clipRect,
      );
      return;
    }
    final size = c.size;
    if (size.isEmpty) return;

    final scratch = CellBuffer(size);
    final screen = screenOffset ?? offset;
    // Paint at a scratch-local origin but propagate the TRUE screen position:
    // descendants that record absolute geometry (focus bounds, pointer
    // regions) must not capture scratch-local coordinates.
    // Effects deliberately keep interaction geometry in the child's stable
    // layout position, but inherited clipping must still apply.
    c.paint(scratch, CellOffset.zero, screenOffset: screen, clipRect: clipRect);

    final cols = buffer.size.cols;
    final rows = buffer.size.rows;
    for (var row = 0; row < size.rows; row++) {
      for (var col = 0; col < size.cols; col++) {
        final cell = scratch.atColRow(col, row);
        // Only leading cells carry a grapheme; empty cells are
        // transparent and continuation cells are emitted by their
        // leading cell's wide write.
        if (cell.role != CellRole.leading) continue;
        final placement = _composite(col, row, cell, size);
        if (placement == null) continue;
        final tc = offset.col + placement.col;
        final tr = offset.row + placement.row;
        if (tc < 0 || tr < 0 || tc >= cols || tr >= rows) continue;
        buffer.writeGrapheme(
          CellOffset(tc, tr),
          cell.grapheme!,
          style: placement.style,
        );
      }
    }
  }
}

/// Clips a child to a fraction of its natural size along each axis,
/// reporting the *clipped* size so surrounding layout reflows. Used
/// by `expand` / `collapse` — the box grows/shrinks and siblings move.
///
/// Distinct from [RenderCellEffect], which is layout-transparent
/// (reveal-in-place). Here the size itself animates.
class RenderClip extends RenderObject implements RenderObjectWithSingleChild {
  RenderClip({
    double widthFactor = 1.0,
    double heightFactor = 1.0,
    RenderObject? child,
  }) : _widthFactor = widthFactor,
       _heightFactor = heightFactor {
    if (child != null) this.child = child;
  }

  double _widthFactor;
  set widthFactor(double v) {
    if (_widthFactor == v) return;
    _widthFactor = v;
    markNeedsLayout();
  }

  double _heightFactor;
  set heightFactor(double v) {
    if (_heightFactor == v) return;
    _heightFactor = v;
    markNeedsLayout();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    final natural = c.layout(constraints.loosen());
    final clipped = CellSize(
      (natural.cols * _widthFactor).round().clamp(0, natural.cols),
      (natural.rows * _heightFactor).round().clamp(0, natural.rows),
    );
    return constraints.constrain(clipped);
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
    final clipped = size;
    if (clipped.isEmpty) return;

    final scratch = CellBuffer(c.size);
    final screen = screenOffset ?? offset;
    final ownScreenRect = CellRect(offset: screen, size: clipped);
    final inheritedIntersection = clipRect?.intersect(ownScreenRect);
    final effectiveClip = clipRect == null
        ? ownScreenRect
        : inheritedIntersection ??
              CellRect(offset: screen, size: CellSize.zero);
    // Scratch-local origin, true screen position — see RenderCellEffect.
    paintWithGeometryClip(ownScreenRect, () {
      c.paint(
        scratch,
        CellOffset.zero,
        screenOffset: screen,
        clipRect: effectiveClip,
      );
    });

    final cols = buffer.size.cols;
    final rows = buffer.size.rows;
    for (var row = 0; row < clipped.rows; row++) {
      for (var col = 0; col < clipped.cols; col++) {
        final cell = scratch.atColRow(col, row);
        if (cell.role != CellRole.leading) continue;
        final tc = offset.col + col;
        final tr = offset.row + row;
        if (tc < 0 || tr < 0 || tc >= cols || tr >= rows) continue;
        buffer.writeGrapheme(
          CellOffset(tc, tr),
          cell.grapheme!,
          style: cell.style,
        );
      }
    }
    // Placements are stored off-grid and therefore are not carried by the
    // leading-cell loop above. Composite the same clipped rectangle so image
    // pixels follow expand/collapse geometry exactly.
    buffer.compositeImageRectFrom(
      scratch,
      CellRect(offset: CellOffset.zero, size: clipped),
      offset,
    );
  }
}
