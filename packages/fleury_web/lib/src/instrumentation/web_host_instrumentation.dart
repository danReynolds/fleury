import 'package:fleury/fleury_host.dart';

import '../frame_presentation.dart';

const double defaultWebFrameBudgetMs = 16.67;

/// Receives structured per-frame data from the retained DOM web host.
abstract interface class WebHostInstrumentation {
  void recordFrame(WebFrameInstrumentation frame);

  /// Receives one deferred semantic flush (Phase 2: semantics run off the
  /// visual frame, so their cost and latency are recorded separately from
  /// [recordFrame]).
  void recordSemanticFlush(WebSemanticFlushInstrumentation flush);
}

/// Default instrumentation sink used when callers do not request records.
final class NoopWebHostInstrumentation implements WebHostInstrumentation {
  const NoopWebHostInstrumentation();

  @override
  void recordFrame(WebFrameInstrumentation frame) {}

  @override
  void recordSemanticFlush(WebSemanticFlushInstrumentation flush) {}
}

/// In-memory instrumentation sink for tests and benchmark adapters.
final class RecordingWebHostInstrumentation implements WebHostInstrumentation {
  final List<WebFrameInstrumentation> _frames = [];
  final List<WebSemanticFlushInstrumentation> _semanticFlushes = [];

  List<WebFrameInstrumentation> get frames => List.unmodifiable(_frames);

  List<WebSemanticFlushInstrumentation> get semanticFlushes =>
      List.unmodifiable(_semanticFlushes);

  @override
  void recordFrame(WebFrameInstrumentation frame) {
    _frames.add(frame);
  }

  @override
  void recordSemanticFlush(WebSemanticFlushInstrumentation flush) {
    _semanticFlushes.add(flush);
  }

  void clear() {
    _frames.clear();
    _semanticFlushes.clear();
  }

  WebInstrumentationSummary summarize({
    double frameBudgetMs = defaultWebFrameBudgetMs,
  }) {
    return WebInstrumentationSummary.fromFrames(
      _frames,
      frameBudgetMs: frameBudgetMs,
    );
  }

  Map<String, Object?> toJson({
    double frameBudgetMs = defaultWebFrameBudgetMs,
  }) {
    return <String, Object?>{
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameCapture',
      'frameBudgetMs': frameBudgetMs,
      'frames': [for (final frame in _frames) frame.toJson()],
      'semanticFlushes': [for (final flush in _semanticFlushes) flush.toJson()],
      'summary': summarize(frameBudgetMs: frameBudgetMs).toJson(),
      'semanticFlushSummary': WebSemanticFlushSummary.fromFlushes(
        _semanticFlushes,
      ).toJson(),
    };
  }
}

/// One deferred semantic flush's timing and count data.
///
/// A flush covers every visual frame presented since the previous flush
/// ([coalescedFrameCount]); [scheduleLatency] is the time from the schedule
/// request (the first contributing frame's commit) to the flush starting.
final class WebSemanticFlushInstrumentation {
  const WebSemanticFlushInstrumentation({
    required this.reason,
    required this.coalescedFrameCount,
    required this.scheduleLatency,
    required this.retainedOutput,
    required this.semanticNodeCount,
    required this.semanticAddedNodeCount,
    required this.semanticRemovedNodeCount,
    required this.semanticUpdatedNodeCount,
    this.semanticDomCreatedElementCount = 0,
    this.semanticDomReusedElementCount = 0,
    this.semanticDomReplacedElementCount = 0,
    required this.semanticFallbackNodeCount,
    required this.semanticUncoveredCellCount,
    this.semanticTreeBuildTime = Duration.zero,
    this.semanticCoverageTime = Duration.zero,
    this.semanticDiffTime = Duration.zero,
    this.semanticPresenterTime = Duration.zero,
    this.semanticFocusSyncTime = Duration.zero,
    required this.totalFlushTime,
  });

  factory WebSemanticFlushInstrumentation.fromJson(Map<String, Object?> json) {
    return WebSemanticFlushInstrumentation(
      reason: _readString(json, 'reason'),
      coalescedFrameCount: _readInt(json, 'coalescedFrameCount'),
      scheduleLatency: _readMicros(json, 'scheduleLatencyMicros'),
      retainedOutput: _readBool(json, 'retainedOutput'),
      semanticNodeCount: _readInt(json, 'semanticNodeCount'),
      semanticAddedNodeCount: _readInt(json, 'semanticAddedNodeCount'),
      semanticRemovedNodeCount: _readInt(json, 'semanticRemovedNodeCount'),
      semanticUpdatedNodeCount: _readInt(json, 'semanticUpdatedNodeCount'),
      semanticDomCreatedElementCount: _readInt(
        json,
        'semanticDomCreatedElementCount',
      ),
      semanticDomReusedElementCount: _readInt(
        json,
        'semanticDomReusedElementCount',
      ),
      semanticDomReplacedElementCount: _readInt(
        json,
        'semanticDomReplacedElementCount',
      ),
      semanticFallbackNodeCount: _readInt(json, 'semanticFallbackNodeCount'),
      semanticUncoveredCellCount: _readInt(json, 'semanticUncoveredCellCount'),
      semanticTreeBuildTime: _readMicros(json, 'semanticTreeBuildMicros'),
      semanticCoverageTime: _readMicros(json, 'semanticCoverageMicros'),
      semanticDiffTime: _readMicros(json, 'semanticDiffMicros'),
      semanticPresenterTime: _readMicros(json, 'semanticPresenterMicros'),
      semanticFocusSyncTime: _readMicros(json, 'semanticFocusSyncMicros'),
      totalFlushTime: _readMicros(json, 'totalFlushMicros'),
    );
  }

