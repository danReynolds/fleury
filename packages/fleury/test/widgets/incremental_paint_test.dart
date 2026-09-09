// Incremental paint: carry the previous frame forward, erase what changed, and
// skip the subtrees whose cells are still valid where they sit.
//
// Three things have to be true and none of them is checked anywhere else. The
// mode has to actually skip (a version that quietly repaints everything passes
// every other test in the suite). Output has to match a full repaint, which is
// the one check frame damage cannot make — damage is DERIVED by comparing the
// two buffers, so a subtree that carried stale cells forward leaves a buffer
// that matches what was painted and reports no change. And the erasing has to
// survive the cases that make it hard: a node that moves, and a node that
// shrinks out from over a clean one.
@Tags(['unit'])
library;

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' show FleuryTester;
import 'package:fleury/src/rendering/render_object.dart' show IncrementalPaint;
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/render_fixtures.dart';

/// Paints whatever [glyph] currently says, and never marks itself dirty.
///
/// A render object is not allowed to do this — what it paints has to be routed
/// through an invalidation — and the point of the widget is to prove the
/// verifier notices when one does.
class _Ungoverned extends LeafRenderObjectWidget {
  const _Ungoverned();
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderUngoverned();
}

class _RenderUngoverned extends RenderObject {
  static String glyph = 'a';

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(1, 1));

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) =>
      buffer.writeGrapheme(offset, glyph);
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  void bump() => setState(() => count += 1);
  @override
  Widget build(BuildContext context) => Text('count=$count');
}

/// The rows of [buffer], trailing blanks trimmed.
List<String> _rows(CellBuffer buffer) => [
  for (var row = 0; row < buffer.size.rows; row++)
    [
      for (var col = 0; col < buffer.size.cols; col++)
        buffer.atColRow(col, row).role == CellRole.leading
            ? buffer.atColRow(col, row).grapheme!
            : ' ',
    ].join().trimRight(),
];

String _describeDamage(TuiFrameDamage damage) => switch (damage) {
  FrameUnchanged() => 'unchanged',
  FrameChanged(:final rows, :final bounds) =>
    'changed rows=${(rows.toList()..sort()).join(",")} bounds=$bounds',
  FrameScrolled(:final rows, :final bounds, :final scrollUpRows) =>
    'scrolled $scrollUpRows rows=${(rows.toList()..sort()).join(",")} '
        'bounds=$bounds',
  _ => 'full',
};

