import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

class _Dot implements CanvasPainter {
  double x = 0;
  @override
  void paint(CanvasContext context) => context.drawDot(x, 0);
}

void main() {
  testWidgets('sparkline refreshes mutated values and length', (tester) {
    final data = <num>[1, 2];
    Widget chart() => RepaintBoundary(child: Sparkline(data: data, max: 10));
    tester.pumpWidget(chart());
    final before = tester.renderToString(size: const CellSize(10, 2));
    data[0] = 10;
    tester.pumpWidget(chart());
    final updated = tester.renderToString(size: const CellSize(10, 2));
    expect(updated, isNot(before));
    data.add(5);
    tester.pumpWidget(chart());
    expect(tester.renderToString(size: const CellSize(10, 2)), isNot(updated));
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.chart)
          .state['chartPointCount'],
      3,
    );
  });

  testWidgets('heatmap refreshes mutable cells, labels and dimensions', (
    tester,
  ) {
    final values = <List<num>>[
      [1, 2],
    ];
    final labels = ['a'];
    Widget chart() => RepaintBoundary(
      child: Heatmap(
        values: values,
        rowLabels: labels,
        max: 10,
        min: 0,
        cellWidth: 1,
      ),
    );
    tester.pumpWidget(chart());
    final before = tester.renderToString(size: const CellSize(20, 5));
    values[0][0] = 10;
    tester.pumpWidget(chart());
    final updated = tester.renderToString(size: const CellSize(20, 5));
    expect(updated, isNot(before));
    values.add([5, 10]);
    labels[0] = 'long';
    labels.add('b');
    tester.pumpWidget(chart());
    final grown = tester.renderToString(size: const CellSize(20, 5));
    expect(grown, contains('long'));
    expect(grown, contains('b'));
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.chart)
          .state['chartRowCount'],
      2,
    );
  });

  testWidgets('mutated points repaint and shrink the active cursor range', (
    tester,
  ) {
    final points = <(num, num)>[(0, 1), (1, 2), (2, 3)];
    final series = [LineSeries(points)];
    Widget chart() => RepaintBoundary(
      child: SizedBox(
        width: 30,
        height: 8,
        child: LineChart(series: series, interactive: true, autofocus: true),
      ),
    );
    tester.pumpWidget(chart());
    tester.sendKey(const KeyEvent(KeyCode.end));
    final before = tester.renderToString(size: const CellSize(30, 8));
    points
      ..clear()
      ..addAll([(0, 20), (1, 30)]);
    tester.pumpWidget(chart());
    expect(tester.renderToString(size: const CellSize(30, 8)), isNot(before));
    final state = tester.semantics().single(role: SemanticRole.chart).state;
    expect(state['chartCursorX'], 1);
    expect(state['chartYMax'], 30);
  });

  testWidgets('same-length log replacement invalidates cached filtering', (
    tester,
  ) {
    final entries = [
      const LogEntry(id: 'a', message: 'match'),
      const LogEntry(id: 'b', message: 'other'),
    ];
    Widget logs() => SizedBox(
      width: 30,
      height: 4,
      child: LogRegion(
        entries: entries,
        showPrefix: false,
        filter: const LogRegionFilterDescriptor(query: 'match'),
      ),
    );
    tester.pumpWidget(logs());
    expect(
      tester.renderToString(size: const CellSize(30, 4)),
      contains('match'),
    );
    entries[0] = const LogEntry(id: 'a', message: 'removed');
    tester.pumpWidget(logs());
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.log)
          .state['filteredEntryCount'],
      0,
    );
  });

  testWidgets('a reused mutable painter refreshes on a new widget', (tester) {
    final painter = _Dot();
    Widget canvas() => RepaintBoundary(
      child: SizedBox(width: 4, height: 2, child: Canvas(painter: painter)),
    );
    tester.pumpWidget(canvas());
    final before = tester.renderToString(size: const CellSize(4, 2));
    painter.x = 1;
    tester.pumpWidget(canvas());
    expect(tester.renderToString(size: const CellSize(4, 2)), isNot(before));
  });

  testWidgets('bar list mutation refreshes paint and intrinsic layout', (
    tester,
  ) {
    final bars = [const Bar('a', 1)];
    Widget chart() => RepaintBoundary(
      child: SizedBox(
        width: 10,
        height: 4,
        child: BarChart(bars: bars, max: 3, barWidth: 1, gap: 1),
      ),
    );
    tester.pumpWidget(chart());
    final before = tester.renderToString(size: const CellSize(10, 4));
    bars[0] = const Bar('a', 3);
    bars.add(const Bar('b', 2));
    tester.pumpWidget(chart());
    final after = tester.renderToString(size: const CellSize(10, 4));
    expect(after, isNot(before));
    expect(after, contains('b'));
  });
}
