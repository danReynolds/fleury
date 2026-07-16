// RenderFlex and friends: the row/column layout algorithm in integer
// terminal cells, with deterministic integer-remainder allocation for
// flex children.

import '../foundation/geometry.dart';
import '../widgets/selection/selectable.dart';
import 'cell.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_object.dart';

/// True only when asserts run (i.e. `dart run`, not an AOT release build),
/// matching how Flutter scopes its debug-only overflow banner.
final bool _assertsEnabled = () {
  var on = false;
  assert(() {
    on = true;
    return true;
  }());
  return on;
}();

/// Axis along which a [RenderFlex] arranges its children.
enum Axis { horizontal, vertical }

/// How a [RenderFlex] sizes itself along its main axis.
enum MainAxisSize {
  /// Take as much space as the parent permits.
  max,

  /// Shrink to fit the sum of children's main-axis extents.
  min,
}

/// Main-axis alignment of [RenderFlex] children.
enum MainAxisAlignment {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// Cross-axis alignment of [RenderFlex] children.
enum CrossAxisAlignment {
  start,
  end,
  center,

  /// Children fill the cross axis. This is the typical chat layout
  /// choice — Row with stretch makes both panes the full terminal
  /// height regardless of their inner content.
  stretch,
}

/// How a flexible child's main-axis allocation is enforced.
enum FlexFit {
  /// Child is forced to take exactly its allocated main-axis extent.
  tight,

  /// Child may take up to its allocated extent; smaller children are
  /// allowed.
  loose,
}

/// A pass-through render object marking its child as flexible inside a
/// [RenderFlex]. The flex factor and fit are read by [RenderFlex] during
/// the main-axis allocation pass; otherwise this render object just
/// forwards layout and paint to its child.
class RenderFlexible extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderFlexible({required int flex, required FlexFit fit})
    : _flex = flex,
      _fit = fit,
      assert(flex > 0, 'Flex factor must be positive');

  int _flex;
  FlexFit _fit;

  int get flex => _flex;
  set flex(int value) {
    assert(value > 0, 'Flex factor must be positive');
    if (_flex == value) return;
    _flex = value;
    markNeedsLayout();
  }

  FlexFit get fit => _fit;
  set fit(FlexFit value) {
    if (_fit == value) return;
    _fit = value;
    markNeedsLayout();
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
    return _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);
  }

  // Flexible delegates intrinsics to its child; the flex factor only matters
  // during actual layout (distributing slack), not when reporting "what would
  // this widget want to be at its natural size?"
  @override
  int computeMaxIntrinsicWidth(int? height) =>
      _child?.computeMaxIntrinsicWidth(height) ?? 0;
  @override
  int computeMinIntrinsicWidth(int? height) =>
      _child?.computeMinIntrinsicWidth(height) ?? 0;
  @override
  int computeMaxIntrinsicHeight(int? width) =>
      _child?.computeMaxIntrinsicHeight(width) ?? 0;
  @override
  int computeMinIntrinsicHeight(int? width) =>
      _child?.computeMinIntrinsicHeight(width) ?? 0;

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

/// Lays out a list of children along a main axis using a flex-based
/// allocation algorithm.
///
/// Children that are themselves [RenderFlexible] participate in flex
/// allocation; their `flex` factors are summed and the remaining
/// main-axis space (after inflexible children take their intrinsic
/// width) is distributed among them. The remainder from integer
/// division is given to the leftmost flexible children in order, so the
/// layout is deterministic.
class RenderFlex extends RenderObject implements RenderObjectWithChildren {
  RenderFlex({
    Axis direction = Axis.horizontal,
    MainAxisSize mainAxisSize = MainAxisSize.max,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
  }) : _direction = direction,
       _mainAxisSize = mainAxisSize,
       _mainAxisAlignment = mainAxisAlignment,
       _crossAxisAlignment = crossAxisAlignment;

