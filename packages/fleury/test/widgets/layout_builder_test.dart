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
}
