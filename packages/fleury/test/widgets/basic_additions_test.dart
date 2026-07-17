// Coverage for the late-2.0 ergonomic additions: Text.textAlign,
// SizedBox.expand / .square, Container.margin / .alignment,
// ConstrainedBox, AspectRatio.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void main() {
  group('Text.textAlign', () {
    testWidgets('left (default) pins lines to the start column', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 10, height: 1, child: Text('hi')),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(0, 0).grapheme, 'h');
      expect(buf.atColRow(1, 0).grapheme, 'i');
      // Column 2..9 is empty (no slack distributed).
      expect(buf.atColRow(2, 0).grapheme, isNull);
    });

    testWidgets('center distributes slack evenly', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 10,
          height: 1,
          child: Text('hi', textAlign: TextAlign.center),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      // 8 cells of slack / 2 = 4 leading empty cells.
      expect(buf.atColRow(3, 0).grapheme, isNull);
      expect(buf.atColRow(4, 0).grapheme, 'h');
      expect(buf.atColRow(5, 0).grapheme, 'i');
      expect(buf.atColRow(6, 0).grapheme, isNull);
    });

    testWidgets('right pins lines to the end column', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 10,
          height: 1,
          child: Text('hi', textAlign: TextAlign.right),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(7, 0).grapheme, isNull);
      expect(buf.atColRow(8, 0).grapheme, 'h');
      expect(buf.atColRow(9, 0).grapheme, 'i');
    });

    testWidgets('multi-line alignment aligns each line independently', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 8,
          height: 2,
          child: Text('hi\nthere', textAlign: TextAlign.center),
        ),
      );
      final buf = tester.render(size: const CellSize(8, 2));
      // 'hi' (width 2) centered in 8 → starts at col 3.
      expect(buf.atColRow(3, 0).grapheme, 'h');
      expect(buf.atColRow(4, 0).grapheme, 'i');
      // 'there' (width 5) centered in 8 → 3 slack / 2 = 1 leading.
      expect(buf.atColRow(1, 1).grapheme, 't');
      expect(buf.atColRow(5, 1).grapheme, 'e');
    });
  });

  group('SizedBox.expand', () {
    testWidgets('takes the full parent size on both axes', (tester) {
      tester.pumpWidget(const SizedBox.expand(child: Text('x')));
      final buf = tester.render(size: const CellSize(6, 3));
      // 'x' is at (0,0); the box claims the whole 6x3 area, so the
      // text widget got constraints of 6x3.
      expect(buf.atColRow(0, 0).grapheme, 'x');
    });
  });

  group('SizedBox.square', () {
    testWidgets('produces a 4x4 box for dimension: 4', (tester) {
      tester.pumpWidget(
        const Center(
          child: SizedBox.square(dimension: 4, child: Text('xxxxxxxx')),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 6));
      // 4x4 centered in 10x6 → leading 3 cols / 1 row.
      // 'xxxxxxxx' soft-wraps inside 4-wide → 'xxxx' / 'xxxx'.
      expect(buf.atColRow(3, 1).grapheme, 'x');
      expect(buf.atColRow(6, 1).grapheme, 'x');
      expect(buf.atColRow(3, 2).grapheme, 'x');
    });
  });

  group('Container.margin', () {
    testWidgets('inserts empty cells outside the border', (tester) {
      tester.pumpWidget(
        const Container(
          margin: EdgeInsets.all(1),
          width: 4,
          height: 2,
          color: AnsiColor(2),
        ),
      );
      final buf = tester.render(size: const CellSize(8, 4));
      // Outside the margin (col 0, row 0) has no fill.
      expect(buf.atColRow(0, 0).style.background, isNull);
      // Inside the container, past the margin: filled.
      expect(buf.atColRow(1, 1).style.background, const AnsiColor(2));
    });
  });

  group('Container.alignment', () {
    testWidgets('Alignment.center centres a smaller child', (tester) {
      tester.pumpWidget(
        const Container(
          width: 8,
          height: 3,
          alignment: Alignment.center,
          child: Text('x'),
        ),
      );
      final buf = tester.render(size: const CellSize(8, 3));
      // 'x' should land at the centre column.
      expect(
        buf.atColRow(3, 1).grapheme == 'x' ||
            buf.atColRow(4, 1).grapheme == 'x',
        isTrue,
      );
    });
  });

  group('ConstrainedBox', () {
    testWidgets('minWidth forces the child wider than its natural size', (
      tester,
    ) {
      tester.pumpWidget(
        const Row(
          children: [
            ConstrainedBox(minWidth: 6, child: Text('hi')),
            Text('|'),
          ],
        ),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      // 'hi' takes 2 cells natural. Constrained to min 6 → the box is
      // 6 wide; '|' lands at col 6.
      expect(buf.atColRow(0, 0).grapheme, 'h');
      expect(buf.atColRow(1, 0).grapheme, 'i');
      expect(buf.atColRow(6, 0).grapheme, '|');
    });

    testWidgets('maxWidth clips the child wider than the allowance', (tester) {
      tester.pumpWidget(
        const ConstrainedBox(
          maxWidth: 3,
          child: Text('hello world', softWrap: false),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(0, 0).grapheme, 'h');
      expect(buf.atColRow(2, 0).grapheme, 'l');
      // Beyond col 3 the ConstrainedBox didn't claim → grapheme is null.
      expect(buf.atColRow(3, 0).grapheme, isNull);
    });
  });

  group('AspectRatio', () {
    testWidgets('produces a box whose width = ratio * height', (tester) {
      tester.pumpWidget(
        const AspectRatio(
          aspectRatio: 2.0,
          child: _ColoredBox(color: AnsiColor(4)),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 3));
      // Largest box at 2:1 in 10x3 → height capped at 3, so width = 6.
      expect(buf.atColRow(5, 2).style.background, const AnsiColor(4));
      // Past col 6 has no fill.
      expect(buf.atColRow(6, 2).style.background, isNull);
    });

    testWidgets('caps by the tighter axis when one is the bottleneck', (
      tester,
    ) {
      tester.pumpWidget(
        const AspectRatio(
          aspectRatio: 1.0,
          child: _ColoredBox(color: AnsiColor(5)),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 4));
      // 1:1 in 10x4 → 4x4.
      expect(buf.atColRow(3, 3).style.background, const AnsiColor(5));
      expect(buf.atColRow(4, 3).style.background, isNull);
    });
  });

  group('Spacer', () {
    testWidgets('pushes siblings to opposite ends of a Row', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 10,
          height: 1,
          child: Row(children: [Text('a'), Spacer(), Text('b')]),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(0, 0).grapheme, 'a');
      // The Spacer absorbs the 8 middle cells, pinning 'b' to the last column.
      expect(buf.atColRow(9, 0).grapheme, 'b');
      expect(buf.atColRow(5, 0).grapheme, isNull);
    });

    testWidgets('flex weights split the gap proportionally', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 11,
          height: 1,
          child: Row(
            children: [
              Text('a'),
              Spacer(), // flex 1 → 2 cells
              Text('b'),
              Spacer(flex: 3), // flex 3 → 6 cells
              Text('c'),
            ],
          ),
        ),
      );
      // 3 glyphs + 8 gap cells, split 1:3 → 2 and 6 cells (no remainder).
      final buf = tester.render(size: const CellSize(11, 1));
      expect(buf.atColRow(0, 0).grapheme, 'a');
      expect(buf.atColRow(3, 0).grapheme, 'b');
      expect(buf.atColRow(10, 0).grapheme, 'c');
    });
  });
}

class _ColoredBox extends StatelessWidget {
  const _ColoredBox({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: Container(color: color));
}