  /// Whether to paint a marker along the edge where children overflowed
  /// the box (Flutter's overflow banner, for a cell grid). Defaults to on
  /// when asserts run; the runtime keeps it on in dev and the test harness
  /// turns it off so it doesn't perturb golden output.
  static bool debugShowOverflow = _assertsEnabled;

  Axis _direction;
  MainAxisSize _mainAxisSize;
  MainAxisAlignment _mainAxisAlignment;
  CrossAxisAlignment _crossAxisAlignment;

  /// Main-axis cells by which children exceeded the box in the last
  /// layout, or 0 when everything fit.
  int _overflow = 0;

  Axis get direction => _direction;
  set direction(Axis value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  MainAxisSize get mainAxisSize => _mainAxisSize;
  set mainAxisSize(MainAxisSize value) {
    if (_mainAxisSize == value) return;
    _mainAxisSize = value;
    markNeedsLayout();
  }

  MainAxisAlignment get mainAxisAlignment => _mainAxisAlignment;
  set mainAxisAlignment(MainAxisAlignment value) {
    if (_mainAxisAlignment == value) return;
    _mainAxisAlignment = value;
    markNeedsLayout();
  }

  CrossAxisAlignment get crossAxisAlignment => _crossAxisAlignment;
  set crossAxisAlignment(CrossAxisAlignment value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  final List<RenderObject> _children = <RenderObject>[];
  final Map<RenderObject, CellOffset> _childOffsets =
      <RenderObject, CellOffset>{};

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    if (hasSameRenderChildrenInOrder(_children, newChildren)) return;
    if (_children.isEmpty) {
      for (final c in newChildren) {
        adoptChild(c);
      }
      _children.addAll(newChildren);
      markNeedsLayout();
      return;
    }
    if (newChildren.isEmpty) {
      for (final c in _children) {
        dropChild(c);
      }
      _children.clear();
      _childOffsets.clear();
      markNeedsLayout();
      return;
    }
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
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_children.isEmpty) {
      return constraints.constrain(CellSize.zero);
    }

    final mainMax = _mainMax(constraints);
    final crossMax = _crossMax(constraints);

    // Pass 1: lay out inflexible children with unbounded main-axis and
    // the available cross-axis range. Sum their main-axis extents.
    var inflexibleExtent = 0;
    var totalFlex = 0;
    final flexibleChildren = <RenderFlexible>[];

    for (final child in _children) {
      if (child is RenderFlexible) {
        totalFlex += child.flex;
        flexibleChildren.add(child);
      } else {
        final cc = _childConstraintsForInflexible(crossMax);
        final size = child.layout(cc);
        inflexibleExtent += _mainExtent(size);
      }
    }

    // Pass 2: allocate remaining main-axis space among flex children.
    // Every flex child gets a layout call (even if allocation is zero)
    // so its `size` is always readable below.
    if (totalFlex > 0) {
      final available = mainMax != null ? _max0(mainMax - inflexibleExtent) : 0;
      final allocations = _allocateFlex(flexibleChildren, available, totalFlex);
      for (var i = 0; i < flexibleChildren.length; i++) {
        final allocation = allocations[i];
        final cc = _childConstraintsForFlexible(
          crossMax,
          allocation,
          flexibleChildren[i].fit,
        );
        flexibleChildren[i].layout(cc);
      }
    }

    // Compute main-axis size of this Flex.
    var usedMain = inflexibleExtent;
    for (final c in flexibleChildren) {
      usedMain += _mainExtent(c.size);
    }
    final ownMain = _mainAxisSize == MainAxisSize.max
        ? (mainMax ?? usedMain)
        : usedMain;

    // Compute cross-axis size: max of children's cross extents, or
    // constraints.maxCross if stretch.
    var maxCross = 0;
    for (final c in _children) {
      final e = _crossExtent(c.size);
      if (e > maxCross) maxCross = e;
    }
    final ownCross = _crossAxisAlignment == CrossAxisAlignment.stretch
        ? (crossMax ?? maxCross)
        : maxCross;

    // Position children. Compute slack along main axis for alignment.
    final mainSlack = ownMain - usedMain;
    var pos = 0;
    var gap = 0;
    switch (_mainAxisAlignment) {
      case MainAxisAlignment.start:
        pos = 0;
        gap = 0;
      case MainAxisAlignment.end:
        pos = mainSlack;
        gap = 0;
      case MainAxisAlignment.center:
        pos = mainSlack ~/ 2;
        gap = 0;
      case MainAxisAlignment.spaceBetween:
        pos = 0;
        gap = _children.length > 1 ? mainSlack ~/ (_children.length - 1) : 0;
      case MainAxisAlignment.spaceAround:
        gap = _children.isNotEmpty ? mainSlack ~/ _children.length : 0;
        pos = gap ~/ 2;
      case MainAxisAlignment.spaceEvenly:
        gap = _children.isNotEmpty ? mainSlack ~/ (_children.length + 1) : 0;
        pos = gap;
    }

    for (final c in _children) {
      final crossExtent = _crossExtent(c.size);
      final crossOffset = switch (_crossAxisAlignment) {
        CrossAxisAlignment.start => 0,
        CrossAxisAlignment.end => ownCross - crossExtent,
        CrossAxisAlignment.center => (ownCross - crossExtent) ~/ 2,
        CrossAxisAlignment.stretch => 0,
      };
      _childOffsets[c] = _direction == Axis.horizontal
          ? CellOffset(pos, crossOffset)
          : CellOffset(crossOffset, pos);
      pos += _mainExtent(c.size) + gap;
    }

    final size = constraints.constrain(
      _direction == Axis.horizontal
          ? CellSize(ownMain, ownCross)
          : CellSize(ownCross, ownMain),
    );
    final boxMain = _mainExtent(size);
    _overflow = usedMain > boxMain ? usedMain - boxMain : 0;
    return size;
  }

