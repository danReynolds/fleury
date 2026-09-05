// Derived geometry oracle.
//
// Every container declares where it put each child (`childOffsetOf`), what
// it clips (`childClip`), and whether it presents the child (`presentsChild`);
// `screenGeometryOf` composes those into a screen rectangle. The paint-time
// capture channels are the existing source of truth: a pointer region's
// registered rectangle and a focus node's rectangle. This oracle lays out the
// container zoo and asserts the derived answer equals the captured one, so a
// container that forgets its contract fails here, not in a user's app.
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

  Widget widget([String? label]) => GestureDetector(
    key: key,
    onTap: () {},
    child: Focus(focusNode: node, child: Text(label ?? name)),
  );

  /// The pointer region's render object, or null when not mounted.
  RenderPointerListener? get pointer =>
      key.currentContext?.findRenderObject() as RenderPointerListener?;

  /// The focus bounds render object: the pointer listener's only child.
  RenderObject? get focus => (pointer as RenderObjectWithSingleChild?)?.child;
}

/// Asserts derived geometry matches what paint captured for [probe].
void expectAgrees(Probe probe, {String? reason}) {
  final pointer = probe.pointer;
  if (pointer == null) return; // not mounted (a lazy row): nothing to compare
  final derivedPointer = screenGeometryOf(pointer);
  expect(
    derivedPointer?.visible,
    pointer.debugScreenRect,
    reason:
        '${probe.name}: pointer region${reason == null ? '' : ' ($reason)'}',
  );
  final focus = probe.focus!;
  final derivedFocus = screenGeometryOf(focus);
  final expected = derivedFocus != null && derivedFocus.visible != null
      ? derivedFocus.bounds
      : null;
  expect(
    expected,
    probe.node.rect,
    reason: '${probe.name}: focus rect${reason == null ? '' : ' ($reason)'}',
  );
}

void main() {
  testWidgets('flex, padding, border, align', (tester) async {
    final a = Probe('A');
    final b = Probe('B');
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
                  a.widget('AAAA'),
                  SizedBox(
                    width: 20,
                    height: 3,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: b.widget('BB'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    tester.render();
    expectAgrees(a);
    expectAgrees(b);
    // Sanity: the numbers are what the layout implies, not just consistent.
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
                base.widget('base'),
                Positioned(left: 5, top: 3, child: over.widget('over')),
              ],
            ),
          ),
          IndexedStack(index: 1, children: [hidden.widget(), shown.widget()]),
          SizedBox(
            width: 20,
            child: Wrap(children: [for (final c in chips) c.widget('chip!')]),
          ),
        ],
      ),
    );
    tester.render();
    for (final p in [base, over, shown, ...chips]) {
      expectAgrees(p);
    }
    expect(over.node.rect, CellRect.fromLTWH(5, 3, 4, 1));
    expect(
      screenGeometryOf(hidden.focus!),
      isNull,
      reason: 'the inactive IndexedStack child is not presented',
    );
    expect(chips[4].node.rect!.top, greaterThan(chips[0].node.rect!.top));
  });

  testWidgets('scroll view: offset, clip, and rows scrolled out', (
    tester,
  ) async {
    final rows = [for (var i = 0; i < 12; i++) Probe('row$i')];
    final controller = ScrollController(offset: 5);
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
    tester.render();
    for (final r in rows) {
      expectAgrees(r, reason: 'scrolled by 5 in a 4-row viewport');
    }
    expect(rows[4].node.rect, isNull, reason: 'above the viewport');
    expect(rows[5].node.rect, CellRect.fromLTWH(0, 1, 4, 1));
    expect(rows[8].node.rect, CellRect.fromLTWH(0, 4, 4, 1));
    expect(rows[9].node.rect, isNull, reason: 'below the viewport');
    // Bounds are still derivable for a clipped-out row; only visibility is
    // null — what a scroll-to-reveal needs and capture cannot answer.
    final scrolledOut = screenGeometryOf(rows[2].focus!)!;
    expect(scrolledOut.visible, isNull);
    expect(scrolledOut.bounds, CellRect.fromLTWH(0, -2, 4, 1));
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
    tester.render();
    var mounted = 0;
    for (final r in rows) {
      if (r.pointer != null) mounted += 1;
      expectAgrees(r);
    }
    expect(mounted, inInclusiveRange(5, 8));
  });

  testWidgets('overlay: an opaque entry hides the entries beneath', (
    tester,
  ) async {
    final under = Probe('under');
    final floater = Probe('floater');
    tester.pumpFleuryHome(under.widget('under'));
    tester.render();
    expectAgrees(under);
    final before = under.node.rect;
    expect(before, isNotNull);

    tester.overlay.insert(
      OverlayEntry(opaque: true, builder: (_) => floater.widget('floater')),
    );
    tester.pump();
    tester.render();
    expectAgrees(floater);
    expect(
      screenGeometryOf(under.focus!),
      isNull,
      reason: 'derived: the base entry is not presented under an opaque one',
    );
    // What capture answers here is whatever the last paint left behind.
    // Recorded for the migration write-up, not asserted.
    // ignore: avoid_print
    print('captured focus rect under an opaque overlay: ${under.node.rect}');
  });
}
