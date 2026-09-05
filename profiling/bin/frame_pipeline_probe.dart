// Informational AOT probe for the shared buffer lifecycle on sample apps.
// Measures mutation -> clear -> build/layout/paint -> exact diff -> commit,
// with debug counters disabled. No ANSI encoding, transport or terminal paint.
// A clean frame is FORCED here; production idle skips rendering altogether.
//
// dart compile exe bin/frame_pipeline_probe.dart -o /tmp/frame-pipeline
// /tmp/frame-pipeline --cols 120 --rows 40 --frames 300
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' show FleuryTester;
import 'package:fleury_samples/samples.dart';

void main(List<String> args) {
  var cols = 120;
  var rows = 40;
  var frames = 300;
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 == args.length) throw ArgumentError('Missing value: ${args[i]}');
    final value = int.parse(args[i + 1]);
    if (value <= 0) throw ArgumentError('Values must be positive');
    switch (args[i]) {
      case '--cols':
        cols = value;
      case '--rows':
        rows = value;
      case '--frames':
        frames = value;
      default:
        throw ArgumentError('Unknown flag: ${args[i]}');
    }
  }
  final size = CellSize(cols, rows);
  stdout.writeln(jsonEncode({
    'kind': 'environment',
    'dart': Platform.version,
    'os': Platform.operatingSystem,
    'cpus': Platform.numberOfProcessors,
    'columns': cols,
    'rows': rows,
    'framesPerMode': frames,
    'warmupFrames': 30,
    'initializationFrames': 30,
  }));
  for (final (name, app) in <(String, Widget)>[
    ('dashboard', const DashboardApp()),
    ('agent', const AgentApp()),
    ('files', const FileManagerApp()),
    ('editor', const EditorApp()),
    ('finance', const FinanceApp()),
  ]) {
    final host = _Host(app, size);
    try {
      for (var i = 0; i < 30; i++) {
        host.frame(host._text == null ? 'full' : 'leaf', i);
      }
      final samples = {
        for (final mode in ['clean', if (host._text != null) 'leaf', 'full'])
          mode: <_Sample>[],
      };
      for (var i = 0; i < frames; i++) {
        for (final mode in samples.keys) {
          samples[mode]!.add(host.frame(mode, i));
        }
      }
      for (final MapEntry(key: mode, value: values) in samples.entries) {
        Map<String, int> distribution(int Function(_Sample) read) {
          final sorted = values.map(read).toList()..sort();
          return {
            'median': sorted[sorted.length ~/ 2],
            'p95': sorted[(sorted.length * .95).ceil() - 1]
          };
        }

        stdout.writeln(jsonEncode({
          'app': name,
          'mode': mode,
          'renderObjects': host.renderObjects.length,
          'leafRenderObjectIndex': host._text == null
              ? null
              : host.renderObjects.indexOf(host._text!),
          'changedFrames': values.where((s) => s.changed).length,
          'totalUs': distribution((s) => s.total),
          'buildUs': distribution((s) => s.build),
          'layoutUs': distribution((s) => s.layout),
          'paintUs': distribution((s) => s.paint),
          'bufferPrepareUs': distribution((s) => s.prepare),
          'finishUs': distribution((s) => s.finish),
        }));
      }
    } finally {
      host.tester.dispose();
    }
  }
}

final class _Sample {
  const _Sample(this.total, this.build, this.layout, this.paint, this.prepare,
      this.finish, this.changed);
  final int total, build, layout, paint, prepare, finish;
  final bool changed;
}

final class _Host {
  _Host(Widget app, this.size) : tester = FleuryTester(viewportSize: size) {
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

  _Sample frame(String mode, int iteration) {
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
    return _Sample(
        watch.elapsedMicroseconds,
        build.inMicroseconds,
        layout.inMicroseconds,
        paint.inMicroseconds,
        frame.bufferPrepareTime.inMicroseconds,
        finish,
        frame.damage is! FrameUnchanged);
  }
}