  // Flex intrinsics: along the main axis the children sum (a Row's natural
  // width is the sum of its children's widths); on the cross axis they take
  // the max. Flex factors aren't applied here — we report the *natural*
  // size; the distribution of slack only matters during real layout.
  @override
  int computeMaxIntrinsicWidth(int? height) => _direction == Axis.horizontal
      ? _sumChildIntrinsic((c) => c.computeMaxIntrinsicWidth(height))
      : _maxChildIntrinsic((c) => c.computeMaxIntrinsicWidth(height));

  @override
  int computeMinIntrinsicWidth(int? height) => _direction == Axis.horizontal
      ? _sumChildIntrinsic((c) => c.computeMinIntrinsicWidth(height))
      : _maxChildIntrinsic((c) => c.computeMinIntrinsicWidth(height));

  @override
  int computeMaxIntrinsicHeight(int? width) => _direction == Axis.horizontal
      ? _maxChildIntrinsic((c) => c.computeMaxIntrinsicHeight(width))
      : _sumChildIntrinsic((c) => c.computeMaxIntrinsicHeight(width));

  @override
  int computeMinIntrinsicHeight(int? width) => _direction == Axis.horizontal
      ? _maxChildIntrinsic((c) => c.computeMinIntrinsicHeight(width))
      : _sumChildIntrinsic((c) => c.computeMinIntrinsicHeight(width));

  int _sumChildIntrinsic(int Function(RenderObject) of) {
    var total = 0;
    for (final c in _children) {
      total += of(c);
    }
    return total;
  }

