import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_flex.dart' show CrossAxisAlignment;
import '../rendering/render_object.dart';
import '../rendering/width_resolver.dart';
import 'basic.dart';
import 'framework.dart';
import 'list_view.dart' show ListController;
import 'media_query.dart';
import 'pointer.dart';
import 'scroll_view.dart' show ScrollController;

/// (content, viewport, offset) in rows or items.
typedef _ScrollbarMetrics = (int, int, int);

/// A vertical scroll indicator drawn in a gutter on the right of [child],
/// reflecting a [ScrollController] (or a [ListController] via
/// [Scrollbar.list]). The thumb's size shows the visible fraction and its
/// position shows how far you've scrolled; when everything fits, the thumb
/// fills the track.
///
/// When the mouse is enabled, click the track or drag the thumb to scroll
/// — the drag is captured, so it keeps tracking even past the bar's edge.
/// Metrics are read at paint (after the scrollable lays out), so the thumb
/// is correct on the first frame and follows scrolling automatically.
class Scrollbar extends StatefulWidget {
  Scrollbar({
    super.key,
    required ScrollController controller,
    required this.child,
    this.thickness = 1,
    this.trackStyle = const CellStyle(dim: true),
    this.thumbStyle = CellStyle.none,
  }) : _metrics = (() => (
         controller.contentExtent,
         controller.viewportExtent,
         controller.offset,
       )),
       _scrollTo = ((f) =>
           controller.offset = (controller.maxOffset * f).round());

  /// Scrollbar for an item-scrolled [ListView]; the thumb reflects the
  /// visible item range, and dragging jumps the viewport by item.
  Scrollbar.list({
    super.key,
    required ListController controller,
    required this.child,
    this.thickness = 1,
    this.trackStyle = const CellStyle(dim: true),
    this.thumbStyle = CellStyle.none,
  }) : _metrics = (() {
         final range = controller.visibleRange;
         if (range == null) {
           return (controller.itemCount, controller.itemCount, 0);
         }
         return (
           controller.itemCount,
           range.last - range.first + 1,
           range.first,
         );
       }),
       _scrollTo = ((f) {
         final range = controller.visibleRange;
         final visible = range == null ? 0 : range.last - range.first + 1;
         final maxFirst = controller.itemCount - visible;
         if (maxFirst <= 0) return;
         controller.jumpToIndex((maxFirst * f).round().clamp(0, maxFirst));
       });

  final _ScrollbarMetrics Function() _metrics;
  final void Function(double fraction) _scrollTo;
  final Widget child;
  final int thickness;
  final CellStyle trackStyle;
  final CellStyle thumbStyle;

  @override
  State<Scrollbar> createState() => _ScrollbarState();
}

/// Holder for a [Scrollbar]'s painted geometry: the render object writes
/// it each paint, the drag handler reads it to map a pointer row → scroll
/// fraction (the same write-at-paint / read-elsewhere idiom as BoundsNotifier).
///
/// [top] is a *screen* row, like BoundsNotifier's rect and the pointer
/// region this pairs with. Mouse events arrive in absolute terminal
/// coordinates, so recording the local paint offset instead would misread
/// every click inside a subtree painted into a scratch buffer — a caching
/// RepaintBoundary, a ListView item, a ScrollView viewport — where the local
/// offset is scratch-relative and the screen offset is not.
class _ScrollbarGeometry {
  int top = 0;
  int height = 0;
}

class _ScrollbarState extends State<Scrollbar> {
  final _ScrollbarGeometry _geom = _ScrollbarGeometry();

  void _jumpToRow(int row) {
    if (_geom.height <= 1) return;
    final f = ((row - _geom.top) / (_geom.height - 1)).clamp(0.0, 1.0);
    widget._scrollTo(f);
  }

