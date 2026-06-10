import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/frame_presentation.dart';
import 'package:fleury_web/src/instrumentation/web_host_instrumentation.dart';
import 'package:test/test.dart';

void main() {
  test('web frame instrumentation round-trips through JSON', () {
    final frame = _frame(
      reason: 'input',
      coalescedReasons: const ['input', 'post-frame'],
      totalFrameMs: 12.5,
      runtimeRenderMs: 2.0,
      runtimeBufferPrepareMs: 0.2,
      runtimeBuildMs: 0.3,
      runtimeBuildPasses: 1,
      runtimeRebuiltElements: 2,
      runtimeMaxDirtyElements: 2,
      runtimeLayoutMs: 0.4,
      runtimePaintMs: 1.1,
      dirtyRowDiffMs: 0.9,
      domApplyMs: 3.5,
      semanticTreeBuildMs: 0.4,
      semanticCoverageMs: 0.5,
      semanticDiffMs: 0.6,
      semanticPresenterMs: 0.7,
      semanticFocusSyncMs: 0.8,
      dirtyRows: 4,
      styleCacheHits: 7,
      styleCacheMisses: 1,
      semanticDomCreatedElements: 2,
      semanticDomReusedElements: 3,
      semanticDomReplacedElements: 4,
      semanticDomAttributesSet: 5,
      semanticDomAttributesRemoved: 6,
    );

    final copy = WebFrameInstrumentation.fromJson(frame.toJson());
    final json = copy.toJson();

    expect(copy.reason, 'input');
    expect(copy.coalescedReasons, ['input', 'post-frame']);
    expect(copy.viewportSize, const CellSize(20, 4));
    expect(copy.damageSource, FrameDamageSource.paintDamage);
    expect(copy.dirtyRowCount, 4);
    expect(copy.styleCacheHits, 7);
    expect(copy.styleCacheMisses, 1);
    expect(copy.runtimePhaseTimingAvailable, isTrue);
    expect(json['runtimePhaseTimingAvailable'], isTrue);
    expect(copy.runtimeBufferPrepareTime.inMicroseconds, 200);
    expect(copy.runtimeBuildTime.inMicroseconds, 300);
    expect(copy.runtimeBuildPassCount, 1);
    expect(copy.runtimeRebuiltElementCount, 2);
    expect(copy.runtimeMaxDirtyElementCount, 2);
    expect(copy.runtimeLayoutTime.inMicroseconds, 400);
    expect(copy.runtimePaintTime.inMicroseconds, 1100);
    expect(copy.dirtyRowDiffTime.inMicroseconds, 900);
    expect(copy.semanticTreeBuildTime.inMicroseconds, 400);
    expect(copy.semanticCoverageTime.inMicroseconds, 500);
    expect(copy.semanticDiffTime.inMicroseconds, 600);
    expect(copy.semanticPresenterTime.inMicroseconds, 700);
    expect(copy.semanticFocusSyncTime.inMicroseconds, 800);
    expect(copy.semanticDomCreatedElementCount, 2);
    expect(copy.semanticDomReusedElementCount, 3);
    expect(copy.semanticDomReplacedElementCount, 4);
    expect(copy.semanticDomAttributesSetCount, 5);
    expect(copy.semanticDomAttributesRemovedCount, 6);
    expect(copy.totalFrameTime.inMicroseconds, 12500);
  });

  test(
    'web frame instrumentation reads old captures without optional timings',
    () {
      final json = _frame().toJson()
        ..remove('runtimePhaseTimingAvailable')
        ..remove('runtimeBufferPrepareMicros')
        ..remove('runtimeBuildMicros')
        ..remove('runtimeBuildPassCount')
        ..remove('runtimeRebuiltElementCount')
        ..remove('runtimeMaxDirtyElementCount')
        ..remove('runtimeLayoutMicros')
        ..remove('runtimePaintMicros')
        ..remove('dirtyRowDiffMicros');

      final copy = WebFrameInstrumentation.fromJson(json);

      expect(copy.runtimePhaseTimingAvailable, isFalse);
      expect(copy.runtimeBufferPrepareTime, Duration.zero);
      expect(copy.runtimeBuildTime, Duration.zero);
      expect(copy.runtimeBuildPassCount, 0);
      expect(copy.runtimeRebuiltElementCount, 0);
      expect(copy.runtimeMaxDirtyElementCount, 0);
      expect(copy.runtimeLayoutTime, Duration.zero);
      expect(copy.runtimePaintTime, Duration.zero);
      expect(copy.dirtyRowDiffTime, Duration.zero);
    },
  );

  test('summary reports total-frame budget misses and dominant p95 slice', () {
    final frames = [
      _frame(
        totalFrameMs: 10,
        runtimeRenderMs: 2,
        runtimeBufferPrepareMs: 0.1,
        runtimeBuildMs: 0.2,
        runtimeBuildPasses: 1,
        runtimeRebuiltElements: 2,
        runtimeMaxDirtyElements: 2,
        runtimeLayoutMs: 0.3,
        runtimePaintMs: 1.5,
        dirtyRowDiffMs: 0.7,
        spanBuildMs: 1,
        domApplyMs: 3,
        semanticTreeBuildMs: 0.2,
        semanticCoverageMs: 0.3,
        semanticDiffMs: 0.4,
        semanticPresenterMs: 0.5,
        semanticFocusSyncMs: 0.6,
        semanticApplyMs: 1,
        dirtyRows: 2,
        styleCacheHits: 3,
        styleCacheMisses: 1,
        semanticDomReusedElements: 1,
      ),
      _frame(
        totalFrameMs: 22,
        runtimeRenderMs: 4,
        runtimeBufferPrepareMs: 0.2,
        runtimeBuildMs: 0.4,
        runtimeBuildPasses: 2,
        runtimeRebuiltElements: 5,
        runtimeMaxDirtyElements: 3,
        runtimeLayoutMs: 0.6,
        runtimePaintMs: 3.0,
        dirtyRowDiffMs: 1.5,
        spanBuildMs: 2,
        domApplyMs: 12,
        semanticTreeBuildMs: 0.4,
        semanticCoverageMs: 0.6,
        semanticDiffMs: 0.8,
        semanticPresenterMs: 1.0,
        semanticFocusSyncMs: 1.2,
        semanticApplyMs: 2,
        dirtyRows: 8,
        styleCacheHits: 9,
        styleCacheMisses: 3,
        semanticDomReusedElements: 2,
      ),
    ];

    final summary = WebInstrumentationSummary.fromFrames(frames);
    final json = summary.toJson();

    expect(summary.frameCount, 2);
    expect(summary.overBudgetFrameCount, 1);
    expect(summary.overBudgetPercent, 50);
    expect(summary.dominantP95Slice, 'domApplyMs');
    expect(summary.timings['totalFrameMs']!.p50, 10);
    expect(summary.timings['totalFrameMs']!.p95, 22);
    expect(summary.timings['runtimeBuildMs']!.sampleCount, 2);
    expect(summary.timings['runtimeBufferPrepareMs']!.sampleCount, 2);
    expect(summary.timings['runtimeBufferPrepareMs']!.p95, 0.2);
    expect(summary.timings['runtimeBuildMs']!.p95, 0.4);
    expect(summary.timings['runtimeLayoutMs']!.sampleCount, 2);
    expect(summary.timings['runtimeLayoutMs']!.p95, 0.6);
    expect(summary.timings['runtimePaintMs']!.sampleCount, 2);
    expect(summary.timings['runtimePaintMs']!.p95, 3.0);
    expect(summary.timings['dirtyRowDiffMs']!.p95, 1.5);
    expect(summary.timings['semanticTreeBuildMs']!.p95, 0.4);
    expect(summary.timings['semanticPresenterMs']!.p95, 1.0);
    expect(summary.counts['runtimeBuildPasses']!.total, 3);
    expect(summary.counts['runtimeRebuiltElements']!.p95, 5);
    expect(summary.counts['runtimeMaxDirtyElements']!.p95, 3);
    expect(summary.counts['dirtyRows']!.total, 10);
    expect(summary.counts['dirtyRows']!.p95, 8);
    expect(summary.counts['semanticDomReusedElements']!.total, 3);
    expect(summary.cacheHitRates['style'], 0.75);
    expect(json['kind'], 'fleuryWebFrameSummary');
    expect(json['frameBudgetMicros'], 16670);
  });

  test('summary prefers runtime subphase for dominant p95 slice', () {
    final summary = WebInstrumentationSummary.fromFrames([
      _frame(
        runtimeRenderMs: 6,
        runtimeBufferPrepareMs: 0.4,
        runtimeBuildMs: 0.5,
        runtimeLayoutMs: 1.0,
        runtimePaintMs: 4.0,
        dirtyRowDiffMs: 0.6,
        spanBuildMs: 0.8,
        domApplyMs: 2.0,
        semanticApplyMs: 1.5,
      ),
    ]);

    expect(summary.dominantP95Slice, 'runtimePaintMs');
  });

  test('summary falls back to runtime render for old captures', () {
    final oldJson =
        _frame(
            runtimeRenderMs: 6,
            runtimeBufferPrepareMs: 0.4,
            dirtyRowDiffMs: 0.6,
            spanBuildMs: 0.8,
            domApplyMs: 2.0,
            semanticApplyMs: 1.5,
          ).toJson()
          ..remove('runtimePhaseTimingAvailable')
          ..remove('runtimeBufferPrepareMicros')
          ..remove('runtimeBuildMicros')
          ..remove('runtimeLayoutMicros')
          ..remove('runtimePaintMicros');

    final summary = WebInstrumentationSummary.fromFrames([
      WebFrameInstrumentation.fromJson(oldJson),
    ]);

    expect(summary.dominantP95Slice, 'runtimeRenderMs');
    expect(summary.timings['runtimeBuildMs']!.sampleCount, 0);
    expect(summary.timings['runtimeBufferPrepareMs']!.sampleCount, 0);
    expect(summary.timings['runtimeLayoutMs']!.sampleCount, 0);
    expect(summary.timings['runtimePaintMs']!.sampleCount, 0);
  });

  test('recording sink serializes frames with summary', () {
    final recorder = RecordingWebHostInstrumentation()
      ..recordFrame(_frame(totalFrameMs: 1))
      ..recordFrame(_frame(totalFrameMs: 2));

    final json = recorder.toJson(frameBudgetMs: 1.5);

    expect(json['kind'], 'fleuryWebFrameCapture');
    expect(json['frames'], isA<List<Object?>>());
    final summary = json['summary'] as Map<String, Object?>;
    expect(summary['overBudgetFrameCount'], 1);
  });

  test('browser performance metrics round-trip optional CDP fields', () {
    const metrics = WebBrowserPerformanceMetrics(
      layoutDurationMs: 1.25,
      recalcStyleDurationMs: 2.5,
      scriptDurationMs: 3.75,
      taskDurationMs: 8.0,
      jsHeapUsedBytes: 1048576,
      jsHeapTotalBytes: 2097152,
      domDocumentCount: 1,
      domNodeCount: 240,
      jsEventListenerCount: 12,
    );

    final json = metrics.toJson();
    final copy = WebBrowserPerformanceMetrics.fromJson(json);

    expect(copy.layoutDurationMs, 1.25);
    expect(copy.recalcStyleDurationMs, 2.5);
    expect(copy.scriptDurationMs, 3.75);
    expect(copy.taskDurationMs, 8.0);
    expect(copy.jsHeapUsedBytes, 1048576);
    expect(copy.jsHeapTotalBytes, 2097152);
    expect(copy.domDocumentCount, 1);
    expect(copy.domNodeCount, 240);
    expect(copy.jsEventListenerCount, 12);
    expect(const WebBrowserPerformanceMetrics().toJson(), isEmpty);
  });
}

