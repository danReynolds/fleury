// Effect chains: fade / slide / flash and composition, driven by the
// .animate() entry point. FakeClock via FleuryTester.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

RgbColor? _fgAt(FleuryTester tester, int col, int row, {CellSize? size}) {
  final fg = tester
      .render(size: size ?? const CellSize(10, 1))
      .atColRow(col, row)
      .style
      .foreground;
  return fg is RgbColor ? fg : null;
}

CellRole _roleAt(FleuryTester tester, int col, int row, {CellSize? size}) =>
    tester.render(size: size ?? const CellSize(10, 1)).atColRow(col, row).role;

void main() {
  group('fadeIn', () {
    testWidgets('RGB text fades from the surface color up to its own', (
      tester,
    ) {
      tester.pumpWidget(
        const Text('hi', style: CellStyle(foreground: RgbColor(200, 100, 50)))
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .fadeIn(),
      );
      // First frame: progress 0 → fully faded into black surface.
      expect(_fgAt(tester, 0, 0), const RgbColor(0, 0, 0));

      tester.pump(const Duration(milliseconds: 50));
      final mid = _fgAt(tester, 0, 0)!;
      expect(mid.r, inExclusiveRange(0, 200));

      tester.pump(const Duration(milliseconds: 100));
      expect(_fgAt(tester, 0, 0), const RgbColor(200, 100, 50));
    });
  });

  group('slideIn', () {
    testWidgets('content arrives at its place by the end', (tester) {
      tester.pumpWidget(
        const Text('X', style: CellStyle(foreground: RgbColor(255, 255, 255)))
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .slideIn(from: Edge.right, distance: 3),
      );
      // First frame: displaced 3 cells to the right, so column 0 empty.
      expect(_roleAt(tester, 0, 0), CellRole.empty);
      expect(_roleAt(tester, 3, 0), CellRole.leading);

      tester.pump(const Duration(milliseconds: 100));
      // Settled in place at column 0.
      expect(_roleAt(tester, 0, 0), CellRole.leading);
    });
  });

  group('flash', () {
    testWidgets('peaks toward the flash color mid-animation then '
        'returns', (tester) {
      const base = RgbColor(100, 100, 100);
      tester.pumpWidget(
        const Text('!', style: CellStyle(foreground: base))
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .flash(color: const RgbColor(255, 0, 0)),
      );
      // t=0: at base.
      expect(_fgAt(tester, 0, 0), base);

      // Mid (~t=0.5): pushed toward red.
      tester.pump(const Duration(milliseconds: 50));
      expect(_fgAt(tester, 0, 0)!.r, greaterThan(base.r));

      // End (t=1): back to base.
      tester.pump(const Duration(milliseconds: 50));
      expect(_fgAt(tester, 0, 0), base);
    });
  });

  group('composition', () {
    testWidgets('fadeIn + slideIn run in parallel', (tester) {
      tester.pumpWidget(
        const Text('go', style: CellStyle(foreground: RgbColor(0, 200, 0)))
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .fadeIn()
            .slideIn(from: Edge.left, distance: 2),
      );
      // Start: faded (black) AND displaced left (col 0 empty since text
      // shifted off the left edge).
      expect(_roleAt(tester, 0, 0), CellRole.empty);

      tester.pump(const Duration(milliseconds: 100));
      // End: in place at col 0, full color.
      expect(_fgAt(tester, 0, 0), const RgbColor(0, 200, 0));
    });
  });

  group('AnimationPolicy.disabled', () {
    testWidgets('entrance is instant — no animation, final state on '
        'first frame', (tester) {
      tester.pumpWidget(
        const Text(
          'z',
          style: CellStyle(foreground: RgbColor(10, 20, 30)),
        ).animate().fadeIn(),
      );
      // Disabled policy snaps the driving Animation to its end, so the
      // child appears at full color immediately.
      expect(_fgAt(tester, 0, 0), const RgbColor(10, 20, 30));
    }, animationPolicy: AnimationPolicy.disabled);
  });

  group('scheduler', () {
    testWidgets('settles and releases the ticker', (tester) {
      tester.pumpWidget(
        const Text('a', style: CellStyle(foreground: RgbColor(1, 2, 3)))
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .fadeIn(),
      );
      expect(tester.scheduler.activeTickerCount, 1);
      tester.pump(const Duration(milliseconds: 200));
      expect(tester.scheduler.activeTickerCount, 0);
    });
  });
}