  int _maxChildIntrinsic(int Function(RenderObject) of) {
    var best = 0;
    for (final c in _children) {
      final v = of(c);
      if (v > best) best = v;
    }
    return best;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (_overflow > 0) {
      // Clip overflowing children to the box (so they don't corrupt
      // siblings or paint out of the buffer), then flag the edge.
      _paintClipped(
        buffer,
        offset,
        screenOffset: screenOffset ?? offset,
        clipRect: clipRect,
      );
      return;
    }
    final baseScreenOffset = screenOffset ?? offset;
    for (final c in _children) {
      final childOffset = _childOffsets[c] ?? CellOffset.zero;
      final paintOffset = offset + childOffset;
      if (_isOutsidePaintBuffer(paintOffset, c.size, buffer.size) &&
          !_subtreeNeedsOffscreenPaint(c)) {
        continue;
      }
      c.paint(
        buffer,
        paintOffset,
        screenOffset: baseScreenOffset + childOffset,
        clipRect: clipRect,
      );
    }
  }

  bool _isOutsidePaintBuffer(
    CellOffset offset,
    CellSize childSize,
    CellSize bufferSize,
  ) {
    if (childSize.isEmpty || bufferSize.isEmpty) return true;
    final left = offset.col;
    final top = offset.row;
    final right = left + childSize.cols;
    final bottom = top + childSize.rows;
    return right <= 0 ||
        bottom <= 0 ||
        left >= bufferSize.cols ||
        top >= bufferSize.rows;
  }

  bool _subtreeNeedsOffscreenPaint(RenderObject object) {
    if (object is Selectable) return true;
    if (object is RenderObjectWithSingleChild) {
      final child = object.child;
      return child != null && _subtreeNeedsOffscreenPaint(child);
    }
    if (object is RenderObjectWithChildren) {
      for (final child in object.children) {
        if (_subtreeNeedsOffscreenPaint(child)) return true;
      }
    }
    return false;
  }