  final String reason;
  final int coalescedFrameCount;
  final Duration scheduleLatency;
  final bool retainedOutput;
  final int semanticNodeCount;
  final int semanticAddedNodeCount;
  final int semanticRemovedNodeCount;
  final int semanticUpdatedNodeCount;
  final int semanticDomCreatedElementCount;
  final int semanticDomReusedElementCount;
  final int semanticDomReplacedElementCount;
  final int semanticFallbackNodeCount;
  final int semanticUncoveredCellCount;
  final Duration semanticTreeBuildTime;
  final Duration semanticCoverageTime;
  final Duration semanticDiffTime;
  final Duration semanticPresenterTime;
  final Duration semanticFocusSyncTime;
  final Duration totalFlushTime;

  /// Schedule latency plus the flush's own duration: the end-to-end time
  /// from "semantic dirt committed" to "assistive DOM updated".
  Duration get presentationLatency => scheduleLatency + totalFlushTime;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'reason': reason,
      'coalescedFrameCount': coalescedFrameCount,
      'scheduleLatencyMicros': scheduleLatency.inMicroseconds,
      'retainedOutput': retainedOutput,
      'semanticNodeCount': semanticNodeCount,
      'semanticAddedNodeCount': semanticAddedNodeCount,
      'semanticRemovedNodeCount': semanticRemovedNodeCount,
      'semanticUpdatedNodeCount': semanticUpdatedNodeCount,
      'semanticDomCreatedElementCount': semanticDomCreatedElementCount,
      'semanticDomReusedElementCount': semanticDomReusedElementCount,
      'semanticDomReplacedElementCount': semanticDomReplacedElementCount,
      'semanticFallbackNodeCount': semanticFallbackNodeCount,
      'semanticUncoveredCellCount': semanticUncoveredCellCount,
      'semanticTreeBuildMicros': semanticTreeBuildTime.inMicroseconds,
      'semanticCoverageMicros': semanticCoverageTime.inMicroseconds,
      'semanticDiffMicros': semanticDiffTime.inMicroseconds,
      'semanticPresenterMicros': semanticPresenterTime.inMicroseconds,
      'semanticFocusSyncMicros': semanticFocusSyncTime.inMicroseconds,
      'totalFlushMicros': totalFlushTime.inMicroseconds,
      'presentationLatencyMicros': presentationLatency.inMicroseconds,
    };
  }
}

/// Aggregates over a capture's semantic flushes.
final class WebSemanticFlushSummary {
  const WebSemanticFlushSummary({
    required this.flushCount,
    required this.coalescedFrameTotal,
    required this.retainedOutputCount,
    required this.presentationLatency,
    required this.totalFlushTime,
  });

  factory WebSemanticFlushSummary.fromFlushes(
    List<WebSemanticFlushInstrumentation> flushes,
  ) {
    return WebSemanticFlushSummary(
      flushCount: flushes.length,
      coalescedFrameTotal: flushes.fold(
        0,
        (sum, flush) => sum + flush.coalescedFrameCount,
      ),
      retainedOutputCount: flushes.where((f) => f.retainedOutput).length,
      presentationLatency: WebMetricSummary.fromDurations(
        flushes.map((f) => f.presentationLatency),
      ),
      totalFlushTime: WebMetricSummary.fromDurations(
        flushes.map((f) => f.totalFlushTime),
      ),
    );
  }

  final int flushCount;
  final int coalescedFrameTotal;
  final int retainedOutputCount;
  final WebMetricSummary presentationLatency;
  final WebMetricSummary totalFlushTime;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'flushCount': flushCount,
      'coalescedFrameTotal': coalescedFrameTotal,
      'retainedOutputCount': retainedOutputCount,
      'presentationLatencyMs': presentationLatency.toJson(),
      'totalFlushMs': totalFlushTime.toJson(),
    };
  }
}

