import 'package:fleury/fleury_host.dart';

import 'metrics/cell_metrics.dart';

/// Visual frame surface implemented by browser renderers.
///
/// This is intentionally visual-only. Input, metrics, clipboard, semantics,
/// and scheduling stay in the host/runtime layer.
abstract interface class FrameSurface {
  CellSize get size;
  WebSurfaceCapabilities get capabilities;

  FrameSurfacePresentationStats present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  );

  void resize(CellSize size, {MeasuredCellBox? metrics});
  Future<void> dispose();
}

/// Capabilities of a web visual surface.
final class WebSurfaceCapabilities {
  const WebSurfaceCapabilities({
    this.supportsTrueColor = true,
    this.supportsSemanticLinks = false,
    this.inlineImages = InlineImageCapability.none,
    this.supportsGlyphOverlay = false,
  });

  final bool supportsTrueColor;
  final bool supportsSemanticLinks;
  final InlineImageCapability inlineImages;
  final bool supportsGlyphOverlay;
}

enum InlineImageCapability { none, domImage }

/// Presenter-ready frame data computed once by the host.
final class FramePresentationPlan {
  const FramePresentationPlan({
    required this.reason,
    required this.fullRepaint,
    required this.size,
    required this.damage,
    required this.dirtyRowModels,
    required this.metricsChanged,
    required this.dirtyRowDiffTime,
    required this.spanBuildTime,
    this.scrollUpRows,
  });

  final String reason;
  final bool fullRepaint;
  final CellSize size;
  final FramePresentationDamage damage;
  final List<RowSpanModel> dirtyRowModels;
  final bool metricsChanged;
  final Duration dirtyRowDiffTime;
  final Duration spanBuildTime;

  /// When non-null, the frame is a detected upward scroll: the surface moves
  /// its first [scrollUpRows] retained row elements to the bottom and then
  /// applies [dirtyRowModels], which cover only the residual rows (entering
  /// rows plus rows that changed beyond the shift).
  ///
  /// [damage] stays the TRUE dirty set (everything moved), so semantic
  /// coverage and diff consumers remain exact.
  final int? scrollUpRows;

  int get dirtyRowCount => damage.dirtyRows.dirtyRowCount;

  int get dirtyCellEstimate => dirtyRowCount * size.cols;

  int get spanCount =>
      dirtyRowModels.fold(0, (count, row) => count + row.runs.length);
}

/// Count data reported by a visual [FrameSurface] after one presentation.
final class FrameSurfacePresentationStats {
  const FrameSurfacePresentationStats({
    required this.rowsReplaced,
    required this.domNodesCreated,
    this.styleCacheHits = 0,
    this.styleCacheMisses = 0,
    this.widthCacheHits = 0,
    this.widthCacheMisses = 0,
  });

  static const none = FrameSurfacePresentationStats(
    rowsReplaced: 0,
    domNodesCreated: 0,
  );

  final int rowsReplaced;
  final int domNodesCreated;
  final int styleCacheHits;
  final int styleCacheMisses;
  final int widthCacheHits;
  final int widthCacheMisses;
}

/// Damage data normalized for web presenters.
final class FramePresentationDamage {
  const FramePresentationDamage({
    required this.fullRepaint,
    required this.requiresFullDiff,
    required this.dirtyBounds,
    required this.dirtyRows,
    required this.source,
  });

  final bool fullRepaint;
  final bool requiresFullDiff;
  final CellRect? dirtyBounds;
  final TuiDirtyRows dirtyRows;
  final FrameDamageSource source;
}

enum FrameDamageSource {
  paintDamage,
  fullRepaint,
  conservativeFullDiff,
  unboundedFallback,

  /// The frame request skipped rendering: no frame work was pending and the
  /// committed front buffer was still exact.
  none,
}

/// Builds [FramePresentationPlan]s from shared runtime frame output.
final class FramePresentationPlanner {
  const FramePresentationPlanner({this.spanBuilder = const CellSpanBuilder()});

  final CellSpanBuilder spanBuilder;

