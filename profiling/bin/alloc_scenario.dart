// The steady-state scenario the per-frame allocation tools share.
//
// `alloc_gate.dart` measures it and `alloc_trace.dart` attributes it to call
// sites, so both MUST drive the identical tree: a gate failure is only
// actionable if the tracer reproduces the same frame. Keeping one definition
// is what guarantees that — the scenario used to live inside the gate, where a
// tracer could only approximate it.
import 'package:fleury/fleury.dart';

import 'gate_support.dart';

/// A steady-state metric model bumped once per frame.
class AllocModel extends ChangeNotifier {
  int v = 0;
  void bump() {
    v++;
    notifyListeners();
  }
}

/// Dashboard-shaped tree: a static header + a watched block whose three
/// metric lines rebuild + repaint every frame. Exercises build, reconcile,
/// layout (widths shift as values grow), and paint — the churn-producing path.
///
/// The watched block also carries explicit app-authored [Semantics]: one node
/// whose label/value change every frame (the leaf-update path) and a small
/// value-stable subtree (the equal-values update path). Semantics /
/// _SemanticBounds / SemanticNodeId are a known per-frame allocation class;
/// without these the gate only sees the Texts' implicit nodes and an
/// app-semantics regression sits outside the window. The semantic strings are
/// bounded-modulo AND zero-padded, so their width is fixed for ANY
/// --warmup/--frames window (not just the default one, where warmup happens
/// to push `v` to 3 digits) — layout, and therefore allocation, cannot drift
/// as the tick grows.
Widget allocScenario(AllocModel m) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Fleury alloc-gate dashboard'),
      const Text('────────────────────────────'),
      ListenableBuilder(
        listenable: m,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('requests : ${m.v}'),
            Text('errors   : ${m.v % 97}'),
            Text('rate/s   : ${(m.v * 7) % 1000}'),
            Semantics(
              role: SemanticRole.region,
              label: 'metrics ${(m.v % 1000).toString().padLeft(3, '0')}',
              value: 'r${(m.v % 97).toString().padLeft(2, '0')}',
              child: Text(
                'sem live : ${(m.v % 1000).toString().padLeft(3, '0')}',
              ),
            ),
            Semantics(
              role: SemanticRole.region,
              label: 'alloc gate static region',
              child: Semantics(
                role: SemanticRole.text,
                label: 'static leaf',
                child: const Text('sem static: ok'),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Drives the real per-frame path against reused front/back buffers, exactly
/// as the runtime does: build -> reconcile -> layout -> paint -> AnsiRenderer
/// diff. Returns a closure that renders one frame.
void Function() allocFrameDriver({
  CellSize size = const CellSize(80, 24),
  required BuildOwner owner,
  required AllocModel model,
  required Element root,
}) {
  const renderer = AnsiRenderer();
  const sink = NullAnsiSink();
  final loop = TuiFrameLoop(renderDamage: owner.renderDamageTracker);
  return () {
    model.bump();
    // Drive the REAL loop rather than re-implementing it. This gate used to
    // hand-mirror TuiFrameLoop, and every change to the loop silently moved
    // the gate off the production path — it was still arming damage tracking
    // and rendering unbounded long after the loop stopped doing either.
    final rendered = loop.render(
      size: size,
      paint: (buffer) => owner.renderFrame(root, buffer),
    )!;
    // Mirrors AnsiFramePresenter's switch, so the tools keep measuring the
    // path production actually takes.
    final damage = rendered.damage;
    renderer.renderDiff(
      rendered.previous,
      rendered.next,
      sink,
      dirtyBounds: damage.diffBounds,
      scrollUpRows: switch (damage) {
        FrameScrolled(:final scrollUpRows) => scrollUpRows,
        FrameFullRepaint() || FrameUnchanged() || FrameChanged() => null,
      },
      hasChanges: damage is! FrameUnchanged,
    );
    loop.commit(rendered);
  };
}
