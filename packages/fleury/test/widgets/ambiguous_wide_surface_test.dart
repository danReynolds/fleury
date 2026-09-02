// RFC 0019 — the same widget on a spec surface and on an ambiguous-wide one.
//
// Two invariants live here, both from the launch audit's 4.a:
//
//   1. A scratch-buffer replay COPIES cells. Every widget that paints its
//      child into a scratch buffer and composites the result (ScrollView,
//      Flex under overflow, the effect layers, Container's background merge)
//      must carry the source cell's width role across verbatim. Re-measuring
//      at the destination lets the destination disagree with the buffer the
//      cells were painted into, which severs wide pairs.
//   2. Glyphs the framework itself draws — border edges, the scrollbar
//      gutter, the ellipsis — are measured with the ACTIVE surface policy,
//      and the geometry reserved for them uses the same measurement.
//
// `─`, `│`, `█` and `…` are East Asian Ambiguous (UAX #11): one cell under
// the spec policy, two on a terminal whose probe measured ambiguous glyphs
// wide — roughly 19 of 30 surveyed terminals, including the macOS, GNOME and
// VS Code defaults.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// A surface whose probe measured ambiguous glyphs two cells wide.
const _ambiguousWide = TextPresentationPolicy(widths: CellWidthPolicy.cjk);

Widget _onSurface(TextPresentationPolicy policy, CellSize size, Widget child) =>
    MediaQuery(
      data: MediaQueryData(
        size: size,
        capabilities: SurfaceCapabilities(textPolicy: policy),
      ),
      child: child,
    );

/// Row [row] as a compact string: a leading cell shows its grapheme, a
/// continuation `>`, an empty cell `.`, an image overlay `#`.
String _row(CellBuffer buffer, {int row = 0, int? cols}) {
  final sb = StringBuffer();
  for (var c = 0; c < (cols ?? buffer.size.cols); c++) {
    final cell = buffer.atColRow(c, row);
    sb.write(switch (cell.role) {
      CellRole.leading => cell.grapheme,
      CellRole.continuation => '>',
      CellRole.empty => '.',
      CellRole.overlay => '#',
    });
  }
  return sb.toString();
}

void main() {
  group('scratch-buffer replay never re-measures', () {
    testWidgets('ScrollView viewport', (tester) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        _onSurface(
          _ambiguousWide,
          size,
          const SizedBox(
            width: 8,
            height: 3,
            child: ScrollView(child: Text('─X')),
          ),
        ),
      );
      expect(
        _row(tester.render(size: size)),
        '─>X.....',
        reason:
            'the viewport replay must carry the continuation cell the child '
            'painted, not re-derive the width at the destination',
      );
    });

    testWidgets('Flex clipping an overflowing child', (tester) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        _onSurface(
          _ambiguousWide,
          size,
          const SizedBox(
            width: 4,
            height: 1,
            child: Row(children: <Widget>[Text('─X'), Text('YZ')]),
          ),
        ),
      );
      expect(
        _row(tester.render(size: size), cols: 3),
        '─>X',
        reason: 'the overflow clip path replays cells, it does not re-measure',
      );
    });

    testWidgets('a cell effect layer', (tester) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        _onSurface(
          _ambiguousWide,
          size,
          Animate(
            trigger: 0,
            effects: <Effect>[Effects.fadeIn()],
            child: const Text('─X'),
          ),
        ),
      );
      expect(
        _row(tester.render(size: size)),
        '─>X.....',
        reason: 'the composite loop replays painted cells verbatim',
      );
    });

    testWidgets('a clipped effect layer', (tester) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        _onSurface(
          _ambiguousWide,
          size,
          Animate(
            trigger: 0,
            effects: <Effect>[Effects.expand()],
            child: const Text('─X'),
          ),
        ),
      );
      expect(
        _row(tester.render(size: size)),
        '─>X.....',
        reason: 'the clip composite replays painted cells verbatim',
      );
    });

    testWidgets('a Container merging its background back in', (tester) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        _onSurface(
          _ambiguousWide,
          size,
          const SizedBox(
            width: 4,
            height: 1,
            child: Container(color: AnsiColor(4), child: Text('─X')),
          ),
        ),
      );
      final buffer = tester.render(size: size);
      expect(_row(buffer, cols: 4), '─>X ', reason: 'the box fills col 3');
      expect(
        buffer.atColRow(1, 0).style.background,
        const AnsiColor(4),
        reason:
            'the continuation half of the pair takes the same background as '
            'its leading cell',
      );
    });
  });

  group('framework glyphs measure with the surface policy', () {
    testWidgets('a border reserves what its glyphs actually draw', (tester) {
      const size = CellSize(12, 3);
      Widget boxed() => const SizedBox(
        width: 12,
        height: 3,
        child: Container(border: BoxBorder(), child: Text('ab')),
      );

      tester.pumpWidget(_onSurface(TextPresentationPolicy.spec, size, boxed()));
      expect(
        _row(tester.render(size: size)),
        '┌──────────┐',
        reason: 'spec: one column per edge, unchanged',
      );

      tester.pumpWidget(_onSurface(_ambiguousWide, size, boxed()));
      final buffer = tester.render(size: size);
      expect(
        _row(buffer),
        '┌>─>─>─>─>┐>',
        reason:
            'an ambiguous-wide terminal draws every box-drawing glyph two '
            'cells wide, so the frame occupies two columns per edge',
      );
      expect(
        _row(buffer, row: 1).substring(0, 2),
        '│>',
        reason: 'the left edge holds both halves of its own glyph',
      );
    });

    testWidgets('the scrollbar gutter widens with its glyphs', (tester) {
      const size = CellSize(10, 3);
      Widget bar() => const SizedBox(
        width: 10,
        height: 3,
        child: ScrollView(scrollbar: true, child: Text('abcdefghi')),
      );

      tester.pumpWidget(_onSurface(TextPresentationPolicy.spec, size, bar()));
      expect(
        _row(tester.render(size: size)),
        'abcdefghi█',
        reason: 'spec: a one-column gutter, unchanged',
      );

      tester.pumpWidget(_onSurface(_ambiguousWide, size, bar()));
      expect(
        _row(tester.render(size: size)),
        'abcdefgh█>',
        reason: 'a two-cell thumb needs a two-column gutter',
      );
    });

    testWidgets('an ellipsis reserves what it measures', (tester) {
      const size = CellSize(6, 1);
      Widget clipped() => const SizedBox(
        width: 6,
        height: 1,
        child: Text(
          'abcdefgh',
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      );

      tester.pumpWidget(
        _onSurface(TextPresentationPolicy.spec, size, clipped()),
      );
      expect(_row(tester.render(size: size)), 'abcde…');

      tester.pumpWidget(_onSurface(_ambiguousWide, size, clipped()));
      expect(
        _row(tester.render(size: size)),
        'abcd…>',
        reason:
            'the ellipsis draws two cells on this surface, so the content '
            'must give up two columns for it — not one',
      );
    });
  });
}
