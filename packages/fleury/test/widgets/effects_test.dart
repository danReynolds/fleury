// Effect chains: fade / slide / flash and composition, driven by the
// .animate() entry point. FakeClock via FleuryTester.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

RgbColor? _fgAt(FleuryTester tester, int col, int row, {CellSize? size}) {
  final fg = tester
      .render(size: size ?? const CellSize(10, 1))
      .atColRow(col, row)
      .style
      .foreground;
  return fg is RgbColor ? fg : null;
}

Cell _cellAt(FleuryTester tester, int col, int row, {CellSize? size}) =>
    tester.render(size: size ?? const CellSize(10, 1)).atColRow(col, row);

CellRole _roleAt(FleuryTester tester, int col, int row, {CellSize? size}) =>
    _cellAt(tester, col, row, size: size).role;

void _tap(FleuryTester tester, int col, int row) {
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.down,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.up,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
}

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

    testWidgets(
      'background-only cells remain opaque and interpolate throughout fade',
      (tester) {
        const surface = RgbColor(10, 20, 30);
        const background = RgbColor(110, 120, 130);
        tester.pumpWidget(
          Stack(
            children: [
              const Text(
                '#',
                style: CellStyle(foreground: RgbColor(255, 255, 255)),
              ),
              const Container(width: 1, height: 1, color: background)
                  .animate(
                    curve: Curves.linear,
                    duration: const Duration(milliseconds: 100),
                  )
                  .fadeIn(surface: surface),
            ],
          ),
        );

        tester.pump(const Duration(milliseconds: 20));
        var cell = _cellAt(tester, 0, 0);
        expect(cell.role, CellRole.leading);
        expect(
          cell.grapheme,
          ' ',
          reason: 'the filled cell must cover the distinct content underneath',
        );
        expect(cell.style.background, const RgbColor(30, 40, 50));

        tester.pump(const Duration(milliseconds: 30));
        cell = _cellAt(tester, 0, 0);
        expect(cell.grapheme, ' ');
        expect(
          cell.style.background,
          const RgbColor(60, 70, 80),
          reason: 'background color must fade independently of foreground',
        );
      },
    );

    testWidgets('RGB background survives coarse non-RGB foreground fade', (
      tester,
    ) {
      const surface = RgbColor(0, 0, 0);
      const background = RgbColor(100, 80, 60);
      tester.pumpWidget(
        const Text(
              'A',
              style: CellStyle(
                foreground: AnsiColor(2),
                background: background,
              ),
            )
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .fadeIn(surface: surface),
      );

      tester.pump(const Duration(milliseconds: 20));
      var cell = _cellAt(tester, 0, 0);
      expect(cell.role, CellRole.leading);
      expect(
        cell.style.foreground,
        const RgbColor(20, 16, 12),
        reason: 'the coarse-path glyph stays hidden against its background',
      );
      expect(cell.style.background, const RgbColor(20, 16, 12));

      tester.pump(const Duration(milliseconds: 30));
      cell = _cellAt(tester, 0, 0);
      expect(cell.style.foreground, const AnsiColor(2));
      expect(cell.style.background, const RgbColor(50, 40, 30));
      expect(cell.style.dim, isTrue);
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

    testWidgets('default distance advances once per child-width cell', (
      tester,
    ) {
      tester.pumpWidget(
        const Text('ABCD')
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .slideIn(from: Edge.right),
      );

      String frame() {
        final buffer = tester.render(size: const CellSize(8, 1));
        return List.generate(8, (col) {
          final cell = buffer.atColRow(col, 0);
          return cell.role == CellRole.leading ? cell.grapheme! : ' ';
        }).join();
      }

      expect(frame(), '    ABCD');
      tester.pump(const Duration(milliseconds: 25));
      expect(frame(), '   ABCD ');
      tester.pump(const Duration(milliseconds: 25));
      expect(frame(), '  ABCD  ');
      tester.pump(const Duration(milliseconds: 25));
      expect(frame(), ' ABCD   ');
      tester.pump(const Duration(milliseconds: 25));
      expect(frame(), 'ABCD    ');
    });

    testWidgets('visible geometry follows the translation inside its hit box', (
      tester,
    ) {
      var taps = 0;
      tester.pumpWidget(
        Semantics(
              id: const SemanticNodeId('moving-action'),
              role: SemanticRole.button,
              label: 'Moving action',
              actions: const {SemanticAction.activate},
              child: GestureDetector(
                onTap: () => taps++,
                child: const Text('ABCD'),
              ),
            )
            .animate(
              curve: Curves.linear,
              duration: const Duration(milliseconds: 100),
            )
            .slideIn(from: Edge.right),
      );

      tester.render(size: const CellSize(8, 1));
      var node = tester.semantics().nodeById(
        const SemanticNodeId('moving-action'),
      );
      expect(node?.bounds, isNull, reason: 'the start is outside its hit box');
      _tap(tester, 4, 0);
      expect(taps, 0, reason: 'paint overflow must not enlarge the hit box');

      tester.pump(const Duration(milliseconds: 50));
      tester.render(size: const CellSize(8, 1));
      node = tester.semantics().nodeById(const SemanticNodeId('moving-action'));
      expect(node?.bounds, CellRect.fromLTWH(2, 0, 2, 1));
      _tap(tester, 2, 0);
      expect(taps, 1, reason: 'the visible in-bounds portion is interactive');
      _tap(tester, 4, 0);
      expect(taps, 1, reason: 'overflow remains outside the stable hit box');
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

    testWidgets('trigger rests on mount and replays for each changed token', (
      tester,
    ) {
      const base = RgbColor(100, 100, 100);

      Widget build(int revision) =>
          const Text('!', style: CellStyle(foreground: base))
              .animate(
                trigger: revision,
                curve: Curves.linear,
                duration: const Duration(milliseconds: 100),
              )
              .flash(color: const RgbColor(255, 0, 0));

      tester.pumpWidget(build(0));
      expect(_fgAt(tester, 0, 0), base);
      expect(
        tester.scheduler.activeTickerCount,
        0,
        reason: 'a trigger-driven effect does not play on mount',
      );

      tester.pumpWidget(build(1));
      expect(_fgAt(tester, 0, 0), base, reason: 'replay starts at t=0');
      expect(tester.scheduler.activeTickerCount, 1);
      tester.pump(const Duration(milliseconds: 50));
      expect(_fgAt(tester, 0, 0)!.r, greaterThan(base.r));
      tester.pump(const Duration(milliseconds: 50));
      expect(_fgAt(tester, 0, 0), base);

      tester.pumpWidget(build(1));
      expect(
        tester.scheduler.activeTickerCount,
        0,
        reason: 'rebuilding with the same token is not a new event',
      );

      tester.pumpWidget(build(2));
      tester.pump(const Duration(milliseconds: 50));
      expect(_fgAt(tester, 0, 0)!.r, greaterThan(base.r));
    });

    testWidgets('a new trigger restarts an in-flight effect', (tester) {
      const base = RgbColor(100, 100, 100);

      Widget build(int revision) =>
          const Text('!', style: CellStyle(foreground: base))
              .animate(
                trigger: revision,
                curve: Curves.linear,
                duration: const Duration(milliseconds: 100),
              )
              .flash(color: const RgbColor(255, 0, 0));

      tester.pumpWidget(build(0));
      tester.pumpWidget(build(1));
      tester.pump(const Duration(milliseconds: 50));
      expect(_fgAt(tester, 0, 0)!.r, greaterThan(base.r));

      tester.pumpWidget(build(2));
      expect(
        _fgAt(tester, 0, 0),
        base,
        reason: 'the latest event restarts progress at the beginning',
      );
      tester.pump(const Duration(milliseconds: 50));
      expect(_fgAt(tester, 0, 0)!.r, greaterThan(base.r));
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

    testWidgets('repeat can start and stop after mount', (tester) {
      Widget build(bool repeat) =>
          const Text('a', style: CellStyle(foreground: RgbColor(1, 2, 3)))
              .animate(
                repeat: repeat,
                curve: Curves.linear,
                duration: const Duration(milliseconds: 100),
              )
              .flash();

      tester.pumpWidget(build(false));
      tester.pump(const Duration(milliseconds: 100));
      expect(tester.scheduler.activeTickerCount, 0);

      tester.pumpWidget(build(true));
      expect(tester.scheduler.activeTickerCount, 1);

      tester.pumpWidget(build(false));
      expect(tester.scheduler.activeTickerCount, 0);
      expect(_fgAt(tester, 0, 0), const RgbColor(1, 2, 3));
    });
  });
}
