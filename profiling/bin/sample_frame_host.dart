// Shared sample-app host for CPU and retained-heap probes.
// Keeps the real buffer lifecycle and adaptive-layout settling identical.
import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' show FleuryTester;

final class FrameSample {
  const FrameSample(this.total, this.build, this.layout, this.paint,
      this.prepare, this.finish, this.changed);
  final int total, build, layout, paint, prepare, finish;
  final bool changed;
}

final class SampleFrameHost {
  SampleFrameHost(Widget app, CellSize size,
      {bool settle = true,
      TextPresentationPolicy textPolicy = TextPresentationPolicy.spec})
      : tester = FleuryTester(viewportSize: size, textPolicy: textPolicy) {
    tester.pumpWidget(app);
    PointerRouter? router;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is PointerRouterScope) router ??= widget.router;
      if (element is RenderObjectElement) {
        final render = element.renderObject;
        renderObjects.add(render);
      }
      element.visitChildren(visit);
    }

    visit(tester.root!);
    _router = router!;
    _loop = TuiFrameLoop(renderDamage: tester.owner.renderDamageTracker);
    if (!settle) return;
    // Adaptive builders can mount descendants after the first layout. Settle
    // those frames before selecting a leaf or collecting the full tree.
    for (var i = 0; i < 30; i++) {
      frame('clean', i);
    }
    renderObjects.clear();
    visit(tester.root!);
    // Choose text mutations that actually change visible cells. A mounted
    // label may be clipped or off screen, especially at smaller viewports.
    // [hasLeaf] is the first visible RenderText (may sit outside any
    // boundary). [hasInside] is the first visible RenderText under a
    // caching RepaintBoundary — the localized update that misses a cache.
    RenderText? firstVisible;
    var firstOriginal = '';
    for (final render in renderObjects.whereType<RenderText>()) {
      if (render.text.isEmpty) continue;
      final original = render.text;
      _text = render;
      _originalText = original;
      frame('leaf', 0);
      final visible = frame('leaf', 1).changed;
      render.text = original;
      frame('clean', 0);
      if (!visible) continue;
      firstVisible ??= render;
      if (firstVisible == render) firstOriginal = original;
      if (_inside == null) {
        final boundary = _enclosingCachingBoundary(render);
        if (boundary != null) {
          _inside = render;
          _insideOriginal = original;
          _insideBoundary = boundary;
        }
      }
      if (_inside != null) break;
    }
    _text = firstVisible;
    _originalText = firstOriginal;
  }

  static RenderRepaintBoundary? _enclosingCachingBoundary(RenderObject node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (parent is RenderRepaintBoundary && parent.cachingEnabled) {
        return parent;
      }
    }
    return null;
  }

  CellSize get size => tester.viewportSize;
  set size(CellSize value) => tester.viewportSize = value;
  final FleuryTester tester;
  final renderObjects = <RenderObject>[];
  late final PointerRouter _router;
  late final TuiFrameLoop _loop;
  RenderText? _text;
  late String _originalText;
  RenderText? _inside;
  String _insideOriginal = '';
  RenderRepaintBoundary? _insideBoundary;

  bool get hasLeaf => _text != null;
  bool get hasInside => _inside != null;
  int? get leafRenderObjectIndex =>
      _text == null ? null : renderObjects.indexOf(_text!);
  int? get insideRenderObjectIndex =>
      _inside == null ? null : renderObjects.indexOf(_inside!);
  CellSize? get insideBoundarySize => _insideBoundary?.size;

  FrameSample frame(String mode, int iteration,
      {void Function(TuiRenderedFrame frame)? onFramePresented}) {
    final watch = Stopwatch()..start();
    if (mode == 'leaf') {
      _text?.text = '${iteration & 1} $_originalText';
    } else if (mode == 'inside') {
      _inside?.text = '${iteration & 1} $_insideOriginal';
    } else if (mode == 'full') {
      for (final render in renderObjects) {
        render.markNeedsPaint();
      }
    }
    var build = Duration.zero;
    var layout = Duration.zero;
    var paint = Duration.zero;
    var paintFinished = 0;
    final frame = _loop.render(
        size: size,
        paint: (buffer) {
          _router.beginFrame();
          // Match TuiRuntime's input transaction in this unpublished host.
          // ignore: invalid_use_of_internal_member
          tester.focusManager.beginFrame();
          try {
            tester.owner.renderFrame(tester.root!, buffer,
                onPhaseTiming: (b, l, p) {
              build = b;
              layout = l;
              paint = p;
            });
            _router.endFrame();
            // ignore: invalid_use_of_internal_member
            tester.focusManager.endFrame();
          } catch (_) {
            _router.abortFrame();
            // ignore: invalid_use_of_internal_member
            tester.focusManager.abortFrame();
            rethrow;
          }
          paintFinished = watch.elapsedMicroseconds;
        })!;
    // Exact diff, scroll eligibility and frame construction after paint.
    final finish = watch.elapsedMicroseconds - paintFinished;
    onFramePresented?.call(frame);
    _loop.commit(frame);
    tester.binding.flushPostFrameCallbacks(tester.clock.now);
    watch.stop();
    return FrameSample(
        watch.elapsedMicroseconds,
        build.inMicroseconds,
        layout.inMicroseconds,
        paint.inMicroseconds,
        frame.bufferPrepareTime.inMicroseconds,
        finish,
        frame.damage is! FrameUnchanged);
  }
}