  void _paintClipped(
    CellBuffer buffer,
    CellOffset offset, {
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    if (size.isEmpty) return;
    // Scratch large enough to hold every child at its offset, so painting
    // never runs off the edge; we then blit only the box region.
    var w = size.cols;
    var h = size.rows;
    for (final c in _children) {
      final co = _childOffsets[c] ?? CellOffset.zero;
      final reachCol = co.col + c.size.cols;
      final reachRow = co.row + c.size.rows;
      if (reachCol > w) w = reachCol;
      if (reachRow > h) h = reachRow;
    }
    final scratch = CellBuffer(CellSize(w, h));
    final ownScreenRect = CellRect(offset: screenOffset, size: size);
    final inheritedIntersection = clipRect?.intersect(ownScreenRect);
    // A null clip means unbounded, so represent a real but empty intersection
    // with a zero-sized rectangle instead of accidentally dropping clipping.
    final effectiveClip = clipRect == null
        ? ownScreenRect
        : inheritedIntersection ??
              CellRect(offset: screenOffset, size: CellSize.zero);
    paintWithGeometryClip(ownScreenRect, () {
      for (final c in _children) {
        final childOffset = _childOffsets[c] ?? CellOffset.zero;
        c.paint(
          scratch,
          childOffset,
          screenOffset: screenOffset + childOffset,
          clipRect: effectiveClip,
        );
      }
    });
    for (var r = 0; r < size.rows; r++) {
      final tr = offset.row + r;
      if (tr < 0 || tr >= buffer.size.rows) continue;
      for (var col = 0; col < size.cols; col++) {
        final cell = scratch.atColRow(col, r);
        if (cell.role != CellRole.leading) continue;
        final tc = offset.col + col;
        if (tc < 0 || tc >= buffer.size.cols) continue;
        buffer.writeGrapheme(
          CellOffset(tc, tr),
          cell.grapheme!,
          style: cell.style,
        );
      }
    }
    // Carry only the Flex box's visible image windows. The scratch may be
    // larger than [size] to accommodate overflowing children; replaying every
    // full placement would let true-pixel content escape the same clip the
    // cell loop applies.
    buffer.compositeImageRectFrom(
      scratch,
      CellRect(offset: CellOffset.zero, size: size),
      offset,
    );
    if (debugShowOverflow) _paintOverflow(buffer, offset);
  }

  /// Paints a red shaded bar along the trailing edge of the box where
  /// content ran past it — an unmissable, terminal-friendly analogue of
  /// Flutter's overflow stripes.
  void _paintOverflow(CellBuffer buffer, CellOffset offset) {
    if (size.isEmpty) return;
    const marker = '▓';
    const style = CellStyle(foreground: AnsiColor(1));
    if (_direction == Axis.horizontal) {
      final col = offset.col + size.cols - 1;
      if (col < 0 || col >= buffer.size.cols) return;
      for (var r = 0; r < size.rows; r++) {
        final row = offset.row + r;
        if (row < 0 || row >= buffer.size.rows) continue;
        buffer.writeGrapheme(CellOffset(col, row), marker, style: style);
      }
    } else {
      final row = offset.row + size.rows - 1;
      if (row < 0 || row >= buffer.size.rows) return;
      for (var c = 0; c < size.cols; c++) {
        final col = offset.col + c;
        if (col < 0 || col >= buffer.size.cols) continue;
        buffer.writeGrapheme(CellOffset(col, row), marker, style: style);
      }
    }
  }

  // ---- Helpers -----------------------------------------------------------

  int _mainExtent(CellSize size) =>
      _direction == Axis.horizontal ? size.cols : size.rows;

  int _crossExtent(CellSize size) =>
      _direction == Axis.horizontal ? size.rows : size.cols;

  int? _mainMax(CellConstraints c) =>
      _direction == Axis.horizontal ? c.maxCols : c.maxRows;

  int? _crossMax(CellConstraints c) =>
      _direction == Axis.horizontal ? c.maxRows : c.maxCols;

  CellConstraints _childConstraintsForInflexible(int? crossMax) {
    // Unbounded main axis, available cross axis.
    if (_direction == Axis.horizontal) {
      return CellConstraints(
        minRows: _crossAxisAlignment == CrossAxisAlignment.stretch
            ? (crossMax ?? 0)
            : 0,
        maxRows: crossMax,
      );
    }
    return CellConstraints(
      minCols: _crossAxisAlignment == CrossAxisAlignment.stretch
          ? (crossMax ?? 0)
          : 0,
      maxCols: crossMax,
    );
  }

  CellConstraints _childConstraintsForFlexible(
    int? crossMax,
    int allocation,
    FlexFit fit,
  ) {
    final minMain = fit == FlexFit.tight ? allocation : 0;
    if (_direction == Axis.horizontal) {
      return CellConstraints(
        minCols: minMain,
        maxCols: allocation,
        minRows: _crossAxisAlignment == CrossAxisAlignment.stretch
            ? (crossMax ?? 0)
            : 0,
        maxRows: crossMax,
      );
    }
    return CellConstraints(
      minCols: _crossAxisAlignment == CrossAxisAlignment.stretch
          ? (crossMax ?? 0)
          : 0,
      maxCols: crossMax,
      minRows: minMain,
      maxRows: allocation,
    );
  }

  /// Deterministic integer flex distribution: floor each share, then
  /// distribute the leftover one cell at a time to the leftmost flex
  /// children in order. Returns allocations in the same order as
  /// [flexChildren].
  List<int> _allocateFlex(
    List<RenderFlexible> flexChildren,
    int available,
    int totalFlex,
  ) {
    final allocations = <int>[
      for (final c in flexChildren) (available * c.flex) ~/ totalFlex,
    ];
    final distributed = allocations.fold<int>(0, (s, v) => s + v);
    var leftover = available - distributed;
    var i = 0;
    while (leftover > 0 && i < allocations.length) {
      allocations[i] += 1;
      leftover -= 1;
      i += 1;
    }
    return allocations;
  }

  int _max0(int v) => v < 0 ? 0 : v;
}