  @override
  Widget build(BuildContext context) {
    final policy = MediaQuery.textPolicyOf(context);
    // The gutter lives at the right edge of a bounded region, and the
    // Expanded below fills the rest. Under an unbounded width the Row would
    // give Expanded zero columns and the content would silently vanish — the
    // guard turns that into a clear, actionable error instead.
    return _RequireBoundedWidth(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.child),
          GestureDetector(
            onTapDown: (col, row) => _jumpToRow(row),
            onDragStart: (col, row) => _jumpToRow(row),
            onDragUpdate: (col, row) => _jumpToRow(row),
            child: SizedBox(
              // The gutter reserves what the bar's glyphs actually draw:
              // `█` and `│` are East Asian Ambiguous, so a surface whose
              // probe measured ambiguous glyphs wide gets a two-column
              // gutter per unit of thickness (RFC 0019). Reserving one
              // there would put the thumb's second cell over the content.
              width: widget.thickness * _barGlyphWidth(policy),
              child: _BarView(
                metrics: widget._metrics,
                geometry: _geom,
                trackStyle: widget.trackStyle,
                thumbStyle: widget.thumbStyle,
                textPolicy: policy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fails loudly if given an unbounded width instead of letting the
/// [Scrollbar]'s `Row`/`Expanded` collapse the content to zero columns — a
/// right-edge gutter has nothing to anchor to without a bounded width. Mirrors
/// how [LayoutBuilder] rejects an unbounded main axis. Transparent otherwise
/// (same size, same paint offset, so the gutter's pointer region is intact).
class _RequireBoundedWidth extends SingleChildRenderObjectWidget {
  const _RequireBoundedWidth({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRequireBoundedWidth();

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {}
}

class _RenderRequireBoundedWidth extends RenderObject
    implements RenderObjectWithSingleChild {
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
    if (!constraints.hasBoundedWidth) {
      throw StateError(
        'Scrollbar needs a bounded width to anchor its gutter, but was given '
        'an unbounded width (e.g. a non-Expanded child of a Row gets an '
        'unbounded main axis). Give it a bounded width — wrap it in Expanded '
        'or a SizedBox(width: ...).',
      );
    }
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
    if (c != null) {
      c.paint(buffer, offset, screenOffset: screenOffset, clipRect: clipRect);
    }
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
    required this.trackStyle,
    required this.thumbStyle,
    required this.textPolicy,
  });

  final _ScrollbarMetrics Function() metrics;
  final _ScrollbarGeometry geometry;
  final CellStyle trackStyle;
  final CellStyle thumbStyle;
  final TextPresentationPolicy textPolicy;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScrollbar(
    metrics: metrics,
    geometry: geometry,
    trackStyle: trackStyle,
    thumbStyle: thumbStyle,
    textPolicy: textPolicy,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScrollbar renderObject,
  ) {
    renderObject
      ..metrics = metrics
      ..geometry = geometry
      ..trackStyle = trackStyle
      ..thumbStyle = thumbStyle
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
    required CellStyle trackStyle,
    required CellStyle thumbStyle,
    required TextPresentationPolicy textPolicy,
  }) : _metrics = metrics,
       _geometry = geometry,
       _trackStyle = trackStyle,
       _thumbStyle = thumbStyle,
       _textPolicy = textPolicy;

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
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.isEmpty) return;
    final h = size.rows;
    // Screen coordinates, matching the pointer region registered for this bar
    // (see PointerRegion.paint) — see [_ScrollbarGeometry].
    _geometry
      ..top = (screenOffset ?? offset).row
      ..height = h;

    final (content, viewport, scrollOffset) = _metrics();
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
    final glyphWidth = _barGlyphWidth(_textPolicy);
    final widths = _textPolicy.widths;
    final lastCol = offset.col + size.cols;
    for (var r = 0; r < h; r++) {
      final row = offset.row + r;
      if (row < 0 || row >= buffer.size.rows) continue;
      final isThumb = r >= thumbTop && r < thumbTop + thumbSize;
      final glyph = isThumb ? _thumbGlyph : _trackGlyph;
      final style = isThumb ? _thumbStyle : _trackStyle;
      for (
        var col = offset.col;
        col + glyphWidth <= lastCol;
        col += glyphWidth
      ) {
        if (col < 0 || col >= buffer.size.cols) continue;
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
