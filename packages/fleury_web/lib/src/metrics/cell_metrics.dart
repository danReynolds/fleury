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
  });

  final double cssCellWidth;
  final double cssCellHeight;
  final double cssCanvasWidth;
  final double cssCanvasHeight;
  final double cssCanvasLeft;
  final double cssCanvasTop;
  final double devicePixelRatio;
  final int cols;
  final int rows;

  CellSize get size => CellSize(cols, rows);

  @override
  bool operator ==(Object other) =>
      other is MeasuredCellBox &&
      other.cssCellWidth == cssCellWidth &&
      other.cssCellHeight == cssCellHeight &&
      other.cssCanvasWidth == cssCanvasWidth &&
      other.cssCanvasHeight == cssCanvasHeight &&
      other.cssCanvasLeft == cssCanvasLeft &&
      other.cssCanvasTop == cssCanvasTop &&
      other.devicePixelRatio == devicePixelRatio &&
      other.cols == cols &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(
    cssCellWidth,
    cssCellHeight,
    cssCanvasWidth,
    cssCanvasHeight,
    cssCanvasLeft,
    cssCanvasTop,
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

  /// Releases browser observers and hidden probes.
  void dispose();
}
