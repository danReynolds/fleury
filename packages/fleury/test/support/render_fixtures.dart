// Shared render-level fixtures for the widget and rendering suites —
// deduplicated from scroll_view_test / error_containment_test / overlay_test,
// which carried verbatim copies.

import 'dart:typed_data';

import 'package:fleury/fleury.dart';

/// A 4×2 leaf that records an inline-image placement (the true-pixel path)
/// rather than painting glyphs — so a test can assert the placement survives
/// a scratch-buffer composite or a repaint-boundary blit.
class ImageLeaf extends LeafRenderObjectWidget {
  const ImageLeaf();
  @override
  RenderObject createRenderObject(BuildContext context) => _ImageLeafRender();
}

class _ImageLeafRender extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(4, 2));
  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    buffer.writeImage(
      offset,
      Uint8List.fromList([1, 2, 3, 4]),
      width: 4,
      height: 2,
    );
  }
}

/// Which phase [Boom] throws in ([healthy] paints real content instead).
enum BoomMode { layout, paint, healthy }

/// A leaf whose layout or paint throws (per [mode]) until healed — the
/// shared crash fixture for containment tests. The paint path writes a
/// partial 'part' BEFORE throwing, so atomicity assertions can prove the
/// error presentation buries pre-throw writes.
class Boom extends LeafRenderObjectWidget {
  const Boom({this.mode = BoomMode.layout, this.size = const CellSize(14, 3)});

  final BoomMode mode;

  /// Laid-out size (under bounded and unbounded constraints alike). At
  /// least 3 rows gets the text error panel rather than the small-region
  /// badge; give it more rows when the message line must fit the panel.
  final CellSize size;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBoom(mode, size);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBoom)
      ..desiredSize = size
      ..mode = mode;
  }
}

class _RenderBoom extends RenderObject {
  _RenderBoom(this._mode, this._desiredSize);

  BoomMode _mode;
  set mode(BoomMode value) {
    if (value == _mode) return;
    _mode = value;
    markNeedsLayout();
  }

  CellSize _desiredSize;
  set desiredSize(CellSize value) {
    if (value == _desiredSize) return;
    _desiredSize = value;
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_mode == BoomMode.layout) throw StateError('layout-boom');
    return constraints.constrain(_desiredSize);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    // Partial write BEFORE the throw: atomicity must bury it.
    buffer.writeText(offset, 'part', style: CellStyle.empty);
    if (_mode == BoomMode.paint) throw StateError('paint-boom');
    buffer.writeText(offset, 'healthy###', style: CellStyle.empty);
  }
}
