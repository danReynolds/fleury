// A LineChart rebuilt by its parent does no cursor work unless it has a
// cursor: every rebuild with a new series list re-sorted every x value, which
// only an interactive chart reads. An unchanged widget does not
// repaint when the same widget instance is reused. A new widget explicitly
// refreshes its data, including mutable lists.
import 'dart:collection';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Points that count how often one is read.
final class _CountingPoints extends ListBase<(num, num)> {
  _CountingPoints(this._points);

  final List<(num, num)> _points;
  var reads = 0;

  @override
  int get length => _points.length;
  @override
  set length(int value) => throw UnsupportedError('fixed');
  @override
  (num, num) operator [](int index) {
    reads++;
    return _points[index];
  }

  @override
  void operator []=(int index, (num, num) value) =>
      throw UnsupportedError('fixed');
}

final class _Host with Notifier {
  var builds = 0;
  void rebuild() {
    builds++;
    notify();
  }
}

Widget _chart(
  _Host host,
  List<(num, num)> points, {
  bool interactive = false,
}) => NotifierBuilder(
  notifier: host,
  // A fresh series list and LineSeries over the same points each build.
  builder: (_, host) => RepaintBoundary(
    child: SizedBox(
      width: 60,
      height: 12,
      child: LineChart(series: [LineSeries(points)], interactive: interactive),
    ),
  ),
);

int _readsPerRebuild(FleuryTester tester, {required bool interactive}) {
  final points = _CountingPoints([
    for (var i = 0; i < 1000; i++) (i, (i * 7) % 50),
  ]);
  final host = _Host();
  tester.pumpWidget(_chart(host, points, interactive: interactive));
  tester.render(size: const CellSize(60, 12));
  points.reads = 0;
  host.rebuild();
  tester.pump();
  return points.reads;
}

void main() {
  testWidgets('a chart without a cursor does not collect its x values', (
    tester,
  ) {
    final interactive = _readsPerRebuild(tester, interactive: true);
    final plain = _readsPerRebuild(tester, interactive: false);

    expect(plain, lessThan(interactive));
  });

  testWidgets('reusing an unchanged chart widget does not repaint', (tester) {
    addTearDown(() => RepaintBoundaryDebugStats.beginFrame(enabled: false));
    final host = _Host();
    final series = [
      LineSeries([for (var i = 0; i < 100; i++) (i, i % 10)]),
    ];
    final chart = SizedBox(
      width: 60,
      height: 12,
      child: LineChart(series: series),
    );
    tester.pumpWidget(
      NotifierBuilder(
        notifier: host,
        builder: (_, _) => RepaintBoundary(child: chart),
      ),
    );
    tester.render(size: const CellSize(60, 12));

    host.rebuild();
    RepaintBoundaryDebugStats.beginFrame(enabled: true);
    tester.pump();
    final stats = RepaintBoundaryDebugStats.takeFrameStats();

    expect(stats.cachedCount, 1, reason: 'the chart kept its paint');
  });

  testWidgets('new points move the cursor range', (tester) {
    final host = _Host();
    var points = <(num, num)>[(0, 1), (1, 2), (2, 3)];
    tester.pumpWidget(
      NotifierBuilder(
        notifier: host,
        builder: (_, _) => SizedBox(
          width: 60,
          height: 12,
          child: LineChart(
            series: [LineSeries(points)],
            interactive: true,
            autofocus: true,
          ),
        ),
      ),
    );
    tester.render(size: const CellSize(60, 12));
    tester.sendKey(const KeyEvent(KeyCode.end));
    Object? cursorX() => tester
        .semantics()
        .single(role: SemanticRole.chart)
        .state['chartCursorX'];
    expect(cursorX(), 2);

    points = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)];
    host.rebuild();
    tester.pump();
    tester.sendKey(const KeyEvent(KeyCode.end));

    expect(cursorX(), 4);
  });
}
