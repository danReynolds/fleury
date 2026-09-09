// A one-axis viewport onto an eagerly laid out child. ListView uses the same
// axis conventions while mounting and measuring only its visible items.

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_flex.dart' show Axis;
import '../rendering/scroll_axis.dart';
import '../rendering/render_object.dart';
import '../input/events.dart';
import 'focus.dart';
import 'framework.dart';
import 'keyboard.dart';
import 'list_view.dart' show EdgeBehavior;
import 'pointer.dart';
import 'scrollbar.dart';
import 'tui_binding.dart';

/// Mutable scroll state for a [ScrollView]: the current offset plus
/// read-only metrics the render object writes back after each layout.
///
/// `offset` is in cells from the start of the content along the view's axis. It is clamped to
/// `0..maxOffset`; before the first layout (when metrics aren't known
/// yet) only the lower bound is enforced, so an initial offset survives
/// until layout can clamp it — mirroring how [ListController] preserves a
/// current item before `itemCount` is known.
class ScrollController extends ChangeNotifier {
  ScrollController({int initialOffset = 0})
    : _offset = initialOffset < 0 ? 0 : initialOffset;

  int _offset;
  int _maxOffset = 0;
  int _viewportExtent = 0;
  int _contentExtent = 0;
  bool _metricsKnown = false;
  bool _disposed = false;
  Object? _owner;

  void _attach(Object owner) {
    _checkNotDisposed();
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError(
        'ScrollController can attach to only one owning view at a time.',
      );
    }
    _owner = owner;
  }

  TuiBinding? _binding;
  bool _metricsNotificationPending = false;
  int _attachment = 0;

  /// Cells scrolled from the start along [ScrollView.scrollDirection]. Clamped to `0..maxOffset`.
  int get offset => _offset;
  set offset(int value) {
    _checkNotDisposed();
    var v = value < 0 ? 0 : value;
    if (_owner != null && _metricsKnown && v > _maxOffset) v = _maxOffset;
    if (_offset == v) return;
    _offset = v;
    notifyListeners();
  }

  /// The largest valid [offset] (`contentExtent - viewportExtent`, or 0
  /// when the content fits). Known only after the first layout.
  int get maxOffset => _maxOffset;

  /// Visible cells along the scrolling axis (after the last layout).
  int get viewportExtent => _viewportExtent;

  /// Content extent in cells along the scrolling axis (after the last layout).
  int get contentExtent => _contentExtent;

  /// Whether the viewport is at the start / end of the content.
  bool get atStart => _offset <= 0;
  bool get atEnd => _offset >= _maxOffset;

  /// Vertical spelling of [atStart].
  bool get atTop => atStart;

  /// Vertical spelling of [atEnd].
  bool get atBottom => atEnd;

  /// Scrolls by [delta] cells along the scrolling axis (negative moves back).
  void scrollBy(int delta) {
    _checkNotDisposed();
    offset = _offset + delta;
  }

  /// Scrolls so cell [value] is at the start of the viewport.
  void jumpTo(int value) {
    _checkNotDisposed();
    offset = value;
  }

  /// Scrolls to the start of the content.
  void scrollToStart() {
    _checkNotDisposed();
    offset = 0;
  }

  /// Scrolls to the end of the content.
  void scrollToEnd() {
    _checkNotDisposed();
    offset = _metricsKnown ? _maxOffset : _offset;
  }

  /// Vertical spelling of [scrollToStart].
  void scrollToTop() => scrollToStart();

  /// Vertical spelling of [scrollToEnd].
  void scrollToBottom() => scrollToEnd();

  /// Layout writes metrics immediately; observers are notified after the frame.
  void _applyMetrics(int contentExtent, int viewportExtent) {
    _checkNotDisposed();
    final before = (_contentExtent, _viewportExtent, _offset);
    _contentExtent = contentExtent;
    _viewportExtent = viewportExtent;
    final max = contentExtent - viewportExtent;
    _maxOffset = max < 0 ? 0 : max;
    _metricsKnown = true;
    if (_offset > _maxOffset) _offset = _maxOffset;
    if (_offset < 0) _offset = 0;
    if (before != (_contentExtent, _viewportExtent, _offset)) {
      _notifyAfterFrame();
    }
  }

  void _notifyAfterFrame() {
    final binding = _binding;
    if (binding == null || _metricsNotificationPending) return;
    _metricsNotificationPending = true;
    final attachment = _attachment;
    binding.addPostFrameCallback((_) {
      if (_disposed || attachment != _attachment) return;
      _metricsNotificationPending = false;
      notifyListeners();
    });
  }

  void _detach([Object? owner]) {
    if (owner != null && !identical(_owner, owner)) return;
    _owner = null;
    _attachment++;
    _metricsNotificationPending = false;
    _binding = null;
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
    _detach();
    super.dispose();
  }
}

