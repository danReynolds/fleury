// Derived geometry: the contract, checked against the buffer.
//
// Every container declares where it put each child (`childOffsetOf`), what
// it clips (`childClipOf`), and whether it presents the child
// (`presentsChild`); `RenderObject.screenGeometry` composes those into a
// screen rectangle, and every consumer — pointer regions, focus rectangles,
// semantic bounds — reads it. The ground truth is the rendered buffer: a
// probe paints a unique label, and its derived geometry must be exactly the
// cells that label landed on. A container that forgets its contract fails
// here (and trips the debug placement check in `RenderObject.paint`), not
// in a user's app.
@TestOn('vm')
library;

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_internal.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

final class Probe {
  Probe(this.name) : key = GlobalKey(), node = FocusNode();
  final String name;
  final GlobalKey key;
  final FocusNode node;

  SemanticNodeId get id => SemanticNodeId(name);

  Widget widget() => GestureDetector(
    key: key,
    onTap: () {},
    child: Focus(
      focusNode: node,
      child: Semantics(
        id: id,
        role: SemanticRole.button,
        label: name,
        child: Text(name),
      ),
    ),
  );

  /// The pointer region's render object, or null when not mounted.
  RenderPointerListener? get pointer =>
      key.currentContext?.findRenderObject() as RenderPointerListener?;
}

/// Where [label] landed in the rendered [lines]: the rect of its cells, or
/// null when it is nowhere on screen. Labels are unique and single-row; a
/// label is not matched inside a longer numbered one (`row1` in `row10`),
/// but labels may abut (wrap chips).
CellRect? locate(List<String> lines, String label) {
  final word = RegExp('${RegExp.escape(label)}(?![0-9])');
  for (var row = 0; row < lines.length; row++) {
    final match = word.firstMatch(lines[row]);
    if (match != null) {
      return CellRect.fromLTWH(match.start, row, label.length, 1);
    }
  }
  return null;
}

List<String> frame(FleuryTester tester, {CellSize? size}) =>
    tester.renderToString(size: size, emptyMark: ' ').split('\n');

/// Asserts every derived consumer agrees with where [probe]'s label landed.
void expectPlaced(
  FleuryTester tester,
  List<String> lines,
  Probe probe, {
  String? reason,
}) {
  final why = reason == null ? '' : ' ($reason)';
  final truth = locate(lines, probe.name);
  final pointer = probe.pointer;
  if (pointer == null) {
    expect(truth, isNull, reason: '${probe.name}: unmounted yet painted$why');
    return;
  }
  final geometry = pointer.screenGeometry();
  expect(
    geometry?.visible,
    truth,
    reason: '${probe.name}: pointer region vs painted cells$why',
  );
  expect(
    probe.node.rect,
    truth == null ? isNull : geometry!.bounds,
    reason: '${probe.name}: focus rect$why',
  );
  expect(
    tester.semantics().nodeById(probe.id)?.bounds,
    truth,
    reason: '${probe.name}: semantic bounds vs painted cells$why',
  );
}

