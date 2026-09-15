import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/render_fixtures.dart';

class _Leaf extends RenderObject {
  int layouts = 0;
  bool fail = false;
  @override
  CellSize performLayout(CellConstraints constraints) {
    layouts++;
    if (fail) throw StateError('removed node laid out');
    return constraints.constrain(const CellSize(3, 1));
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {}
}

class _Parent extends RenderObject implements RenderObjectWithSingleChild {
  _Parent(RenderObject child) {
    this.child = child;
  }
  int layouts = 0;
  bool sawPendingLayout = false;
  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    layouts++;
    sawPendingLayout = needsLayout;
    return _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {}
}

class _Probe extends LeafRenderObjectWidget {
  const _Probe(this.renderObject);
  final RenderObject renderObject;
  @override
  RenderObject createRenderObject(BuildContext context) => renderObject;
}

class _Flex extends RenderFlex {
  _Flex() : super(direction: Axis.vertical);
  int layouts = 0;
  @override
  CellSize performLayout(CellConstraints constraints) {
    layouts++;
    return super.performLayout(constraints);
  }
}

void main() {
  for (final wrapped in [false, true]) {
    Widget wrap(Widget child) => wrapped
        ? Padding(padding: const EdgeInsets.all(0), child: child)
        : child;
    testWidgets('intrinsic content grows through wrapper=$wrapped', (tester) {
      Widget tree(String text) =>
          SizedBox(height: 1, child: IntrinsicWidth(child: wrap(Text(text))));
      tester.pumpWidget(tree('aa'));
      expect(tester.renderToString(size: const CellSize(20, 1)).trim(), 'aa');
      tester.pumpWidget(tree('hello'));
      expect(
        tester.renderToString(size: const CellSize(20, 1)).trim(),
        'hello',
      );
    });
    Widget tree(BoomMode mode) => SizedBox(
      width: 28,
      height: 5,
      child: ErrorBoundary(
        rethrowContained: false,
        child: wrap(Boom(mode: mode)),
      ),
    );
    testWidgets('layout failure remains contained through wrapper=$wrapped', (
      tester,
    ) {
      tester.pumpWidget(tree(BoomMode.healthy));
      expect(
        tester.renderToString(size: const CellSize(30, 6)),
        contains('healthy###'),
      );
      tester.pumpWidget(tree(BoomMode.layout));
      expect(
        tester.renderToString(size: const CellSize(30, 6)),
        contains('layout-boom'),
      );
    });
    testWidgets('contained layout recovers through wrapper=$wrapped', (tester) {
      tester.pumpWidget(tree(BoomMode.layout));
      expect(
        tester.renderToString(size: const CellSize(30, 6)),
        contains('layout-boom'),
      );
      tester.pumpWidget(tree(BoomMode.healthy));
      expect(
        tester.renderToString(size: const CellSize(30, 6)),
        contains('healthy###'),
      );
    });
  }
  testWidgets('removed dirty nodes are not laid out', (tester) {
    final child = _Leaf();
    tester.pumpWidget(SizedBox(width: 10, height: 2, child: _Probe(child)));
    final layouts = child.layouts;
    child.fail = true;
    child.markNeedsLayout();
    tester.pumpWidget(const SizedBox(width: 10, height: 2, child: Text('new')));
    expect(child.layouts, layouts);
  });
  test('trees without a frame tracker still propagate layout changes', () {
    final child = _Leaf();
    final root = _Parent(child);
    final constraints = CellConstraints.tight(const CellSize(10, 2));
    root.layout(constraints);
    child.markNeedsLayout();
    root.layout(constraints);
    expect(child.layouts, 2);
  });

  test('fixed pane updates preserve parent layout and sibling offsets', () {
    final text = RenderText(text: 'short');
    final pane = RenderSizedBox(width: 12, height: 3, child: text);
    final sibling = _Leaf();
    final root = _Flex()..replaceAllChildren([pane, sibling]);
    const constraints = CellConstraints(maxCols: 40, maxRows: 10);
    root.layout(constraints);
    final siblingOffset = root.childOffsetOf(sibling);
    text.text = 'long text that wraps across several lines';
    root.layout(constraints);
    expect(root.layouts, 1);
    expect(sibling.layouts, 1);
    expect(root.childOffsetOf(sibling), siblingOffset);

    // Changing the pane itself must invalidate its parent's geometry.
    pane.height = 5;
    root.layout(constraints);
    expect(root.layouts, 2);
    expect(root.childOffsetOf(sibling).row, 5);
  });

  test('one fixed axis does not isolate intrinsic or allocated size', () {
    final text = RenderText(text: 'short');
    final pane = RenderSizedBox(width: 6, child: text);
    final sibling = _Leaf();
    final root = _Flex()..replaceAllChildren([pane, sibling]);
    const constraints = CellConstraints(maxCols: 40, maxRows: 20);
    root.layout(constraints);
    text.text = 'one two three four five';
    root.layout(constraints);
    expect(root.layouts, 2);
    expect(root.childOffsetOf(sibling).row, greaterThan(1));
  });

  test('custom parents retain their normal layout behavior', () {
    final text = RenderText(text: 'short');
    final root = _Parent(RenderSizedBox(width: 12, height: 3, child: text));
    const constraints = CellConstraints(maxCols: 40, maxRows: 10);
    root.layout(constraints);
    text.text = 'a much longer piece of content';
    root.layout(constraints);
    expect(root.layouts, 2);
    expect(root.sawPendingLayout, isTrue);
  });

  testWidgets('error scope above an isolated pane contains and recovers', (
    tester,
  ) {
    Widget tree(BoomMode mode) => ErrorBoundary(
      rethrowContained: false,
      child: Column(
        children: [
          SizedBox(width: 28, height: 5, child: Boom(mode: mode)),
          const Text('sibling'),
        ],
      ),
    );
    tester.pumpWidget(tree(BoomMode.healthy));
    tester.pumpWidget(tree(BoomMode.layout));
    expect(
      tester.renderToString(size: const CellSize(30, 8)),
      contains('layout-boom'),
    );
    tester.pumpWidget(tree(BoomMode.healthy));
    final result = tester.renderToString(size: const CellSize(30, 8));
    expect(result, contains('healthy###'));
    expect(result, contains('sibling'));
    expect(result, isNot(contains('layout-boom')));
  });

  test('moving a dirty pane uses its new parent constraints', () {
    final text = RenderText(text: 'short');
    final pane = RenderSizedBox(width: 20, height: 3, child: text);
    final first = _Flex()..replaceAllChildren([pane]);
    final second = _Flex();
    first.layout(const CellConstraints(maxCols: 30, maxRows: 10));
    text.text = 'much longer content that needs new wrapping';
    first.replaceAllChildren([]);
    second.replaceAllChildren([pane]);
    first.layout(const CellConstraints(maxCols: 30, maxRows: 10));
    second.layout(const CellConstraints(maxCols: 8, maxRows: 10));
    expect(pane.size.cols, 8);
    expect(text.size.cols, 8);
  });

  testWidgets('first-error recovery recomputes ancestor sibling positions', (
    tester,
  ) {
    Widget tree(BoomMode mode) => Column(
      children: [
        ErrorBoundary(
          rethrowContained: false,
          child: SizedBox(width: 12, height: 4, child: Boom(mode: mode)),
        ),
        const Text('after'),
      ],
    );
    tester.pumpWidget(tree(BoomMode.layout));
    tester.render(size: const CellSize(20, 8));
    tester.pumpWidget(tree(BoomMode.healthy));
    final lines = tester
        .renderToString(size: const CellSize(20, 8))
        .split('\n');
    expect(lines[4].trim(), 'after');
    expect(lines[1], isNot(contains('after')));
  });

  testWidgets('intrinsic height follows multiline changes through wrappers', (
    tester,
  ) {
    Widget tree(String text) => SizedBox(
      width: 6,
      child: IntrinsicHeight(
        child: Padding(padding: const EdgeInsets.all(0), child: Text(text)),
      ),
    );
    tester.pumpWidget(tree('aa'));
    tester.pumpWidget(tree('aa\nbb\ncc'));
    expect(tester.renderToString(size: const CellSize(10, 4)), contains('cc'));
  });

  test('incremental cells and geometry match forced layout over mutations', () {
    (_Flex, List<RenderText>, List<RenderSizedBox>) scene() {
      final texts = List.generate(12, (i) => RenderText(text: 'pane $i'));
      final panes = [
        for (final text in texts)
          RenderSizedBox(width: 16, height: 3, child: text),
      ];
      return (_Flex()..replaceAllChildren(panes), texts, panes);
    }

    final incrementalScene = scene();
    final fullScene = scene();
    final random = Random(251);
    for (var step = 0; step < 160; step++) {
      final index = random.nextInt(12);
      final text = List.filled(
        1 + random.nextInt(18),
        step.isEven ? 'hello 世界' : 'a\nbc',
      ).join(' ');
      final height = 1 + random.nextInt(5);
      final width = 8 + random.nextInt(16);
      for (final (root, texts, panes) in [incrementalScene, fullScene]) {
        texts[index].text = text;
        if (step % 7 == 0) panes[index].height = height;
        if (step % 11 == 0) panes[index].width = width;
        if (step % 13 == 0) {
          root.replaceAllChildren(
            step.isEven ? panes : panes.reversed.toList(),
          );
        }
      }
      final viewport = CellSize(step % 9 == 0 ? 14 : 30, 60);
      final constraints = CellConstraints.loose(viewport);
      incrementalScene.$1.layout(constraints);
      final incremental = CellBuffer(viewport);
      incrementalScene.$1.paint(incremental, CellOffset.zero);

      void dirty(RenderObject node) {
        node.markNeedsLayout();
        node.visitRenderChildren(dirty);
      }

      dirty(fullScene.$1);
      fullScene.$1.layout(constraints);
      final full = CellBuffer(viewport);
      fullScene.$1.paint(full, CellOffset.zero);
      expect(
        [for (final pane in incrementalScene.$3) pane.screenGeometry()],
        [for (final pane in fullScene.$3) pane.screenGeometry()],
        reason: 'geometry at mutation $step',
      );
      expect(
        [
          for (var y = 0; y < viewport.rows; y++)
            for (var x = 0; x < viewport.cols; x++) incremental.atColRow(x, y),
        ],
        [
          for (var y = 0; y < viewport.rows; y++)
            for (var x = 0; x < viewport.cols; x++) full.atColRow(x, y),
        ],
        reason: 'cells at mutation $step',
      );
    }
  });
}