void main() {
  group('incremental paint', () {
    setUp(IncrementalPaint.resetCounters);

    testWidgets('an unchanged frame skips instead of repainting', (tester) {
      tester.pumpWidget(
        const Column(children: [Text('alpha'), Text('beta'), Text('gamma')]),
      );
      const size = CellSize(12, 3);
      tester.render(size: size);

      IncrementalPaint.resetCounters();
      final second = tester.render(size: size);

      expect(
        IncrementalPaint.skippedCount,
        greaterThan(0),
        reason:
            'nothing was skipped — the mode is inert and every other '
            'assertion here would be vacuous',
      );
      expect(_rows(second), ['alpha', 'beta', 'gamma']);
    });

    testWidgets('one changed row repaints without disturbing its siblings', (
      tester,
    ) {
      final middle = GlobalKey<_CounterState>();
      tester.pumpWidget(
        Column(
          children: [
            const Text('alpha'),
            _Counter(key: middle),
            const Text('gamma'),
          ],
        ),
      );
      const size = CellSize(12, 3);
      expect(_rows(tester.render(size: size)), ['alpha', 'count=0', 'gamma']);

      middle.currentState!.bump();
      tester.pump();
      IncrementalPaint.resetCounters();
      expect(_rows(tester.render(size: size)), ['alpha', 'count=1', 'gamma']);
      expect(
        IncrementalPaint.skippedCount,
        greaterThan(0),
        reason: 'the unchanged siblings should have been carried forward',
      );
    });

    testWidgets('shrinking text leaves nothing of the longer text behind', (
      tester,
    ) {
      Widget tree(String label) =>
          Column(children: [Text(label), const Text('below')]);
      tester.pumpWidget(tree('a very long line'));
      const size = CellSize(20, 2);
      expect(_rows(tester.render(size: size)), ['a very long line', 'below']);

      tester.pumpWidget(tree('hi'));
      expect(
        _rows(tester.render(size: size)),
        ['hi', 'below'],
        reason: 'the tail of the longer line was not erased',
      );
    });

    testWidgets('a node that moves does not blank what took its place', (
      tester,
    ) {
      // The failure this is here for: erasing a moved node's old rect just
      // before repainting it wipes whatever already painted there this frame.
      Widget tree({required bool swapped}) => Column(
        children: [
          Text(swapped ? 'second' : 'first'),
          Text(swapped ? 'first' : 'second'),
        ],
      );
      tester.pumpWidget(tree(swapped: false));
      const size = CellSize(10, 2);
      expect(_rows(tester.render(size: size)), ['first', 'second']);

      tester.pumpWidget(tree(swapped: true));
      expect(_rows(tester.render(size: size)), ['second', 'first']);
    });

    testWidgets('an overlapping node that shrinks uncovers what is beneath', (
      tester,
    ) {
      // Stack children overlap by construction, so a clean node underneath one
      // that vacates cells has to repaint — the reason damage is a region and
      // not a per-parent "my children never overlap" promise.
      Widget tree({required int coverRows}) => Stack(
        children: [
          const Column(children: [Text('one'), Text('two'), Text('three')]),
          Positioned(
            top: 0,
            left: 0,
            child: Column(
              children: [
                for (var i = 0; i < coverRows; i++) const Text('XXXXX'),
              ],
            ),
          ),
        ],
      );
      const size = CellSize(8, 3);
      tester.pumpWidget(tree(coverRows: 3));
      expect(_rows(tester.render(size: size)), ['XXXXX', 'XXXXX', 'XXXXX']);

      tester.pumpWidget(tree(coverRows: 1));
      expect(
        _rows(tester.render(size: size)),
        ['XXXXX', 'two', 'three'],
        reason: 'the rows the cover vacated still show the cover',
      );
    });
  });

  group('inline images', () {
    // Placements live OFF the cell grid, so a carried frame brings the previous
    // frame's placements across with its cells and no cell comparison — the
    // full-repaint oracle included, until it was taught to look — can tell that
    // one is stale. The presenter draws from the placement list.
    testWidgets('placements do not accumulate frame over frame', (tester) {
      tester.pumpWidget(
        const Column(children: [Text('a'), ImageLeaf(), Text('b')]),
      );
      const size = CellSize(8, 5);
      for (var i = 0; i < 5; i++) {
        expect(
          tester.render(size: size).imagePlacements.length,
          1,
          reason: 'frame $i',
        );
      }
    });

    testWidgets('a removed image leaves no placement behind', (tester) {
      Widget tree({required bool withImage}) => Column(
        children: [
          const Text('a'),
          if (withImage) const ImageLeaf(),
          const Text('b'),
        ],
      );
      const size = CellSize(8, 5);
      tester.pumpWidget(tree(withImage: true));
      expect(tester.render(size: size).imagePlacements.length, 1);
      tester.pumpWidget(tree(withImage: false));
      expect(tester.render(size: size).imagePlacements, isEmpty);
    });

    testWidgets('a moved image leaves no placement at the old spot', (tester) {
      Widget tree({required bool imageFirst}) => Column(
        children: [
          if (imageFirst) const ImageLeaf() else const Text('a'),
          if (imageFirst) const Text('a') else const ImageLeaf(),
        ],
      );
      const size = CellSize(8, 6);
      tester.pumpWidget(tree(imageFirst: true));
      expect(tester.render(size: size).imagePlacements.single.row, 0);
      tester.pumpWidget(tree(imageFirst: false));
      final after = tester.render(size: size).imagePlacements;
      expect(after.length, 1, reason: 'the old placement was carried forward');
      expect(after.single.row, greaterThan(0));
    });
  });

  group('full-repaint verification', () {
    setUp(() {
      IncrementalPaint.resetCounters();
      _RenderUngoverned.glyph = 'a';
    });
    tearDown(() {
      IncrementalPaint.verifyAgainstFullRepaint = false;
      _RenderUngoverned.glyph = 'a';
    });

    testWidgets('passes on a tree that invalidates properly', (tester) {
      IncrementalPaint.verifyAgainstFullRepaint = true;
      final middle = GlobalKey<_CounterState>();
      tester.pumpWidget(
        Column(
          children: [
            const Text('alpha'),
            _Counter(key: middle),
          ],
        ),
      );
      const size = CellSize(12, 2);
      tester.render(size: size);
      middle.currentState!.bump();
      tester.pump();
      expect(_rows(tester.render(size: size)), ['alpha', 'count=1']);
    });

    testWidgets('catches a subtree that changed what it paints silently', (
      tester,
    ) {
      // Without this the whole mode rests on a check that has never been seen
      // to disagree. The render object changes its glyph with no invalidation,
      // so incremental paint carries the old cell forward — and the buffer,
      // frame damage and every golden agree it is fine.
      IncrementalPaint.verifyAgainstFullRepaint = true;
      tester.pumpWidget(const Column(children: [Text('x'), _Ungoverned()]));
      const size = CellSize(4, 2);
      tester.render(size: size);

      _RenderUngoverned.glyph = 'b';
      expect(
        () => tester.render(size: size),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('diverged from a full repaint'), contains('row 1')),
          ),
        ),
      );
    });

    testWidgets('that same divergence is invisible without the check', (
      tester,
    ) {
      // The other half of the mutation test: the failure above is real, and
      // nothing else in the pipeline can see it.
      IncrementalPaint.verifyAgainstFullRepaint = false;
      tester.pumpWidget(const Column(children: [Text('x'), _Ungoverned()]));
      const size = CellSize(4, 2);
      expect(_rows(tester.render(size: size)), ['x', 'a']);

      _RenderUngoverned.glyph = 'b';
      expect(
        _rows(tester.render(size: size)),
        ['x', 'a'],
        reason:
            'the stale cell should have been carried forward silently — '
            'if this now reads "b" the skip never happened and the check '
            'above proves nothing',
      );
    });
  });

  group('the terminal sees the same bytes', () {
    // The strongest end-to-end statement available: run the same sequence of
    // frames through the real frame loop twice — once painting incrementally,
    // once not — and require that the presenter is handed identical bytes AND
    // identical damage. Damage equality is the direct test of the promise the
    // bounded diff rests on: a carried frame differs from the one before it
    // ONLY where it wrote, so scanning just that region has to find exactly
    // what scanning the whole screen finds.
    ({List<String> frames, List<String> damage}) run({
      required bool incremental,
    }) {
      final was = IncrementalPaint.enabled;
      IncrementalPaint.enabled = incremental;
      try {
        final tester = FleuryTester(viewportSize: const CellSize(24, 6));
        final counter = GlobalKey<_CounterState>();
        final label = ValueNotifier<String>('alpha');
        tester.pumpWidget(
          Column(
            children: [
              const Text('a static header'),
              ListenableBuilder(
                listenable: label,
                builder: (context, _) => Text(label.value),
              ),
              _Counter(key: counter),
              const Text('a static footer'),
            ],
          ),
        );
        // The loop is driven directly rather than through `tester.render`, so
        // there is exactly one stream of frames over this tree.
        final loop = TuiFrameLoop(
          renderDamage: tester.owner.renderDamageTracker,
        );
        final frames = <String>[];
        final damage = <String>[];
        void frame() {
          final rendered = loop.render(
            size: tester.viewportSize,
            paintsIncrementally: incremental,
            paint: (buffer) => tester.owner.renderFrame(tester.root!, buffer),
          )!;
          final sink = StringAnsiSink();
          const AnsiRenderer(
            synchronizedOutput: false,
          ).renderFull(rendered.next, sink);
          frames.add(sink.output);
          damage.add(_describeDamage(rendered.damage));
          loop.commit(rendered);
        }

        frame();
        counter.currentState!.bump();
        frame();
        label.value = 'a much longer label';
        frame();
        frame();
        label.value = 'x';
        frame();
        counter.currentState!.bump();
        frame();
        tester.dispose();
        return (frames: frames, damage: damage);
      } finally {
        IncrementalPaint.enabled = was;
      }
    }

    test('byte for byte, and damage for damage', () {
      final off = run(incremental: false);
      final on = run(incremental: true);
      expect(on.frames, off.frames, reason: 'the emitted bytes diverged');
      expect(
        on.damage,
        off.damage,
        reason:
            'the bounded diff and the full scan disagreed about what '
            'changed — the promise the bound rests on does not hold',
      );
      expect(
        off.damage.where((d) => d.startsWith('changed')).length,
        greaterThan(2),
        reason:
            'too few frames actually changed anything; the comparison '
            'would be vacuous',
      );
    });
  });
}
