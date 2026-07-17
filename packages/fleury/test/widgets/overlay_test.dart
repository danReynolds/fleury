// Overlay + OverlayEntry tests. Exercise the lifecycle (insert,
// remove, mark needs build), stacking order, opaque-entry hiding,
// and the per-entry repaint boundaries (adaptive engagement, replay,
// containment).

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:fleury/src/rendering/render_repaint_boundary.dart';
import 'package:test/test.dart';

import '../support/render_fixtures.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

class _Probe extends StatefulWidget {
  const _Probe({required this.label, required this.log});
  final String label;
  final List<String> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('mount:${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('unmount:${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

/// Locates the first [OverlayState] in the subtree rooted at [root].
/// Used by tests that need to drive [OverlayState.insert] without
/// resorting to a GlobalKey.
OverlayState _findOverlayState(Element root) {
  OverlayState? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is OverlayState) {
      found = e.state as OverlayState;
      return;
    }
    e.visitChildren(visit);
  }

  visit(root);
  if (found == null) {
    throw StateError('No OverlayState below this element.');
  }
  return found!;
}

/// Counts [RenderRepaintBoundary] render objects in the tester's tree.
/// Distinguishes "boundary absent" (addRepaintBoundaries: false) from
/// "boundary present but disengaged" (single visible entry), which paint
/// stats alone cannot.
int _boundaryRenderObjectCount(FleuryTester tester) {
  var count = 0;
  void visit(Element e) {
    if (e is RenderObjectElement && e.renderObject is RenderRepaintBoundary) {
      count++;
    }
    e.visitChildren(visit);
  }

  visit(tester.root!);
  return count;
}

class _BumpCounter extends StatefulWidget {
  const _BumpCounter({super.key, required this.label});
  final String label;

  @override
  State<_BumpCounter> createState() => _BumpCounterState();
}

class _BumpCounterState extends State<_BumpCounter> {
  int count = 0;
  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('${widget.label}=$count');
}

/// A floating-entry body offset down [rows] so it never overlaps the base
/// entry's cells.
Widget _floatAt(int rows, Widget child) => Padding(
  padding: EdgeInsets.only(top: rows),
  child: child,
);

void main() {
  group('Overlay', () {
    test('initialEntries mount in order at construction', () {
      final log = <String>[];
      final owner = BuildOwner();
      owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
            OverlayEntry(
              builder: (_) => _Probe(label: 'B', log: log),
            ),
          ],
        ),
      );
      expect(log, ['mount:A', 'mount:B']);
    });

