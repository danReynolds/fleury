import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<String> _lines(
  FleuryTester tester, {
  required int cols,
  required int rows,
}) {
  final buf = tester.render(size: CellSize(cols, rows));
  return [
    for (var r = 0; r < rows; r++)
      [
        for (var c = 0; c < cols; c++)
          buf.atColRow(c, r).role == CellRole.leading
              ? buf.atColRow(c, r).grapheme!
              : ' ',
      ].join().trimRight(),
  ];
}

void main() {
  testWidgets('frames its child with a border and padding', (tester) {
    tester.pumpWidget(const Dialog(child: Text('hi')));
    // Rounded border around ' hi ' (symmetric horizontal padding of 1).
    expect(_lines(tester, cols: 6, rows: 3), ['╭────╮', '│ hi │', '╰────╯']);
  });

  testWidgets('renders a bold title above the content', (tester) {
    tester.pumpWidget(const Dialog(title: 'Confirm', child: Text('ok')));
    final lines = _lines(tester, cols: 11, rows: 5);
    expect(lines[0], '╭─────────╮');
    expect(lines[1], '│ Confirm │');
    expect(lines[2], '│         │', reason: 'blank line under the title');
    expect(lines[3], '│ ok      │');
    expect(lines[4], '╰─────────╯');

    final buf = tester.render(size: const CellSize(11, 5));
    expect(buf.atColRow(2, 1).style.bold, isTrue, reason: 'title is bold');
  });

  testWidgets('present() centers a Dialog over the page', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Navigator(home: _Host((c) => ctx = c)));
    Navigator.of(ctx).present<void>(const Dialog(child: Text('x')));
    tester.pump(const Duration(milliseconds: 300)); // settle the entrance
    // 5x3 panel centered in a 12x5 field.
    expect(_lines(tester, cols: 12, rows: 5), [
      '',
      '   ╭───╮',
      '   │ x │',
      '   ╰───╯',
      '',
    ]);
  });
}

class _Host extends StatelessWidget {
  const _Host(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const EmptyBox();
  }
}
