import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

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
    final flag = _Flag();
    tester.pumpWidget(
      _Listen(
        flag: flag,
        builder: (on) => LayoutBuilder(
          builder: (context, constraints) => Text(on ? 'after' : 'before'),
        ),
      ),
    );
    String flat() => tester.renderToString(size: const CellSize(10, 1)).trim();
    expect(flat(), 'before');

    flag.set(true); // rebuilds only the _Listen leaf; constraints unchanged
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
}

class _Flag extends ChangeNotifier {
  bool value = false;
  void set(bool v) {
    value = v;
    notifyListeners();
  }
}

/// Rebuilds alone when [flag] fires — an external-dependency leaf rebuild.
class _Listen extends StatefulWidget {
  const _Listen({required this.flag, required this.builder});
  final _Flag flag;
  final Widget Function(bool on) builder;
  @override
  State<_Listen> createState() => _ListenState();
}

class _ListenState extends State<_Listen> {
  @override
  void initState() {
    super.initState();
    widget.flag.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.flag.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(widget.flag.value);
}
