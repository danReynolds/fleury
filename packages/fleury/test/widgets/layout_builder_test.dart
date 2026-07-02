import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

import '../support/reactive_helpers.dart';

void main() {
  testWidgets('builds against the incoming constraints', (tester) {
    Widget responsive() => LayoutBuilder(
      builder: (context, constraints) =>
          Text((constraints.maxCols ?? 0) >= 10 ? 'wide' : 'narrow'),
    );

    tester.pumpWidget(responsive());
    expect(tester.renderToString(size: const CellSize(20, 1)).trim(), 'wide');
    expect(tester.renderToString(size: const CellSize(6, 1)).trim(), 'narrow');
  });

  testWidgets('switches subtree type as constraints cross a breakpoint', (
    tester,
  ) {
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          if ((constraints.maxCols ?? 0) >= 8) {
            return const Row(children: [Text('A'), Text('B')]);
          }
          return const Column(children: [Text('A'), Text('B')]);
        },
      ),
    );
    // Wide: A and B side by side on row 0.
    var buf = tester.render(size: const CellSize(10, 2));
    expect(buf.atColRow(0, 0).grapheme, 'A');
    expect(buf.atColRow(1, 0).grapheme, 'B');
    // Narrow: stacked down column 0.
    buf = tester.render(size: const CellSize(4, 2));
    expect(buf.atColRow(0, 0).grapheme, 'A');
    expect(buf.atColRow(0, 1).grapheme, 'B');
  });

  testWidgets('rebuilds when the builder widget updates', (tester) {
    Widget responsive(String label) => LayoutBuilder(
      builder: (context, constraints) => Text(
        '${(constraints.maxCols ?? 0) >= 10 ? 'wide' : 'narrow'} $label',
      ),
    );

    tester.pumpWidget(responsive('first'));
    expect(
      tester.renderToString(size: const CellSize(20, 1)).trim(),
      'wide first',
    );

    tester.pumpWidget(responsive('second'));
    expect(
      tester.renderToString(size: const CellSize(20, 1)).trim(),
      'wide second',
    );
  });

  testWidgets('reads an inherited MediaQuery inside the builder', (tester) {
    tester.viewportSize = const CellSize(24, 6);
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) =>
            Text('screen=${MediaQuery.sizeOf(context).cols}'),
      ),
    );
    expect(
      tester.renderToString(size: const CellSize(24, 1)).trim(),
      'screen=24',
    );
  });

  // --- Regressions -------------------------------------------------------

  testWidgets('an element-level invalidation re-runs the builder '
      '(markNeedsBuild forces relayout)', (tester) {
    // The builder only runs inside performLayout, which short-circuits when
    // constraints are unchanged — a notifier-driven rebuild used to leave the
    // subtree permanently stale.
    final flag = Flag();
    tester.pumpWidget(
      Reactive(
        flag: flag,
        builder: (on) => LayoutBuilder(
          builder: (context, constraints) => Text(on ? 'after' : 'before'),
        ),
      ),
    );
    String flat() => tester.renderToString(size: const CellSize(10, 1)).trim();
    expect(flat(), 'before');

    flag.set(true); // rebuilds only the Reactive leaf; constraints unchanged
    tester.pump();
    expect(flat(), 'after',
        reason: 'the dirtied LayoutBuilder must relayout and re-run its '
            'builder even though its constraints did not change');
  });

  testWidgets('collapsing to zero under an unbounded axis throws in debug '
      '(instead of blanking silently)', (tester) {
    // An inflexible Row child receives an unbounded main axis
    // (maxCols == null); a width-keyed builder computes (null ?? 0) ~/ 3 = 0
    // and used to blank the pane with no diagnostic.
    tester.pumpWidget(
      Row(children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: (constraints.maxCols ?? 0) ~/ 3,
            child: const Text('nav'),
          ),
        ),
        const Expanded(child: Text('main')),
      ]),
    );
    expect(
      () => tester.renderToString(size: const CellSize(24, 2)),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('unbounded maxCols'),
      )),
    );
  });

  testWidgets('a min-forced empty child under an unbounded axis does not '
      'assert (stretch exemption)', (tester) {
    // CrossAxisAlignment.stretch forces minRows = crossMax, so a deliberately
    // empty child sizes (0 x crossMax) under the unbounded Row axis — the
    // collapse assert must not fire for extents the child did not choose.
    tester.pumpWidget(
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) => const Text('')),
          const Expanded(child: Text('main')),
        ],
      ),
    );
    final out = tester.renderToString(size: const CellSize(20, 2));
    expect(out, contains('main'), reason: 'lays out without throwing');
  });

  testWidgets('the builder is memoized: repeated layout passes with '
      'unchanged constraints do not re-run it', (tester) {
    var runs = 0;
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          runs++;
          return const Text('stable');
        },
      ),
    );
    tester.renderToString(size: const CellSize(10, 1));
    expect(runs, 1);

    // Same constraints, more passes: layout recurses through the node but
    // the built child is reused. Re-running here is the seed of a rebuild
    // loop when the subtree isn't identity-stable (each re-run produces
    // damage that schedules the next frame).
    tester.renderToString(size: const CellSize(10, 1));
    tester.pump();
    tester.renderToString(size: const CellSize(10, 1));
    expect(runs, 1,
        reason: 'unchanged constraints + clean element = no builder re-run');

    // A genuine constraint change still rebuilds.
    tester.renderToString(size: const CellSize(6, 1));
    expect(runs, 2);

    // And returning to a previously-seen size rebuilds again (the memo is
    // last-constraints, not a cache).
    tester.renderToString(size: const CellSize(10, 1));
    expect(runs, 3);
  });

  testWidgets('memoization does not swallow widget updates delivered under '
      'identical constraints', (tester) {
    var runs = 0;
    Widget labeled(String label) => LayoutBuilder(
      builder: (context, constraints) {
        runs++;
        return Text(label);
      },
    );

    tester.pumpWidget(labeled('first'));
    expect(tester.renderToString(size: const CellSize(10, 1)).trim(), 'first');
    final after = runs;

    tester.pumpWidget(labeled('second')); // new closure, same constraints
    expect(
      tester.renderToString(size: const CellSize(10, 1)).trim(),
      'second',
      reason: 'a new builder closure invalidates the memoized child',
    );
    expect(runs, after + 1);
  });

  testWidgets('memoization does not swallow a child setState under '
      'identical constraints', (tester) {
    // State BELOW the LayoutBuilder rebuilds through the normal build phase,
    // not through the builder callback — the memo must not interfere.
    final flag = Flag();
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) => Reactive(
          flag: flag,
          builder: (on) => Text(on ? 'after' : 'before'),
        ),
      ),
    );
    String flat() => tester.renderToString(size: const CellSize(10, 1)).trim();
    expect(flat(), 'before');
    flag.set(true);
    tester.pump();
    expect(flat(), 'after');
  });

  testWidgets('a descendant relayout forces performLayout but the memo still '
      'skips the builder (isolates the memo from the RO layout cache)',
      (tester) {
    // The 'repeated passes' test above is also satisfied by the render-object
    // layout cache (layout() short-circuits unchanged constraints without
    // calling performLayout). THIS drives the case only the builder-memo
    // covers: a descendant whose size change walks markNeedsLayout UP through
    // the RenderLayoutBuilder, forcing performLayout under unchanged
    // constraints. The builder must NOT re-run (the LB element wasn't
    // invalidated) — pre-memo it re-inflated the subtree every such pass,
    // the render-damage loop this fix removes.
    final flag = Flag();
    var runs = 0;
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          runs++;
          return Reactive(
            flag: flag,
            builder: (on) => Text(on ? 'wiiiide' : 'x'), // size changes
          );
        },
      ),
    );
    String flat() => tester.renderToString(size: const CellSize(12, 1)).trim();
    expect(flat(), 'x');
    expect(runs, 1);

    flag.set(true); // descendant setState → child size change → spine relayout
    tester.pump();
    expect(flat(), 'wiiiide', reason: 'the descendant change still renders');
    expect(runs, 1,
        reason: 'the forced relayout did NOT re-run the builder — the memo '
            'skipped it (pre-memo this re-inflated the subtree every pass)');
  });

  testWidgets('a bounded LayoutBuilder in a Row (via Expanded) lays out fine',
      (tester) {
    tester.pumpWidget(
      Row(children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              width: (constraints.maxCols ?? 0) ~/ 3,
              child: const Text('nav'),
            ),
          ),
        ),
        const Expanded(child: Text('main')),
      ]),
    );
    final out = tester.renderToString(size: const CellSize(24, 2));
    expect(out, contains('nav'));
    expect(out, contains('main'));
  });

  testWidgets('a listenable read inside the builder stays live under the memo',
      (tester) {
    // The builder runs during layout, where the active build target used to be
    // unset — so an ElementDependency read (Animation.value) never subscribed,
    // and the memo then froze it. With the build target set, the read
    // subscribes the LayoutBuilder element and the value change invalidates
    // the memoized child even though constraints don't move.
    final anim = Animation<int>(1);
    addTearDown(anim.dispose);
    tester.pumpWidget(
      LayoutBuilder(builder: (context, constraints) => Text('v=${anim.value}')),
    );
    String flat() => tester.renderToString(size: const CellSize(10, 1)).trim();
    expect(flat(), 'v=1');

    anim.snap(2); // notifies subscribers; constraints unchanged
    tester.pump();
    expect(flat(), 'v=2',
        reason: 'the layout-time read auto-subscribed the element, so the '
            'change invalidates the memo');
  });

  testWidgets('a throwing builder is retried on the next pass, not skipped '
      'as clean', (tester) {
    // The stale flag is cleared BEFORE the callback and restored if it throws,
    // so an unchanged-constraints retry re-runs the builder instead of serving
    // the never-built (or half-built) child.
    var boom = true;
    var runs = 0;
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          runs++;
          if (boom) throw StateError('builder boom');
          return const Text('recovered');
        },
      ),
    );
    expect(() => tester.renderToString(size: const CellSize(12, 1)),
        throwsA(isA<StateError>()));
    final afterThrow = runs;

    boom = false;
    expect(tester.renderToString(size: const CellSize(12, 1)).trim(),
        'recovered');
    expect(runs, greaterThan(afterThrow),
        reason: 'the retry re-ran the builder despite unchanged constraints');
  });

  testWidgets('an invalidation fired during the build itself is honored, '
      'not swallowed', (tester) {
    // Clearing the stale flag before the callback means a re-entrant
    // markNeedsBuild (from within the builder) survives: the loop re-runs the
    // builder on the same pass instead of the flag being wiped by the epilogue.
    var runs = 0;
    var reentered = false;
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          runs++;
          if (!reentered) {
            reentered = true;
            (context as Element).markNeedsBuild(); // invalidate mid-build
          }
          return Text('runs=$runs');
        },
      ),
    );
    expect(tester.renderToString(size: const CellSize(12, 1)).trim(), 'runs=2',
        reason: 'the re-entrant invalidation forced a second build this pass');
  });
}


