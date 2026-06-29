@TestOn('browser')
library;

import 'dart:async';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/focus/web_focus_coordinator.dart';
import 'package:fleury_web/src/frame_presentation.dart';
import 'package:fleury_web/src/input/input_source.dart';
import 'package:fleury_web/src/instrumentation/web_host_instrumentation.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:fleury_web/src/run_tui_surface.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:fleury_web/src/semantics/semantic_flush_scheduler.dart';
import 'package:fleury_web/src/semantics/semantic_presenter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

class _FakeSemanticFlush implements SemanticFlushScheduler {
  void Function()? _pending;
  var scheduleCount = 0;
  var disposed = false;

  bool get pending => _pending != null;

  @override
  void schedule(void Function() flush) {
    scheduleCount += 1;
    _pending ??= flush;
  }

  @override
  void dispose() {
    disposed = true;
    _pending = null;
  }

  void fire() {
    final flush = _pending;
    if (flush == null) throw StateError('No pending semantic flush.');
    _pending = null;
    flush();
  }
}

class _FakeFlush {
  Duration? delay;
  void Function()? _pending;
  var scheduleCount = 0;

  bool get pending => _pending != null;

  void schedule(Duration delay, void Function() flush) {
    scheduleCount += 1;
    this.delay = delay;
    _pending = flush;
  }

  void fire() {
    final flush = _pending;
    if (flush == null) throw StateError('No pending frame flush.');
    _pending = null;
    delay = null;
    flush();
  }
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var count = 0;

  void increment() => setState(() => count += 1);

  @override
  Widget build(BuildContext context) {
    return Column(children: [const Text('dom host'), Text('count $count')]);
  }
}

class _FakeMetrics implements CellMetrics {
  _FakeMetrics(this.box);

  MeasuredCellBox box;
  void Function()? _onMetricsDirty;
  var disposed = false;

  @override
  MeasuredCellBox measure() => box;

  @override
  MeasuredCellBox? get cachedMeasurement => box;

  @override
  void startObserving(void Function() onMetricsDirty) {
    _onMetricsDirty = onMetricsDirty;
  }

  @override
  void markDirty() {}

  @override
  CellOffset cellForPoint(double x, double y) {
    if (box.cols <= 0 || box.rows <= 0) return CellOffset.zero;
    final col = (x / box.cssCellWidth).floor().clamp(0, box.cols - 1).toInt();
    final row = (y / box.cssCellHeight).floor().clamp(0, box.rows - 1).toInt();
    return CellOffset(col, row);
  }

  @override
  CellOffset? cellForViewportPoint(double clientX, double clientY) {
    if (box.cols <= 0 || box.rows <= 0) return null;
    return cellForPoint(
      clientX - box.cssCanvasLeft,
      clientY - box.cssCanvasTop,
    );
  }

  @override
  void dispose() {
    disposed = true;
  }

  void emitResize(MeasuredCellBox next) {
    box = next;
    _onMetricsDirty?.call();
  }
}

class _FakeInputSource implements TuiInputSource, KeyboardCaptureTarget {
  TuiInputSink? _sink;
  CellRect? caretRect;
  MeasuredCellBox? caretMetrics;
  var caretSyncCount = 0;
  var keyboardCaptureCount = 0;
  var disposed = false;

  @override
  void start(TuiInputSink onEvent) {
    _sink = onEvent;
  }

  @override
  void dispose() {
    disposed = true;
    _sink = null;
  }

  @override
  void syncCaretGeometry(CellRect? caretRect, MeasuredCellBox? metrics) {
    this.caretRect = caretRect;
    caretMetrics = metrics;
    caretSyncCount += 1;
  }

  @override
  void ensureKeyboardCapture() {
    keyboardCaptureCount += 1;
  }

  void emit(TuiEvent event) {
    final sink = _sink;
    if (sink == null) throw StateError('Input source is not started.');
    sink(event);
  }
}

class _ThrowingKeyboardCaptureInputSource extends _FakeInputSource {
  _ThrowingKeyboardCaptureInputSource(this.error);

  final Object error;

  @override
  void ensureKeyboardCapture() {
    throw error;
  }
}

class _FakeClipboard extends Clipboard {
  String? lastWritten;

  @override
  String? readInProcess() => lastWritten;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    lastWritten = text;
    return ClipboardWriteReport(
      result: ClipboardWriteResult.inProcessOnly,
      resolution: const CapabilityResolution(
        feature: TerminalFeature.clipboardWrite,
        level: CapabilityLevel.preferred,
        state: CapabilityResolutionState.degraded,
        fallbackLabel: 'in-process register',
      ),
      policy: policy,
      payloadBytes: text.length,
      osc52EncodedLength: text.length,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: false,
      osc52Attempted: false,
      osc52Emitted: false,
    );
  }
}

