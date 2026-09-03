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
//
// Every case runs on BOTH surfaces through `testWidgetsOnBothTextPolicies`,
// which sets the tester's own `textPolicy` — the surface knob production
// resolves from the width probe. It used to be reached by hand-wrapping each
// subject in a MediaQuery, which is why this file was the only one in the
// suite that ever left spec (the launch audit's D2).

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

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

/// Picks the expectation for the surface under test.
String _perPolicy(
  TextPresentationPolicy policy, {
  required String spec,
  required String wide,
}) => policy == TextPresentationPolicy.spec ? spec : wide;

void main() {
  group('scratch-buffer replay never re-measures', () {
    testWidgetsOnBothTextPolicies('ScrollView viewport', (tester, policy) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        const SizedBox(
          width: 8,
          height: 3,
          child: ScrollView(child: Text('─X')),
        ),
      );
      expect(
        _row(tester.render(size: size)),
        _perPolicy(policy, spec: '─X......', wide: '─>X.....'),
        reason:
            'the viewport replay must carry the continuation cell the child '
            'painted, not re-derive the width at the destination',
      );
    }, viewportSize: const CellSize(8, 3));

    testWidgetsOnBothTextPolicies('Flex clipping an overflowing child', (
      tester,
      policy,
    ) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 1,
          child: Row(children: <Widget>[Text('─X'), Text('YZ')]),
        ),
      );
      expect(
        _row(tester.render(size: size), cols: 3),
        _perPolicy(policy, spec: '─XY', wide: '─>X'),
        reason: 'the overflow clip path replays cells, it does not re-measure',
      );
    }, viewportSize: const CellSize(8, 3));

    testWidgetsOnBothTextPolicies('a cell effect layer', (tester, policy) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        Animate(
          trigger: 0,
          effects: <Effect>[Effects.fadeIn()],
          child: const Text('─X'),
        ),
      );
      expect(
        _row(tester.render(size: size)),
        _perPolicy(policy, spec: '─X......', wide: '─>X.....'),
        reason: 'the composite loop replays painted cells verbatim',
      );
    }, viewportSize: const CellSize(8, 3));

    testWidgetsOnBothTextPolicies('a clipped effect layer', (tester, policy) {
      const size = CellSize(8, 3);
      tester.pumpWidget(
        Animate(
          trigger: 0,
          effects: <Effect>[Effects.expand()],
          child: const Text('─X'),
        ),
      );
      expect(
        _row(tester.render(size: size)),
        _perPolicy(policy, spec: '─X......', wide: '─>X.....'),
        reason: 'the clip composite replays painted cells verbatim',
      );
    }, viewportSize: const CellSize(8, 3));

    testWidgetsOnBothTextPolicies(
      'a Container merging its background back in',
      (tester, policy) {
        const size = CellSize(8, 3);
        tester.pumpWidget(
          const SizedBox(
            width: 4,
            height: 1,
            child: Container(color: AnsiColor(4), child: Text('─X')),
          ),
        );
        final buffer = tester.render(size: size);
        expect(
          _row(buffer, cols: 4),
          _perPolicy(policy, spec: '─X  ', wide: '─>X '),
          reason: 'the box fills the columns the text does not',
        );
        expect(
          buffer.atColRow(1, 0).style.background,
          const AnsiColor(4),
          reason:
              'the second column of the pair takes the same background as the '
              'leading cell (on spec it is the second glyph; on an '
              'ambiguous-wide surface it is the continuation half)',
        );
      },
      viewportSize: const CellSize(8, 3),
    );
  });

  group('framework glyphs measure with the surface policy', () {
    testWidgetsOnBothTextPolicies(
      'a border reserves what its glyphs actually draw',
      (tester, policy) {
        const size = CellSize(12, 3);
        tester.pumpWidget(
          const SizedBox(
            width: 12,
            height: 3,
            child: Container(border: BoxBorder(), child: Text('ab')),
          ),
        );
        final buffer = tester.render(size: size);
        expect(
          _row(buffer),
          _perPolicy(policy, spec: '┌──────────┐', wide: '┌>─>─>─>─>┐>'),
          reason:
              'an ambiguous-wide terminal draws every box-drawing glyph two '
              'cells wide, so the frame occupies two columns per edge',
        );
        expect(
          _row(buffer, row: 1).substring(0, 2),
          _perPolicy(policy, spec: '│a', wide: '│>'),
          reason: 'the left edge holds both halves of its own glyph',
        );
      },
      viewportSize: const CellSize(12, 3),
    );

    testWidgetsOnBothTextPolicies(
      'the scrollbar gutter widens with its glyphs',
      (tester, policy) {
        const size = CellSize(10, 3);
        tester.pumpWidget(
          const SizedBox(
            width: 10,
            height: 3,
            child: ScrollView(scrollbar: true, child: Text('abcdefghi')),
          ),
        );
        expect(
          _row(tester.render(size: size)),
          _perPolicy(policy, spec: 'abcdefghi█', wide: 'abcdefgh█>'),
          reason: 'a two-cell thumb needs a two-column gutter',
        );
      },
      viewportSize: const CellSize(10, 3),
    );

    testWidgetsOnBothTextPolicies('an ellipsis reserves what it measures', (
      tester,
      policy,
    ) {
      const size = CellSize(6, 1);
      tester.pumpWidget(
        const SizedBox(
          width: 6,
          height: 1,
          child: Text(
            'abcdefgh',
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      expect(
        _row(tester.render(size: size)),
        _perPolicy(policy, spec: 'abcde…', wide: 'abcd…>'),
        reason:
            'the ellipsis draws two cells on an ambiguous-wide surface, so '
            'the content must give up two columns for it — not one',
      );
    }, viewportSize: const CellSize(6, 1));
  });
}
