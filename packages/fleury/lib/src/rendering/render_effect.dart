// RenderCellEffect: the compositing primitive behind cell-style animated
// effects (fade, flash, wipe, tint, shimmer, …).
//
// On a cell grid there's no alpha or pixel buffer, so effects can't
// recolor or move arbitrary child content in place. Instead this
// render object paints its child into a scratch CellBuffer, then
// composites each painted cell into the real buffer through a
// per-cell function. That function can:
//
//   - recolor / restyle the cell    (fade, tint, flash, shimmer)
//   - drop it                       (wipe / clip)
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
/// the visible region; an arbitrary per-cell transform has no general reverse
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
        // transparent and continuation cells travel with their leading
        // cell's replay.
        if (cell.role != CellRole.leading) continue;
        final placement = _composite(col, row, cell, size);
        if (placement == null) continue;
        final tc = offset.col + placement.col;
        final tr = offset.row + placement.row;
        if (tc < 0 || tr < 0 || tc >= cols || tr >= rows) continue;
        // Replay with the composite's style: an effect recolors cells, it
        // never re-measures them. The width role comes from the scratch the
        // child painted under this surface's policy.
        buffer.replayCellFrom(
          scratch,
          col,
          row,
          tc,
          tr,
          style: placement.style,
        );
      }
    }
  }
}

/// Paints a child at an integer-cell translation without changing layout.
///
/// Unlike [RenderCellEffect]'s arbitrary per-cell mapping, translation has a
/// well-defined inverse. That lets this render object move the whole painted
/// rectangle — text, opaque blank cells, and inline-image placements — while
/// keeping focus, pointer, caret, and semantic geometry at the same visible
/// position. Painted cells may overflow the stable layout box, while descendant
/// interaction geometry is clipped to that box. This mirrors a box transform:
/// the translated content stays visible, but it does not create a new hit-test
/// region outside the space its parent allocated.
class RenderCellTranslation extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderCellTranslation({
    double horizontalFraction = 0,
    double verticalFraction = 0,
    CellOffset cellOffset = CellOffset.zero,
    RenderObject? child,
  }) : _horizontalFraction = horizontalFraction,
       _verticalFraction = verticalFraction,
       _cellOffset = cellOffset {
    if (child != null) this.child = child;
  }

  double _horizontalFraction;
  set horizontalFraction(double value) {
    if (_horizontalFraction == value) return;
    final before = _resolvedOffset;
    _horizontalFraction = value;
    if (before == null || before != _resolvedOffset) markNeedsPaintOnly();
  }

  double _verticalFraction;
  set verticalFraction(double value) {
    if (_verticalFraction == value) return;
    final before = _resolvedOffset;
    _verticalFraction = value;
    if (before == null || before != _resolvedOffset) markNeedsPaintOnly();
  }

  CellOffset _cellOffset;
  set cellOffset(CellOffset value) {
    if (_cellOffset == value) return;
    final before = _resolvedOffset;
    _cellOffset = value;
    if (before == null || before != _resolvedOffset) markNeedsPaintOnly();
  }

  RenderObject? _child;
  CellSize? _childSize;

  @override
  RenderObject? get child => _child;

  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    _childSize = null;
    if (value != null) adoptChild(value);
  }

  CellOffset? get _resolvedOffset {
    final childSize = _childSize;
    if (childSize == null) return null;
    return CellOffset(
      _cellOffset.col + (childSize.cols * _horizontalFraction).round(),
      _cellOffset.row + (childSize.rows * _verticalFraction).round(),
    );
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    final childSize = c.layout(constraints);
    _childSize = childSize;
    return childSize;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final c = _child;
    final translation = _resolvedOffset;
    if (c == null || translation == null || c.size.isEmpty) return;
    if (translation == CellOffset.zero) {
      c.paint(
        buffer,
        offset,
        screenOffset: screenOffset ?? offset,
        clipRect: clipRect,
      );
      return;
    }

    final screen = screenOffset ?? offset;
    final ownScreenRect = CellRect(offset: screen, size: size);
    final inheritedHitBox = clipRect?.intersect(ownScreenRect);
    final effectiveGeometryClip = clipRect == null
        ? ownScreenRect
        : inheritedHitBox ?? CellRect(offset: screen, size: CellSize.zero);
    final scratch = CellBuffer(c.size);

    // The child records geometry where it is visibly painted, not at its
    // stable layout origin. Interaction remains bounded by the layout box even
    // though the translated cells themselves may overflow it.
    paintWithGeometryClip(ownScreenRect, () {
      c.paint(
        scratch,
        CellOffset.zero,
        screenOffset: screen + translation,
        clipRect: effectiveGeometryClip,
      );
    });

    final translatedChildRect = CellRect(
      offset: screen + translation,
      size: c.size,
    );
    final visible =
        clipRect?.intersect(translatedChildRect) ??
        (clipRect == null ? translatedChildRect : null);
    if (visible == null) return;

    final sourceRect = CellRect.fromLTWH(
      visible.left - translatedChildRect.left,
      visible.top - translatedChildRect.top,
      visible.size.cols,
      visible.size.rows,
    );
    final destination = CellOffset(
      offset.col + visible.left - ownScreenRect.left,
      offset.row + visible.top - ownScreenRect.top,
    );
    _compositePaintedRect(
      source: scratch,
      sourceRect: sourceRect,
      destination: buffer,
      destinationOffset: destination,
    );
  }
}