  FramePresentationPlan build({
    required String reason,
    required TuiRenderedFrame frame,
    bool metricsChanged = false,
  }) {
    final runtimeDamage = frame.damage;
    final dirtyRowsResult = _dirtyRowsForFrame(frame);
    final dirtyRows = dirtyRowsResult.rows;
    final damage = FramePresentationDamage(
      fullRepaint: runtimeDamage.fullRepaint,
      requiresFullDiff: runtimeDamage.requiresFullDiff,
      dirtyBounds: runtimeDamage.diffBounds,
      dirtyRows: dirtyRows,
      source: _sourceFor(runtimeDamage),
    );

    // A full-dirty frame may really be an upward scroll: the shared detector
    // (the same one the ANSI renderer scrolls with) tells us the retained
    // rows can be MOVED, leaving only residual rows to rebuild.
    int? scrollUpRows;
    var rowsToBuild = dirtyRows;
    if (!runtimeDamage.fullRepaint &&
        dirtyRows.isFull &&
        frame.previous.size == frame.next.size) {
      final stats = screenDiffStats(frame.previous, frame.next);
      final shift = detectBeneficialScrollUp(frame.previous, frame.next, stats);
      if (shift != null) {
        scrollUpRows = shift;
        rowsToBuild = _residualScrollRows(frame.previous, frame.next, shift);
      }
    }

    final spanBuildStopwatch = Stopwatch()..start();
    final dirtyRowModels = spanBuilder.buildDirtyRows(frame.next, rowsToBuild);
    spanBuildStopwatch.stop();

    return FramePresentationPlan(
      reason: reason,
      fullRepaint: runtimeDamage.fullRepaint,
      size: frame.next.size,
      damage: damage,
      dirtyRowModels: dirtyRowModels,
      metricsChanged: metricsChanged,
      dirtyRowDiffTime: dirtyRowsResult.diffTime,
      spanBuildTime: spanBuildStopwatch.elapsed,
      scrollUpRows: scrollUpRows,
    );
  }

  /// Rows that still need their spans rebuilt after scrolling up by [shift]:
  /// every entering row at the bottom (the moved elements carry stale spans)
  /// plus any retained row whose content changed beyond the shift.
  TuiDirtyRows _residualScrollRows(
    CellBuffer previous,
    CellBuffer next,
    int shift,
  ) {
    final rows = next.size.rows;
    final residual = <int>[];
    for (var row = 0; row < rows - shift; row++) {
      if (!rowsEqual(previous, row + shift, next, row)) residual.add(row);
    }
    for (var row = rows - shift; row < rows; row++) {
      residual.add(row);
    }
    return TuiDirtyRows.fromRows(residual, rowCount: rows);
  }

  FrameDamageSource _sourceFor(TuiFrameDamage damage) {
    if (damage.fullRepaint) return FrameDamageSource.fullRepaint;
    if (damage.requiresFullDiff) return FrameDamageSource.conservativeFullDiff;
    if (damage.diffBounds != null) return FrameDamageSource.paintDamage;
    return FrameDamageSource.unboundedFallback;
  }

  _DirtyRowsResult _dirtyRowsForFrame(TuiRenderedFrame frame) {
    final runtimeDamage = frame.damage;
    if (runtimeDamage.fullRepaint) {
      return _DirtyRowsResult(
        rows: TuiDirtyRows.full(frame.next.size.rows),
        diffTime: Duration.zero,
      );
    }
    final bounds = runtimeDamage.diffBounds;
    if (bounds != null) {
      // dirtyRowsFor prefers the exact painted-row set when the buffer
      // tracked one, so scattered updates stay scattered instead of being
      // smeared into the union rect's row span.
      return _DirtyRowsResult(
        rows: runtimeDamage.dirtyRowsFor(frame.next.size),
        diffTime: Duration.zero,
      );
    }
    final diffStopwatch = Stopwatch()..start();
    final rows = _diffDirtyRows(frame.previous, frame.next);
    diffStopwatch.stop();
    return _DirtyRowsResult(rows: rows, diffTime: diffStopwatch.elapsed);
  }

  TuiDirtyRows _diffDirtyRows(CellBuffer previous, CellBuffer next) {
    if (previous.size != next.size) return TuiDirtyRows.full(next.size.rows);
    final cols = next.size.cols;
    final rows = next.size.rows;
    final dirtyRows = <int>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if (previous.atColRow(col, row) != next.atColRow(col, row)) {
          dirtyRows.add(row);
          break;
        }
      }
    }
    return TuiDirtyRows.fromRows(dirtyRows, rowCount: rows);
  }
}

final class _DirtyRowsResult {
  const _DirtyRowsResult({required this.rows, required this.diffTime});

  final TuiDirtyRows rows;
  final Duration diffTime;
}
