// Second-cut effects: wipe in/out, expand/shrink, shimmer,
// pulse, shake.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

import '../support/render_fixtures.dart';

String _row(FleuryTester tester, int cols, {int row = 0, int? height}) {
  final buf = tester.render(size: CellSize(cols, height ?? row + 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    final cell = buf.atColRow(c, row);
    sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
  }
  return sb.toString().trimRight();
}

void main() {
  test('Effects exposes the canonical built-in vocabulary', () {
    final effects = <Effect>[
      Effects.fadeIn(),
      Effects.fadeOut(),
      Effects.slideIn(),
      Effects.slideOut(),
      Effects.wipeIn(),
      Effects.wipeOut(),
      Effects.expand(),
      Effects.shrink(),
      Effects.flash(),
      Effects.shimmer(),
      Effects.pulse(),
      Effects.shake(),
    ];

    expect(effects, hasLength(12));
  });

  group('wipeIn', () {
    testWidgets('wipes columns into view left→right', (tester) {
      tester.pumpWidget(
        const Text('hello')
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .wipeIn(from: Edge.left),
      );
      // t=0: nothing is visible.
      expect(_row(tester, 6), '');
      // ~t=0.6: first 3 of 5 cols.
      tester.pump(const Duration(milliseconds: 60));
      expect(_row(tester, 6), 'hel');
      // end: full.
      tester.pump(const Duration(milliseconds: 100));
      expect(_row(tester, 6), 'hello');
    });
  });

  group('expand / shrink', () {
    testWidgets('expand vertical grows the box height (layout '
        'reflows)', (tester) {
      // A 2-line child inside a Column; expanding clips its height.
      tester.pumpWidget(
        Column(
          children: [
            const Column(children: [Text('A'), Text('B')])
                .animate(
                  curve: Curves.linear,
                  duration: const Duration(milliseconds: 100),
                )
                .expand(axis: Axis.vertical),
            const Text('after'),
          ],
        ),
      );
      // t=0: child height 0 → only "after" shows on row 0.
      expect(_row(tester, 6, row: 0, height: 3), 'after');

      tester.pump(const Duration(milliseconds: 100));
      // Fully expanded: A, B, then after.
      expect(_row(tester, 6, row: 0, height: 3), 'A');
      expect(_row(tester, 6, row: 1, height: 3), 'B');
      expect(_row(tester, 6, row: 2, height: 3), 'after');
    });

    testWidgets('shrink vertical reduces height before reaching zero', (
      tester,
    ) {
      tester.pumpWidget(
        Column(
          children: [
            const Column(children: [Text('A'), Text('B'), Text('C'), Text('D')])
                .animate(
                  curve: Curves.linear,
                  duration: const Duration(milliseconds: 100),
                )
                .shrink(axis: Axis.vertical),
            const Text('after'),
          ],
        ),
      );
      expect(_row(tester, 6, row: 4, height: 5), 'after');

      tester.pump(const Duration(milliseconds: 50));
      expect(_row(tester, 6, row: 0, height: 3), 'A');
      expect(_row(tester, 6, row: 1, height: 3), 'B');
      expect(_row(tester, 6, row: 2, height: 3), 'after');

      tester.pump(const Duration(milliseconds: 50));
      expect(_row(tester, 6, row: 0, height: 1), 'after');
    });

    testWidgets('alignment chooses the edge revealed by expand', (tester) {
      tester.pumpWidget(
        Column(
          children: [
            const Column(children: [Text('A'), Text('B'), Text('C'), Text('D')])
                .animate(
                  curve: Curves.linear,
                  duration: const Duration(milliseconds: 100),
                )
                .expand(axis: Axis.vertical, alignment: Alignment.bottomLeft),
            const Text('after'),
          ],
        ),
      );

      tester.pump(const Duration(milliseconds: 25));
      expect(_row(tester, 6, row: 0, height: 2), 'D');
      expect(_row(tester, 6, row: 1, height: 2), 'after');
    });

    testWidgets('vertical clipping carries a partial true-pixel image', (
      tester,
    ) {
      tester.pumpWidget(
        const ImageLeaf()
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .expand(axis: Axis.vertical),
      );

      tester.pump(const Duration(milliseconds: 50));
      final partial = tester.render(size: const CellSize(4, 2));
      final clipped = partial.imagePlacements.single;
      expect(
        [clipped.col, clipped.row, clipped.cols, clipped.rows],
        [0, 0, 4, 1],
      );
      expect([clipped.boxCols, clipped.boxRows], [4, 2]);
      expect([clipped.boxOffsetCol, clipped.boxOffsetRow], [0, 0]);

      tester.pump(const Duration(milliseconds: 50));
      final full = tester.render(size: const CellSize(4, 2));
      final placement = full.imagePlacements.single;
      expect([placement.cols, placement.rows], [4, 2]);
      expect(placement.isClipped, isFalse);
    });

    testWidgets('a fully collapsed box retires semantic bounds', (tester) {
      tester.pumpWidget(
        const Semantics(
              id: SemanticNodeId('collapsing'),
              role: SemanticRole.status,
              label: 'Collapsing',
              child: Text('status'),
            )
            .animate(
              curve: Curves.linear,
              duration: Duration(milliseconds: 100),
            )
            .shrink(axis: Axis.vertical),
      );

      tester.render(size: const CellSize(10, 1));
      var node = tester.semantics().nodeById(
        const SemanticNodeId('collapsing'),
      );
      expect(node?.bounds, CellRect.fromLTWH(0, 0, 6, 1));

      tester.pump(const Duration(milliseconds: 100));
      tester.render(size: const CellSize(10, 1));
      node = tester.semantics().nodeById(const SemanticNodeId('collapsing'));
      expect(node?.bounds, isNull);
    });
  });

  group('slide images', () {
    testWidgets('translation preserves true-pixel image placement', (tester) {
      tester.pumpWidget(
        const ImageLeaf()
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .slideIn(from: Edge.right),
      );

      tester.pump(const Duration(milliseconds: 50));
      final buffer = tester.render(size: const CellSize(8, 2));
      final placement = buffer.imagePlacements.single;
      expect(
        [placement.col, placement.row, placement.cols, placement.rows],
        [2, 0, 4, 2],
      );
      expect([placement.boxCols, placement.boxRows], [4, 2]);
      expect([placement.boxOffsetCol, placement.boxOffsetRow], [0, 0]);
    });
  });

  group('shimmer (looping)', () {
    testWidgets('auto-loops and brightens cells toward the highlight', (
      tester,
    ) {
      tester.pumpWidget(
        const Text('load', style: CellStyle(foreground: RgbColor(80, 80, 80)))
            .animate(duration: const Duration(milliseconds: 200))
            .shimmer(highlight: const RgbColor(255, 255, 255)),
      );
      // Looping effect keeps a ticker alive indefinitely.
      tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.scheduler.activeTickerCount,
        1,
        reason: 'shimmer loops; ticker never settles',
      );
      // Some cell is brighter than the base at some point in the sweep.
      var sawBrighter = false;
      for (var i = 0; i < 12; i++) {
        tester.pump(const Duration(milliseconds: 20));
        final buf = tester.render(size: const CellSize(4, 1));
        for (var c = 0; c < 4; c++) {
          final fg = buf.atColRow(c, 0).style.foreground;
          if (fg is RgbColor && fg.r > 80) sawBrighter = true;
        }
      }
      expect(sawBrighter, isTrue);
    });
  });

  group('pulse (looping)', () {
    testWidgets('auto-loops', (tester) {
      tester.pumpWidget(
        const Text(
          '●',
          style: CellStyle(foreground: RgbColor(200, 0, 0)),
        ).animate(duration: const Duration(milliseconds: 200)).pulse(),
      );
      tester.pump(const Duration(milliseconds: 100));
      expect(tester.scheduler.activeTickerCount, 1);
    });
  });

  group('shake (one-shot)', () {
    testWidgets('settles back to rest by the end', (tester) {
      tester.pumpWidget(
        const Text('!', style: CellStyle(foreground: RgbColor(255, 0, 0)))
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .shake(axis: Axis.horizontal, amplitude: 2),
      );
      tester.pump(const Duration(milliseconds: 100));
      // Settled: glyph back at column 0.
      expect(_row(tester, 6), '!');
      expect(tester.scheduler.activeTickerCount, 0);
    });
  });

  group('AnimationPolicy.disabled', () {
    testWidgets(
      'looping shimmer rests (no ticker)',
      (tester) {
        tester.pumpWidget(
          const Text(
            'x',
            style: CellStyle(foreground: RgbColor(50, 50, 50)),
          ).animate().shimmer(),
        );
        expect(
          tester.scheduler.activeTickerCount,
          0,
          reason: 'disabled policy: loop rests at the first value',
        );
      },
      animationPolicy: AnimationPolicy.disabled,
    );
  });
}
