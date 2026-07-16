import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury/src/rendering/render_effect.dart';
import 'package:fleury/src/rendering/render_repaint_boundary.dart';
import 'package:test/test.dart';

import '../support/render_fixtures.dart';

/// All [RenderRepaintBoundary]s in the tree, in visit (outer-first) order.
List<RenderRepaintBoundary> _boundaries(FleuryTester tester) {
  final found = <RenderRepaintBoundary>[];
  void visit(Element e) {
    if (e is RenderObjectElement) {
      final render = e.renderObject;
      if (render is RenderRepaintBoundary) found.add(render);
    }
    e.visitChildren(visit);
  }

  visit(tester.root!);
  return found;
}

List<Selectable> _selectables(FleuryTester tester) {
  final found = <Selectable>[];
  void visit(Element e) {
    if (e is RenderObjectElement && e.renderObject is Selectable) {
      found.add(e.renderObject as Selectable);
    }
    e.visitChildren(visit);
  }

  visit(tester.root!);
  return found;
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  void bump() => setState(() => count++);
  @override
  Widget build(BuildContext context) => Text('count=$count');
}

/// Paints its child through a scratch-local origin while preserving the real
/// screen origin, matching the coordinate split used by effects/scrollables.
final class _ScratchPaint extends SingleChildRenderObjectWidget {
  const _ScratchPaint({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderCellEffect(_identityComposite);
  }

  static CellPlacement _identityComposite(
    int col,
    int row,
    Cell cell,
    CellSize size,
  ) {
    return CellPlacement(col, row, cell.style);
  }
}

void main() {
  group('RepaintBoundary', () {
    testWidgets('produces identical rendered output to its child', (tester) {
      const size = CellSize(40, 3);
      tester.pumpWidget(
        const Column(children: [Text('alpha'), Text('beta'), Text('gamma')]),
      );
      final without = tester.renderToString(size: size);

      tester.pumpWidget(
        const RepaintBoundary(
          child: Column(children: [Text('alpha'), Text('beta'), Text('gamma')]),
        ),
      );
      final wrapped = tester.renderToString(size: size);

      expect(
        wrapped,
        without,
        reason: 'a boundary must be transparent to its viewer',
      );
    });

    testWidgets('invalidates its cache when a wrapped widget rebuilds', (
      tester,
    ) {
      final key = GlobalKey<_CounterState>();
      tester.pumpWidget(RepaintBoundary(child: _Counter(key: key)));
      expect(
        tester.renderToString(size: const CellSize(12, 1)).trim(),
        'count=0',
      );

      key.currentState!.bump();
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(12, 1)).trim(),
        'count=1',
        reason: 'setState inside the boundary must invalidate the cache',
      );
    });

    testWidgets(
      'holds its cached output stable when a sibling outside it rebuilds',
      (tester) {
        final sibling = GlobalKey<_CounterState>();
        tester.pumpWidget(
          Column(
            children: [
              const RepaintBoundary(child: Text('static')),
              _Counter(key: sibling),
            ],
          ),
        );
        const size = CellSize(12, 2);
        expect(
          tester.renderToString(size: size),
          tester.renderToString(size: size),
          reason: 'initial output is deterministic',
        );

        // Sibling changes, boundary's contents do not.
        sibling.currentState!.bump();
        tester.pump();
        final out = tester.renderToString(size: size);
        expect(out.contains('static'), isTrue);
        expect(out.contains('count=1'), isTrue);
      },
    );

    testWidgets(
      'a GestureDetector inside a cached boundary still fires on cache-hit',
      (tester) {
        // Pointer hit-testing is fed by paint-order registration, and a
        // cache-hit skips the subtree paint — so without the boundary
        // replaying its captured pointer regions, an interactive widget
        // inside a cached item (a button in a list row) would silently go
        // dead the moment the boundary stops repainting.
        var taps = 0;
        final sibling = GlobalKey<_CounterState>();
        tester.pumpWidget(
          Column(
            children: [
              RepaintBoundary(
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const Text('tap me'),
                ),
              ),
              _Counter(key: sibling),
            ],
          ),
        );
        const size = CellSize(20, 2);
        tester.render(size: size); // frame 1: paints + registers the region

        // A sibling changes; the boundary's own content does not, so the next
        // frame is a cache-hit — the frame that drops the region without the
        // replay fix.
        sibling.currentState!.bump();
        tester.render(size: size);

        // Click the region that now exists only because the boundary replayed
        // it. down + up over the same cell = a tap.
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
          reason:
              'the boundary must replay pointer regions on cache-hit — '
              'without it the GestureDetector is dead once cached',
        );
      },
    );

    testWidgets('cached focus and caret geometry follows a moved boundary', (
      tester,
    ) {
      final focusNode = FocusNode();
      final controller = TextEditingController(text: 'abc');
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      final editor = SizedBox(
        width: 6,
        height: 1,
        child: TextInput(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
        ),
      );

      tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 1, top: 1),
          child: RepaintBoundary(child: editor),
        ),
      );
      tester.render(size: const CellSize(20, 5));
      expect(focusNode.rect, CellRect.fromLTWH(1, 1, 6, 1));
      expect(focusNode.caretRect, CellRect.fromLTWH(4, 1, 1, 1));

      // Keep the exact editor instance so the boundary cache stays valid; only
      // its ancestor-provided paint offset changes.
      tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: RepaintBoundary(child: editor),
        ),
      );
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(20, 5));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(stats.cachedCount, 1, reason: 'the editor paint was skipped');
      expect(focusNode.rect, CellRect.fromLTWH(4, 2, 6, 1));
      expect(focusNode.caretRect, CellRect.fromLTWH(7, 2, 1, 1));
    });

    testWidgets('cached Text and RichText selection geometry follows moves', (
      tester,
    ) {
      final cases = <Widget>[
        const Text('plain'),
        const RichText(text: TextSpan(text: 'rich!')),
      ];

      for (final content in cases) {
        final boundary = RepaintBoundary(child: content);
        tester.pumpWidget(
          Padding(
            padding: const EdgeInsets.only(left: 1, top: 1),
            child: boundary,
          ),
        );
        tester.render(size: const CellSize(20, 5));
        expect(
          _selectables(tester).single.cellBounds,
          CellRect.fromLTWH(1, 1, 5, 1),
        );

        tester.pumpWidget(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: boundary,
          ),
        );
        RepaintBoundaryDebugStats.beginFrame(enabled: true);
        tester.render(size: const CellSize(20, 5));
        final stats = RepaintBoundaryDebugStats.takeFrameStats();

        expect(stats.cachedCount, 1, reason: '$content paint was skipped');
        expect(
          _selectables(tester).single.cellBounds,
          CellRect.fromLTWH(4, 2, 5, 1),
        );
        expect(
          _selectables(tester).single.visibleBounds,
          CellRect.fromLTWH(4, 2, 5, 1),
        );
      }
    });

    testWidgets('cached selectable geometry reapplies a changing scroll clip', (
      tester,
    ) {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        SizedBox(
          width: 6,
          height: 1,
          child: ScrollView(
            controller: controller,
            child: const Column(
              children: [
                Text('top'),
                RepaintBoundary(child: Text('target')),
              ],
            ),
          ),
        ),
      );

      tester.render(size: const CellSize(6, 1));
      var target = _selectables(
        tester,
      ).singleWhere((selectable) => selectable.cellBounds?.size.cols == 6);
      expect(target.cellBounds, CellRect.fromLTWH(0, 1, 6, 1));
      expect(target.visibleBounds, isNull);

      controller.jumpTo(1);
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(6, 1));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      target = _selectables(
        tester,
      ).singleWhere((selectable) => selectable.cellBounds?.size.cols == 6);
      expect(stats.cachedCount, 1, reason: 'the target paint was skipped');
      expect(target.cellBounds, CellRect.fromLTWH(0, 0, 6, 1));
      expect(target.visibleBounds, CellRect.fromLTWH(0, 0, 6, 1));
    });

    testWidgets('cached anchor geometry keeps its follower attached on move', (
      tester,
    ) {
      final link = AnchorLink();
      final boundary = RepaintBoundary(
        child: Anchor(link: link, child: const Text('A')),
      );

      Widget frame(EdgeInsets padding) => Stack(
        children: [
          Padding(padding: padding, child: boundary),
          Follower(link: link, child: const Text('m')),
        ],
      );

      tester.pumpWidget(frame(const EdgeInsets.only(left: 1, top: 1)));
      tester.render(size: const CellSize(12, 6));
      expect(link.rect, CellRect.fromLTWH(1, 1, 1, 1));

      tester.pumpWidget(frame(const EdgeInsets.only(left: 4, top: 2)));
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final moved = tester.render(size: const CellSize(12, 6));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(stats.cachedCount, 1, reason: 'the anchor paint was skipped');
      expect(link.rect, CellRect.fromLTWH(4, 2, 1, 1));
      expect(moved.atColRow(4, 3).grapheme, 'm');
    });

    testWidgets('cached contained-error semantics follows a moved boundary', (
      tester,
    ) {
      const boundary = RepaintBoundary(
        child: ErrorBoundary(rethrowContained: false, child: Boom()),
      );

      Widget frame(EdgeInsets padding) => Padding(
        padding: padding,
        child: const SizedBox(width: 6, height: 2, child: boundary),
      );

      tester.pumpWidget(frame(const EdgeInsets.only(left: 1, top: 1)));
      tester.render(size: const CellSize(12, 6));
      expect(
        tester
            .semantics()
            .where(role: SemanticRole.errorBoundary)
            .single
            .bounds,
        CellRect.fromLTWH(1, 1, 6, 2),
      );

      tester.pumpWidget(frame(const EdgeInsets.only(left: 4, top: 2)));
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: const CellSize(12, 6));
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(stats.cachedCount, 1, reason: 'the error paint was skipped');
      expect(
        tester
            .semantics()
            .where(role: SemanticRole.errorBoundary)
            .single
            .bounds,
        CellRect.fromLTWH(4, 2, 6, 2),
      );
    });

    testWidgets(
      'nested cache replay preserves scratch screen transforms and pointers',
      (tester) {
        final focusNode = FocusNode();
        final controller = TextEditingController(text: 'abc');
        addTearDown(focusNode.dispose);
        addTearDown(controller.dispose);
        var taps = 0;

        tester.pumpWidget(
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 1),
            child: RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.only(left: 3, top: 1),
                child: _ScratchPaint(
                  child: RepaintBoundary(
                    child: GestureDetector(
                      onTap: () => taps++,
                      child: SizedBox(
                        width: 6,
                        height: 1,
                        child: TextInput(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        const size = CellSize(20, 5);
        tester.render(size: size);
        expect(focusNode.rect, CellRect.fromLTWH(5, 2, 6, 1));
        expect(focusNode.caretRect, CellRect.fromLTWH(8, 2, 1, 1));

        RepaintBoundaryDebugStats.beginFrame(enabled: true);
        tester.render(size: size);
        final stats = RepaintBoundaryDebugStats.takeFrameStats();

        expect(stats.cachedCount, 1, reason: 'the outer cache skipped both');
        expect(focusNode.rect, CellRect.fromLTWH(5, 2, 6, 1));
        expect(focusNode.caretRect, CellRect.fromLTWH(8, 2, 1, 1));

        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 5,
            row: 2,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 5,
            row: 2,
          ),
        );
        expect(
          taps,
          1,
          reason: 'the replayed pointer region uses screen space',
        );
      },
    );

    testWidgets('nested cache replay preserves semantic screen transforms', (
      tester,
    ) {
      tester.pumpWidget(
        const Padding(
          padding: EdgeInsets.only(left: 2, top: 1),
          child: RepaintBoundary(
            child: Padding(
              padding: EdgeInsets.only(left: 3, top: 1),
              child: _ScratchPaint(
                child: RepaintBoundary(
                  child: Semantics(
                    id: SemanticNodeId('scratch-semantic'),
                    role: SemanticRole.button,
                    label: 'Scratch semantic',
                    child: Text('action'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      const size = CellSize(20, 5);
      tester.render(size: size);
      var node = tester.semantics().nodeById(
        const SemanticNodeId('scratch-semantic'),
      );
      expect(node?.bounds, CellRect.fromLTWH(5, 2, 6, 1));

      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      node = tester.semantics().nodeById(
        const SemanticNodeId('scratch-semantic'),
      );

      expect(stats.cachedCount, 1);
      expect(node?.bounds, CellRect.fromLTWH(5, 2, 6, 1));
    });

    testWidgets(
      'nested cache replay keeps scroll-clipped focus and semantics hidden',
      (tester) {
        final focusNode = FocusNode();
        final controller = TextEditingController(text: 'abc');
        final scrollController = ScrollController();
        addTearDown(focusNode.dispose);
        addTearDown(controller.dispose);
        addTearDown(scrollController.dispose);

        tester.pumpWidget(
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 1),
            child: RepaintBoundary(
              child: SizedBox(
                width: 6,
                height: 1,
                child: ScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      const Text('shown'),
                      RepaintBoundary(
                        child: Semantics(
                          id: const SemanticNodeId('clipped-editor'),
                          role: SemanticRole.textField,
                          label: 'Clipped editor',
                          child: SizedBox(
                            width: 6,
                            height: 1,
                            child: TextInput(
                              controller: controller,
                              focusNode: focusNode,
                              autofocus: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        const size = CellSize(20, 5);
        tester.render(size: size);
        expect(focusNode.rect, isNull);
        expect(focusNode.caretRect, isNull);
        expect(
          tester
              .semantics()
              .nodeById(const SemanticNodeId('clipped-editor'))
              ?.bounds,
          isNull,
        );

        RepaintBoundaryDebugStats.beginFrame(enabled: true);
        tester.render(size: size);
        final stats = RepaintBoundaryDebugStats.takeFrameStats();

        expect(stats.cachedCount, 1);
        expect(focusNode.rect, isNull);
        expect(focusNode.caretRect, isNull);
        expect(
          tester
              .semantics()
              .nodeById(const SemanticNodeId('clipped-editor'))
              ?.bounds,
          isNull,
        );
      },
    );

    testWidgets('overflow scratch paint preserves screen origin and clip', (
      tester,
    ) {
      final focusNode = FocusNode();
      final controller = TextEditingController(text: 'abc');
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: RepaintBoundary(
            child: SizedBox(
              width: 4,
              height: 1,
              child: Row(
                children: [
                  const SizedBox(width: 2, height: 1, child: Text('ok')),
                  Semantics(
                    id: const SemanticNodeId('overflow-editor'),
                    role: SemanticRole.textField,
                    label: 'Overflow editor',
                    child: SizedBox(
                      width: 6,
                      height: 1,
                      child: TextInput(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      const size = CellSize(16, 4);
      tester.render(size: size);
      expect(focusNode.rect, CellRect.fromLTWH(4, 1, 6, 1));
      expect(focusNode.caretRect, isNull);
      expect(
        tester
            .semantics()
            .nodeById(const SemanticNodeId('overflow-editor'))
            ?.bounds,
        CellRect.fromLTWH(4, 1, 2, 1),
      );

      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(stats.cachedCount, 1);
      expect(focusNode.rect, CellRect.fromLTWH(4, 1, 6, 1));
      expect(focusNode.caretRect, isNull);
      expect(
        tester
            .semantics()
            .nodeById(const SemanticNodeId('overflow-editor'))
            ?.bounds,
        CellRect.fromLTWH(4, 1, 2, 1),
      );
    });

    testWidgets('a clipped cache-hit image matches its visible source window', (
      tester,
    ) {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        ScrollView(
          controller: controller,
          child: const Column(
            children: [
              RepaintBoundary(child: ImageLeaf()),
              SizedBox(width: 4, height: 8, child: Text('tail')),
            ],
          ),
        ),
      );
      const viewport = CellSize(4, 3);
      tester.render(size: viewport);

      controller.scrollBy(1);
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      final partial = tester.render(size: viewport);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.cachedCount, greaterThanOrEqualTo(1));
      final p = partial.imagePlacements.single;
      expect([p.col, p.row, p.cols, p.rows], [0, 0, 4, 1]);
      expect([p.boxCols, p.boxRows], [4, 2]);
      expect([p.boxOffsetCol, p.boxOffsetRow], [0, 1]);
    });

    testWidgets('ancestor clips are reapplied instead of retained locally', (
      tester,
    ) {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      const semantic = RepaintBoundary(
        child: Semantics(
          id: SemanticNodeId('tall-semantic'),
          role: SemanticRole.region,
          label: 'Tall semantic',
          child: SizedBox(width: 4, height: 3, child: Text('tall')),
        ),
      );
      tester.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: SizedBox(
            width: 4,
            height: 2,
            child: ScrollView(controller: scrollController, child: semantic),
          ),
        ),
      );
      const size = CellSize(12, 5);
      tester.render(size: size);
      expect(
        tester
            .semantics()
            .nodeById(const SemanticNodeId('tall-semantic'))
            ?.bounds,
        CellRect.fromLTWH(2, 1, 4, 2),
      );

      scrollController.jumpTo(1);
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      final stats = RepaintBoundaryDebugStats.takeFrameStats();

      expect(stats.cachedCount, 1);
      expect(
        tester
            .semantics()
            .nodeById(const SemanticNodeId('tall-semantic'))
            ?.bounds,
        CellRect.fromLTWH(2, 1, 4, 2),
      );
    });

    testWidgets(
      'inner clips survive a changing tighter ancestor on cache replay',
      (tester) {
        final outer = ScrollController(offset: 1);
        final inner = ScrollController(offset: 1);
        addTearDown(outer.dispose);
        addTearDown(inner.dispose);
        var taps = 0;

        tester.pumpWidget(
          SizedBox(
            width: 4,
            height: 2,
            child: ScrollView(
              controller: outer,
              child: Column(
                children: [
                  RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: SizedBox(
                        width: 4,
                        height: 2,
                        child: ScrollView(
                          controller: inner,
                          child: Semantics(
                            id: const SemanticNodeId('nested-clip-target'),
                            role: SemanticRole.button,
                            label: 'Nested clip target',
                            child: GestureDetector(
                              onTap: () => taps += 1,
                              child: const SizedBox(
                                width: 4,
                                height: 3,
                                child: Column(
                                  children: [Text('A'), Text('B'), Text('C')],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4, height: 1, child: Text('tail')),
                ],
              ),
            ),
          ),
        );

        const size = CellSize(4, 2);
        final first = tester.renderToString(size: size, emptyMark: ' ');
        expect(first, 'B\nC\n');
        expect(
          tester
              .semantics()
              .nodeById(const SemanticNodeId('nested-clip-target'))
              ?.bounds,
          CellRect.fromLTWH(0, 0, 4, 2),
        );

        outer.jumpTo(0);
        tester.pump();
        RepaintBoundaryDebugStats.beginFrame(enabled: true);
        final second = tester.renderToString(size: size, emptyMark: ' ');
        final stats = RepaintBoundaryDebugStats.takeFrameStats();

        expect(stats.cachedCount, 1);
        expect(second, '\nB\n');
        expect(
          tester
              .semantics()
              .nodeById(const SemanticNodeId('nested-clip-target'))
              ?.bounds,
          CellRect.fromLTWH(0, 1, 4, 1),
        );

        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 0,
            row: 0,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 0,
            row: 0,
          ),
        );
        expect(taps, 0, reason: 'the inner viewport still clips row zero');

        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 0,
            row: 1,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 0,
            row: 1,
          ),
        );
        expect(taps, 1);
      },
    );

    testWidgets(
      'initially hidden inner viewport is retained for later cache reveal',
      (tester) {
        final outer = ScrollController();
        addTearDown(outer.dispose);
        var taps = 0;

        tester.pumpWidget(
          SizedBox(
            width: 8,
            height: 2,
            child: ScrollView(
              controller: outer,
              child: RepaintBoundary(
                child: Column(
                  children: [
                    const Text('top'),
                    const Text('spacer'),
                    SizedBox(
                      width: 8,
                      height: 1,
                      child: ScrollView(
                        child: Semantics(
                          id: const SemanticNodeId('revealed-target'),
                          role: SemanticRole.button,
                          label: 'Revealed target',
                          child: GestureDetector(
                            onTap: () => taps += 1,
                            child: const Text('inner'),
                          ),
                        ),
                      ),
                    ),
                    const Text('tail'),
                  ],
                ),
              ),
            ),
          ),
        );

        const size = CellSize(8, 2);
        final first = tester.renderToString(size: size, emptyMark: ' ');
        expect(first, 'top\nspacer\n');
        expect(
          tester
              .semantics()
              .nodeById(const SemanticNodeId('revealed-target'))
              ?.bounds,
          isNull,
        );

        outer.jumpTo(1);
        tester.pump();
        RepaintBoundaryDebugStats.beginFrame(enabled: true);
        final second = tester.renderToString(size: size, emptyMark: ' ');
        final stats = RepaintBoundaryDebugStats.takeFrameStats();

        expect(stats.cachedCount, 1);
        expect(second, 'spacer\ninner\n');
        expect(
          tester
              .semantics()
              .nodeById(const SemanticNodeId('revealed-target'))
              ?.bounds,
          CellRect.fromLTWH(0, 1, 8, 1),
        );

        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 0,
            row: 1,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 0,
            row: 1,
          ),
        );
        expect(taps, 1);
      },
    );

    testWidgets('controller scrolling invalidates an enclosing cache', (
      tester,
    ) {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        RepaintBoundary(
          child: SizedBox(
            width: 6,
            height: 1,
            child: ScrollView(
              controller: controller,
              child: const Column(children: [Text('first'), Text('second')]),
            ),
          ),
        ),
      );

      const size = CellSize(6, 1);
      expect(tester.renderToString(size: size).trim(), 'first');

      controller.jumpTo(1);
      tester.pump();
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      expect(tester.renderToString(size: size).trim(), 'second');
      final stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.repaintedCount, 1);
      expect(stats.cachedCount, 0);
    });

    testWidgets('collapsing a boundary clears retained paint geometry', (
      tester,
    ) {
      final focusNode = FocusNode();
      final controller = TextEditingController(text: 'abc');
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      final editor = Semantics(
        id: const SemanticNodeId('collapsing-editor'),
        role: SemanticRole.textField,
        label: 'Collapsing editor',
        child: TextInput(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
        ),
      );

      tester.pumpWidget(
        RepaintBoundary(child: SizedBox(width: 6, height: 1, child: editor)),
      );
      tester.render(size: const CellSize(12, 3));
      expect(focusNode.rect, CellRect.fromLTWH(0, 0, 6, 1));
      expect(focusNode.caretRect, CellRect.fromLTWH(3, 0, 1, 1));
      expect(
        tester
            .semantics()
            .nodeById(const SemanticNodeId('collapsing-editor'))
            ?.bounds,
        CellRect.fromLTWH(0, 0, 6, 1),
      );

      tester.pumpWidget(
        RepaintBoundary(child: SizedBox(width: 0, height: 0, child: editor)),
      );
      tester.render(size: const CellSize(12, 3));

      expect(focusNode.rect, isNull);
      expect(focusNode.caretRect, isNull);
      expect(
        tester
            .semantics()
            .nodeById(const SemanticNodeId('collapsing-editor'))
            ?.bounds,
        isNull,
      );
    });

    testWidgets('a change under an INNER boundary refreshes the OUTER cache', (
      tester,
    ) {
      // An outer boundary's cached blit embeds the inner boundary's painted
      // cells, so a change under the inner must dirty the outer too — else the
      // outer cache-hits and blits stale content (and, with pointer/semantic
      // replay, re-registers regions from a subtree that has since changed).
      final inner = GlobalKey<_CounterState>();
      tester.pumpWidget(
        RepaintBoundary(
          child: RepaintBoundary(child: _Counter(key: inner)),
        ),
      );
      const size = CellSize(12, 1);
      expect(tester.renderToString(size: size).trim(), 'count=0');

      inner.currentState!.bump();
      tester.pump();
      expect(
        tester.renderToString(size: size).trim(),
        'count=1',
        reason:
            'the inner change must reach the screen through the outer '
            'boundary — marking only the nearest boundary leaves it stale',
      );
    });

    testWidgets('a removed inner region does not keep firing via the outer', (
      tester,
    ) {
      // The input counterpart of the staleness bug: without dirtying the outer,
      // a GestureDetector removed inside an inner boundary would keep firing
      // its captured onTap when the outer replays its stale regions.
      var taps = 0;
      final toggle = GlobalKey<_ToggleState>();
      tester.pumpWidget(
        RepaintBoundary(
          child: RepaintBoundary(
            child: _Toggle(key: toggle, onTap: () => taps++),
          ),
        ),
      );
      const size = CellSize(12, 1);
      tester.render(size: size); // region present + captured

      toggle.currentState!.hide(); // remove the GestureDetector
      tester.render(size: size); // outer must refresh, dropping the region

      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 1,
          row: 0,
        ),
      );
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 1,
          row: 0,
        ),
      );
      expect(
        taps,
        0,
        reason:
            'a removed region must not keep firing through a stale outer cache',
      );
    });

    testWidgets('re-engaging an inner boundary dirties the outer cache', (
      tester,
    ) {
      // A disengaged (pass-through) inner boundary is invisible to the
      // invalidation walk. When it re-engages, its own needsPaint is set —
      // but from then on every change inside it short-circuits at the
      // (already dirty) inner boundary, so the OUTER cache would keep
      // blitting stale cells unless the enable itself dirtied the ancestors
      // (markAncestorRepaintBoundariesDirty).
      final key = GlobalKey<_CounterState>();
      tester.pumpWidget(
        RepaintBoundary(
          child: RepaintBoundary(child: _Counter(key: key)),
        ),
      );
      const size = CellSize(12, 1);
      final inner = _boundaries(tester).last;
      inner.cachingEnabled = false;
      tester.render(size: size); // outer caches THROUGH the pass-through inner

      inner.cachingEnabled = true; // setter alone; no other invalidation
      key.currentState!.bump(); // walk short-circuits at the dirty inner
      tester.pump();
      expect(
        tester.renderToString(size: size).trim(),
        'count=1',
        reason: 'the outer boundary must repaint, not blit its stale cache',
      );
    });
  });
}

class _Toggle extends StatefulWidget {
  const _Toggle({super.key, required this.onTap});
  final void Function() onTap;
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _shown = true;
  void hide() => setState(() => _shown = false);
  @override
  Widget build(BuildContext context) => _shown
      ? GestureDetector(onTap: widget.onTap, child: const Text('hit'))
      : const Text('gone');
}