WebFrameInstrumentation _frame({
  String reason = 'initial',
  List<String> coalescedReasons = const ['initial'],
  double totalFrameMs = 1,
  double runtimeRenderMs = 0.1,
  double runtimeBufferPrepareMs = 0,
  double runtimeBuildMs = 0,
  int runtimeBuildPasses = 0,
  int runtimeRebuiltElements = 0,
  int runtimeMaxDirtyElements = 0,
  double runtimeLayoutMs = 0,
  double runtimePaintMs = 0,
  double dirtyRowDiffMs = 0,
  double spanBuildMs = 0.1,
  double domApplyMs = 0.1,
  double semanticTreeBuildMs = 0,
  double semanticCoverageMs = 0,
  double semanticDiffMs = 0,
  double semanticPresenterMs = 0,
  double semanticFocusSyncMs = 0,
  double semanticApplyMs = 0.1,
  int dirtyRows = 1,
  int styleCacheHits = 0,
  int styleCacheMisses = 0,
  int semanticDomCreatedElements = 0,
  int semanticDomReusedElements = 0,
  int semanticDomReplacedElements = 0,
  int semanticDomAttributesSet = 0,
  int semanticDomAttributesRemoved = 0,
  bool runtimePhaseTimingAvailable = true,
}) {
  return WebFrameInstrumentation(
    reason: reason,
    coalescedReasons: coalescedReasons,
    viewportSize: const CellSize(20, 4),
    damageSource: FrameDamageSource.paintDamage,
    fullRepaint: false,
    metricsChanged: false,
    dirtyRowCount: dirtyRows,
    dirtyCellEstimate: dirtyRows * 20,
    spanCount: dirtyRows + 1,
    domNodesCreated: dirtyRows + 2,
    rowsReplaced: dirtyRows,
    styleCacheHits: styleCacheHits,
    styleCacheMisses: styleCacheMisses,
    widthCacheHits: 0,
    widthCacheMisses: 0,
    metricsReadCount: 1,
    semanticNodeCount: 2,
    semanticAddedNodeCount: 1,
    semanticRemovedNodeCount: 0,
    semanticUpdatedNodeCount: 1,
    semanticDomCreatedElementCount: semanticDomCreatedElements,
    semanticDomReusedElementCount: semanticDomReusedElements,
    semanticDomReplacedElementCount: semanticDomReplacedElements,
    semanticDomAttributesSetCount: semanticDomAttributesSet,
    semanticDomAttributesRemovedCount: semanticDomAttributesRemoved,
    semanticFallbackNodeCount: 0,
    semanticUncoveredCellCount: 0,
    runtimeRenderTime: _ms(runtimeRenderMs),
    runtimePhaseTimingAvailable: runtimePhaseTimingAvailable,
    runtimeBuildPassCount: runtimeBuildPasses,
    runtimeRebuiltElementCount: runtimeRebuiltElements,
    runtimeMaxDirtyElementCount: runtimeMaxDirtyElements,
    runtimeBufferPrepareTime: _ms(runtimeBufferPrepareMs),
    runtimeBuildTime: _ms(runtimeBuildMs),
    runtimeLayoutTime: _ms(runtimeLayoutMs),
    runtimePaintTime: _ms(runtimePaintMs),
    dirtyRowDiffTime: _ms(dirtyRowDiffMs),
    spanBuildTime: _ms(spanBuildMs),
    domApplyTime: _ms(domApplyMs),
    semanticTreeBuildTime: _ms(semanticTreeBuildMs),
    semanticCoverageTime: _ms(semanticCoverageMs),
    semanticDiffTime: _ms(semanticDiffMs),
    semanticPresenterTime: _ms(semanticPresenterMs),
    semanticFocusSyncTime: _ms(semanticFocusSyncMs),
    semanticApplyTime: _ms(semanticApplyMs),
    totalFrameTime: _ms(totalFrameMs),
  );
}

Duration _ms(double value) => Duration(microseconds: (value * 1000).round());
