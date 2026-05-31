// Second-cut effects: reveal/conceal, expand/collapse, shimmer,
// pulse, shake.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

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
  group('reveal', () {
    testWidgets('typewriter: reveals columns left→right', (tester) {
      tester.pumpWidget(
        const Text('hello')
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .reveal(from: Edge.left),
      );
      // t=0: nothing revealed.
      expect(_row(tester, 6), '');
      // ~t=0.6: first 3 of 5 cols.
      tester.pump(const Duration(milliseconds: 60));
      expect(_row(tester, 6), 'hel');
      // end: full.
      tester.pump(const Duration(milliseconds: 100));
      expect(_row(tester, 6), 'hello');
    });
  });

  group('expand / collapse', () {
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