/// One presented browser frame's timing and count data.
final class WebFrameInstrumentation {
  const WebFrameInstrumentation({
    required this.reason,
    required this.coalescedReasons,
    required this.viewportSize,
    required this.damageSource,
    required this.fullRepaint,
    required this.metricsChanged,
    this.renderSkipped = false,
    required this.dirtyRowCount,
    required this.dirtyCellEstimate,
    required this.spanCount,
    required this.domNodesCreated,
    required this.rowsReplaced,
    required this.styleCacheHits,
    required this.styleCacheMisses,
    required this.widthCacheHits,
    required this.widthCacheMisses,
    required this.metricsReadCount,
    required this.semanticNodeCount,
    required this.semanticAddedNodeCount,
    required this.semanticRemovedNodeCount,
    required this.semanticUpdatedNodeCount,
    this.semanticDomCreatedElementCount = 0,
    this.semanticDomReusedElementCount = 0,
    this.semanticDomReplacedElementCount = 0,
    this.semanticDomAttributesSetCount = 0,
    this.semanticDomAttributesRemovedCount = 0,
    required this.semanticFallbackNodeCount,
    required this.semanticUncoveredCellCount,
    required this.runtimeRenderTime,
    required this.runtimePhaseTimingAvailable,
    this.runtimeBuildPassCount = 0,
    this.runtimeRebuiltElementCount = 0,
    this.runtimeMaxDirtyElementCount = 0,
    this.runtimeBufferPrepareTime = Duration.zero,
    this.runtimeBuildTime = Duration.zero,
    this.runtimeLayoutTime = Duration.zero,
    this.runtimePaintTime = Duration.zero,
    this.dirtyRowDiffTime = Duration.zero,
    required this.spanBuildTime,
    required this.domApplyTime,
    this.semanticTreeBuildTime = Duration.zero,
    this.semanticCoverageTime = Duration.zero,
    this.semanticDiffTime = Duration.zero,
    this.semanticPresenterTime = Duration.zero,
    this.semanticFocusSyncTime = Duration.zero,
    required this.semanticApplyTime,
    required this.totalFrameTime,
  });

  factory WebFrameInstrumentation.fromPresentation({
    required FramePresentationPlan plan,
    required FrameSurfacePresentationStats surfaceStats,
    required SemanticPresentationStats semanticStats,
    SemanticCoverageAudit coverageAudit = SemanticCoverageAudit.empty,
    required int metricsReadCount,
    required Duration runtimeRenderTime,
    bool runtimePhaseTimingAvailable = true,
    BuildFlushStats runtimeBuildStats = BuildFlushStats.zero,
    Duration runtimeBufferPrepareTime = Duration.zero,
    Duration runtimeBuildTime = Duration.zero,
    Duration runtimeLayoutTime = Duration.zero,
    Duration runtimePaintTime = Duration.zero,
    Duration dirtyRowDiffTime = Duration.zero,
    required Duration spanBuildTime,
    required Duration domApplyTime,
    Duration semanticTreeBuildTime = Duration.zero,
    Duration semanticCoverageTime = Duration.zero,
    Duration semanticDiffTime = Duration.zero,
    Duration semanticPresenterTime = Duration.zero,
    Duration semanticFocusSyncTime = Duration.zero,
    required Duration semanticApplyTime,
    required Duration totalFrameTime,
    List<String> coalescedReasons = const <String>[],
  }) {
    final reasons = coalescedReasons.isEmpty
        ? plan.reason.split('+').where((reason) => reason.isNotEmpty).toList()
        : coalescedReasons;
    return WebFrameInstrumentation(
      reason: plan.reason,
      coalescedReasons: List.unmodifiable(reasons),
      viewportSize: plan.size,
      damageSource: plan.damage.source,
      fullRepaint: plan.fullRepaint,
      metricsChanged: plan.metricsChanged,
      dirtyRowCount: plan.dirtyRowCount,
      dirtyCellEstimate: plan.dirtyCellEstimate,
      spanCount: plan.spanCount,
      domNodesCreated: surfaceStats.domNodesCreated,
      rowsReplaced: surfaceStats.rowsReplaced,
      styleCacheHits: surfaceStats.styleCacheHits,
      styleCacheMisses: surfaceStats.styleCacheMisses,
      widthCacheHits: surfaceStats.widthCacheHits,
      widthCacheMisses: surfaceStats.widthCacheMisses,
      metricsReadCount: metricsReadCount,
      semanticNodeCount: semanticStats.nodeCount,
      semanticAddedNodeCount: semanticStats.addedNodeCount,
      semanticRemovedNodeCount: semanticStats.removedNodeCount,
      semanticUpdatedNodeCount: semanticStats.updatedNodeCount,
      semanticDomCreatedElementCount: semanticStats.createdElementCount,
      semanticDomReusedElementCount: semanticStats.reusedElementCount,
      semanticDomReplacedElementCount: semanticStats.replacedElementCount,
      semanticDomAttributesSetCount: semanticStats.attributesSetCount,
      semanticDomAttributesRemovedCount: semanticStats.attributesRemovedCount,
      semanticFallbackNodeCount: coverageAudit.fallbackNodeCount,
      semanticUncoveredCellCount: coverageAudit.uncoveredCellCount,
      runtimeRenderTime: runtimeRenderTime,
      runtimePhaseTimingAvailable: runtimePhaseTimingAvailable,
      runtimeBuildPassCount: runtimeBuildStats.passCount,
      runtimeRebuiltElementCount: runtimeBuildStats.rebuiltElementCount,
      runtimeMaxDirtyElementCount: runtimeBuildStats.maxDirtyElementCount,
      runtimeBufferPrepareTime: runtimeBufferPrepareTime,
      runtimeBuildTime: runtimeBuildTime,
      runtimeLayoutTime: runtimeLayoutTime,
      runtimePaintTime: runtimePaintTime,
      dirtyRowDiffTime: dirtyRowDiffTime,
      spanBuildTime: spanBuildTime,
      domApplyTime: domApplyTime,
      semanticTreeBuildTime: semanticTreeBuildTime,
      semanticCoverageTime: semanticCoverageTime,
      semanticDiffTime: semanticDiffTime,
      semanticPresenterTime: semanticPresenterTime,
      semanticFocusSyncTime: semanticFocusSyncTime,
      semanticApplyTime: semanticApplyTime,
      totalFrameTime: totalFrameTime,
    );
  }