class _FakeSemanticPresenter
    implements SemanticFramePresenter, SemanticActionRequestSink {
  final trees = <SemanticTree>[];
  final updates = <SemanticTreeUpdate?>[];
  SemanticActionRequestHandler? _onSemanticActionRequest;
  var disposed = false;

  @override
  set onSemanticActionRequest(SemanticActionRequestHandler? handler) {
    _onSemanticActionRequest = handler;
  }

  @override
  SemanticPresentationStats present(
    SemanticTree tree, {
    SemanticTreeUpdate? update,
  }) {
    trees.add(tree);
    updates.add(update);
    return SemanticPresentationStats(
      nodeCount: tree.nodes.length,
      addedNodeCount: update?.added.length ?? 0,
      removedNodeCount: update?.removed.length ?? 0,
      updatedNodeCount: update?.updated.length ?? 0,
      createdElementCount: 0,
      reusedElementCount: 0,
      replacedElementCount: 0,
      attributesSetCount: 0,
      attributesRemovedCount: 0,
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _onSemanticActionRequest = null;
  }

  void requestAction(SemanticNodeId id, SemanticAction action) {
    final handler = _onSemanticActionRequest;
    if (handler == null) throw StateError('No semantic action handler.');
    handler(id, action);
  }
}

final class _ThrowingResizeSurface implements FrameSurface {
  _ThrowingResizeSurface(this.error);

  final Object error;
  var disposed = false;

  @override
  CellSize get size => CellSize.zero;

  @override
  WebSurfaceCapabilities get capabilities => const WebSurfaceCapabilities();

  @override
  FrameSurfacePresentationStats present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  ) {
    return FrameSurfacePresentationStats.none;
  }

  @override
  void resize(CellSize size, {MeasuredCellBox? metrics}) {
    throw error;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _ThrowingPresentSurface implements FrameSurface {
  _ThrowingPresentSurface(this.error, {required this.size});

  final Object error;
  var disposed = false;

  @override
  final CellSize size;

  @override
  WebSurfaceCapabilities get capabilities => const WebSurfaceCapabilities();

  @override
  FrameSurfacePresentationStats present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  ) {
    throw error;
  }

  @override
  void resize(CellSize size, {MeasuredCellBox? metrics}) {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _ThrowingDisposeSurface implements FrameSurface {
  _ThrowingDisposeSurface(this.error, {required this.size});

  final Object error;
  var disposed = false;

  @override
  final CellSize size;

  @override
  WebSurfaceCapabilities get capabilities => const WebSurfaceCapabilities();

  @override
  FrameSurfacePresentationStats present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  ) {
    return FrameSurfacePresentationStats.none;
  }

  @override
  void resize(CellSize size, {MeasuredCellBox? metrics}) {}

  @override
  Future<void> dispose() async {
    disposed = true;
    throw error;
  }
}

class _LeafWithRawText extends StatefulWidget {
  const _LeafWithRawText({super.key});

  @override
  State<_LeafWithRawText> createState() => _LeafWithRawTextState();
}

class _LeafWithRawTextState extends State<_LeafWithRawText> {
  var generation = 0;

  void advance() => setState(() => generation += 1);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          id: const SemanticNodeId('status'),
          role: SemanticRole.status,
          label: 'gen $generation',
          includeChildren: false,
          child: const SizedBox.fromSize(cols: 6, rows: 1),
        ),
        _RawPaintedText('raw$generation'),
      ],
    );
  }
}

final class _RawPaintedText extends LeafRenderObjectWidget {
  const _RawPaintedText(this.text);

  final String text;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRawPaintedText(text);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderRawPaintedText renderObject,
  ) {
    renderObject.text = text;
  }
}

final class _RenderRawPaintedText extends RenderObject {
  _RenderRawPaintedText(this._text);

  String _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    return constraints.constrain(CellSize(_text.length, 1));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    buffer.writeText(offset, _text);
  }
}

MeasuredCellBox _box({
  required int cols,
  required int rows,
  double cssCellWidth = 10,
  double cssCellHeight = 20,
}) => MeasuredCellBox(
  cssCellWidth: cssCellWidth,
  cssCellHeight: cssCellHeight,
  cssCanvasWidth: cols * cssCellWidth,
  cssCanvasHeight: rows * cssCellHeight,
  devicePixelRatio: 1,
  cols: cols,
  rows: rows,
);

