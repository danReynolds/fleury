// ScrollView: a scrollable window onto a single, taller child.
//
// Where `ListView` windows a list of items (only the visible ones are
// laid out), `ScrollView` takes one arbitrary child — a long paragraph,
// a form, a rendered document — measures it at its full natural height,
// and paints a clipped window at the current scroll offset. It is the
// generic viewport primitive the rest of the widget layer reuses (a
// pager, a tree body, scrollable panels) rather than each reinventing
// scroll math + clipping.
//
// Three pieces, mirroring ListView:
//   - ScrollController — a ChangeNotifier holding the scroll offset plus
//     read-back metrics (max offset, viewport / content extent). Optional;
//     the widget creates its own when none is given.
//   - ScrollView — the widget. Claims arrow / page / home / end when
//     focused and scrolls the viewport.
//   - _RenderScrollView — measures the child with an unbounded main axis,
//     clamps the offset, and paints the visible window (clipping the rest).
//
// Intentionally not here: horizontal scrolling, momentum/smooth scroll
// (cells are integers — scrolling is discrete), and windowed building for
// enormous children (use `ListView.builder` when most content is
// off-screen; ScrollView still lays out the whole child, but paints only
// the visible viewport into an intermediate buffer).

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../input/events.dart';
import 'focus.dart';
import 'framework.dart';
import 'list_view.dart' show EdgeBehavior;
import 'pointer.dart';
import 'scrollbar.dart';

/// Mutable scroll state for a [ScrollView]: the current offset plus
/// read-only metrics the render object writes back after each layout.
///
/// `offset` is in rows from the top of the content. It is clamped to
/// `0..maxOffset`; before the first layout (when metrics aren't known
/// yet) only the lower bound is enforced, so an initial offset survives
/// until layout can clamp it — mirroring how [ListController] preserves a
/// selection before `itemCount` is known.
class ScrollController extends ChangeNotifier {
  ScrollController({int offset = 0}) : _offset = offset < 0 ? 0 : offset;

  int _offset;
  int _maxOffset = 0;
  int _viewportExtent = 0;
  int _contentExtent = 0;
  bool _metricsKnown = false;
  bool _disposed = false;

  /// Rows scrolled from the top. Clamped to `0..maxOffset`.
  int get offset => _offset;
  set offset(int value) {
    _checkNotDisposed();
    var v = value < 0 ? 0 : value;
    if (_metricsKnown && v > _maxOffset) v = _maxOffset;
    if (_offset == v) return;
    _offset = v;
    notifyListeners();
  }

  /// The largest valid [offset] (`contentExtent - viewportExtent`, or 0
  /// when the content fits). Known only after the first layout.
  int get maxOffset => _maxOffset;

  /// Visible rows in the viewport (after the last layout).
  int get viewportExtent => _viewportExtent;

  /// Total rows the content occupies (after the last layout).
  int get contentExtent => _contentExtent;

  /// Whether the viewport is at the top / bottom of the content.
  bool get atTop => _offset <= 0;
  bool get atBottom => _offset >= _maxOffset;

  /// Scrolls by [delta] rows (negative scrolls up).
  void scrollBy(int delta) {
    _checkNotDisposed();
    offset = _offset + delta;
  }

  /// Scrolls so [value] is the top row.
  void jumpTo(int value) {
    _checkNotDisposed();
    offset = value;
  }

  /// Scrolls to the very top / bottom.
  void scrollToTop() {
    _checkNotDisposed();
    offset = 0;
  }

  void scrollToBottom() {
    _checkNotDisposed();
    offset = _metricsKnown ? _maxOffset : _offset;
  }

