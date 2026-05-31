// RenderStack: overlay layout. Children paint in declaration order, so
// later children overwrite earlier ones — that's the whole point of a
// stack. Positioned children carry their own offset (and optional size);
// non-positioned children sit at the top-left and contribute to the
// stack's intrinsic size.

import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_object.dart';

/// A pass-through render object marking its child as positioned inside
/// a [RenderStack]. The stack reads [left], [top], [width], and [height]
/// to lay out and place the child.
///
/// `width` / `height` of `null` mean "use the child's intrinsic size for
/// that axis." `left` / `top` default to 0.
class RenderPositioned extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderPositioned({int left = 0, int top = 0, int? width, int? height})
    : _left = left,
      _top = top,
      _width = width,
      _height = height,
      assert(left >= 0, 'left must be non-negative'),
      assert(top >= 0, 'top must be non-negative'),
      assert(width == null || width >= 0, 'width must be non-negative'),
      assert(height == null || height >= 0, 'height must be non-negative');

  int _left;
  int _top;
  int? _width;
  int? _height;

  int get left => _left;
  set left(int value) {
    assert(value >= 0);
    if (_left == value) return;
    _left = value;
  }

  int get top => _top;
  set top(int value) {
    assert(value >= 0);
    if (_top == value) return;
    _top = value;
  }

  int? get width => _width;
  set width(int? value) {
    assert(value == null || value >= 0);
    if (_width == value) return;
    _width = value;
  }

  int? get height => _height;
  set height(int? value) {
    assert(value == null || value >= 0);
    if (_height == value) return;
    _height = value;
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    // The stack lays this out by directly passing constraints derived
    // from `_left`, `_top`, `_width`, `_height`. When invoked from a
    // non-Stack parent we just forward to the child.
    return _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}

/// Stacks children at the same origin and lets later siblings overwrite
/// earlier ones. Non-positioned children determine the stack's size
/// (intrinsic of the largest); positioned children float on top with
/// explicit offsets and sizes.
///
/// This is the primitive behind modals, popovers, status overlays, and
/// any other "thing on top of thing" surface a TUI needs.
class RenderStack extends RenderObject implements RenderObjectWithChildren {
  RenderStack();

  final List<RenderObject> _children = <RenderObject>[];
  final Map<RenderObject, CellOffset> _childOffsets =
      <RenderObject, CellOffset>{};

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    final newSet = Set<RenderObject>.identity()..addAll(newChildren);
    for (final c in List<RenderObject>.from(_children)) {
      if (!newSet.contains(c)) {
        dropChild(c);
        _childOffsets.remove(c);
      }
    }
    final oldSet = Set<RenderObject>.identity()..addAll(_children);
    for (final c in newChildren) {
      if (!oldSet.contains(c)) {
        adoptChild(c);
      }
    }
    _children
      ..clear()
      ..addAll(newChildren);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_children.isEmpty) {
      return constraints.constrain(CellSize.zero);
    }

    // Pass 1: non-positioned children with loose constraints. Track the
    // largest intrinsic so the stack itself knows how big to be.
    var maxCols = 0;
    var maxRows = 0;
    for (final c in _children) {
      if (c is RenderPositioned) continue;
      final size = c.layout(constraints.loosen());
      _childOffsets[c] = CellOffset.zero;
      if (size.cols > maxCols) maxCols = size.cols;
      if (size.rows > maxRows) maxRows = size.rows;
    }

    final ownSize = constraints.constrain(CellSize(maxCols, maxRows));

    // Pass 2: positioned children with constraints derived from their
    // own (left, top, width, height) and the stack's own size.
    for (final c in _children) {
      if (c is! RenderPositioned) continue;
      final w = c.width;
      final h = c.height;
      final cMaxCols = ownSize.cols - c.left;
      final cMaxRows = ownSize.rows - c.top;
      // Skip if completely outside the stack — child can't fit anywhere.
      if (cMaxCols <= 0 || cMaxRows <= 0) {
        c.layout(const CellConstraints(maxCols: 0, maxRows: 0));
        _childOffsets[c] = CellOffset(c.left, c.top);
        continue;
      }
      final cc = CellConstraints(
        minCols: w ?? 0,
        maxCols: w ?? cMaxCols,
        minRows: h ?? 0,
        maxRows: h ?? cMaxRows,
      );
      c.layout(cc);
      _childOffsets[c] = CellOffset(c.left, c.top);
    }

    return ownSize;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final so = screenOffset ?? offset;
    for (final c in _children) {
      final childOffset = _childOffsets[c] ?? CellOffset.zero;
      c.paint(
        buffer,
        offset + childOffset,
        screenOffset: so + childOffset,
        clipRect: clipRect,
      );
    }
  }
}

/// Keeps every child mounted and laid out, but paints only the one at
/// [index]. Because the off-screen children stay in the tree, their
/// [State] (scroll position, text, expansion…) survives switching away
/// and back — the state-preserving counterpart to swapping the subtree.
///
/// Sized to the largest child so the visible slot doesn't jump as the
/// index changes. An out-of-range [index] paints nothing.
class RenderIndexedStack extends RenderObject
    implements RenderObjectWithChildren {
  RenderIndexedStack({int index = 0}) : _index = index;

  int _index;
  set index(int value) => _index = value;

  final List<RenderObject> _children = <RenderObject>[];

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    final newSet = Set<RenderObject>.identity()..addAll(newChildren);
    for (final c in List<RenderObject>.from(_children)) {
      if (!newSet.contains(c)) dropChild(c);
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
    var maxCols = 0;
    var maxRows = 0;
    for (final c in _children) {
      final size = c.layout(constraints);
      if (size.cols > maxCols) maxCols = size.cols;
      if (size.rows > maxRows) maxRows = size.rows;
    }
    return constraints.constrain(CellSize(maxCols, maxRows));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (_index < 0 || _index >= _children.length) return;
    _children[_index].paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}