  /// A frame request that skipped build/layout/paint entirely: the runtime
  /// reported no frame work and the committed front buffer was still exact.
  factory WebFrameInstrumentation.skipped({
    required String reason,
    required CellSize viewportSize,
    required int semanticNodeCount,
    required int semanticFallbackNodeCount,
    required int semanticUncoveredCellCount,
    required Duration totalFrameTime,
  }) {
    return WebFrameInstrumentation(
      reason: reason,
      coalescedReasons: List.unmodifiable(
        reason.split('+').where((part) => part.isNotEmpty),
      ),
      viewportSize: viewportSize,
      damageSource: FrameDamageSource.none,
      fullRepaint: false,
      metricsChanged: false,
      renderSkipped: true,
      dirtyRowCount: 0,
      dirtyCellEstimate: 0,
      spanCount: 0,
      domNodesCreated: 0,
      rowsReplaced: 0,
      styleCacheHits: 0,
      styleCacheMisses: 0,
      widthCacheHits: 0,
      widthCacheMisses: 0,
      metricsReadCount: 0,
      semanticNodeCount: semanticNodeCount,
      semanticAddedNodeCount: 0,
      semanticRemovedNodeCount: 0,
      semanticUpdatedNodeCount: 0,
      semanticFallbackNodeCount: semanticFallbackNodeCount,
      semanticUncoveredCellCount: semanticUncoveredCellCount,
      runtimeRenderTime: Duration.zero,
      runtimePhaseTimingAvailable: false,
      spanBuildTime: Duration.zero,
      domApplyTime: Duration.zero,
      semanticApplyTime: Duration.zero,
      totalFrameTime: totalFrameTime,
    );
  }

  factory WebFrameInstrumentation.fromJson(Map<String, Object?> json) {
    final viewport = _readMap(json, 'viewport');
    return WebFrameInstrumentation(
      reason: _readString(json, 'reason'),
      coalescedReasons: List.unmodifiable(
        _readStringList(json, 'coalescedReasons'),
      ),
      viewportSize: CellSize(
        _readInt(viewport, 'cols'),
        _readInt(viewport, 'rows'),
      ),
      damageSource: _readDamageSource(json, 'damageSource'),
      fullRepaint: _readBool(json, 'fullRepaint'),
      metricsChanged: _readBool(json, 'metricsChanged'),
      renderSkipped: json['renderSkipped'] == true,
      dirtyRowCount: _readInt(json, 'dirtyRowCount'),
      dirtyCellEstimate: _readInt(json, 'dirtyCellEstimate'),
      spanCount: _readInt(json, 'spanCount'),
      domNodesCreated: _readInt(json, 'domNodesCreated'),
      rowsReplaced: _readInt(json, 'rowsReplaced'),
      styleCacheHits: _readInt(json, 'styleCacheHits'),
      styleCacheMisses: _readInt(json, 'styleCacheMisses'),
      widthCacheHits: _readInt(json, 'widthCacheHits'),
      widthCacheMisses: _readInt(json, 'widthCacheMisses'),
      metricsReadCount: _readInt(json, 'metricsReadCount'),
      semanticNodeCount: _readInt(json, 'semanticNodeCount'),
      semanticAddedNodeCount: _readInt(json, 'semanticAddedNodeCount'),
      semanticRemovedNodeCount: _readInt(json, 'semanticRemovedNodeCount'),
      semanticUpdatedNodeCount: _readInt(json, 'semanticUpdatedNodeCount'),
      semanticDomCreatedElementCount:
          _readOptionalInt(json, 'semanticDomCreatedElementCount') ?? 0,
      semanticDomReusedElementCount:
          _readOptionalInt(json, 'semanticDomReusedElementCount') ?? 0,
      semanticDomReplacedElementCount:
          _readOptionalInt(json, 'semanticDomReplacedElementCount') ?? 0,
      semanticDomAttributesSetCount:
          _readOptionalInt(json, 'semanticDomAttributesSetCount') ?? 0,
      semanticDomAttributesRemovedCount:
          _readOptionalInt(json, 'semanticDomAttributesRemovedCount') ?? 0,
      semanticFallbackNodeCount: _readInt(json, 'semanticFallbackNodeCount'),
      semanticUncoveredCellCount: _readInt(json, 'semanticUncoveredCellCount'),
      runtimeRenderTime: _readMicros(json, 'runtimeRenderMicros'),
      runtimePhaseTimingAvailable:
          _readOptionalBool(json, 'runtimePhaseTimingAvailable') ??
          (json.containsKey('runtimeBuildMicros') &&
              json.containsKey('runtimeLayoutMicros') &&
              json.containsKey('runtimePaintMicros')),
      runtimeBuildPassCount:
          _readOptionalInt(json, 'runtimeBuildPassCount') ?? 0,
      runtimeRebuiltElementCount:
          _readOptionalInt(json, 'runtimeRebuiltElementCount') ?? 0,
      runtimeMaxDirtyElementCount:
          _readOptionalInt(json, 'runtimeMaxDirtyElementCount') ?? 0,
      runtimeBufferPrepareTime: _readOptionalMicros(
        json,
        'runtimeBufferPrepareMicros',
      ),
      runtimeBuildTime: _readOptionalMicros(json, 'runtimeBuildMicros'),
      runtimeLayoutTime: _readOptionalMicros(json, 'runtimeLayoutMicros'),
      runtimePaintTime: _readOptionalMicros(json, 'runtimePaintMicros'),
      dirtyRowDiffTime: _readOptionalMicros(json, 'dirtyRowDiffMicros'),
      spanBuildTime: _readMicros(json, 'spanBuildMicros'),
      domApplyTime: _readMicros(json, 'domApplyMicros'),
      semanticTreeBuildTime: _readOptionalMicros(
        json,
        'semanticTreeBuildMicros',
      ),
      semanticCoverageTime: _readOptionalMicros(json, 'semanticCoverageMicros'),
      semanticDiffTime: _readOptionalMicros(json, 'semanticDiffMicros'),
      semanticPresenterTime: _readOptionalMicros(
        json,
        'semanticPresenterMicros',
      ),
      semanticFocusSyncTime: _readOptionalMicros(
        json,
        'semanticFocusSyncMicros',
      ),
      semanticApplyTime: _readMicros(json, 'semanticApplyMicros'),
      totalFrameTime: _readMicros(json, 'totalFrameMicros'),
    );
  }

