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
  SampleFrameHost(Widget app, this.size)
      : tester = FleuryTester(viewportSize: size) {
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
    // Adaptive builders can mount descendants after the first layout. Settle
    // those frames before selecting a leaf or collecting the full tree.
    for (var i = 0; i < 30; i++) {
      frame('clean', i);
    }
    renderObjects.clear();
    visit(tester.root!);
    // Choose a text mutation that actually changes visible cells. A mounted
    // label may be clipped or off screen, especially at smaller viewports.
    for (final render in renderObjects.whereType<RenderText>()) {
      if (render.text.isEmpty) continue;
      _text = render;
      _originalText = render.text;
      frame('leaf', 0);
      final visible = frame('leaf', 1).changed;
      render.text = _originalText;
      frame('clean', 0);
      if (visible) return;
    }
    // Some apps draw their visible text in custom render objects. Do not
    // report a localized text measurement when no such mutation is visible.
    _text = null;
  }

  final CellSize size;
  final FleuryTester tester;
  final renderObjects = <RenderObject>[];
  late final PointerRouter _router;
  late final TuiFrameLoop _loop;
  RenderText? _text;
  late String _originalText;

  bool get hasLeaf => _text != null;
  int? get leafRenderObjectIndex =>
      _text == null ? null : renderObjects.indexOf(_text!);

  FrameSample frame(String mode, int iteration) {
    final watch = Stopwatch()..start();
    if (mode == 'leaf') {
      _text?.text = '${iteration & 1} $_originalText';
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
          tester.owner.renderFrame(tester.root!, buffer,
              onPhaseTiming: (b, l, p) {
            build = b;
            layout = l;
            paint = p;
          });
          paintFinished = watch.elapsedMicroseconds;
        })!;
    // Exact diff, scroll eligibility and frame construction after paint.
    final finish = watch.elapsedMicroseconds - paintFinished;
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
