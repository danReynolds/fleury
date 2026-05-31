import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_flex.dart' show CrossAxisAlignment;
import '../rendering/render_object.dart';
import 'basic.dart';
import 'framework.dart';
import 'list_view.dart' show ListController;
import 'pointer.dart';
import 'scroll_view.dart' show ScrollController;

/// (content, viewport, offset) in rows or items.
typedef ScrollbarMetrics = (int, int, int);

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
    this.thumbStyle = CellStyle.empty,
  }) : metrics = (() => (
         controller.contentExtent,
         controller.viewportExtent,
         controller.offset,
       )),
       scrollTo = ((f) =>
           controller.offset = (controller.maxOffset * f).round());

  /// Scrollbar for an item-scrolled [ListView]; the thumb reflects the
  /// visible item range, and dragging jumps the viewport by item.
  Scrollbar.list({
    super.key,
    required ListController controller,
    required this.child,
    this.thickness = 1,
    this.trackStyle = const CellStyle(dim: true),
    this.thumbStyle = CellStyle.empty,
  }) : metrics = (() {
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
       scrollTo = ((f) {
         final range = controller.visibleRange;
         final visible = range == null ? 0 : range.last - range.first + 1;
         final maxFirst = controller.itemCount - visible;
         if (maxFirst <= 0) return;
         controller.jumpToIndex((maxFirst * f).round().clamp(0, maxFirst));
       });

  final ScrollbarMetrics Function() metrics;
  final void Function(double fraction) scrollTo;
  final Widget child;
  final int thickness;
  final CellStyle trackStyle;
  final CellStyle thumbStyle;

  @override
  State<Scrollbar> createState() => _ScrollbarState();
}

/// Holder for a [Scrollbar]'s painted geometry: the render object writes
/// it each paint, the drag handler reads it to map a pointer row → scroll
/// fraction (the same write-at-paint / read-elsewhere idiom as AnchorLink).
class ScrollbarGeometry {
  int top = 0;
  int height = 0;
}

class _ScrollbarState extends State<Scrollbar> {
  final ScrollbarGeometry _geom = ScrollbarGeometry();

  void _jumpToRow(int row) {
    if (_geom.height <= 1) return;
    final f = ((row - _geom.top) / (_geom.height - 1)).clamp(0.0, 1.0);
    widget.scrollTo(f);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: widget.child),
        GestureDetector(
          onTapDown: (col, row) => _jumpToRow(row),
          onDragStart: (col, row) => _jumpToRow(row),
          onDragUpdate: (col, row) => _jumpToRow(row),
          child: SizedBox(
            width: widget.thickness,
            child: _BarView(
              metrics: widget.metrics,
              geometry: _geom,
              trackStyle: widget.trackStyle,
              thumbStyle: widget.thumbStyle,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarView extends LeafRenderObjectWidget {
  const _BarView({
    required this.metrics,
    required this.geometry,
    required this.trackStyle,
    required this.thumbStyle,
  });

  final ScrollbarMetrics Function() metrics;
  final ScrollbarGeometry geometry;
  final CellStyle trackStyle;
  final CellStyle thumbStyle;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderScrollbar(
    metrics: metrics,
    geometry: geometry,
    trackStyle: trackStyle,
    thumbStyle: thumbStyle,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderScrollbar renderObject,
  ) {
    renderObject
      ..metrics = metrics
      ..geometry = geometry
      ..trackStyle = trackStyle
      ..thumbStyle = thumbStyle;
  }
}

/// Fills its slot and paints the scrollbar track + thumb, recording its
/// painted geometry for the drag handler. Reads metrics at paint so they
/// reflect the just-completed layout.
class RenderScrollbar extends RenderObject {
  RenderScrollbar({
    required ScrollbarMetrics Function() metrics,
    required ScrollbarGeometry geometry,
    required CellStyle trackStyle,
    required CellStyle thumbStyle,
  }) : _metrics = metrics,
       _geometry = geometry,
       _trackStyle = trackStyle,
       _thumbStyle = thumbStyle;

  ScrollbarMetrics Function() _metrics;
  set metrics(ScrollbarMetrics Function() v) => _metrics = v;
  ScrollbarGeometry _geometry;
  set geometry(ScrollbarGeometry v) => _geometry = v;
  CellStyle _trackStyle;
  set trackStyle(CellStyle v) => _trackStyle = v;
  CellStyle _thumbStyle;
  set thumbStyle(CellStyle v) => _thumbStyle = v;

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
    _geometry
      ..top = offset.row
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

    for (var r = 0; r < h; r++) {
      final row = offset.row + r;
      if (row < 0 || row >= buffer.size.rows) continue;
      final isThumb = r >= thumbTop && r < thumbTop + thumbSize;
      final glyph = isThumb ? '█' : '│';
      final style = isThumb ? _thumbStyle : _trackStyle;
      for (var col = offset.col; col < offset.col + size.cols; col++) {
        if (col < 0 || col >= buffer.size.cols) continue;
        buffer.writeGrapheme(CellOffset(col, row), glyph, style: style);
      }
    }
  }
}