  final String reason;
  final List<String> coalescedReasons;
  final CellSize viewportSize;
  final FrameDamageSource damageSource;
  final bool fullRepaint;
  final bool metricsChanged;

  /// Whether this frame request skipped rendering entirely (no frame work).
  final bool renderSkipped;
  final int dirtyRowCount;
  final int dirtyCellEstimate;
  final int spanCount;
  final int domNodesCreated;
  final int rowsReplaced;
  final int styleCacheHits;
  final int styleCacheMisses;
  final int widthCacheHits;
  final int widthCacheMisses;
  final int metricsReadCount;
  final int semanticNodeCount;
  final int semanticAddedNodeCount;
  final int semanticRemovedNodeCount;
  final int semanticUpdatedNodeCount;
  final int semanticDomCreatedElementCount;
  final int semanticDomReusedElementCount;
  final int semanticDomReplacedElementCount;
  final int semanticDomAttributesSetCount;
  final int semanticDomAttributesRemovedCount;
  final int semanticFallbackNodeCount;
  final int semanticUncoveredCellCount;
  final Duration runtimeRenderTime;
  final bool runtimePhaseTimingAvailable;
  final int runtimeBuildPassCount;
  final int runtimeRebuiltElementCount;
  final int runtimeMaxDirtyElementCount;
  final Duration runtimeBufferPrepareTime;
  final Duration runtimeBuildTime;
  final Duration runtimeLayoutTime;
  final Duration runtimePaintTime;
  final Duration dirtyRowDiffTime;
  final Duration spanBuildTime;
  final Duration domApplyTime;
  final Duration semanticTreeBuildTime;
  final Duration semanticCoverageTime;
  final Duration semanticDiffTime;
  final Duration semanticPresenterTime;
  final Duration semanticFocusSyncTime;
  final Duration semanticApplyTime;
  final Duration totalFrameTime;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'reason': reason,
      'coalescedReasons': coalescedReasons,
      'viewport': <String, Object?>{
        'cols': viewportSize.cols,
        'rows': viewportSize.rows,
      },
      'damageSource': damageSource.name,
      'fullRepaint': fullRepaint,
      'metricsChanged': metricsChanged,
      'renderSkipped': renderSkipped,
      'dirtyRowCount': dirtyRowCount,
      'dirtyCellEstimate': dirtyCellEstimate,
      'spanCount': spanCount,
      'domNodesCreated': domNodesCreated,
      'rowsReplaced': rowsReplaced,
      'styleCacheHits': styleCacheHits,
      'styleCacheMisses': styleCacheMisses,
      'widthCacheHits': widthCacheHits,
      'widthCacheMisses': widthCacheMisses,
      'metricsReadCount': metricsReadCount,
      'semanticNodeCount': semanticNodeCount,
      'semanticAddedNodeCount': semanticAddedNodeCount,
      'semanticRemovedNodeCount': semanticRemovedNodeCount,
      'semanticUpdatedNodeCount': semanticUpdatedNodeCount,
      'semanticDomCreatedElementCount': semanticDomCreatedElementCount,
      'semanticDomReusedElementCount': semanticDomReusedElementCount,
      'semanticDomReplacedElementCount': semanticDomReplacedElementCount,
      'semanticDomAttributesSetCount': semanticDomAttributesSetCount,
      'semanticDomAttributesRemovedCount': semanticDomAttributesRemovedCount,
      'semanticFallbackNodeCount': semanticFallbackNodeCount,
      'semanticUncoveredCellCount': semanticUncoveredCellCount,
      'runtimeRenderMicros': runtimeRenderTime.inMicroseconds,
      'runtimePhaseTimingAvailable': runtimePhaseTimingAvailable,
      'runtimeBuildPassCount': runtimeBuildPassCount,
      'runtimeRebuiltElementCount': runtimeRebuiltElementCount,
      'runtimeMaxDirtyElementCount': runtimeMaxDirtyElementCount,
      'runtimeBufferPrepareMicros': runtimeBufferPrepareTime.inMicroseconds,
      'runtimeBuildMicros': runtimeBuildTime.inMicroseconds,
      'runtimeLayoutMicros': runtimeLayoutTime.inMicroseconds,
      'runtimePaintMicros': runtimePaintTime.inMicroseconds,
      'dirtyRowDiffMicros': dirtyRowDiffTime.inMicroseconds,
      'spanBuildMicros': spanBuildTime.inMicroseconds,
      'domApplyMicros': domApplyTime.inMicroseconds,
      'semanticTreeBuildMicros': semanticTreeBuildTime.inMicroseconds,
      'semanticCoverageMicros': semanticCoverageTime.inMicroseconds,
      'semanticDiffMicros': semanticDiffTime.inMicroseconds,
      'semanticPresenterMicros': semanticPresenterTime.inMicroseconds,
      'semanticFocusSyncMicros': semanticFocusSyncTime.inMicroseconds,
      'semanticApplyMicros': semanticApplyTime.inMicroseconds,
      'totalFrameMicros': totalFrameTime.inMicroseconds,
    };
  }
}

