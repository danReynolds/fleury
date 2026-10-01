import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_flex.dart' show Axis, CrossAxisAlignment;
import '../rendering/scroll_axis.dart';
import '../rendering/render_object.dart';
import '../rendering/width_resolver.dart';
import 'basic.dart';
import 'framework.dart';
import 'list_view.dart' show ListController;
import 'media_query.dart';
import 'pointer.dart';
import 'scroll_view.dart' show ScrollController;

/// (content, viewport, offset) in cells or item fractions.
typedef _ScrollbarMetrics = (int, int, int);

/// A scroll indicator drawn beside [child] (vertical) or below it (horizontal),
/// reflecting a [ScrollController] (or a [ListController] via
/// [Scrollbar.list]). The thumb's size shows the visible fraction and its
/// position shows how far you've scrolled; when everything fits, the thumb
/// fills the track unless [showWhenFits] is false.
///
/// `ScrollView(scrollbar: true)` and `ListView(scrollbar: true)` add one that
/// shares the view's own controller. Wrap a view yourself to style the bar,
/// giving it and the view the same controller.
///
/// When the mouse is enabled, click the track or drag the thumb to scroll
/// — the drag is captured, so it keeps tracking even past the bar's edge.
/// Metrics are read at paint (after the scrollable lays out), so the thumb
/// is correct on the first frame and follows scrolling automatically.
///
/// The bar takes its gutter from its own space, so it needs a bounded width
/// (vertical) or height (horizontal); laid out without one, it throws a
/// [StateError].
class Scrollbar extends StatefulWidget {
  Scrollbar({
    super.key,

    /// The controller of the scroll view in [child]; give that view the same
    /// controller. The thumb follows the controller's extents and
    /// [ScrollController.offset], and a click or drag on the bar sets that
    /// offset.
    required ScrollController controller,
    required this.child,
    this.thickness = 1,
    this.scrollDirection = Axis.vertical,
    this.trackStyle = const CellStyle(dim: true),
    this.thumbStyle = CellStyle.none,
    this.showWhenFits = true,
  }) : _metrics = (() => (
         controller.contentExtent,
         controller.viewportExtent,
         controller.offset,
       )),
       _scrollTo = ((f) =>
           controller.offset = (controller.maxOffset * f).round());

  /// Scrollbar for a `ListView`, including partial visibility within oversized items.
  /// Unmeasured items count equally, so geometry is approximate for mixed
  /// sizes. Dragging to either endpoint reaches the actual content edge.
  Scrollbar.list({
    super.key,

    /// The controller of the list in [child]; give that list the same
    /// controller. The thumb follows [ListController.scrollFraction] and
    /// [ListController.visibleFraction], and a click or drag on the bar calls
    /// [ListController.jumpToFraction], which scrolls without moving the
    /// list's cursor.
    required ListController controller,
    required this.child,
    this.thickness = 1,
    this.scrollDirection = Axis.vertical,
    this.trackStyle = const CellStyle(dim: true),
    this.thumbStyle = CellStyle.none,
    this.showWhenFits = true,
  }) : _metrics = (() {
         // Fixed precision keeps the bar independent of whether the viewport
         // spans many short items or part of one oversized item.
         const units = 1000000;
         final visible = (controller.visibleFraction * units).round();
         return (
           units,
           visible,
           (controller.scrollFraction * (units - visible)).round(),
         );
       }),
       _scrollTo = controller.jumpToFraction;

  final _ScrollbarMetrics Function() _metrics;
  final void Function(double fraction) _scrollTo;

  /// The scrolling view the bar reflects, which must scroll with the
  /// controller the bar was given. It gets all the space except the bar's
  /// gutter.
  final Widget child;

  /// How thick the bar is: the glyph columns of a vertical bar's gutter, or
  /// the rows of a horizontal bar's. Each column or row repeats the same track
  /// and thumb.
  ///
  /// A bar glyph is one cell wide, or two on a terminal measured to draw
  /// ambiguous-width glyphs double-width, so a vertical gutter is `thickness`
  /// or twice that many cells wide.
  final int thickness;

  /// Must match the axis of the owning view. Horizontal bars use a bottom gutter.
  final Axis scrollDirection;

  /// The style of the track, the part of the bar the thumb doesn't cover,
  /// drawn with `│` (vertical) or `─` (horizontal). Defaults to dim.
  final CellStyle trackStyle;

  /// The style of the thumb, drawn with `█`. Defaults to [CellStyle.none],
  /// the terminal's own colors: the bar doesn't read the theme.
  final CellStyle thumbStyle;

  /// Whether to draw the bar when all content is visible. When false, a fitting
  /// view keeps its gutter and child identity but paints no bar and ignores
  /// track clicks and drags. The default preserves the full-track thumb.
  final bool showWhenFits;

  @override
  State<Scrollbar> createState() => _ScrollbarState();
}