/// A scrollable viewport onto a single [child].
///
/// When focused, claims:
///   - Up / Down (vertical), Left / Right (horizontal) — scroll one cell.
///   - PageUp / PageDown — scroll a viewport's worth.
///   - Home / End — jump to the start / end.
///
/// At either edge, [edgeBehavior] decides whether the key is
/// consumed (`contain`) or returned to the focus chain (`bubble`) so an
/// ancestor — e.g. a pane coordinator — can move focus instead.
class ScrollView extends StatefulWidget {
  const ScrollView({
    super.key,
    required this.child,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.focusNode,
    this.autofocus = false,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.scrollbar = false,
  });

  /// The full content subtree; it is laid out eagerly and clipped to the viewport.
  final Widget child;

  /// The axis along which content scrolls. The other axis stays constrained.
  final Axis scrollDirection;

  /// External controller. If null, the widget creates and disposes its own.
  final ScrollController? controller;

  /// External focus node. If null, the widget creates and disposes its own.
  final FocusNode? focusNode;

  /// Whether to request focus on first mount.
  final bool autofocus;

  /// How main-axis arrows and wheel gestures behave at an edge.
  final EdgeBehavior edgeBehavior;

  /// When true, wrap the viewport in a [Scrollbar] gutter that reflects the
  /// scroll position and lets the mouse drag/click to scroll. A one-line
  /// opt-in sharing this view's own controller.
  ///
  /// The gutter is on the right for vertical scrolling and below the content
  /// for horizontal scrolling. It needs a bounded cross axis: width for a
  /// vertical view, height for a horizontal one.
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
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ScrollView');
    _ownsFocusNode = widget.focusNode == null;
    _controller = widget.controller ?? ScrollController();
    _ownsController = widget.controller == null;
    _controller._attach(this);
    _controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(ScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onChange);
      _controller._detach(this);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? ScrollController();
      _ownsController = widget.controller == null;
      _controller._attach(this);
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