    test('insert appends to the top of the stack', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      final newEntry = OverlayEntry(
        builder: (_) => _Probe(label: 'B', log: log),
      );
      state.insert(newEntry);
      owner.flushBuild();
      expect(log, ['mount:A', 'mount:B']);
      expect(state.entries.length, 2);
      expect(state.entries.last, same(newEntry));
    });

    test('insert below: places the new entry under the anchor', () {
      final owner = BuildOwner();
      final anchorEntry = OverlayEntry(builder: (_) => const Text('anchor'));
      final root = owner.mountRoot(Overlay(initialEntries: [anchorEntry]));
      final state = _findOverlayState(root);
      final lowerEntry = OverlayEntry(builder: (_) => const Text('lower'));
      state.insert(lowerEntry, below: anchorEntry);
      owner.flushBuild();
      expect(state.entries, [lowerEntry, anchorEntry]);
    });

    test('remove unmounts the entry and shrinks the stack', () {
      final log = <String>[];
      final owner = BuildOwner();
      late final OverlayEntry b;
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
            b = OverlayEntry(
              builder: (_) => _Probe(label: 'B', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      expect(log, ['mount:A', 'mount:B']);

      b.remove();
      owner.flushBuild();
      expect(log, ['mount:A', 'mount:B', 'unmount:B']);
      expect(state.entries.length, 1);
    });

    test('opaque entry hides lower entries; lower entries with '
        'maintainState=false unmount', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              maintainState: false,
              builder: (_) => _Probe(label: 'A', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      state.insert(
        OverlayEntry(
          opaque: true,
          builder: (_) => _Probe(label: 'opaque', log: log),
        ),
      );
      owner.flushBuild();
      // A is below an opaque entry AND opted out of maintainState,
      // so its subtree gets removed from the Stack and unmounts.
      expect(log, ['mount:A', 'mount:opaque', 'unmount:A']);
    });

    test('opaque entry with maintainState=true (default) keeps the '
        'lower entry mounted', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      state.insert(
        OverlayEntry(
          opaque: true,
          builder: (_) => _Probe(label: 'opaque', log: log),
        ),
      );
      owner.flushBuild();
      // A stays mounted (state is preserved across visibility
      // changes); only the opaque entry is added.
      expect(log, ['mount:A', 'mount:opaque']);
    });

    test('markNeedsBuild reaches the entry', () {
      final owner = BuildOwner();
      final entry = OverlayEntry(builder: (_) => const Text('hi'));
      final root = owner.mountRoot(Overlay(initialEntries: [entry]));
      final state = _findOverlayState(root);
      entry.markNeedsBuild();
      // No exception; reachable.
      owner.flushBuild();
      expect(state.entries, [entry]);
    });

    test('disposed entry removes itself and rejects visible mutation', () {
      final owner = BuildOwner();
      final entry = OverlayEntry(builder: (_) => const Text('hi'));
      final root = owner.mountRoot(Overlay(initialEntries: [entry]));
      final state = _findOverlayState(root);

      entry.dispose();
      owner.flushBuild();
      entry.dispose();

      expect(state.entries, isEmpty);
      expect(entry.opaque, isFalse);
      expect(() => entry.remove(), returnsNormally);
      expect(
        () => entry.markNeedsBuild(),
        _stateError('OverlayEntry has been disposed.'),
      );
      expect(
        () => entry.opaque = true,
        _stateError('OverlayEntry has been disposed.'),
      );
    });

    test('disposed entry cannot be inserted', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(Overlay());
      final state = _findOverlayState(root);
      final entry = OverlayEntry(builder: (_) => const Text('disposed'))
        ..dispose();

      expect(
        () => state.insert(entry),
        _stateError('OverlayEntry has been disposed.'),
      );
      expect(state.entries, isEmpty);
    });
  });

  group('auto repaint boundaries', () {
    // beginFrame flips a process-global; make sure it never leaks recording
    // into a later test in the same run.
    tearDown(() => RepaintBoundaryDebugStats.beginFrame(enabled: false));

    testWidgets('each entry is auto-wrapped in a repaint boundary', (tester) {
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            for (var i = 0; i < 3; i++)
              OverlayEntry(builder: (_) => Text('entry $i')),
          ],
        ),
      );
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(12, 3));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.boundaryCount, 3, reason: 'one boundary per entry');
      expect(_boundaryRenderObjectCount(tester), 3);
    });

    testWidgets('addRepaintBoundaries: false wraps nothing', (tester) {
      tester.pumpWidget(
        Overlay(
          addRepaintBoundaries: false,
          initialEntries: [
            for (var i = 0; i < 3; i++)
              OverlayEntry(builder: (_) => Text('entry $i')),
          ],
        ),
      );
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(12, 3));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        stats.boundaryCount,
        0,
        reason: 'the escape hatch inserts no boundaries',
      );
      expect(_boundaryRenderObjectCount(tester), 0);
    });

    testWidgets('a single visible entry stays pass-through', (tester) {
      tester.pumpWidget(
        Overlay(
          initialEntries: [OverlayEntry(builder: (_) => const Text('solo'))],
        ),
      );
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final out = tester.renderToString(size: const CellSize(10, 2));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        stats.boundaryCount,
        0,
        reason:
            'no sibling churn to protect against — an always-dirty single '
            'entry must not pay a per-frame cache-write + blit',
      );
      expect(
        _boundaryRenderObjectCount(tester),
        1,
        reason: 'the boundary stays in the tree, just disengaged',
      );
      expect(out, contains('solo'));
    });

    testWidgets('a second entry engages caching; churn then blits the base', (
      tester,
    ) {
      final overlayKey = GlobalKey<OverlayState>();
      final base = GlobalKey<_BumpCounterState>();
      tester.pumpWidget(
        Overlay(
          key: overlayKey,
          initialEntries: [
            OverlayEntry(
              builder: (_) => _BumpCounter(key: base, label: 'base'),
            ),
          ],
        ),
      );
      const size = CellSize(20, 4);
      tester.render(size: size); // single entry: pass-through frame

      final float = GlobalKey<_BumpCounterState>();
      overlayKey.currentState!.insert(
        OverlayEntry(
          builder: (_) => _floatAt(2, _BumpCounter(key: float, label: 'float')),
        ),
      );
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      var stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.boundaryCount, 2, reason: 'both entries now engaged');
      expect(
        stats.repaintedCount,
        2,
        reason: 'engagement warm-up repaint on the insertion frame',
      );

      float.currentState!.bump();
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final out = tester.renderToString(size: size);
      stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        stats.repaintedCount,
        1,
        reason: 'only the churning entry repaints — the paint-walk win',
      );
      expect(stats.cachedCount, 1, reason: 'the base entry blits from cache');
      expect(out, contains('base=0'), reason: 'blitted cells are correct');
      expect(out, contains('float=1'));

      // Churn the base instead: its boundary repaints, the float blits.
      base.currentState!.bump();
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final out2 = tester.renderToString(size: size);
      stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.repaintedCount, 1);
      expect(stats.cachedCount, 1);
      expect(out2, contains('base=1'));
      expect(out2, contains('float=1'));
    });

    testWidgets('removing the second entry disengages the boundaries', (
      tester,
    ) {
      final base = GlobalKey<_BumpCounterState>();
      late final OverlayEntry floatEntry;
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _BumpCounter(key: base, label: 'base'),
            ),
            floatEntry = OverlayEntry(
              builder: (_) => _floatAt(2, const Text('float')),
            ),
          ],
        ),
      );
      const size = CellSize(20, 4);
      tester.render(size: size); // two visible entries: engaged

      floatEntry.remove();
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      var out = tester.renderToString(size: size);
      var stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        stats.boundaryCount,
        0,
        reason: 'a single entry again: pass-through, no boundary stats',
      );
      expect(out, isNot(contains('float')));

      // The base keeps rendering correctly through the disengaged boundary.
      base.currentState!.bump();
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      out = tester.renderToString(size: size);
      stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.boundaryCount, 0);
      expect(out, contains('base=1'));
    });

    testWidgets('a cached blit copies only content cells, not the damage '
        'halo', (tester) {
      // Grapheme writes record ±1 col of damage (wide-cell eviction guards),
      // and the blit is a raw rect copy stamped ON TOP of the entries
      // beneath. The blit rect must therefore be the tight non-empty
      // bounds: a raw damage rect would blit its empty halo columns over
      // the base entry's adjacent content.
      final base = GlobalKey<_BumpCounterState>();
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _BumpCounter(key: base, label: 'basebase'),
            ),
            OverlayEntry(
              builder: (_) => const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('XY'),
              ),
            ),
          ],
        ),
      );
      const size = CellSize(14, 2);
      tester.render(size: size); // warm both caches

      base.currentState!.bump(); // float cache-hits, blits over fresh base
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final out = tester.renderToString(size: size);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.cachedCount, 1, reason: 'the float entry blit from cache');
      expect(
        out,
        contains('baseXYse=1'),
        reason: 'base cells beside the float content survive its blit',
      );
    });

    testWidgets('an opaque top entry above an occluded stack stays '
        'pass-through', (tester) {
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(builder: (_) => const Text('under')),
            OverlayEntry(opaque: true, builder: (_) => const Text('cover')),
          ],
        ),
      );
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final out = tester.renderToString(size: const CellSize(10, 2));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        stats.boundaryCount,
        0,
        reason:
            'occluded entries are not churn sources — one VISIBLE entry '
            'means pass-through',
      );
      expect(out, contains('cover'));
      expect(out, isNot(contains('under')));
    });

    testWidgets('a GestureDetector in a cache-hit entry still fires', (tester) {
      // Pointer hit-testing is fed by paint-order registration; a cache-hit
      // frame must replay the base entry's regions or its buttons go dead
      // the moment a sibling entry churns.
      var taps = 0;
      final float = GlobalKey<_BumpCounterState>();
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => GestureDetector(
                onTap: () => taps++,
                child: const Text('tap me'),
              ),
            ),
            OverlayEntry(
              builder: (_) =>
                  _floatAt(2, _BumpCounter(key: float, label: 'float')),
            ),
          ],
        ),
      );
      const size = CellSize(20, 4);
      tester.render(size: size); // warm both caches

      float.currentState!.bump();
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.cachedCount, 1, reason: 'the base entry was a cache-hit');

      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 2,
          row: 0,
        ),
      );
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 2,
          row: 0,
        ),
      );
      expect(
        taps,
        1,
        reason: 'the boundary must replay pointer regions on cache-hit',
      );
    });

    testWidgets('semantic bounds survive a cache-hit frame', (tester) {
      final float = GlobalKey<_BumpCounterState>();
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => const Padding(
                padding: EdgeInsets.only(left: 2, top: 1),
                child: Text('Cached'),
              ),
            ),
            OverlayEntry(
              builder: (_) =>
                  _floatAt(3, _BumpCounter(key: float, label: 'float')),
            ),
          ],
        ),
      );
      const size = CellSize(20, 5);
      tester.render(size: size);
      var node = tester.semantics().single(
        role: SemanticRole.text,
        label: 'Cached',
      );
      expect(node.bounds, CellRect.fromLTWH(2, 1, 6, 1));

      float.currentState!.bump();
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.cachedCount, 1, reason: 'the base entry was a cache-hit');
      node = tester.semantics().single(
        role: SemanticRole.text,
        label: 'Cached',
      );
      expect(
        node.bounds,
        CellRect.fromLTWH(2, 1, 6, 1),
        reason: 'replayed semantic bounds stay correct on cached frames',
      );
    });

    testWidgets('an inline-image placement survives a cache-hit frame', (
      tester,
    ) {
      final float = GlobalKey<_BumpCounterState>();
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(builder: (_) => const ImageLeaf()),
            OverlayEntry(
              builder: (_) =>
                  _floatAt(3, _BumpCounter(key: float, label: 'float')),
            ),
          ],
        ),
      );
      const size = CellSize(10, 5);
      final warm = tester.render(size: size);
      expect(warm.imagePlacements, hasLength(1), reason: 'carried on repaint');

      float.currentState!.bump();
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final buf = tester.render(size: size);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.cachedCount, 1, reason: 'the image entry was a cache-hit');
      final placement = buf.imagePlacements.single;
      expect(placement.col, 0);
      expect(placement.row, 0);
      expect(buf.images, isNotEmpty);
      expect(
        buf.atColRow(0, 0).role,
        CellRole.overlay,
        reason: 'overlay cells and their placement both survive the blit',
      );
    });

    testWidgets('a throwing entry contains to its own cells and recovers', (
      tester,
    ) {
      // Production posture: contain instead of the tester's rethrow.
      tester.owner.rethrowContainedRenderErrors = false;
      final contained = <FrameContainmentError>[];
      tester.owner.onContainedRenderError = contained.add;
      // The throw happens INSIDE the entry boundary's cached paint (under
      // the damage-suppression and capture-collector scopes) — exactly the
      // path the entry's implicit ErrorBoundary must contain cleanly. 14×5
      // so the message line fits inside the panel.
      var mode = BoomMode.paint;
      late final OverlayEntry boomEntry;
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            // Containment is entry-granular: the presentation fills the
            // crashing ENTRY's cells (rows 0-4 here), so the sibling sits
            // below them to show it is untouched.
            OverlayEntry(builder: (_) => _floatAt(6, const Text('base stays'))),
            boomEntry = OverlayEntry(
              builder: (_) => Boom(mode: mode, size: const CellSize(14, 5)),
            ),
          ],
        ),
      );
      const size = CellSize(30, 8);
      final out = tester.renderToString(size: size);
      expect(out, contains('base stays'), reason: 'sibling entry unaffected');
      expect(out, contains('⚠'), reason: 'presentation painted');
      expect(out, contains('paint-boom'));
      expect(contained, hasLength(1));

      // Heal the entry: the throw ran mid-cached-paint under the boundary,
      // so a clean recovery also proves the damage-suppression and
      // capture-collector scopes were restored.
      mode = BoomMode.healthy;
      boomEntry.markNeedsBuild();
      tester.pump();
      final healed = tester.renderToString(size: size);
      expect(healed, contains('healthy###'), reason: 'subtree re-attempted');
      expect(healed, isNot(contains('paint-boom')));
      expect(healed, contains('base stays'));
    });

    testWidgets('entry state survives visibility and engagement flips', (
      tester,
    ) {
      final counter = GlobalKey<_BumpCounterState>();
      final top = OverlayEntry(builder: (_) => _floatAt(2, const Text('top')));
      tester.pumpWidget(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _BumpCounter(key: counter, label: 'base'),
            ),
            top,
          ],
        ),
      );
      const size = CellSize(20, 4);
      tester.render(size: size);
      counter.currentState!.bump();
      tester.pump();
      final before = counter.currentState!;
      expect(tester.renderToString(size: size), contains('base=1'));

      // Occlude: visibleCount drops to 1, so the boundaries also disengage.
      top.opaque = true;
      tester.pump();
      final hidden = tester.renderToString(size: size);
      expect(hidden, isNot(contains('base=1')));
      expect(hidden, contains('top'));

      top.opaque = false; // reveal: boundaries re-engage
      tester.pump();
      final shown = tester.renderToString(size: size);
      expect(
        shown,
        contains('base=1'),
        reason: 'state survived the hide/show cycle',
      );
      expect(
        identical(counter.currentState, before),
        isTrue,
        reason: 'no reparenting across visibility/engagement flips',
      );
    });
  });

  group('OverlayEntryMountSync', () {
    testWidgets('a burst of syncs converges in one pass', (tester) async {
      final overlayKey = GlobalKey<OverlayState>();
      tester.pumpWidget(
        Overlay(
          key: overlayKey,
          initialEntries: [OverlayEntry(builder: (_) => const Text('base'))],
        ),
      );
      var wanted = true;
      final sync = OverlayEntryMountSync(
        entry: OverlayEntry(builder: (_) => const Text('layer')),
        resolveOverlay: () => overlayKey.currentState,
        shouldMount: () => wanted,
      );
      sync
        ..sync()
        ..sync()
        ..sync();
      expect(
        overlayKey.currentState!.entries,
        hasLength(1),
        reason: 'convergence is deferred to a microtask',
      );
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      // A non-coalesced burst would have tripped insert()'s
      // already-inserted assert; one pass mounts the entry once.
      expect(overlayKey.currentState!.entries, hasLength(2));

      // The pass re-reads the predicate: a mount request immediately
      // retracted converges on the final (unmounted) state.
      wanted = false;
      sync.sync();
      wanted = true;
      sync.sync(); // coalesced with the pending pass
      await Future<void>.delayed(Duration.zero);
      expect(overlayKey.currentState!.entries, hasLength(2));
    });

    testWidgets('a pass that finds no overlay is retried by a later sync', (
      tester,
    ) async {
      final overlayKey = GlobalKey<OverlayState>();
      tester.pumpWidget(
        Overlay(
          key: overlayKey,
          initialEntries: [OverlayEntry(builder: (_) => const Text('base'))],
        ),
      );
      var resolvable = false;
      final sync = OverlayEntryMountSync(
        entry: OverlayEntry(builder: (_) => const Text('layer')),
        resolveOverlay: () => resolvable ? overlayKey.currentState : null,
        shouldMount: () => true,
      );
      sync.sync();
      await Future<void>.delayed(Duration.zero);
      expect(
        overlayKey.currentState!.entries,
        hasLength(1),
        reason: 'the pass was dropped — no overlay to converge against',
      );

      // Self-healing: mountedness is derived from the entry's attachment,
      // not stored, so nothing desynced — the next sync simply converges.
      resolvable = true;
      sync.sync();
      await Future<void>.delayed(Duration.zero);
      expect(overlayKey.currentState!.entries, hasLength(2));
    });

    testWidgets('syncNow converges immediately; dispose unmounts', (
      tester,
    ) async {
      final overlayKey = GlobalKey<OverlayState>();
      tester.pumpWidget(
        Overlay(
          key: overlayKey,
          initialEntries: [OverlayEntry(builder: (_) => const Text('base'))],
        ),
      );
      var wanted = true;
      final notifier = _TestNotifier();
      final sync = OverlayEntryMountSync(
        entry: OverlayEntry(builder: (_) => const Text('layer')),
        resolveOverlay: () => overlayKey.currentState,
        shouldMount: () => wanted,
      )..attachTo(notifier);

      sync.syncNow();
      expect(
        overlayKey.currentState!.entries,
        hasLength(2),
        reason: 'syncNow mounts on the same turn (no microtask)',
      );

      wanted = false;
      notifier.fire(); // listener path: converges a microtask later
      await Future<void>.delayed(Duration.zero);
      expect(overlayKey.currentState!.entries, hasLength(1));

      wanted = true;
      sync.syncNow();
      expect(overlayKey.currentState!.entries, hasLength(2));

      sync.dispose();
      expect(
        overlayKey.currentState!.entries,
        hasLength(1),
        reason: 'dispose removes the mounted entry',
      );
      notifier.fire(); // detached: must not schedule anything
      await Future<void>.delayed(Duration.zero);
      expect(overlayKey.currentState!.entries, hasLength(1));
    });
  });
}

class _TestNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}
