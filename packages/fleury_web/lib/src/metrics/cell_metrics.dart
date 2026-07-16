import 'package:fleury/fleury_host.dart';

/// Cached browser cell metrics for a Fleury visual surface.
final class MeasuredCellBox {
  const MeasuredCellBox({
    required this.cssCellWidth,
    required this.cssCellHeight,
    required this.cssCanvasWidth,
    required this.cssCanvasHeight,
    required this.devicePixelRatio,
    required this.cols,
    required this.rows,
    this.cssCanvasLeft = 0,
    this.cssCanvasTop = 0,
    this.cssCanvasInsetLeft = 0,
    this.cssCanvasInsetTop = 0,
    this.hostPositionIsStatic = true,
    double? layoutCellWidth,
    double? layoutCellHeight,
  }) : layoutCellWidth = layoutCellWidth ?? cssCellWidth,
       layoutCellHeight = layoutCellHeight ?? cssCellHeight;

  /// Device-pixel-snapped cell box used for rendering. Every grid row/cell is
  /// laid out against these so vertical box-drawing glyphs tile seamlessly
  /// (a fractional height never lands on a device pixel, so borders dash).
  final double cssCellWidth;
  final double cssCellHeight;

  /// Unsnapped natural cell advance — the pitch the browser actually lays text
  /// out at (`white-space:pre` advances by the font's natural glyph width, and
  /// a row's line box is its natural height, not the snapped value). Hit-testing
  /// must use this: the snapped box drifts ~0.1px per cell from the rendered
  /// grid, which accumulates into an off-by-one near the bottom of a long list.
  final double layoutCellWidth;
  final double layoutCellHeight;
  final double cssCanvasWidth;
  final double cssCanvasHeight;

  /// Canvas origin in browser viewport coordinates. Fixed-position browser
  /// affordances such as the hidden IME capture element use this origin.
  final double cssCanvasLeft;
  final double cssCanvasTop;

  /// Canvas origin relative to an absolutely-positioned child of the host.
  ///
  /// The host is the overlay's containing block. Its absolute-position origin
  /// is the host's padding-box edge, so these values contain the host padding
  /// but not its viewport position or border. Using [cssCanvasLeft] here would
  /// count the host's viewport origin twice whenever it is not at (0, 0).
  final double cssCanvasInsetLeft;
  final double cssCanvasInsetTop;

  /// Whether the host needs a positioned containing block for overlays.
  ///
  /// This is captured alongside the other computed-style reads so paint-side
  /// consumers never need to force browser layout or style resolution.
  final bool hostPositionIsStatic;
  final double devicePixelRatio;
  final int cols;
  final int rows;

  CellSize get size => CellSize(cols, rows);

  @override
  bool operator ==(Object other) =>
      other is MeasuredCellBox &&
      other.cssCellWidth == cssCellWidth &&
      other.cssCellHeight == cssCellHeight &&
      other.layoutCellWidth == layoutCellWidth &&
      other.layoutCellHeight == layoutCellHeight &&
      other.cssCanvasWidth == cssCanvasWidth &&
      other.cssCanvasHeight == cssCanvasHeight &&
      other.cssCanvasLeft == cssCanvasLeft &&
      other.cssCanvasTop == cssCanvasTop &&
      other.cssCanvasInsetLeft == cssCanvasInsetLeft &&
      other.cssCanvasInsetTop == cssCanvasInsetTop &&
      other.hostPositionIsStatic == hostPositionIsStatic &&
      other.devicePixelRatio == devicePixelRatio &&
      other.cols == cols &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(
    cssCellWidth,
    cssCellHeight,
    layoutCellWidth,
    layoutCellHeight,
    cssCanvasWidth,
    cssCanvasHeight,
    cssCanvasLeft,
    cssCanvasTop,
    cssCanvasInsetLeft,
    cssCanvasInsetTop,
    hostPositionIsStatic,
    devicePixelRatio,
    cols,
    rows,
  );
}

/// Authoritative browser geometry source for a web host.
abstract interface class CellMetrics {
  /// Reads browser geometry and returns a cached measurement.
  MeasuredCellBox measure();

  /// Last completed measurement, if one exists.
  MeasuredCellBox? get cachedMeasurement;

  /// Starts observing resize-like invalidations.
  void startObserving(void Function() onMetricsDirty);

  /// Marks cached metrics dirty without reading layout.
  void markDirty();

  /// Maps a point in surface-local CSS pixels to a cell using the last completed
  /// measurement.
  ///
  /// This must not read browser layout. Hosts call [measure] during the frame
  /// read phase; event handlers can use this mapping without forcing layout
  /// outside that phase.
  CellOffset cellForPoint(double x, double y);

  /// Maps a browser viewport/client point to a surface cell.
  ///
  /// DOM-backed implementations may read the host's current origin so pointer
  /// input remains correct when the page scrolls or surrounding layout moves
  /// the host after the last size measurement. The cached measurement remains
  /// authoritative for cell size and grid extent.
  CellOffset? cellForViewportPoint(double clientX, double clientY);

  /// Releases browser observers and hidden probes.
  void dispose();
}