/// Aggregated report used by web benchmark gates.
final class WebInstrumentationSummary {
  WebInstrumentationSummary({
    required this.frameCount,
    required this.frameBudgetMs,
    required this.overBudgetFrameCount,
    required this.overBudgetPercent,
    required this.dominantP95Slice,
    required this.timings,
    required this.counts,
    required this.cacheHitRates,
  });

  factory WebInstrumentationSummary.fromFrames(
    Iterable<WebFrameInstrumentation> frames, {
    double frameBudgetMs = defaultWebFrameBudgetMs,
  }) {
    final captured = frames.toList(growable: false);
    final frameBudgetMicros = (frameBudgetMs * 1000).round();
    final overBudgetFrameCount = captured
        .where(
          (frame) => frame.totalFrameTime.inMicroseconds > frameBudgetMicros,
        )
        .length;
    final runtimePhaseTimedFrames = captured
        .where((frame) => frame.runtimePhaseTimingAvailable)
        .toList(growable: false);
    final timings = <String, WebMetricSummary>{
      'runtimeRenderMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.runtimeRenderTime),
      ),
      'runtimeBufferPrepareMs': WebMetricSummary.fromDurations(
        runtimePhaseTimedFrames.map((frame) => frame.runtimeBufferPrepareTime),
      ),
      'runtimeBuildMs': WebMetricSummary.fromDurations(
        runtimePhaseTimedFrames.map((frame) => frame.runtimeBuildTime),
      ),
      'runtimeLayoutMs': WebMetricSummary.fromDurations(
        runtimePhaseTimedFrames.map((frame) => frame.runtimeLayoutTime),
      ),
      'runtimePaintMs': WebMetricSummary.fromDurations(
        runtimePhaseTimedFrames.map((frame) => frame.runtimePaintTime),
      ),
      'dirtyRowDiffMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.dirtyRowDiffTime),
      ),
      'spanBuildMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.spanBuildTime),
      ),
      'domApplyMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.domApplyTime),
      ),
      'semanticTreeBuildMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.semanticTreeBuildTime),
      ),
      'semanticCoverageMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.semanticCoverageTime),
      ),
      'semanticDiffMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.semanticDiffTime),
      ),
      'semanticPresenterMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.semanticPresenterTime),
      ),
      'semanticFocusSyncMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.semanticFocusSyncTime),
      ),
      'semanticApplyMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.semanticApplyTime),
      ),
      'totalFrameMs': WebMetricSummary.fromDurations(
        captured.map((frame) => frame.totalFrameTime),
      ),
    };
    final counts = <String, WebMetricSummary>{
      'dirtyRows': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.dirtyRowCount),
      ),
      'dirtyCells': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.dirtyCellEstimate),
      ),
      'spans': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.spanCount),
      ),
      'domNodesCreated': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.domNodesCreated),
      ),
      'rowsReplaced': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.rowsReplaced),
      ),
      'styleCacheHits': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.styleCacheHits),
      ),
      'styleCacheMisses': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.styleCacheMisses),
      ),
      'widthCacheHits': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.widthCacheHits),
      ),
      'widthCacheMisses': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.widthCacheMisses),
      ),
      'metricsReads': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.metricsReadCount),
      ),
      'runtimeBuildPasses': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.runtimeBuildPassCount),
      ),
      'runtimeRebuiltElements': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.runtimeRebuiltElementCount),
      ),
      'runtimeMaxDirtyElements': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.runtimeMaxDirtyElementCount),
      ),
      'semanticNodes': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticNodeCount),
      ),
      'semanticAddedNodes': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticAddedNodeCount),
      ),
      'semanticRemovedNodes': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticRemovedNodeCount),
      ),
      'semanticUpdatedNodes': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticUpdatedNodeCount),
      ),
      'semanticDomCreatedElements': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticDomCreatedElementCount),
      ),
      'semanticDomReusedElements': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticDomReusedElementCount),
      ),
      'semanticDomReplacedElements': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticDomReplacedElementCount),
      ),
      'semanticDomAttributesSet': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticDomAttributesSetCount),
      ),
      'semanticDomAttributesRemoved': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticDomAttributesRemovedCount),
      ),
      'semanticFallbackNodes': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticFallbackNodeCount),
      ),
      'semanticUncoveredCells': WebMetricSummary.fromNumbers(
        captured.map((frame) => frame.semanticUncoveredCellCount),
      ),
    };
    return WebInstrumentationSummary(
      frameCount: captured.length,
      frameBudgetMs: frameBudgetMs,
      overBudgetFrameCount: overBudgetFrameCount,
      overBudgetPercent: captured.isEmpty
          ? 0
          : overBudgetFrameCount * 100 / captured.length,
      dominantP95Slice: _dominantP95Slice(timings),
      timings: Map.unmodifiable(timings),
      counts: Map.unmodifiable(counts),
      cacheHitRates: Map.unmodifiable(<String, double>{
        'style': _hitRate(
          hits: counts['styleCacheHits']!.total,
          misses: counts['styleCacheMisses']!.total,
        ),
        'width': _hitRate(
          hits: counts['widthCacheHits']!.total,
          misses: counts['widthCacheMisses']!.total,
        ),
      }),
    );
  }

  final int frameCount;
  final double frameBudgetMs;
  final int overBudgetFrameCount;
  final double overBudgetPercent;
  final String dominantP95Slice;
  final Map<String, WebMetricSummary> timings;
  final Map<String, WebMetricSummary> counts;
  final Map<String, double> cacheHitRates;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameSummary',
      'frameCount': frameCount,
      'frameBudgetMs': frameBudgetMs,
      'frameBudgetMicros': (frameBudgetMs * 1000).round(),
      'overBudgetFrameCount': overBudgetFrameCount,
      'overBudgetPercent': overBudgetPercent,
      'dominantP95Slice': dominantP95Slice,
      'timings': <String, Object?>{
        for (final entry in timings.entries) entry.key: entry.value.toJson(),
      },
      'counts': <String, Object?>{
        for (final entry in counts.entries) entry.key: entry.value.toJson(),
      },
      'cacheHitRates': cacheHitRates,
    };
  }
}

