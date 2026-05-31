// RenderWrap: flow layout. Lays children left-to-right, wrapping to a
// new run (row) when the next child won't fit the available width — the
// layout behind chips, tags, token lists, and toolbars that reflow.
//
// Horizontal flow only for now (the dominant case). Children are laid
// out loosely (sized to content, bounded to the line width); a child too
// wide for the line gets its own run. `spacing` separates children
// within a run; `runSpacing` separates the runs.

import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_object.dart';

/// Flows children into wrapping runs along the horizontal axis.
class RenderWrap extends RenderObject implements RenderObjectWithChildren {
  RenderWrap({int spacing = 0, int runSpacing = 0})
    : _spacing = spacing,
      _runSpacing = runSpacing;

  int _spacing;
  int get spacing => _spacing;
  set spacing(int value) {
    if (_spacing == value) return;
    _spacing = value;
  }

  int _runSpacing;
  int get runSpacing => _runSpacing;
  set runSpacing(int value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
  }

  final List<RenderObject> _children = <RenderObject>[];
  final Map<RenderObject, CellOffset> _offsets = <RenderObject, CellOffset>{};

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    final newSet = Set<RenderObject>.identity()..addAll(newChildren);
    for (final c in List<RenderObject>.from(_children)) {
      if (!newSet.contains(c)) {
        dropChild(c);
        _offsets.remove(c);
      }
    }
    final oldSet = Set<RenderObject>.identity()..addAll(_children);
    for (final c in newChildren) {
      if (!oldSet.contains(c)) adoptChild(c);
    }
    _children
      ..clear()
      ..addAll(newChildren);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_children.isEmpty) return constraints.constrain(CellSize.zero);

    final maxCols = constraints.maxCols;
    final childConstraints = CellConstraints(maxCols: maxCols);

    var x = 0; // next free column within the current run
    var y = 0; // top row of the current run
    var runHeight = 0;
    var widestRun = 0;

    for (final child in _children) {
      final size = child.layout(childConstraints);
      // Wrap to a new run when this child (plus its gap) overflows the
      // line — but never wrap when it's already the first in the run.
      if (maxCols != null && x != 0 && x + _spacing + size.cols > maxCols) {
        if (x > widestRun) widestRun = x;
        y += runHeight + _runSpacing;
        x = 0;
        runHeight = 0;
      }
      if (x != 0) x += _spacing;
      _offsets[child] = CellOffset(x, y);
      x += size.cols;
      if (size.rows > runHeight) runHeight = size.rows;
    }
    if (x > widestRun) widestRun = x;

    return constraints.constrain(CellSize(widestRun, y + runHeight));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    for (final child in _children) {
      final o = _offsets[child] ?? CellOffset.zero;
      child.paint(
        buffer,
        offset + o,
        screenOffset: (screenOffset ?? offset) + o,
        clipRect: clipRect,
      );
    }
  }
}