void main() {
  testWidgets('flex, padding, border, align', (tester) async {
    final a = Probe('AAAA');
    final b = Probe('BB');
    tester.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('header'),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 1),
            child: Container.framed(
              child: Row(
                children: [
                  a.widget(),
                  SizedBox(
                    width: 20,
                    height: 3,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: b.widget(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final lines = frame(tester);
    expectPlaced(tester, lines, a);
    expectPlaced(tester, lines, b);
    // The numbers are what the layout implies, not just self-consistent.
    expect(a.node.rect, CellRect.fromLTWH(3, 3, 4, 1));
    expect(b.node.rect, CellRect.fromLTWH(25, 5, 2, 1));
  });

  testWidgets('stack, positioned, indexed stack, wrap', (tester) async {
    final base = Probe('base');
    final over = Probe('over');
    final hidden = Probe('hidden');
    final shown = Probe('shown');
    final chips = [for (var i = 0; i < 5; i++) Probe('chip$i')];
    tester.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            height: 6,
            child: Stack(
              children: [
                base.widget(),
                Positioned(left: 5, top: 3, child: over.widget()),
              ],
            ),
          ),
          IndexedStack(index: 1, children: [hidden.widget(), shown.widget()]),
          SizedBox(
            width: 20,
            child: Wrap(children: [for (final c in chips) c.widget()]),
          ),
        ],
      ),
    );
    final lines = frame(tester);
    for (final p in [base, over, hidden, shown, ...chips]) {
      expectPlaced(tester, lines, p);
    }
    expect(over.node.rect, CellRect.fromLTWH(5, 3, 4, 1));
    expect(
      hidden.pointer!.screenGeometry(),
      isNull,
      reason: 'the inactive IndexedStack child is not presented',
    );
    expect(chips[4].node.rect!.top, greaterThan(chips[0].node.rect!.top));
  });

  testWidgets('scroll view: offset, clip, and rows scrolled out', (
    tester,
  ) async {
    final rows = [for (var i = 0; i < 12; i++) Probe('row$i')];
    final controller = ScrollController(initialOffset: 5);
    tester.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('header'),
          SizedBox(
            height: 4,
            child: ScrollView(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final r in rows) r.widget()],
              ),
            ),
          ),
        ],
      ),
    );
    final lines = frame(tester);
    for (final r in rows) {
      expectPlaced(
        tester,
        lines,
        r,
        reason: 'scrolled by 5 in a 4-row viewport',
      );
    }
    expect(rows[4].node.rect, isNull, reason: 'above the viewport');
    expect(rows[5].node.rect, CellRect.fromLTWH(0, 1, 4, 1));
    expect(rows[8].node.rect, CellRect.fromLTWH(0, 4, 4, 1));
    expect(rows[9].node.rect, isNull, reason: 'below the viewport');
    // Bounds are still derivable for a clipped-out row; only visibility is
    // null — what a scroll-to-reveal needs.
    final scrolledOut = rows[2].pointer!.screenGeometry()!;
    expect(scrolledOut.visible, isNull);
    expect(scrolledOut.bounds, CellRect.fromLTWH(0, -2, 4, 1));

    // A scroll is a paint-only invalidation: geometry follows the next frame
    // with nothing recorded and no cache replayed.
    controller.jumpTo(7);
    tester.pump();
    final scrolled = frame(tester);
    for (final r in rows) {
      expectPlaced(tester, scrolled, r, reason: 'after scrolling to 7');
    }
    expect(rows[7].node.rect, CellRect.fromLTWH(0, 1, 4, 1));
  });

  testWidgets('lazy list: mounted rows only', (tester) async {
    final rows = [for (var i = 0; i < 40; i++) Probe('item$i')];
    tester.pumpWidget(
      SizedBox(
        height: 5,
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index, _) => rows[index].widget(),
        ),
      ),
    );
    final lines = frame(tester);
    var mounted = 0;
    for (final r in rows) {
      if (r.pointer != null) mounted += 1;
      expectPlaced(tester, lines, r);
    }
    expect(mounted, inInclusiveRange(5, 8));
  });

  testWidgets('repaint boundary: a cache hit moves with its container', (
    tester,
  ) async {
    final cached = Probe('cached');
    final controller = ScrollController();
    tester.pumpWidget(
      SizedBox(
        height: 2,
        child: ScrollView(
          controller: controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('top'),
              RepaintBoundary(child: cached.widget()),
              const Text('bottom'),
            ],
          ),
        ),
      ),
    );
    expectPlaced(tester, frame(tester), cached);
    expect(cached.node.rect, CellRect.fromLTWH(0, 1, 6, 1));

    controller.jumpTo(1);
    tester.pump();
    RepaintBoundaryDebugStats.beginFrame(enabled: true);
    final lines = frame(tester);
    expect(
      RepaintBoundaryDebugStats.takeFrameStats().cachedCount,
      1,
      reason: 'the boundary blitted its cache instead of repainting',
    );
    expectPlaced(tester, lines, cached, reason: 'cache hit at a new row');
    expect(cached.node.rect, CellRect.fromLTWH(0, 0, 6, 1));
  });

  testWidgets('overlay: an opaque entry hides the entries beneath', (
    tester,
  ) async {
    final under = Probe('under');
    final floater = Probe('floater');
    tester.pumpWidget(FleuryApp(title: 'Geometry test', home: under.widget()));
    expectPlaced(tester, frame(tester), under);
    expect(under.node.rect, isNotNull);

    tester.overlay.insert(
      OverlayEntry(opaque: true, builder: (_) => floater.widget()),
    );
    tester.pump();
    final lines = frame(tester);
    expectPlaced(tester, lines, floater);
    expectPlaced(tester, lines, under, reason: 'under an opaque entry');
    expect(
      under.pointer!.screenGeometry(),
      isNull,
      reason: 'the base entry is not presented under an opaque one',
    );
    expect(under.node.rect, isNull);
  });

  group('paint must agree with the contract (debug check)', () {
    testWidgets('a child painted where childOffsetOf does not place it', (
      tester,
    ) async {
      tester.mountWidget(const _Misplacing(child: Text('x')));
      expect(
        () => tester.render(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('childOffsetOf'),
          ),
        ),
      );
    });

    testWidgets('a child painted that presentsChild reports hidden', (
      tester,
    ) async {
      tester.mountWidget(const _Hiding(child: Text('x')));
      expect(
        () => tester.render(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('presentsChild'),
          ),
        ),
      );
    });
  });
}

/// Paints its child one column right of where it claims to.
final class _Misplacing extends SingleChildRenderObjectWidget {
  const _Misplacing({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMisplacing();
}

final class _RenderMisplacing extends _RenderPassThrough {
  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    child?.paint(buffer, offset + const CellOffset(1, 0));
  }
}

/// Paints a child it declares as not presented.
final class _Hiding extends SingleChildRenderObjectWidget {
  const _Hiding({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHiding();
}

final class _RenderHiding extends _RenderPassThrough {
  @override
  bool presentsChild(RenderObject child) => false;

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    child?.paint(buffer, offset);
  }
}

abstract class _RenderPassThrough extends RenderObject
    implements RenderObjectWithSingleChild {
  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);
}
