import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a timed pump paints the selected animation frame', (tester) {
    Widget moving(double left) => AnimationBuilder<double>(
      left,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
      builder: (_, value, _) => Padding(
        padding: EdgeInsets.only(left: value.round()),
        child: const Text('Moving'),
      ),
    );
    tester.pumpWidget(moving(0));
    tester.pumpWidget(moving(10));
    tester.pump(const Duration(milliseconds: 500));
    expect(tester.clock.now, const Duration(milliseconds: 500));
    expect(
      tester.semantics().single(label: 'Moving').bounds,
      CellRect.fromLTWH(5, 0, 6, 1),
    );
  });

  testWidgets('pumps layout-time children at the current viewport', (tester) {
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) =>
            Text('${constraints.maxCols}/${MediaQuery.sizeOf(context).cols}'),
      ),
    );
    expect(tester.exists(text('80/80')), isTrue);
    expect(tester.semantics().single(label: '80/80').bounds, isNotNull);

    tester.viewportSize = const CellSize(40, 3);
    tester.pump();
    expect(tester.exists(text('40/40')), isTrue);
    expect(tester.exists(text('80/80')), isFalse);
    expect(tester.clock.now, Duration.zero);
  });

  testWidgets('callbacks see painted geometry and defer new callbacks', (
    tester,
  ) {
    final frames = <CellRect?>[];
    void record(Duration _) {
      frames.add(tester.semantics().single(label: 'Ready').bounds);
      if (frames.length == 1) tester.binding.addPostFrameCallback(record);
    }

    tester.binding.addPostFrameCallback(record);
    tester.pumpWidget(
      const Padding(
        padding: EdgeInsets.only(left: 2, top: 1),
        child: Text('Ready'),
      ),
    );
    expect(frames, [CellRect.fromLTWH(2, 1, 5, 1)]);

    tester.pumpWidget(
      const Padding(
        padding: EdgeInsets.only(left: 4, top: 2),
        child: Text('Ready'),
      ),
    );
    expect(frames, [
      CellRect.fromLTWH(2, 1, 5, 1),
      CellRect.fromLTWH(4, 2, 5, 1),
    ]);
  });

  testWidgets('pump paints pointer targets without a separate render', (
    tester,
  ) {
    var taps = 0;
    Widget target(int left) => Padding(
      padding: EdgeInsets.only(left: left),
      child: GestureDetector(onTap: () => taps++, child: const Text('Tap')),
    );
    void click(int col) {
      for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
        tester.sendMouse(
          MouseEvent(kind: kind, button: MouseButton.left, col: col, row: 0),
        );
      }
    }

    tester.pumpWidget(target(0));
    click(1);
    expect(taps, 1);
    tester.mountWidget(target(5));
    tester.pump();
    click(1);
    expect(taps, 1);
    click(6);
    expect(taps, 2);
  });

  testWidgets('render size resizes MediaQuery and preserves mounted state', (
    tester,
  ) {
    final key = GlobalKey<_ViewportProbeState>();
    tester.pumpWidget(_ViewportProbe(key: key));
    final state = key.currentState;

    expect(
      tester.renderToString(size: const CellSize(40, 3)),
      contains('40/40'),
    );
    expect(tester.viewportSize, const CellSize(40, 3));
    expect(key.currentState, same(state));
    tester.pump();
    expect(tester.exists(text('40/40')), isTrue);
  });

  testWidgets('mount and render expose partial phases explicitly', (tester) {
    var callbacks = 0;
    tester.binding.addPostFrameCallback((_) => callbacks++);
    tester.mountWidget(LayoutBuilder(builder: (_, _) => const Text('Ready')));
    expect(tester.exists(text('Ready')), isFalse);
    expect(callbacks, 0);
    tester.render();
    expect(tester.exists(text('Ready')), isTrue);
    expect(callbacks, 0);
    tester.pump();
    expect(callbacks, 1);
  });

  testWidgets('layout failures occur in the operation that renders', (tester) {
    final failure = StateError('layout failed');
    final widget = LayoutBuilder(builder: (_, _) => throw failure);
    tester.mountWidget(widget);
    expect(() => tester.pump(), throwsA(same(failure)));
    expect(() => tester.pumpWidget(widget), throwsA(same(failure)));
  });
}

class _ViewportProbe extends StatefulWidget {
  const _ViewportProbe({super.key});

  @override
  State<_ViewportProbe> createState() => _ViewportProbeState();
}

class _ViewportProbeState extends State<_ViewportProbe> {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        Text('${constraints.maxCols}/${MediaQuery.sizeOf(context).cols}'),
  );
}
