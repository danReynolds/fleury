// Retained-tree tax probe (informational, not a gate).
//
// Fleury keeps the whole render tree resident and, on every frame, walks it to
// find dirty layout/paint work, then replays cached repaint boundaries into the
// frame buffer. The question this answers: on the SHIPPED sample apps, what
// does that tax cost when nothing changed (idle), when one leaf changed
// (localized), and how does it compare with painting everything (full)?
//
//   dart run bin/retained_tax_probe.dart [--cols 120] [--rows 40] [--frames 40]
import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart'
    show FleuryTester, RenderLayoutDebugStats, RepaintBoundaryDebugStats;
import 'package:fleury_samples/samples.dart';

void main(List<String> args) {
  var cols = 120;
  var rows = 40;
  var frames = 40;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--cols':
        cols = int.parse(args[++i]);
      case '--rows':
        rows = int.parse(args[++i]);
      case '--frames':
        frames = int.parse(args[++i]);
    }
  }
  final size = CellSize(cols, rows);
  final apps = <(String, Widget)>[
    ('dashboard', const DashboardApp()),
    ('agent', const AgentApp()),
    ('files', const FileManagerApp()),
    ('editor', const EditorApp()),
    ('finance', const FinanceApp()),
  ];
  print('viewport ${cols}x$rows · median of $frames frames · times in µs');
  for (final (name, app) in apps) {
    final host = _Host(app, size);
    try {
      for (var i = 0; i < 30; i++) {
        host.frame();
      }
      final counts = host.count();
      final idle = <_Sample>[];
      final leaf = <_Sample>[];
      final full = <_Sample>[];
      final relayout = <_Sample>[];
      for (var i = 0; i < frames; i++) {
        idle.add(host.frame());
        host.deepestLeaf().markNeedsPaint();
        leaf.add(host.frame());
        host.visitRenderObjects((r) => r.markNeedsPaint());
        full.add(host.frame());
        host.rootRenderObject.markNeedsLayout();
        relayout.add(host.frame());
      }
      final rows = [
        ('idle', _median(idle)),
        ('leaf', _median(leaf)),
        ('full', _median(full)),
        ('relayout', _median(relayout)),
      ];
      print(
        '$name: ${counts.$1} render objects, ${counts.$2} repaint boundaries',
      );
      final fullPaint = rows[2].$2.paint;
      for (final (label, m) in rows) {
        print(
          '  ${label.padRight(9)} build ${m.build.toString().padLeft(5)} '
          'layout ${m.layout.toString().padLeft(5)} '
          'paint ${m.paint.toString().padLeft(5)} µs | '
          'layout perf/skip ${m.layoutPerformed}/${m.layoutSkipped} · '
          'boundaries repainted/cached ${m.repainted}/${m.cached} · '
          'cells replayed ${m.copiedCells} · '
          'paint vs full ${fullPaint == 0 ? '-' : (m.paint / fullPaint).toStringAsFixed(2)}',
        );
      }
    } finally {
      host.dispose();
    }
  }
  print('');
  print(
    'idle = nothing dirty (the retained-tree tax: walk + cached-boundary '
    'replay); leaf = one deepest leaf repainted; full = every render object '
    'dirty; relayout = root markNeedsLayout.',
  );
}

final class _Sample {
  const _Sample({
    required this.build,
    required this.layout,
    required this.paint,
    required this.layoutPerformed,
    required this.layoutSkipped,
    required this.repainted,
    required this.cached,
    required this.copiedCells,
  });
  final int build;
  final int layout;
  final int paint;
  final int layoutPerformed;
  final int layoutSkipped;
  final int repainted;
  final int cached;
  final int copiedCells;
}

_Sample _median(List<_Sample> samples) {
  int med(int Function(_Sample) f) {
    final v = samples.map(f).toList()..sort();
    return v[v.length ~/ 2];
  }

  return _Sample(
    build: med((s) => s.build),
    layout: med((s) => s.layout),
    paint: med((s) => s.paint),
    layoutPerformed: med((s) => s.layoutPerformed),
    layoutSkipped: med((s) => s.layoutSkipped),
    repainted: med((s) => s.repainted),
    cached: med((s) => s.cached),
    copiedCells: med((s) => s.copiedCells),
  );
}

final class _Host {
  _Host(Widget scene, this.size)
      : _buffer = CellBuffer(size),
        tester = FleuryTester(viewportSize: size) {
    // The tester mounts the same root shape runApp does (overlay, keyboard,
    // focus, pointer and clipboard scopes), so the sample apps see production
    // ambient state and the overlay's own layers are counted in the walk.
    tester.pumpWidget(scene);
    PointerRouter? router;
    void find(Element e) {
      final w = e.widget;
      if (w is PointerRouterScope) router = w.router;
      if (router == null) e.visitChildren(find);
    }

    find(root);
    _pointerRouter = router!;
  }

  late final PointerRouter _pointerRouter;

  final CellSize size;
  final FleuryTester tester;
  final CellBuffer _buffer;

  BuildOwner get owner => tester.owner;
  Element get root => tester.root!;

  RenderObject get rootRenderObject => owner.findRootRenderObject(root)!;

  void visitRenderObjects(void Function(RenderObject) visitor) {
    void visit(Element e) {
      if (e is RenderObjectElement) visitor(e.renderObject);
      e.visitChildren(visit);
    }

    visit(root);
  }

  /// A render object with no render-object descendants, as deep as possible.
  RenderObject deepestLeaf() {
    RenderObject? best;
    var bestDepth = -1;
    void visit(Element e, int depth) {
      var hasRenderChild = false;
      e.visitChildren((c) {
        hasRenderChild |= c is RenderObjectElement;
        visit(c, depth + 1);
      });
      if (e is RenderObjectElement && !hasRenderChild && depth > bestDepth) {
        best = e.renderObject;
        bestDepth = depth;
      }
    }

    visit(root, 0);
    return best ?? rootRenderObject;
  }

  (int objects, int boundaries) count() {
    var objects = 0;
    var boundaries = 0;
    visitRenderObjects((r) {
      objects++;
      if (r.isRepaintBoundary) boundaries++;
    });
    return (objects, boundaries);
  }

  _Sample frame() {
    RepaintBoundaryDebugStats.beginFrame(enabled: true);
    RenderLayoutDebugStats.beginFrame(enabled: true);
    _pointerRouter.beginFrame();
    _buffer.withoutDamageTracking(_buffer.clear);
    var build = Duration.zero;
    var layout = Duration.zero;
    var paint = Duration.zero;
    owner.renderFrame(
      root,
      _buffer,
      onPhaseTiming: (b, l, p) {
        build = b;
        layout = l;
        paint = p;
      },
    );
    final paintStats = RepaintBoundaryDebugStats.takeFrameStats();
    final layoutStats = RenderLayoutDebugStats.takeFrameStats();
    tester.binding.flushPostFrameCallbacks(tester.clock.now);
    return _Sample(
      build: build.inMicroseconds,
      layout: layout.inMicroseconds,
      paint: paint.inMicroseconds,
      layoutPerformed: layoutStats.performedCount,
      layoutSkipped: layoutStats.skippedCount,
      repainted: paintStats.repaintedCount,
      cached: paintStats.cachedCount,
      copiedCells: paintStats.copiedCellCount,
    );
  }

  void dispose() {
    RepaintBoundaryDebugStats.beginFrame(enabled: false);
    RenderLayoutDebugStats.beginFrame(enabled: false);
    tester.dispose();
  }
}