/// Numeric summary for either timing milliseconds or per-frame counters.
final class WebMetricSummary {
  const WebMetricSummary({
    required this.sampleCount,
    required this.total,
    required this.p50,
    required this.p95,
    required this.max,
  });

  factory WebMetricSummary.fromDurations(Iterable<Duration> durations) {
    return WebMetricSummary.fromNumbers(
      durations.map((duration) => duration.inMicroseconds / 1000),
    );
  }

  factory WebMetricSummary.fromNumbers(Iterable<num> values) {
    final sorted =
        values
            .map((value) => value.toDouble())
            .where((value) => value.isFinite)
            .toList()
          ..sort();
    if (sorted.isEmpty) {
      return const WebMetricSummary(
        sampleCount: 0,
        total: 0,
        p50: 0,
        p95: 0,
        max: 0,
      );
    }
    return WebMetricSummary(
      sampleCount: sorted.length,
      total: sorted.fold<double>(0, (sum, value) => sum + value),
      p50: _percentile(sorted, 0.50),
      p95: _percentile(sorted, 0.95),
      max: sorted.last,
    );
  }

  final int sampleCount;
  final double total;
  final double p50;
  final double p95;
  final double max;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sampleCount': sampleCount,
      'total': total,
      'p50': p50,
      'p95': p95,
      'max': max,
    };
  }
}