void main() {
  test('renders a Fleury widget tree through a retained DOM surface', () async {
    final root = web.document.createElement('div');
    final surface = DomGridSurface(root: root, size: const CellSize(20, 3));
    final flush = _FakeFlush();

    final host = await runTuiSurface(
      () => const Text('hello dom'),
      surface: surface,
      flushScheduler: flush.schedule,
    );

    expect(flush.pending, isTrue);
    expect(root.textContent, isEmpty);

    flush.fire();
    await host.awaitSemanticIdle();

    expect(root.textContent, contains('hello dom'));
    expect(surface.presentCount, 1);
    expect(surface.rowElements, hasLength(3));

    await host.dispose();
  });

  test('setState schedules and presents another DOM frame', () async {
    final root = web.document.createElement('div');
    final surface = DomGridSurface(root: root, size: const CellSize(20, 4));
    final flush = _FakeFlush();
    final key = GlobalKey<_CounterState>();

    final host = await runTuiSurface(
      () => _Counter(key: key),
      surface: surface,
      flushScheduler: flush.schedule,
    );
    flush.fire();
    await host.awaitSemanticIdle();
    expect(root.textContent, contains('count 0'));
    final replaceCountAfterInitial = surface.rowReplaceCount;

    key.currentState!.increment();

    expect(flush.pending, isTrue);
    flush.fire();
    await host.awaitSemanticIdle();

    expect(root.textContent, contains('count 1'));
    expect(surface.presentCount, 2);
    expect(surface.rowReplaceCount, greaterThan(replaceCountAfterInitial));

    await host.dispose();
  });

  test(
    'metrics resize is enqueued and applied during the next frame',
    () async {
      final root = web.document.createElement('div');
      final metrics = _FakeMetrics(_box(cols: 8, rows: 2));
      final surface = DomGridSurface(root: root, size: CellSize.zero);
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => const Text('metric host'),
        surface: surface,
        cellMetrics: metrics,
        flushScheduler: flush.schedule,
      );

      expect(surface.size, const CellSize(8, 2));
      expect(surface.rowElements, hasLength(2));
      expect(root.getAttribute('style'), contains('width:80px'));
      expect(root.getAttribute('style'), contains('height:40px'));
      flush.fire();
      await host.awaitSemanticIdle();

      metrics.emitResize(_box(cols: 12, rows: 3));

      expect(flush.pending, isTrue);
      expect(surface.size, const CellSize(8, 2));
      expect(surface.rowElements, hasLength(2));

      flush.fire();
      await host.awaitSemanticIdle();

      expect(surface.size, const CellSize(12, 3));
      expect(surface.rowElements, hasLength(3));
      expect(root.getAttribute('style'), contains('width:120px'));
      expect(root.getAttribute('style'), contains('height:60px'));
      expect(root.textContent, contains('metric host'));

      await host.dispose();
      expect(metrics.disposed, isTrue);
    },
  );

  test(
    'input source events are queued and dispatched during the next frame',
    () async {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: const CellSize(20, 1));
      final flush = _FakeFlush();
      final input = _FakeInputSource();
      final controller = TextEditingController();

      final host = await runTuiSurface(
        () => TextInput(controller: controller, autofocus: true),
        surface: surface,
        inputSource: input,
        flushScheduler: flush.schedule,
      );
      flush.fire();
      await host.awaitSemanticIdle();
      expect(controller.text, isEmpty);

      input.emit(const TextInputEvent('a'));

      expect(flush.pending, isTrue);
      expect(controller.text, isEmpty);

      flush.fire();
      await host.awaitSemanticIdle();

      expect(controller.text, 'a');
      expect(root.textContent, contains('a'));

      await host.dispose();
      expect(input.disposed, isTrue);
    },
  );

  test(
    'IME composition input is queued and dispatched during a frame',
    () async {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: const CellSize(20, 1));
      final flush = _FakeFlush();
      final input = _FakeInputSource();
      final controller = TextEditingController(text: 'git ');

      final host = await runTuiSurface(
        () => TextInput(controller: controller, autofocus: true),
        surface: surface,
        inputSource: input,
        flushScheduler: flush.schedule,
      );
      flush.fire();
      await host.awaitSemanticIdle();
      expect(controller.text, 'git ');

      input.emit(const TextCompositionEvent.update('che'));

      expect(flush.pending, isTrue);
      expect(controller.text, 'git ');

      flush.fire();
      await host.awaitSemanticIdle();

      expect(controller.text, 'git che');
      expect(controller.hasComposingRange, isTrue);

      input.emit(const TextCompositionEvent.commit('checkout'));
      flush.fire();
      await host.awaitSemanticIdle();

      expect(controller.text, 'git checkout');
      expect(controller.hasComposingRange, isFalse);
      expect(root.textContent, contains('git checkout'));

      await host.dispose();
      expect(input.disposed, isTrue);
    },
  );

  test('focused caret geometry is synced after presentation', () async {
    final root = web.document.createElement('div');
    final metrics = _FakeMetrics(_box(cols: 20, rows: 1));
    final surface = DomGridSurface(root: root, size: CellSize.zero);
    final flush = _FakeFlush();
    final input = _FakeInputSource();
    final controller = TextEditingController(text: 'abc');

    final host = await runTuiSurface(
      () => TextInput(controller: controller, autofocus: true),
      surface: surface,
      cellMetrics: metrics,
      inputSource: input,
      flushScheduler: flush.schedule,
    );

    flush.fire();
    await host.awaitSemanticIdle();

    expect(input.caretSyncCount, greaterThan(0));
    expect(input.caretRect, CellRect.fromLTWH(3, 0, 1, 1));
    expect(input.caretMetrics, same(metrics.box));

    await host.dispose();
  });

  test('semantic DOM presenter receives current frame semantics', () async {
    final visualRoot = web.document.createElement('div');
    final semanticRoot = web.document.createElement('div');
    final surface = DomGridSurface(
      root: visualRoot,
      size: const CellSize(24, 1),
    );
    final semantics = SemanticDomPresenter(root: semanticRoot);
    final flush = _FakeFlush();
    final controller = TextEditingController(text: 'deploy');

    final host = await runTuiSurface(
      () => TextInput(
        controller: controller,
        autofocus: true,
        placeholder: 'Command',
      ),
      surface: surface,
      semanticPresenter: semantics,
      flushScheduler: flush.schedule,
    );

    flush.fire();
    await host.awaitSemanticIdle();

    final field =
        semanticRoot.querySelector('[role="textbox"]')! as web.HTMLInputElement;
    expect(visualRoot.ariaHidden, 'true');
    expect(semanticRoot.getAttribute('aria-hidden'), isNull);
    expect(semanticRoot.className, 'fleury-semantics');
    expect(field.getAttribute('aria-label'), 'Command');
    expect(field.value, 'deploy');
    expect(field.getAttribute('data-fleury-value'), 'deploy');
    expect(field.getAttribute('data-fleury-focused'), 'true');
    expect(field.getAttribute('data-fleury-actions'), contains('focus'));

    await host.dispose();
    expect(semanticRoot.children.length, 0);
  });

  test('semantic presenter receives retained owner updates', () async {
    final visualRoot = web.document.createElement('div');
    final surface = DomGridSurface(
      root: visualRoot,
      size: const CellSize(24, 2),
    );
    final semantics = _FakeSemanticPresenter();
    final flush = _FakeFlush();
    final key = GlobalKey<_CounterState>();

    final host = await runTuiSurface(
      () => _Counter(key: key),
      surface: surface,
      semanticPresenter: semantics,
      flushScheduler: flush.schedule,
    );

    flush.fire();
    await host.awaitSemanticIdle();

    expect(semantics.updates, hasLength(1));
    expect(semantics.updates.single?.previous, isNull);
    expect(semantics.updates.single?.added, isNotEmpty);
    expect(
      semantics.trees.single.nodes.map((node) => node.label),
      contains('count 0'),
    );

    key.currentState!.increment();
    flush.fire();
    await host.awaitSemanticIdle();

    expect(semantics.updates, hasLength(2));
    expect(semantics.updates.last?.previous, isNotNull);
    expect(semantics.updates.last?.updated, isNotEmpty);
    expect(
      semantics.trees.last.nodes.map((node) => node.label),
      contains('count 1'),
    );

    await host.dispose();
    expect(semantics.disposed, isTrue);
  });

  test(
    'records per-frame instrumentation for visual and semantic presenters',
    () async {
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final metrics = _FakeMetrics(_box(cols: 16, rows: 2));
      final surface = DomGridSurface(root: visualRoot, size: CellSize.zero);
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => const Text('instrumented'),
        surface: surface,
        cellMetrics: metrics,
        semanticPresenter: semantics,
        instrumentation: instrumentation,
        flushScheduler: flush.schedule,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      expect(instrumentation.frames, hasLength(1));
      final frame = instrumentation.frames.single;
      expect(frame.reason, 'initial');
      expect(frame.coalescedReasons, ['initial']);
      expect(frame.viewportSize, const CellSize(16, 2));
      expect(frame.fullRepaint, isTrue);
      expect(frame.metricsChanged, isFalse);
      expect(frame.metricsReadCount, 1);
      expect(frame.dirtyRowCount, 2);
      expect(frame.dirtyCellEstimate, 32);
      expect(frame.spanCount, greaterThan(0));
      expect(frame.rowsReplaced, 2);
      expect(frame.domNodesCreated, greaterThan(0));
      expect(frame.styleCacheMisses, greaterThan(0));
      expect(frame.styleCacheHits, greaterThan(0));
      expect(frame.semanticFallbackNodeCount, 0);
      expect(frame.semanticUncoveredCellCount, 0);
      expect(instrumentation.semanticFlushes, hasLength(1));
      final semanticFlush = instrumentation.semanticFlushes.single;
      expect(semanticFlush.coalescedFrameCount, 1);
      expect(semanticFlush.retainedOutput, isFalse);
      expect(semanticFlush.semanticNodeCount, greaterThan(0));
      expect(semanticFlush.semanticAddedNodeCount, greaterThan(0));
      expect(semanticFlush.semanticFallbackNodeCount, 0);
      expect(semanticFlush.semanticUncoveredCellCount, 0);
      expect(semanticFlush.totalFlushTime, greaterThanOrEqualTo(Duration.zero));
      expect(
        semanticFlush.presentationLatency,
        greaterThanOrEqualTo(semanticFlush.totalFlushTime),
      );
      expect(frame.runtimeRenderTime, greaterThanOrEqualTo(Duration.zero));
      expect(frame.runtimeBuildTime, greaterThanOrEqualTo(Duration.zero));
      expect(frame.runtimeLayoutTime, greaterThanOrEqualTo(Duration.zero));
      expect(frame.runtimePaintTime, greaterThanOrEqualTo(Duration.zero));
      expect(frame.dirtyRowDiffTime, Duration.zero);
      expect(frame.spanBuildTime, greaterThanOrEqualTo(Duration.zero));
      expect(frame.domApplyTime, greaterThanOrEqualTo(Duration.zero));
      expect(frame.semanticApplyTime, greaterThanOrEqualTo(Duration.zero));
      expect(frame.totalFrameTime, greaterThanOrEqualTo(Duration.zero));

      await host.dispose();
    },
  );

  test(
    'semantic DOM receives text fallback for uncovered painted cells',
    () async {
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(10, 1),
      );
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => const _RawPaintedText('raw'),
        surface: surface,
        semanticPresenter: semantics,
        instrumentation: instrumentation,
        flushScheduler: flush.schedule,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      final fallback = semanticRoot.querySelector(
        '[data-fleury-semantic-id="__fleury_text_fallback_0_0"]',
      )!;
      expect(visualRoot.getAttribute('aria-hidden'), 'true');
      expect(fallback.getAttribute('data-fleury-semantic-role'), 'text');
      expect(fallback.textContent, 'raw');
      expect(fallback.getAttribute('data-fleury-bounds-left'), '0');
      expect(fallback.getAttribute('data-fleury-bounds-width'), '3');
      expect(
        instrumentation.semanticFlushes.single.semanticFallbackNodeCount,
        1,
      );
      expect(
        instrumentation.semanticFlushes.single.semanticUncoveredCellCount,
        3,
      );

      await host.dispose();
    },
  );

  test(
    'unchanged semantic and visual output skips semantic presentation',
    () async {
      final visualRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 1),
      );
      final semantics = _FakeSemanticPresenter();
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => const Text('stable'),
        surface: surface,
        semanticPresenter: semantics,
        instrumentation: instrumentation,
        flushScheduler: flush.schedule,
      );

      flush.fire();
      await host.awaitSemanticIdle();
      expect(semantics.trees, hasLength(1));
      expect(
        instrumentation.semanticFlushes.single.semanticAddedNodeCount,
        greaterThan(0),
      );

      host.requestFrame('noop');
      flush.fire();
      await host.awaitSemanticIdle();

      expect(semantics.trees, hasLength(1));
      expect(instrumentation.frames, hasLength(2));
      // The noop frame replaced no rows and carried no semantic dirt, so no
      // second flush was even scheduled.
      expect(instrumentation.semanticFlushes, hasLength(1));
      final retained = instrumentation.frames.last;
      expect(retained.semanticNodeCount, greaterThan(0));
      expect(retained.semanticAddedNodeCount, 0);
      expect(retained.semanticRemovedNodeCount, 0);
      expect(retained.semanticUpdatedNodeCount, 0);
      expect(retained.semanticFallbackNodeCount, 0);
      expect(retained.semanticUncoveredCellCount, 0);

      await host.dispose();
    },
  );

  test(
    'unchanged raw painted fallback still presents semantic coverage',
    () async {
      final visualRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(10, 1),
      );
      final semantics = _FakeSemanticPresenter();
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => const _RawPaintedText('raw'),
        surface: surface,
        semanticPresenter: semantics,
        instrumentation: instrumentation,
        flushScheduler: flush.schedule,
      );

      flush.fire();
      await host.awaitSemanticIdle();
      expect(semantics.trees, hasLength(1));
      expect(
        instrumentation.semanticFlushes.single.semanticFallbackNodeCount,
        1,
      );

      host.requestFrame('noop');
      flush.fire();
      await host.awaitSemanticIdle();

      // The buffer did not change, so the retained fallback persists without
      // another semantic flush or presentation.
      expect(semantics.trees, hasLength(1));
      expect(instrumentation.frames, hasLength(2));
      expect(instrumentation.semanticFlushes, hasLength(1));
      expect(instrumentation.frames.last.semanticFallbackNodeCount, 1);
      expect(instrumentation.frames.last.semanticUncoveredCellCount, 3);

      await host.dispose();
    },
  );

  test(
    'leaf update with active text fallback refreshes fallback from the buffer',
    () async {
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(10, 2),
      );
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();
      final key = GlobalKey<_LeafWithRawTextState>();

      final host = await runTuiSurface(
        () => _LeafWithRawText(key: key),
        surface: surface,
        semanticPresenter: semantics,
        instrumentation: instrumentation,
        flushScheduler: flush.schedule,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      final fallbackSelector =
          '[data-fleury-semantic-id="__fleury_text_fallback_1_0"]';
      expect(semanticRoot.querySelector(fallbackSelector)!.textContent, 'raw0');
      expect(
        instrumentation.semanticFlushes.single.semanticFallbackNodeCount,
        1,
      );

      // A retained leaf patch of the fallback-bearing tree would keep the
      // stale 'raw0' fallback "covering" the repainted cells; the host must
      // take the full-rebuild path and regenerate fallback from the buffer.
      key.currentState!.advance();
      flush.fire();
      await host.awaitSemanticIdle();

      expect(semanticRoot.querySelector(fallbackSelector)!.textContent, 'raw1');
      expect(
        semanticRoot
            .querySelector('[data-fleury-semantic-id="status"]')!
            .textContent,
        contains('gen 1'),
      );
      expect(instrumentation.semanticFlushes.last.semanticFallbackNodeCount, 1);

      await host.dispose();
    },
  );

  test(
    'two hosts on one page have isolated frame and semantic state',
    () async {
      final rootA = web.document.createElement('div');
      final rootB = web.document.createElement('div');
      final semanticRootA = web.document.createElement('div');
      final semanticRootB = web.document.createElement('div');
      final surfaceA = DomGridSurface(root: rootA, size: const CellSize(24, 2));
      final surfaceB = DomGridSurface(root: rootB, size: const CellSize(24, 2));
      final semanticsA = SemanticDomPresenter(root: semanticRootA);
      final semanticsB = SemanticDomPresenter(root: semanticRootB);
      final instrumentationB = RecordingWebHostInstrumentation();
      final flushA = _FakeFlush();
      final flushB = _FakeFlush();
      final keyA = GlobalKey<_CounterState>();

      final hostA = await runTuiSurface(
        () => _Counter(key: keyA),
        surface: surfaceA,
        semanticPresenter: semanticsA,
        flushScheduler: flushA.schedule,
      );
      final hostB = await runTuiSurface(
        () => const Text('steady'),
        surface: surfaceB,
        semanticPresenter: semanticsB,
        instrumentation: instrumentationB,
        flushScheduler: flushB.schedule,
      );

      flushA.fire();
      await hostA.awaitSemanticIdle();
      flushB.fire();
      await hostB.awaitSemanticIdle();

      // Drive host A only. With shared static trackers, A's dirt would have
      // been consumed (or corrupted) by whichever host's frame ran first.
      keyA.currentState!.increment();
      flushA.fire();
      await hostA.awaitSemanticIdle();
      expect(semanticRootA.textContent, contains('count 1'));

      // Host B re-renders after A's update: its retained semantic output must
      // be untouched (no spurious updates from A's dirty state).
      hostB.requestFrame('noop');
      flushB.fire();
      await hostB.awaitSemanticIdle();
      final retained = instrumentationB.frames.last;
      expect(retained.semanticAddedNodeCount, 0);
      expect(retained.semanticRemovedNodeCount, 0);
      expect(retained.semanticUpdatedNodeCount, 0);
      expect(semanticRootB.textContent, contains('steady'));

      await hostA.dispose();
      await hostB.dispose();
    },
  );

  test('no-change frame requests skip rendering entirely', () async {
    final visualRoot = web.document.createElement('div');
    final surface = DomGridSurface(
      root: visualRoot,
      size: const CellSize(16, 1),
    );
    final semantics = _FakeSemanticPresenter();
    final instrumentation = RecordingWebHostInstrumentation();
    final flush = _FakeFlush();

    final host = await runTuiSurface(
      () => const Text('stable'),
      surface: surface,
      semanticPresenter: semantics,
      instrumentation: instrumentation,
      flushScheduler: flush.schedule,
    );

    flush.fire();
    await host.awaitSemanticIdle();
    expect(instrumentation.frames.single.renderSkipped, isFalse);

    host.requestFrame('noop');
    flush.fire();
    await host.awaitSemanticIdle();

    final skipped = instrumentation.frames.last;
    expect(skipped.renderSkipped, isTrue);
    expect(skipped.rowsReplaced, 0);
    expect(skipped.domNodesCreated, 0);
    expect(skipped.runtimePhaseTimingAvailable, isFalse);
    expect(skipped.semanticNodeCount, greaterThan(0));
    // No semantic work either: the retained output is still exact.
    expect(instrumentation.semanticFlushes, hasLength(1));
    expect(visualRoot.textContent, contains('stable'));

    await host.dispose();
  });

  test('multiple visual frames coalesce into one semantic flush', () async {
    final visualRoot = web.document.createElement('div');
    final semanticRoot = web.document.createElement('div');
    final surface = DomGridSurface(
      root: visualRoot,
      size: const CellSize(24, 2),
    );
    final semantics = SemanticDomPresenter(root: semanticRoot);
    final instrumentation = RecordingWebHostInstrumentation();
    final flush = _FakeFlush();
    final semanticFlush = _FakeSemanticFlush();
    final key = GlobalKey<_CounterState>();

    final host = await runTuiSurface(
      () => _Counter(key: key),
      surface: surface,
      semanticPresenter: semantics,
      semanticFlushScheduler: semanticFlush,
      flushScheduler: flush.schedule,
      instrumentation: instrumentation,
    );

    // Three visual frames land before the deferred flush gets to run.
    flush.fire();
    key.currentState!.increment();
    flush.fire();
    key.currentState!.increment();
    flush.fire();

    expect(instrumentation.frames, hasLength(3));
    expect(instrumentation.semanticFlushes, isEmpty);
    expect(semanticRoot.textContent, isEmpty);

    semanticFlush.fire();

    // One flush covered all three frames and presented only the latest state.
    expect(instrumentation.semanticFlushes, hasLength(1));
    final coalesced = instrumentation.semanticFlushes.single;
    expect(coalesced.coalescedFrameCount, 3);
    expect(coalesced.retainedOutput, isFalse);
    expect(semanticRoot.textContent, contains('count 2'));
    expect(semanticRoot.textContent, isNot(contains('count 1')));
    expect(semanticFlush.pending, isFalse);

    await host.dispose();
    expect(semanticFlush.disposed, isTrue);
  });

  test(
    'semantic actions force-flush pending semantics before dispatch',
    () async {
      var calls = 0;
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 2),
      );
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();
      final semanticFlush = _FakeSemanticFlush();
      final key = GlobalKey<_CounterState>();

      final host = await runTuiSurface(
        () => Column(
          children: [
            _Counter(key: key),
            Semantics(
              id: const SemanticNodeId('run'),
              role: SemanticRole.button,
              label: 'Run',
              actions: const {SemanticAction.activate},
              onAction: (action) => calls += 1,
              child: const Text('Run'),
            ),
          ],
        ),
        surface: surface,
        semanticPresenter: semantics,
        semanticFlushScheduler: semanticFlush,
        flushScheduler: flush.schedule,
        instrumentation: instrumentation,
      );

      flush.fire();
      semanticFlush.fire();
      final button = semanticRoot.querySelector(
        '[data-fleury-semantic-id="run"]',
      )!;

      // Leave a semantic flush pending (stale tree) when the action arrives:
      // the action frame must force-flush before dispatching.
      key.currentState!.increment();
      flush.fire();
      expect(semanticFlush.pending, isTrue);

      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );
      flush.fire();
      await Future<void>.delayed(Duration.zero);

      expect(
        instrumentation.semanticFlushes.map((f) => f.reason),
        contains('semantic-action'),
      );
      expect(semanticRoot.textContent, contains('count 1'));
      expect(calls, 1);

      await host.dispose();
    },
  );

  test(
    'semantic DOM activation is queued and dispatched during a frame',
    () async {
      var calls = 0;
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 1),
      );
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final input = _FakeInputSource();
      final focusCoordinator = WebFocusCoordinator();
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => Semantics(
          id: const SemanticNodeId('run'),
          role: SemanticRole.button,
          label: 'Run',
          actions: const {SemanticAction.activate},
          onAction: (action) {
            expect(action, SemanticAction.activate);
            calls += 1;
          },
          child: const Text('Run'),
        ),
        surface: surface,
        inputSource: input,
        semanticPresenter: semantics,
        flushScheduler: flush.schedule,
        focusCoordinator: focusCoordinator,
        instrumentation: instrumentation,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      final button = semanticRoot.querySelector(
        '[data-fleury-semantic-id="run"]',
      )!;
      expect(button.getAttribute('data-fleury-primary-action'), 'activate');

      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );

      expect(calls, 0);
      expect(input.keyboardCaptureCount, 0);
      expect(focusCoordinator.activeSemanticNode, isNull);
      expect(flush.pending, isTrue);

      flush.fire();
      await host.awaitSemanticIdle();

      expect(focusCoordinator.activeSemanticNode, const SemanticNodeId('run'));

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      expect(input.keyboardCaptureCount, 1);
      expect(
        focusCoordinator.browserFocusTarget,
        WebFocusTarget.keyboardCapture,
      );
      expect(flush.pending, isTrue);
      flush.fire();
      await host.awaitSemanticIdle();

      expect(
        instrumentation.frames.last.reason,
        'semantic-action:activate:completed',
      );

      await host.dispose();
    },
  );

  test(
    'semantic action request sink records unsupported and notFound statuses',
    () async {
      final visualRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 1),
      );
      final semantics = _FakeSemanticPresenter();
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => const Semantics(
          id: SemanticNodeId('run'),
          role: SemanticRole.button,
          label: 'Run',
          actions: {SemanticAction.activate},
          child: Text('Run'),
        ),
        surface: surface,
        semanticPresenter: semantics,
        flushScheduler: flush.schedule,
        instrumentation: instrumentation,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      semantics.requestAction(
        const SemanticNodeId('run'),
        SemanticAction.focus,
      );
      flush.fire();
      await host.awaitSemanticIdle();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(flush.pending, isTrue);
      flush.fire();
      await host.awaitSemanticIdle();
      expect(
        instrumentation.frames.last.reason,
        'semantic-action:focus:unsupported',
      );

      semantics.requestAction(
        const SemanticNodeId('missing'),
        SemanticAction.activate,
      );
      flush.fire();
      await host.awaitSemanticIdle();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(flush.pending, isTrue);
      flush.fire();
      await host.awaitSemanticIdle();
      expect(
        instrumentation.frames.last.reason,
        'semantic-action:activate:notFound',
      );

      await host.dispose();
    },
  );

  test(
    'semantic action request before first semantic tree records notFound',
    () async {
      final visualRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 1),
      );
      final semantics = _FakeSemanticPresenter();
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => const Semantics(
          id: SemanticNodeId('run'),
          role: SemanticRole.button,
          label: 'Run',
          actions: {SemanticAction.activate},
          child: Text('Run'),
        ),
        surface: surface,
        semanticPresenter: semantics,
        flushScheduler: flush.schedule,
        instrumentation: instrumentation,
      );

      semantics.requestAction(
        const SemanticNodeId('run'),
        SemanticAction.activate,
      );

      flush.fire();
      await host.awaitSemanticIdle();
      expect(flush.pending, isTrue);
      flush.fire();
      await host.awaitSemanticIdle();
      expect(
        instrumentation.frames.last.reason,
        'semantic-action:activate:notFound',
      );

      await host.dispose();
    },
  );

  test(
    'web semantic activation survives a coverage-fallback frame: dispatch '
    'resolves against the live element tree, not a null-map currentTree',
    () async {
      var calls = 0;
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 2),
      );
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final input = _FakeInputSource();
      final focusCoordinator = WebFocusCoordinator();
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => Column(
          children: [
            Semantics(
              id: const SemanticNodeId('run'),
              role: SemanticRole.button,
              label: 'Run',
              actions: const {SemanticAction.activate},
              onAction: (action) {
                expect(action, SemanticAction.activate);
                calls += 1;
              },
              child: const Text('Run'),
            ),
            // Uncovered painted text forces applySemanticTextFallback, which
            // rebuilds currentTree via the const SemanticTree(root:) ctor — a
            // tree with NO element map. Action dispatch must resolve against the
            // live element tree (fromElement), not that map-less currentTree, or
            // a real, actionable button silently no-ops after any fallback frame.
            const _RawPaintedText('raw'),
          ],
        ),
        surface: surface,
        inputSource: input,
        semanticPresenter: semantics,
        flushScheduler: flush.schedule,
        focusCoordinator: focusCoordinator,
        instrumentation: instrumentation,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      // Precondition: the fallback actually engaged, so currentTree is now the
      // map-less tree — the exact state that regressed dispatch.
      expect(
        instrumentation.semanticFlushes.last.semanticFallbackNodeCount,
        greaterThan(0),
        reason: 'raw painted text must be uncovered to reproduce the regression',
      );

      final button = semanticRoot.querySelector(
        '[data-fleury-semantic-id="run"]',
      )!;
      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );
      expect(calls, 0);

      flush.fire();
      await host.awaitSemanticIdle();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        1,
        reason: 'the action must fire despite the null-map currentTree',
      );

      flush.fire();
      await host.awaitSemanticIdle();
      expect(
        instrumentation.frames.last.reason,
        'semantic-action:activate:completed',
      );

      await host.dispose();
    },
  );

  test('semantic DOM activation records failed action status', () async {
    var calls = 0;
    final visualRoot = web.document.createElement('div');
    final semanticRoot = web.document.createElement('div');
    final surface = DomGridSurface(
      root: visualRoot,
      size: const CellSize(16, 1),
    );
    final semantics = SemanticDomPresenter(root: semanticRoot);
    final instrumentation = RecordingWebHostInstrumentation();
    final flush = _FakeFlush();

    final host = await runTuiSurface(
      () => Semantics(
        id: const SemanticNodeId('run'),
        role: SemanticRole.button,
        label: 'Run',
        actions: const {SemanticAction.activate},
        onAction: (action) {
          expect(action, SemanticAction.activate);
          calls += 1;
          throw StateError('semantic action failed');
        },
        child: const Text('Run'),
      ),
      surface: surface,
      semanticPresenter: semantics,
      flushScheduler: flush.schedule,
      instrumentation: instrumentation,
    );

    flush.fire();
    await host.awaitSemanticIdle();

    final button = semanticRoot.querySelector(
      '[data-fleury-semantic-id="run"]',
    )!;
    button.dispatchEvent(
      web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
    );

    flush.fire();
    await host.awaitSemanticIdle();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 1);
    expect(flush.pending, isTrue);
    flush.fire();
    await host.awaitSemanticIdle();
    expect(
      instrumentation.frames.last.reason,
      'semantic-action:activate:failed',
    );

    await host.dispose();
  });

  test(
    'semantic DOM activation still records status after capture failure',
    () async {
      var calls = 0;
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 1),
      );
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final input = _ThrowingKeyboardCaptureInputSource(
        StateError('focus failed'),
      );
      final focusCoordinator = WebFocusCoordinator();
      final instrumentation = RecordingWebHostInstrumentation();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => Semantics(
          id: const SemanticNodeId('run'),
          role: SemanticRole.button,
          label: 'Run',
          actions: const {SemanticAction.activate},
          onAction: (action) {
            expect(action, SemanticAction.activate);
            calls += 1;
          },
          child: const Text('Run'),
        ),
        surface: surface,
        inputSource: input,
        semanticPresenter: semantics,
        flushScheduler: flush.schedule,
        focusCoordinator: focusCoordinator,
        instrumentation: instrumentation,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      final button = semanticRoot.querySelector(
        '[data-fleury-semantic-id="run"]',
      )!;
      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );

      flush.fire();
      await host.awaitSemanticIdle();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      expect(focusCoordinator.browserFocusTarget, WebFocusTarget.semanticNode);
      expect(flush.pending, isTrue);
      flush.fire();
      await host.awaitSemanticIdle();
      expect(
        instrumentation.frames.last.reason,
        'semantic-action:activate:completed',
      );

      await host.dispose();
    },
  );

  test(
    'semantic DOM activation does not fake keyboard focus without capture target',
    () async {
      var calls = 0;
      final visualRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      final surface = DomGridSurface(
        root: visualRoot,
        size: const CellSize(16, 1),
      );
      final semantics = SemanticDomPresenter(root: semanticRoot);
      final focusCoordinator = WebFocusCoordinator();
      final flush = _FakeFlush();

      final host = await runTuiSurface(
        () => Semantics(
          id: const SemanticNodeId('run'),
          role: SemanticRole.button,
          label: 'Run',
          actions: const {SemanticAction.activate},
          onAction: (action) {
            expect(action, SemanticAction.activate);
            calls += 1;
          },
          child: const Text('Run'),
        ),
        surface: surface,
        semanticPresenter: semantics,
        flushScheduler: flush.schedule,
        focusCoordinator: focusCoordinator,
      );

      flush.fire();
      await host.awaitSemanticIdle();

      final button = semanticRoot.querySelector(
        '[data-fleury-semantic-id="run"]',
      )!;
      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );

      flush.fire();
      await host.awaitSemanticIdle();
      expect(focusCoordinator.activeSemanticNode, const SemanticNodeId('run'));
      expect(focusCoordinator.browserFocusTarget, WebFocusTarget.semanticNode);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      expect(focusCoordinator.browserFocusTarget, WebFocusTarget.semanticNode);

      await host.dispose();
    },
  );

  test('clipboard backend is installed for the host lifetime', () async {
    final previousClipboard = _FakeClipboard();
    Clipboard.instance = previousClipboard;
    addTearDown(() => Clipboard.instance = previousClipboard);
    final clipboard = _FakeClipboard();
    final root = web.document.createElement('div');
    final surface = DomGridSurface(root: root, size: const CellSize(10, 1));
    final flush = _FakeFlush();

    final host = await runTuiSurface(
      () => const Text('clipboard'),
      surface: surface,
      clipboard: clipboard,
      flushScheduler: flush.schedule,
    );

    expect(Clipboard.instance, same(clipboard));

    await host.dispose();

    expect(Clipboard.instance, same(previousClipboard));
  });

  test(
    'setup failures restore clipboard and dispose partial host state',
    () async {
      final previousClipboard = _FakeClipboard();
      Clipboard.instance = previousClipboard;
      addTearDown(() => Clipboard.instance = previousClipboard);
      final clipboard = _FakeClipboard();
      final error = StateError('resize failed');
      final surface = _ThrowingResizeSurface(error);
      final metrics = _FakeMetrics(_box(cols: 8, rows: 2));
      final input = _FakeInputSource();
      final semantics = _FakeSemanticPresenter();

      await expectLater(
        runTuiSurface(
          () => const Text('unused'),
          surface: surface,
          cellMetrics: metrics,
          inputSource: input,
          semanticPresenter: semantics,
          clipboard: clipboard,
        ),
        throwsA(same(error)),
      );

      expect(Clipboard.instance, same(previousClipboard));
      expect(surface.disposed, isTrue);
      expect(metrics.disposed, isTrue);
      expect(input.disposed, isTrue);
      expect(semantics.disposed, isTrue);
    },
  );

  test(
    'dispose restores clipboard and generated host resources after cleanup error',
    () async {
      final previousClipboard = _FakeClipboard();
      Clipboard.instance = previousClipboard;
      addTearDown(() => Clipboard.instance = previousClipboard);
      final clipboard = _FakeClipboard();
      final error = StateError('surface dispose failed');
      final surface = _ThrowingDisposeSurface(
        error,
        size: const CellSize(10, 1),
      );
      final flush = _FakeFlush();
      var generatedHostResourcesDisposed = false;

      final host = await runTuiSurface(
        () => const Text('cleanup'),
        surface: surface,
        clipboard: clipboard,
        flushScheduler: flush.schedule,
        disposeHostResources: () {
          generatedHostResourcesDisposed = true;
        },
      );

      expect(Clipboard.instance, same(clipboard));

      await expectLater(host.dispose(), throwsA(same(error)));

      expect(surface.disposed, isTrue);
      expect(generatedHostResourcesDisposed, isTrue);
      expect(Clipboard.instance, same(previousClipboard));
    },
  );

  test(
    'frame presentation failures dispose host resources and stop frames',
    () async {
      final previousClipboard = _FakeClipboard();
      Clipboard.instance = previousClipboard;
      addTearDown(() => Clipboard.instance = previousClipboard);
      final clipboard = _FakeClipboard();
      final error = StateError('present failed');
      final surface = _ThrowingPresentSurface(
        error,
        size: const CellSize(10, 1),
      );
      final input = _FakeInputSource();
      final semantics = _FakeSemanticPresenter();
      final flush = _FakeFlush();
      var generatedHostResourcesDisposed = false;

      final host = await runTuiSurface(
        () => const Text('frame failure'),
        surface: surface,
        inputSource: input,
        semanticPresenter: semantics,
        clipboard: clipboard,
        flushScheduler: flush.schedule,
        disposeHostResources: () {
          generatedHostResourcesDisposed = true;
        },
      );

      expect(Clipboard.instance, same(clipboard));
      expect(flush.pending, isTrue);

      expect(() => flush.fire(), throwsA(same(error)));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(surface.disposed, isTrue);
      expect(input.disposed, isTrue);
      expect(semantics.disposed, isTrue);
      expect(generatedHostResourcesDisposed, isTrue);
      expect(Clipboard.instance, same(previousClipboard));

      host.requestFrame('after-frame-error');
      expect(flush.pending, isFalse);
      await host.dispose();
    },
  );

  test('dispose waits for in-flight frame-failure cleanup', () async {
    final previousClipboard = _FakeClipboard();
    Clipboard.instance = previousClipboard;
    addTearDown(() => Clipboard.instance = previousClipboard);
    final clipboard = _FakeClipboard();
    final error = StateError('present failed');
    final surface = _ThrowingPresentSurface(error, size: const CellSize(10, 1));
    final flush = _FakeFlush();
    final cleanupStarted = Completer<void>();
    final cleanupCanFinish = Completer<void>();
    var generatedHostResourcesDisposed = false;

    final host = await runTuiSurface(
      () => const Text('frame failure'),
      surface: surface,
      clipboard: clipboard,
      flushScheduler: flush.schedule,
      disposeHostResources: () async {
        cleanupStarted.complete();
        await cleanupCanFinish.future;
        generatedHostResourcesDisposed = true;
      },
    );

    expect(Clipboard.instance, same(clipboard));
    expect(() => flush.fire(), throwsA(same(error)));

    await cleanupStarted.future;
    var disposeCompleted = false;
    final disposeFuture = host.dispose().then((_) {
      disposeCompleted = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(disposeCompleted, isFalse);
    expect(generatedHostResourcesDisposed, isFalse);
    expect(Clipboard.instance, same(clipboard));

    cleanupCanFinish.complete();
    await disposeFuture;

    expect(disposeCompleted, isTrue);
    expect(generatedHostResourcesDisposed, isTrue);
    expect(surface.disposed, isTrue);
    expect(Clipboard.instance, same(previousClipboard));
  });
}
