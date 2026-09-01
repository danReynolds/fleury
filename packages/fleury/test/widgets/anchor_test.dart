// Anchor + Follower: a follower positions its child relative to the
// anchor's painted rect, flipping/clamping at screen edges.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Finds the (col, row) of the first cell whose grapheme is [g]. The
/// follower resolves its position at paint time, reading the anchor's
/// rect recorded earlier in the same paint pass (anchors paint before
/// followers above them), so a single render suffices.
({int col, int row})? _find(
  FleuryTester tester,
  String g, {
  required int cols,
  required int rows,
}) {
  final buf = tester.render(size: CellSize(cols, rows));
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if (buf.atColRow(c, r).grapheme == g) return (col: c, row: r);
    }
  }
  return null;
}

void main() {
  testWidgets('follower sits just below the anchor', (tester) {
    final chip = BoundsNotifier();
    tester.pumpWidget(
      Stack(
        children: [
          // Anchor a 4x1 box at (3, 2).
          Padding(
            padding: const EdgeInsets.only(left: 3, top: 2),
            child: BoundsObserver(notifier: chip, child: const Text('AAAA')),
          ),
          BoundsAnchor(notifier: chip, child: const Text('m')),
        ],
      ),
    );
    // Anchor bottom row = 2 + 1 = 3; left = 3 → 'm' at (3, 3).
    expect(_find(tester, 'm', cols: 12, rows: 6), (col: 3, row: 3));
  });

  testWidgets('follower flips above the anchor near the bottom edge', (tester) {
    final chip = BoundsNotifier();
    tester.pumpWidget(
      Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: BoundsObserver(notifier: chip, child: const Text('A')),
          ),
          // A 3-row-tall follower can't fit below an anchor at row 4 in a
          // 6-row screen, so it flips to sit above the anchor.
          BoundsAnchor(
            notifier: chip,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [Text('x'), Text('y'), Text('z')],
            ),
          ),
        ],
      ),
    );
    // Anchor at row 4; flipped above → bottom at row 4, so 'z' at row 3,
    // 'x' at row 1.
    expect(_find(tester, 'x', cols: 8, rows: 6)?.row, 1);
    expect(_find(tester, 'z', cols: 8, rows: 6)?.row, 3);
  });

  testWidgets('follower clamps horizontally to stay on screen', (tester) {
    final chip = BoundsNotifier();
    tester.pumpWidget(
      Stack(
        children: [
          // Anchor near the right edge of an 8-wide screen.
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: BoundsObserver(notifier: chip, child: const Text('A')),
          ),
          BoundsAnchor(notifier: chip, child: const Text('wide')), // 4 wide
        ],
      ),
    );
    // left would be 6, but 6 + 4 > 8 → clamp to 4 so it fits.
    expect(_find(tester, 'w', cols: 8, rows: 3)?.col, 4);
  });

  group('right placement', () {
    testWidgets('sits to the right of the anchor, top-aligned', (tester) {
      final chip = BoundsNotifier();
      tester.pumpWidget(
        Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 1),
              child: BoundsObserver(
                notifier: chip,
                child: const Text('AAA'),
              ), // (2..5, 1)
            ),
            BoundsAnchor(
              notifier: chip,
              alignment: Alignment.topRight,
              anchorAlignment: Alignment.topLeft,
              child: const Text('m'),
            ),
          ],
        ),
      );
      // Right edge of anchor = 2 + 3 = 5; top = 1 → 'm' at (5, 1).
      expect(_find(tester, 'm', cols: 12, rows: 6), (col: 5, row: 1));
    });

    testWidgets('flips to the left when it would overflow the right edge', (
      tester,
    ) {
      final chip = BoundsNotifier();
      tester.pumpWidget(
        Stack(
          children: [
            // Anchor 'A' near the right edge of an 8-wide screen.
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: BoundsObserver(
                notifier: chip,
                child: const Text('A'),
              ), // (6..7)
            ),
            BoundsAnchor(
              notifier: chip,
              alignment: Alignment.topRight,
              anchorAlignment: Alignment.topLeft,
              child: const Text('xyz'), // 3 wide
            ),
          ],
        ),
      );
      // right=7, 7+3 > 8 → flip left of anchor: 6 - 3 = 3.
      expect(_find(tester, 'x', cols: 8, rows: 3)?.col, 3);
    });
  });

  // AnchoredFloat = BoundsAnchor + the pointer barrier that every float owes
  // the app beneath it. Forgetting the barrier is invisible until someone
  // clicks: the float paints over the app, but the app's pointer regions are
  // still registered underneath.
  group('AnchoredFloat', () {
    ({int col, int row})? locate(FleuryTester tester, String g) =>
        _find(tester, g, cols: 12, rows: 6);

    Widget app({
      required BoundsNotifier chip,
      required void Function() onBehind,
      required void Function() onInside,
      void Function()? onOutside,
    }) => Stack(
      children: [
        Column(
          children: [
            BoundsObserver(notifier: chip, child: const Text('A')),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: onBehind,
              child: const SizedBox(width: 6, height: 1, child: Text('behind')),
            ),
          ],
        ),
        // Default bottomLeft: the float lands at (0, 1), two rows above
        // 'behind' — so a tap on 'behind' lands on the barrier, not the float.
        AnchoredFloat(
          notifier: chip,
          onTapOutside: onOutside,
          child: GestureDetector(
            onTap: onInside,
            child: const SizedBox(width: 2, height: 1, child: Text('ok')),
          ),
        ),
      ],
    );

    testWidgets('absorbs a tap that would otherwise hit the app beneath', (
      tester,
    ) {
      var behind = 0;
      var outside = 0;
      final chip = BoundsNotifier();
      tester.pumpWidget(
        app(
          chip: chip,
          onBehind: () => behind++,
          onInside: () {},
          onOutside: () => outside++,
        ),
      );
      tester.render(size: const CellSize(12, 6));
      // 'behind' is on row 3, columns 0..5; the float only covers row 1.
      _tap(tester, 0, 3);
      expect(behind, 0, reason: 'the barrier owns every cell of the slot');
      expect(outside, 1, reason: 'the tap reached onTapOutside instead');
    });

    testWidgets('a tap on the float itself still reaches its own controls', (
      tester,
    ) {
      var inside = 0;
      var outside = 0;
      final chip = BoundsNotifier();
      tester.pumpWidget(
        app(
          chip: chip,
          onBehind: () {},
          onInside: () => inside++,
          onOutside: () => outside++,
        ),
      );
      final at = locate(tester, 'o')!;
      tester.render(size: const CellSize(12, 6));
      _tap(tester, at.col, at.row);
      expect(inside, 1, reason: 'descendants paint later and keep winning');
      expect(outside, 0);
    });

    testWidgets('a null onTapOutside still absorbs (the float stays put)', (
      tester,
    ) {
      var behind = 0;
      final chip = BoundsNotifier();
      tester.pumpWidget(
        app(chip: chip, onBehind: () => behind++, onInside: () {}),
      );
      tester.render(size: const CellSize(12, 6));
      _tap(tester, 0, 3);
      expect(behind, 0, reason: 'absorbed, just inert');
    });
  });
}

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