/// Capture-level browser metrics gathered through Chrome DevTools Protocol.
///
/// Durations are milliseconds. Heap values are bytes. All fields are optional
/// because browser domains and metrics vary by engine/version.
final class WebBrowserPerformanceMetrics {
  const WebBrowserPerformanceMetrics({
    this.layoutDurationMs,
    this.recalcStyleDurationMs,
    this.scriptDurationMs,
    this.taskDurationMs,
    this.jsHeapUsedBytes,
    this.jsHeapTotalBytes,
    this.domDocumentCount,
    this.domNodeCount,
    this.jsEventListenerCount,
  });

  factory WebBrowserPerformanceMetrics.fromJson(Map<String, Object?> json) {
    return WebBrowserPerformanceMetrics(
      layoutDurationMs: _readOptionalDouble(json, 'layoutDurationMs'),
      recalcStyleDurationMs: _readOptionalDouble(json, 'recalcStyleDurationMs'),
      scriptDurationMs: _readOptionalDouble(json, 'scriptDurationMs'),
      taskDurationMs: _readOptionalDouble(json, 'taskDurationMs'),
      jsHeapUsedBytes: _readOptionalDouble(json, 'jsHeapUsedBytes'),
      jsHeapTotalBytes: _readOptionalDouble(json, 'jsHeapTotalBytes'),
      domDocumentCount: _readOptionalInt(json, 'domDocumentCount'),
      domNodeCount: _readOptionalInt(json, 'domNodeCount'),
      jsEventListenerCount: _readOptionalInt(json, 'jsEventListenerCount'),
    );
  }

  final double? layoutDurationMs;
  final double? recalcStyleDurationMs;
  final double? scriptDurationMs;
  final double? taskDurationMs;
  final double? jsHeapUsedBytes;
  final double? jsHeapTotalBytes;
  final int? domDocumentCount;
  final int? domNodeCount;
  final int? jsEventListenerCount;

  bool get isEmpty => toJson().isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (layoutDurationMs != null) 'layoutDurationMs': layoutDurationMs,
      if (recalcStyleDurationMs != null)
        'recalcStyleDurationMs': recalcStyleDurationMs,
      if (scriptDurationMs != null) 'scriptDurationMs': scriptDurationMs,
      if (taskDurationMs != null) 'taskDurationMs': taskDurationMs,
      if (jsHeapUsedBytes != null) 'jsHeapUsedBytes': jsHeapUsedBytes,
      if (jsHeapTotalBytes != null) 'jsHeapTotalBytes': jsHeapTotalBytes,
      if (domDocumentCount != null) 'domDocumentCount': domDocumentCount,
      if (domNodeCount != null) 'domNodeCount': domNodeCount,
      if (jsEventListenerCount != null)
        'jsEventListenerCount': jsEventListenerCount,
    };
  }
}

Map<String, Object?> _readMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Expected object at `$key`.');
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected string at `$key`.');
}

List<String> _readStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const <String>[];
  if (value is List) return value.map((item) => item.toString()).toList();
  throw FormatException('Expected list at `$key`.');
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Expected number at `$key`.');
}

double? _readOptionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Expected number at `$key`.');
}

int? _readOptionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toInt();
  throw FormatException('Expected number at `$key`.');
}

bool _readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected boolean at `$key`.');
}

bool? _readOptionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('Expected boolean at `$key`.');
}

Duration _readMicros(Map<String, Object?> json, String key) {
  return Duration(microseconds: _readInt(json, key));
}

Duration _readOptionalMicros(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return Duration.zero;
  if (value is num) return Duration(microseconds: value.toInt());
  throw FormatException('Expected number at `$key`.');
}

FrameDamageSource _readDamageSource(Map<String, Object?> json, String key) {
  final name = _readString(json, key);
  for (final source in FrameDamageSource.values) {
    if (source.name == name) return source;
  }
  throw FormatException('Unknown frame damage source `$name`.');
}

double _percentile(List<double> sorted, double percentile) {
  if (sorted.isEmpty) return 0;
  final index = (sorted.length * percentile).ceil().clamp(1, sorted.length) - 1;
  return sorted[index];
}

String _dominantP95Slice(Map<String, WebMetricSummary> timings) {
  final hasRuntimeSubphaseTimings =
      (timings['runtimeBuildMs']?.p95 ?? 0) > 0 ||
      (timings['runtimeLayoutMs']?.p95 ?? 0) > 0 ||
      (timings['runtimePaintMs']?.p95 ?? 0) > 0;
  final candidates = <String>[
    if (hasRuntimeSubphaseTimings) ...[
      'runtimeBuildMs',
      'runtimeLayoutMs',
      'runtimePaintMs',
    ] else
      'runtimeRenderMs',
    'dirtyRowDiffMs',
    'spanBuildMs',
    'domApplyMs',
    'semanticApplyMs',
  ];
  var best = 'none';
  var bestValue = 0.0;
  for (final candidate in candidates) {
    final value = timings[candidate]?.p95 ?? 0;
    if (value > bestValue) {
      best = candidate;
      bestValue = value;
    }
  }
  return best;
}

double _hitRate({required double hits, required double misses}) {
  final total = hits + misses;
  return total <= 0 ? 0 : hits / total;
}