  /// Called by the render object during layout. Direct field writes (no
  /// notify) — these mirror layout state and notifying here would loop.
  void _applyMetrics(int contentExtent, int viewportExtent) {
    _checkNotDisposed();
    _contentExtent = contentExtent;
    _viewportExtent = viewportExtent;
    final max = contentExtent - viewportExtent;
    _maxOffset = max < 0 ? 0 : max;
    _metricsKnown = true;
    if (_offset > _maxOffset) _offset = _maxOffset;
    if (_offset < 0) _offset = 0;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('ScrollController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// A scrollable viewport onto a single [child].
///
/// When focused, claims:
///   - Up / Down — scroll one row (respecting [edgeBehavior] at the ends).
///   - PageUp / PageDown — scroll a viewport's worth.
///   - Home / End — jump to top / bottom.
///
/// At the top/bottom edge, [edgeBehavior] decides whether the key is
/// consumed (`contain`) or returned to the focus chain (`bubble`) so an
/// ancestor — e.g. a pane coordinator — can move focus instead.
class ScrollView extends StatefulWidget {
  const ScrollView({
    super.key,
    required this.child,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.scrollbar = false,
  });

  /// The full content subtree; it is laid out eagerly and clipped to the viewport.
  final Widget child;

  /// External controller. If null, the widget creates and disposes its own.
  final ScrollController? controller;

  /// External focus node. If null, the widget creates and disposes its own.
  final FocusNode? focusNode;

  /// Whether to request focus on first mount.
  final bool autofocus;

  /// What to do with up/down at the top/bottom edge.
  final EdgeBehavior edgeBehavior;

  /// When true, wrap the viewport in a [Scrollbar] gutter that reflects the
  /// scroll position and lets the mouse drag/click to scroll. A one-line
  /// opt-in sharing this view's own controller.
  ///
  /// Needs a bounded width to anchor the right-edge gutter — under an unbounded
  /// width it throws a clear error rather than collapsing the content; wrap the
  /// view in an Expanded or a SizedBox.
  final bool scrollbar;

  @override
  State<ScrollView> createState() => _ScrollViewState();
}

class _ScrollViewState extends State<ScrollView> {
  late ScrollController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  int _paintRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ScrollView');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(ScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? ScrollController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ScrollView');
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  void _onChange() {
    setState(() {
      _paintRevision += 1;
    });
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final page = _controller.viewportExtent < 1
        ? 1
        : _controller.viewportExtent;
    switch (event.code) {
      case KeyCode.arrowUp:
        if (_controller.atTop) return _edge();
        _controller.scrollBy(-1);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        if (_controller.atBottom) return _edge();
        _controller.scrollBy(1);
        return KeyEventResult.handled;
      case KeyCode.pageUp:
        if (_controller.atTop) return _edge();
        _controller.scrollBy(-page);
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        if (_controller.atBottom) return _edge();
        _controller.scrollBy(page);
        return KeyEventResult.handled;
      case KeyCode.home:
        _controller.scrollToTop();
        return KeyEventResult.handled;
      case KeyCode.end:
        _controller.scrollToBottom();
        return KeyEventResult.handled;
      default:
        // Ctrl+D / Ctrl+U scroll a half page (the less / vim convention).
        if (event.hasCtrl && !event.hasAlt) {
          final half = page < 2 ? 1 : page ~/ 2;
          if (event.code.character == 'd') {
            if (_controller.atBottom) return _edge();
            _controller.scrollBy(half);
            return KeyEventResult.handled;
          }
          if (event.code.character == 'u') {
            if (_controller.atTop) return _edge();
            _controller.scrollBy(-half);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _edge() => widget.edgeBehavior == EdgeBehavior.bubble
      ? KeyEventResult.ignored
      : KeyEventResult.handled;

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = PointerScrollListener(
      router: PointerRouterScope.maybeOf(context),
      onScrollUp: () => _controller.scrollBy(-3),
      onScrollDown: () => _controller.scrollBy(3),
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKey: _handleKey,
        child: _ScrollViewport(
          controller: _controller,
          paintRevision: _paintRevision,
          child: widget.child,
        ),
      ),
    );
    if (!widget.scrollbar) return content;
    // Needs a bounded width to anchor the right-edge gutter — Scrollbar throws
    // a clear error under unbounded width rather than collapsing the content.
    return Scrollbar(controller: _controller, child: content);
  }
}

class _ScrollViewport extends SingleChildRenderObjectWidget {
  const _ScrollViewport({
    required this.controller,
    required this.paintRevision,
    required super.child,
  });

  final ScrollController controller;
  final int paintRevision;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollView(controller: controller, paintRevision: paintRevision);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScrollView renderObject,
  ) {
    renderObject.controller = controller;
    renderObject.paintRevision = paintRevision;
  }
}

/// Measures the child with an unbounded main axis (so it reports its full
/// height), fills the bounded viewport, clamps the controller's offset to
/// the content, and paints the visible window — dropping everything above
/// and below it.
class _RenderScrollView extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderScrollView({
    required ScrollController controller,
    required int paintRevision,
  }) : _controller = controller,
       _paintRevision = paintRevision;

  ScrollController _controller;
  ScrollController get controller => _controller;
  set controller(ScrollController value) {
    if (identical(_controller, value)) return;
    _controller = value;
    markNeedsLayout();
  }

  int _paintRevision;
  set paintRevision(int value) {
    if (_paintRevision == value) return;
    _paintRevision = value;
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
    if (c == null) {
      _controller._applyMetrics(0, 0);
      return constraints.constrain(CellSize.zero);
    }
    // Bound the cross axis to our width; leave the main axis unbounded so
    // the child reports its full content height.
    final childSize = c.layout(
      CellConstraints(
        minCols: constraints.minCols,
        maxCols: constraints.maxCols,
      ),
    );
    final cols = constraints.hasBoundedWidth
        ? constraints.maxCols!
        : childSize.cols;
    final rows = constraints.hasBoundedHeight
        ? constraints.maxRows!
        : childSize.rows;
    final size = constraints.constrain(CellSize(cols, rows));
    _controller._applyMetrics(childSize.rows, size.rows);
    return size;
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
    final childSize = c.size;
    if (childSize.isEmpty || size.isEmpty) return;

    // Our screen rect. clipRect is intersected with any ancestor clip
    // so a ScrollView nested inside another clipped region honors
    // both boundaries.
    final ourScreenOffset = screenOffset ?? offset;
    final ourScreenRect = CellRect(offset: ourScreenOffset, size: size);
    final inheritedIntersection = clipRect?.intersect(ourScreenRect);
    if (clipRect != null &&
        inheritedIntersection == null &&
        !isRetainingPaintGeometry) {
      return;
    }
    // A retained boundary must cache locally hidden viewport content too: an
    // ancestor scroll can reveal it later without invalidating this subtree.
    // Preserve a real empty clip for geometry while still walking/painting the
    // viewport into the boundary-local cache.
    final effectiveClip = clipRect == null
        ? ourScreenRect
        : inheritedIntersection ??
              CellRect(offset: ourScreenOffset, size: CellSize.zero);

    final scroll = _controller.offset;
    // Paint only the visible viewport into scratch. The negative child offset
    // drops rows above the scroll window while screenOffset preserves the
    // child's full screen-space origin for selection and hit-testing.
    final scratch = CellBuffer(size);
    paintWithGeometryClip(ourScreenRect, () {
      c.paint(
        scratch,
        CellOffset(0, -scroll),
        screenOffset: CellOffset(
          ourScreenOffset.col,
          ourScreenOffset.row - scroll,
        ),
        clipRect: effectiveClip,
      );
    });

    final bufCols = buffer.size.cols;
    final bufRows = buffer.size.rows;
    final visibleCols = size.cols < childSize.cols ? size.cols : childSize.cols;
    for (var r = 0; r < size.rows; r++) {
      for (var col = 0; col < visibleCols; col++) {
        final cell = scratch.atColRow(col, r);
        if (cell.role != CellRole.leading) continue;
        final tc = offset.col + col;
        final tr = offset.row + r;
        if (tc < 0 || tr < 0 || tc >= bufCols || tr >= bufRows) continue;
        buffer.writeGrapheme(
          CellOffset(tc, tr),
          cell.grapheme!,
          style: cell.style,
        );
      }
    }
    // Inline images live on the buffer as placements, not in cells, so carry
    // the exact source window the leading-cell loop used. The scratch
    // placements are already scroll-adjusted (the child painted at
    // row -scroll); preserving their original box metadata keeps partial
    // leading/trailing slices fitted against the unscrolled image.
    buffer.compositeImageRectFrom(
      scratch,
      CellRect.fromLTWH(0, 0, visibleCols, size.rows),
      offset,
    );
  }
}