/// Where the bar is on screen: derived from its render object's layout when
/// a drag on the track needs to map a local pointer position to a scroll fraction.
class _ScrollbarGeometry {
  RenderObject? host;
}

class _ScrollbarState extends State<Scrollbar> {
  final _ScrollbarGeometry _geom = _ScrollbarGeometry();

  void _jumpToPosition(CellOffset position) {
    final (content, viewport, _) = widget._metrics();
    if (!widget.showWhenFits && content <= viewport) return;
    final host = _geom.host;
    if (host == null) return;
    final extent = widget.scrollDirection.extent(host.size);
    if (extent <= 1) return;
    final f = (widget.scrollDirection.position(position) / (extent - 1)).clamp(
      0.0,
      1.0,
    );
    widget._scrollTo(f);
  }

  @override
  Widget build(BuildContext context) {
    final policy = MediaQuery.textPolicyOf(context);
    final vertical = widget.scrollDirection == Axis.vertical;
    // The flex divides the cross axis between the viewport and its gutter.
    // On ambiguous-wide surfaces a vertical bar reserves whole glyph widths.
    return _RequireBoundedCrossAxis(
      scrollDirection: widget.scrollDirection,
      child: Flex(
        direction: vertical ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.child),
          GestureDetector(
            onTapDown: (details) => _jumpToPosition(details.localPosition),
            onDragUpdate: (details) => _jumpToPosition(details.localPosition),
            child: SizedBox(
              width: vertical
                  ? widget.thickness * _barGlyphWidth(policy)
                  : null,
              height: vertical ? null : widget.thickness,
              child: _BarView(
                metrics: widget._metrics,
                geometry: _geom,
                scrollDirection: widget.scrollDirection,
                trackStyle: widget.trackStyle,
                thumbStyle: widget.thumbStyle,
                textPolicy: policy,
                showWhenFits: widget.showWhenFits,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A gutter needs a bounded cross axis. Otherwise Expanded would silently
/// allocate zero cells to its sibling viewport.
class _RequireBoundedCrossAxis extends SingleChildRenderObjectWidget {
  const _RequireBoundedCrossAxis({
    required this.scrollDirection,
    required super.child,
  });
  final Axis scrollDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRequireBoundedCrossAxis(scrollDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderRequireBoundedCrossAxis renderObject,
  ) {
    if (renderObject.scrollDirection != scrollDirection) {
      renderObject.scrollDirection = scrollDirection;
      renderObject.markNeedsLayout();
    }
  }
}

class _RenderRequireBoundedCrossAxis extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderRequireBoundedCrossAxis(this.scrollDirection);
  Axis scrollDirection;
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
    if (scrollDirection.maxCrossExtent(constraints) == null) {
      final dimension = scrollDirection == Axis.vertical ? 'width' : 'height';
      throw StateError(
        'Scrollbar needs a bounded $dimension to anchor its gutter, but was given '
        'an unbounded $dimension. Give it a bounded $dimension — wrap it in Expanded '
        'or a SizedBox($dimension: ...).',
      );
    }
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    return c.layout(constraints);
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    _child?.paint(buffer, offset);
  }
}

/// The bar's two glyphs. Both are East Asian Ambiguous (UAX #11): one cell
/// under the spec policy, two on a surface whose probe measured ambiguous
/// glyphs wide (RFC 0019).
const String _thumbGlyph = '\u2588';
const String _trackGlyph = '\u2502';

const WidthResolver _barWidthResolver = DefaultWidthResolver();

/// Columns one bar glyph occupies under [policy] — the gutter's reserved
/// width per unit of thickness, and the step the paint advances by. Both
/// sides of that agreement read this one function.
int _barGlyphWidth(TextPresentationPolicy policy) {
  final thumb = _barWidthResolver.widthOfGrapheme(_thumbGlyph, policy.widths);
  final track = _barWidthResolver.widthOfGrapheme(_trackGlyph, policy.widths);
  return thumb > track ? thumb : track;
}

class _BarView extends LeafRenderObjectWidget {
  const _BarView({
    required this.metrics,
    required this.geometry,
    required this.scrollDirection,
    required this.trackStyle,
    required this.thumbStyle,
    required this.textPolicy,
    required this.showWhenFits,
  });

  final _ScrollbarMetrics Function() metrics;
  final _ScrollbarGeometry geometry;
  final Axis scrollDirection;
  final CellStyle trackStyle;
  final CellStyle thumbStyle;
  final TextPresentationPolicy textPolicy;
  final bool showWhenFits;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScrollbar(
    metrics: metrics,
    geometry: geometry,
    scrollDirection: scrollDirection,
    trackStyle: trackStyle,
    thumbStyle: thumbStyle,
    textPolicy: textPolicy,
    showWhenFits: showWhenFits,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScrollbar renderObject,
  ) {
    renderObject
      ..metrics = metrics
      ..geometry = geometry
      ..scrollDirection = scrollDirection
      ..trackStyle = trackStyle
      ..thumbStyle = thumbStyle
      ..showWhenFits = showWhenFits
      ..textPolicy = textPolicy;
  }
}

/// Fills its slot and paints the scrollbar track + thumb, recording its
/// painted geometry for the drag handler. Reads metrics at paint so they
/// reflect the just-completed layout.
class _RenderScrollbar extends RenderObject {
  _RenderScrollbar({
    required _ScrollbarMetrics Function() metrics,
    required _ScrollbarGeometry geometry,
    required Axis scrollDirection,
    required CellStyle trackStyle,
    required CellStyle thumbStyle,
    required TextPresentationPolicy textPolicy,
    required bool showWhenFits,
  }) : _metrics = metrics,
       _geometry = geometry,
       _scrollDirection = scrollDirection,
       _trackStyle = trackStyle,
       _thumbStyle = thumbStyle,
       _showWhenFits = showWhenFits,
       _textPolicy = textPolicy {
    geometry.host = this;
  }

  Axis _scrollDirection;
  set scrollDirection(Axis value) {
    if (_scrollDirection == value) return;
    _scrollDirection = value;
    markNeedsPaintOnly();
  }

  bool _showWhenFits;
  set showWhenFits(bool value) {
    if (_showWhenFits == value) return;
    _showWhenFits = value;
    markNeedsPaintOnly();
  }

  TextPresentationPolicy _textPolicy;
  set textPolicy(TextPresentationPolicy v) {
    if (_textPolicy == v) return;
    _textPolicy = v;
    markNeedsPaintOnly();
  }

  _ScrollbarMetrics Function() _metrics;
  set metrics(_ScrollbarMetrics Function() v) {
    if (identical(_metrics, v)) return;
    _metrics = v;
    markNeedsPaintOnly();
  }

  _ScrollbarGeometry _geometry;
  set geometry(_ScrollbarGeometry v) {
    if (_geometry == v) return;
    _geometry = v;
    v.host = this;
    markNeedsPaintOnly();
  }

  CellStyle _trackStyle;
  set trackStyle(CellStyle v) {
    if (_trackStyle == v) return;
    _trackStyle = v;
    markNeedsPaintOnly();
  }

  CellStyle _thumbStyle;
  set thumbStyle(CellStyle v) {
    if (_thumbStyle == v) return;
    _thumbStyle = v;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    // Fill the gutter slot the parent allotted.
    final cols = constraints.maxCols ?? constraints.minCols;
    final rows = constraints.maxRows ?? constraints.minRows;
    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    if (size.isEmpty) return;
    // Quantize horizontal geometry to whole glyphs. A minimum one-cell thumb
    // at the last column would disappear on an ambiguous-wide surface.
    final glyphWidth = _barGlyphWidth(_textPolicy);
    final h = _scrollDirection == Axis.vertical
        ? size.rows
        : size.cols ~/ glyphWidth;
    if (h == 0) return;
    final (content, viewport, scrollOffset) = _metrics();
    if (!_showWhenFits && content <= viewport) return;
    final int thumbSize;
    final int thumbTop;
    if (content <= viewport || content <= 0) {
      thumbSize = h;
      thumbTop = 0;
    } else {
      thumbSize = ((h * viewport) / content).round().clamp(1, h);
      final maxOffset = content - viewport;
      thumbTop = ((h - thumbSize) * scrollOffset / maxOffset).round().clamp(
        0,
        h - thumbSize,
      );
    }

    // The gutter reserved `thickness × glyphWidth` columns (see
    // [_ScrollbarState.build]); tile it with whole glyphs measured the same
    // way. A glyph that no longer fits is skipped rather than written
    // half-in — on an ambiguous-wide surface a one-column write would put
    // the thumb's second cell over the content beside it.
    final widths = _textPolicy.widths;
    final lastCol = offset.col + size.cols;
    for (var r = 0; r < size.rows; r++) {
      final row = offset.row + r;
      if (row < 0 || row >= buffer.size.rows) continue;
      for (
        var col = offset.col;
        col + glyphWidth <= lastCol;
        col += glyphWidth
      ) {
        if (col < 0 || col >= buffer.size.cols) continue;
        final position = _scrollDirection == Axis.vertical
            ? r
            : (col - offset.col) ~/ glyphWidth;
        final isThumb = position >= thumbTop && position < thumbTop + thumbSize;
        final glyph = isThumb
            ? _thumbGlyph
            : (_scrollDirection == Axis.vertical ? _trackGlyph : '\u2500');
        final style = isThumb ? _thumbStyle : _trackStyle;
        buffer.writeGrapheme(
          CellOffset(col, row),
          glyph,
          style: style,
          policy: widths,
        );
      }
    }
  }
}