  /// Detector adapter: this widget consumes only the scrolls it can
  /// perform, so an arrow at the edge falls through to whoever is next
  /// (RFC 0020 §17's conditional-consumption floor).
  void _detectKey(KeyEvent event) {
    if (_handleKey(event) == KeyEventResult.handled) event.consume();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final page = _controller.viewportExtent < 1
        ? 1
        : _controller.viewportExtent;
    final code = widget.scrollDirection.navigationKey(event.code);
    if (code == null) return KeyEventResult.ignored;
    switch (code) {
      case KeyCode.arrowUp:
        if (_controller.atStart) return _edge();
        _controller.scrollBy(-1);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        if (_controller.atEnd) return _edge();
        _controller.scrollBy(1);
        return KeyEventResult.handled;
      case KeyCode.pageUp:
        if (_controller.atStart) return _edge();
        _controller.scrollBy(-page);
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        if (_controller.atEnd) return _edge();
        _controller.scrollBy(page);
        return KeyEventResult.handled;
      case KeyCode.home:
        _controller.scrollToStart();
        return KeyEventResult.handled;
      case KeyCode.end:
        _controller.scrollToEnd();
        return KeyEventResult.handled;
      default:
        // Ctrl+D / Ctrl+U scroll a half page (the less / vim convention).
        if (event.hasCtrl && !event.hasAlt) {
          final half = page < 2 ? 1 : page ~/ 2;
          if (event.code.character == 'd') {
            if (_controller.atEnd) return _edge();
            _controller.scrollBy(half);
            return KeyEventResult.handled;
          }
          if (event.code.character == 'u') {
            if (_controller.atStart) return _edge();
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
  void deactivate() {
    _controller.removeListener(_onChange);
    _controller._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _controller._attach(this);
    _controller._binding = TuiBinding.maybeOf(context);
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller._detach(this);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller._binding = TuiBinding.maybeOf(context);
    final Widget content = MouseRegion(
      onScroll: (details) {
        final delta = widget.scrollDirection.position(details.delta);
        if (delta == 0) return false;
        final before = _controller.offset;
        _controller.scrollBy(delta * 3);
        return _controller.offset != before ||
            widget.edgeBehavior == EdgeBehavior.contain;
      },
      child: KeyDetector(
        onKey: _detectKey,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          child: _ScrollViewport(
            controller: _controller,
            scrollDirection: widget.scrollDirection,
            paintRevision: _paintRevision,
            child: widget.child,
          ),
        ),
      ),
    );
    if (!widget.scrollbar) return content;
    // The gutter shares this view's controller and axis.
    return Scrollbar(
      controller: _controller,
      scrollDirection: widget.scrollDirection,
      child: content,
    );
  }
}

class _ScrollViewport extends SingleChildRenderObjectWidget {
  const _ScrollViewport({
    required this.controller,
    required this.paintRevision,
    required this.scrollDirection,
    required super.child,
  });

  final ScrollController controller;
  final int paintRevision;
  final Axis scrollDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScrollView(
    controller: controller,
    paintRevision: paintRevision,
    scrollDirection: scrollDirection,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScrollView renderObject,
  ) {
    renderObject.controller = controller;
    renderObject.scrollDirection = scrollDirection;
    renderObject.paintRevision = paintRevision;
  }
}

/// Measures the child with an unbounded scrolling axis, clamps the offset,
/// and paints the visible window into a viewport-sized scratch buffer.
class _RenderScrollView extends RenderObject
    implements RenderObjectWithSingleChild {
  @override
  CellOffset childOffsetOf(RenderObject child) =>
      _scrollDirection.offset(-_controller.offset);

  @override
  CellRect? childClipOf(RenderObject child) =>
      CellRect(offset: CellOffset.zero, size: size);

  _RenderScrollView({
    required ScrollController controller,
    required int paintRevision,
    required Axis scrollDirection,
  }) : _controller = controller,
       _paintRevision = paintRevision,
       _scrollDirection = scrollDirection;

  Axis _scrollDirection;
  set scrollDirection(Axis value) {
    if (_scrollDirection == value) return;
    _scrollDirection = value;
    markNeedsLayout();
  }

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
    // Constrain the cross axis and measure the child's full scrolling extent.
    final childSize = c.layout(
      _scrollDirection.childConstraints(constraints, keepCrossMinimum: true),
    );
    final cols = constraints.hasBoundedWidth
        ? constraints.maxCols!
        : childSize.cols;
    final rows = constraints.hasBoundedHeight
        ? constraints.maxRows!
        : childSize.rows;
    final size = constraints.constrain(CellSize(cols, rows));
    _controller._applyMetrics(
      _scrollDirection.extent(childSize),
      _scrollDirection.extent(size),
    );
    return size;
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    final c = _child;
    if (c == null) return;
    final childSize = c.size;
    if (childSize.isEmpty || size.isEmpty) return;

    // Entirely outside the buffer: nothing of the viewport can land.
    final bufferRect = CellRect(offset: CellOffset.zero, size: buffer.size);
    if (CellRect(offset: offset, size: size).intersect(bufferRect) == null) {
      return;
    }

    final scroll = _controller.offset;
    // Paint only the visible viewport into scratch: the negative child offset
    // drops content before the scroll window and the scratch's bounds clip
    // the rest. Descendants derive their screen position from
    // [childOffsetOf], never from where they land in the scratch.
    final scratch = CellBuffer(size);
    c.paint(scratch, _scrollDirection.offset(-scroll));

    final bufCols = buffer.size.cols;
    final bufRows = buffer.size.rows;
    final visibleCols = size.cols < childSize.cols ? size.cols : childSize.cols;
    for (var r = 0; r < size.rows; r++) {
      final tr = offset.row + r;
      if (tr < 0 || tr >= bufRows) continue;
      for (var col = 0; col < visibleCols; col++) {
        final tc = offset.col + col;
        if (tc < 0 || tc >= bufCols) continue;
        // Replay, not re-measure: the viewport carries the cells the child
        // painted, wide-pair roles included. Re-deriving the width here would
        // let the frame buffer disagree with the scratch the child measured
        // into, severing every ambiguous-width pair on a surface whose probe
        // measured ambiguous glyphs wide.
        buffer.replayCellFrom(scratch, col, r, tc, tr);
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