/// Clips an aligned slice of a child to a fraction of its natural size along
/// each axis, reporting the *clipped* size so surrounding layout reflows. Used
/// by `expand` / `shrink` — the box grows/shrinks and siblings move.
///
/// Distinct from [RenderCellEffect], which is layout-transparent
/// (reveal-in-place). Here the size itself animates.
class RenderClip extends RenderObject implements RenderObjectWithSingleChild {
  RenderClip({
    double widthFactor = 1.0,
    double heightFactor = 1.0,
    int horizontalAlignment = -1,
    int verticalAlignment = -1,
    RenderObject? child,
  }) : _widthFactor = widthFactor,
       _heightFactor = heightFactor,
       _horizontalAlignment = horizontalAlignment,
       _verticalAlignment = verticalAlignment,
       assert(horizontalAlignment >= -1 && horizontalAlignment <= 1),
       assert(verticalAlignment >= -1 && verticalAlignment <= 1) {
    if (child != null) this.child = child;
  }

  double _widthFactor;
  set widthFactor(double v) {
    if (_widthFactor == v) return;
    final before = _projectedSize;
    _widthFactor = v;
    if (before == null || before != _projectedSize) markNeedsLayout();
  }

  double _heightFactor;
  set heightFactor(double v) {
    if (_heightFactor == v) return;
    final before = _projectedSize;
    _heightFactor = v;
    if (before == null || before != _projectedSize) markNeedsLayout();
  }

  int _horizontalAlignment;
  set horizontalAlignment(int value) {
    assert(value >= -1 && value <= 1);
    if (_horizontalAlignment == value) return;
    _horizontalAlignment = value;
    markNeedsPaintOnly();
  }

  int _verticalAlignment;
  set verticalAlignment(int value) {
    assert(value >= -1 && value <= 1);
    if (_verticalAlignment == value) return;
    _verticalAlignment = value;
    markNeedsPaintOnly();
  }

  RenderObject? _child;
  CellSize? _naturalSize;
  CellConstraints? _lastConstraints;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    _naturalSize = null;
    _lastConstraints = null;
    if (value != null) adoptChild(value);
  }

  CellSize? get _projectedSize {
    final natural = _naturalSize;
    final constraints = _lastConstraints;
    if (natural == null || constraints == null) return null;
    return constraints.constrain(
      CellSize(
        (natural.cols * _widthFactor).round().clamp(0, natural.cols),
        (natural.rows * _heightFactor).round().clamp(0, natural.rows),
      ),
    );
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    final natural = c.layout(constraints.loosen());
    _naturalSize = natural;
    _lastConstraints = constraints;
    return _projectedSize!;
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
    if (c.size.isEmpty) return;

    final scratch = CellBuffer(c.size);
    final screen = screenOffset ?? offset;
    final ownScreenRect = CellRect(offset: screen, size: clipped);
    final inheritedIntersection = clipRect?.intersect(ownScreenRect);
    final visibleBox = clipRect == null ? ownScreenRect : inheritedIntersection;
    final effectiveClip = clipRect == null
        ? ownScreenRect
        : inheritedIntersection ??
              CellRect(offset: screen, size: CellSize.zero);
    // Scratch-local origin, true screen position — see RenderCellEffect.
    paintWithGeometryClip(ownScreenRect, () {
      c.paint(
        scratch,
        CellOffset.zero,
        screenOffset: screen - _alignedSourceOffset(c.size, clipped),
        clipRect: effectiveClip,
      );
    });
    if (visibleBox == null || clipped.isEmpty) return;

    final targetLocal = visibleBox.offset - ownScreenRect.offset;
    final alignedSource = _alignedSourceOffset(c.size, clipped);
    final sourceRect = CellRect(
      offset: alignedSource + targetLocal,
      size: visibleBox.size,
    );
    _compositePaintedRect(
      source: scratch,
      sourceRect: sourceRect,
      destination: buffer,
      destinationOffset: offset + targetLocal,
    );
  }

  CellOffset _alignedSourceOffset(CellSize natural, CellSize clipped) =>
      CellOffset(
        _alignedStart(natural.cols, clipped.cols, _horizontalAlignment),
        _alignedStart(natural.rows, clipped.rows, _verticalAlignment),
      );
}

int _alignedStart(int natural, int visible, int alignment) {
  final slack = natural - visible;
  if (alignment < 0) return 0;
  if (alignment > 0) return slack;
  return slack ~/ 2;
}

/// Transparently composites a clipped painted-cell rectangle and its image
/// placements. Empty cells remain transparent; wide glyphs are dropped rather
/// than split when the source rectangle cuts through their trailing cell.
void _compositePaintedRect({
  required CellBuffer source,
  required CellRect sourceRect,
  required CellBuffer destination,
  required CellOffset destinationOffset,
}) {
  final cols = destination.size.cols;
  final rows = destination.size.rows;
  for (var row = 0; row < sourceRect.size.rows; row++) {
    final sourceRow = sourceRect.top + row;
    for (var col = 0; col < sourceRect.size.cols; col++) {
      final sourceCol = sourceRect.left + col;
      final cell = source.atColRow(sourceCol, sourceRow);
      if (cell.role != CellRole.leading) continue;
      if (col + 1 >= sourceRect.size.cols &&
          sourceCol + 1 < source.size.cols &&
          source.atColRow(sourceCol + 1, sourceRow).role ==
              CellRole.continuation) {
        continue;
      }
      final targetCol = destinationOffset.col + col;
      final targetRow = destinationOffset.row + row;
      if (targetCol < 0 ||
          targetRow < 0 ||
          targetCol >= cols ||
          targetRow >= rows) {
        continue;
      }
      // Replay, not re-measure — see [CellBuffer.replayCellFrom]. The clip
      // above already dropped any pair the source rectangle cut.
      destination.replayCellFrom(
        source,
        sourceCol,
        sourceRow,
        targetCol,
        targetRow,
      );
    }
  }
  destination.compositeImageRectFrom(source, sourceRect, destinationOffset);
}
