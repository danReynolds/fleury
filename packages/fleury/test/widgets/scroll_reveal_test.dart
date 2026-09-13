import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_internal.dart' show revealInScrollViews;
import 'package:test/test.dart';

import '../support/harness.dart';

Widget _box(Axis axis, int main, {int cross = 12, Widget? child, Key? key}) =>
    SizedBox(
      key: key,
      width: axis == Axis.vertical ? cross : main,
      height: axis == Axis.vertical ? main : cross,
      child: child,
    );

Widget _along(Axis axis, List<Widget> children) => axis == Axis.vertical
    ? Column(mainAxisSize: MainAxisSize.min, children: children)
    : Row(mainAxisSize: MainAxisSize.min, children: children);

void main() {
  for (final axis in Axis.values) {
    testWidgets('reveal both edges and keep visible targets still: $axis', (
      tester,
    ) {
      final scroll = ScrollController();
      final target = GlobalKey();
      tester.pumpWidget(
        _box(
          axis,
          4,
          child: ScrollView(
            controller: scroll,
            scrollDirection: axis,
            child: _along(axis, [
              _box(axis, 10),
              _box(axis, 2, key: target, child: const Text('GO')),
              _box(axis, 10),
            ]),
          ),
        ),
      );
      tester.render();
      final render = target.currentContext!.findRenderObject()!;
      revealInScrollViews(render);
      expect(scroll.offset, 8);
      tester.pump();
      revealInScrollViews(render);
      expect(scroll.offset, 8);
      scroll.offset = 12;
      tester.pump();
      revealInScrollViews(render);
      expect(scroll.offset, 10);
      tester.pumpWidget(const Text('gone'));
      scroll.dispose();
    });

    testWidgets('oversized targets reveal their start: $axis', (tester) {
      final scroll = ScrollController();
      final target = GlobalKey();
      tester.pumpWidget(
        _box(
          axis,
          4,
          child: ScrollView(
            controller: scroll,
            scrollDirection: axis,
            child: _along(axis, [
              _box(axis, 10),
              _box(axis, 8, key: target),
              _box(axis, 10),
            ]),
          ),
        ),
      );
      tester.render();
      revealInScrollViews(target.currentContext!.findRenderObject()!);
      expect(scroll.offset, 10);
      tester.pumpWidget(const Text('gone'));
      scroll.dispose();
    });

    testWidgets('nested viewports reveal inside out: outer $axis', (tester) {
      final outer = ScrollController();
      final inner = ScrollController();
      final target = GlobalKey();
      tester.pumpWidget(
        _box(
          axis,
          axis == Axis.vertical ? 6 : 8,
          child: ScrollView(
            controller: outer,
            scrollDirection: axis,
            child: _along(axis, [
              _box(axis, 10),
              SizedBox(
                width: 6,
                height: 4,
                child: ScrollView(
                  controller: inner,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      SizedBox(key: target, height: 2, child: const Text('GO')),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              _box(axis, 10),
            ]),
          ),
        ),
      );
      tester.render();
      revealInScrollViews(target.currentContext!.findRenderObject()!);
      expect(inner.offset, 8);
      // Horizontally, only the two-column target needs revealing; vertically,
      // it occupies the last two rows of the already-scrolled inner pane.
      expect(outer.offset, axis == Axis.horizontal ? 4 : 8);
      tester.pump();
      expect(tester.renderToString(), contains('GO'));
      tester.pumpWidget(const Text('gone'));
      inner.dispose();
      outer.dispose();
    });
  }

  testWidgets('a large surrounding region does not hide the primary target', (
    tester,
  ) {
    final scroll = ScrollController();
    final target = GlobalKey();
    final surrounding = GlobalKey();
    tester.pumpWidget(
      SizedBox(
        width: 20,
        height: 4,
        child: ScrollView(
          controller: scroll,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Column(
                key: surrounding,
                children: [
                  const SizedBox(height: 2),
                  Text('CONTROL', key: target),
                  const SizedBox(height: 7),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    tester.render();
    revealInScrollViews(
      target.currentContext!.findRenderObject()!,
      surrounding: surrounding.currentContext!.findRenderObject(),
    );
    expect(scroll.offset, 9);
    tester.pump();
    expect(tester.renderToString(), contains('CONTROL'));
    tester.pumpWidget(const Text('gone'));
    scroll.dispose();
  });

  testWidgets('hidden ancestry prevents inner and outer scroll changes', (
    tester,
  ) {
    final outer = ScrollController();
    final inner = ScrollController();
    final target = GlobalKey();
    tester.pumpWidget(
      SizedBox(
        width: 20,
        height: 4,
        child: ScrollView(
          controller: outer,
          child: Column(
            children: [
              const SizedBox(height: 10),
              IndexedStack(
                children: [
                  const Text('VISIBLE'),
                  SizedBox(
                    height: 4,
                    child: ScrollView(
                      controller: inner,
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          Text('HIDDEN', key: target),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    tester.render();
    revealInScrollViews(target.currentContext!.findRenderObject()!);
    expect(inner.offset, 0);
    expect(outer.offset, 0);
    tester.pumpWidget(const Text('gone'));
    inner.dispose();
    outer.dispose();
  });
}
