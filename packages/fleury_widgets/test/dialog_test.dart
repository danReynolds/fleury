import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
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

  testWidgets('exposes dialog semantics', (tester) {
    tester.pumpWidget(const Dialog(title: 'Confirm', child: Text('ok')));

    final node = tester.semantics().single(
      role: SemanticRole.dialog,
      label: 'Confirm',
    );
    expect(node.state.values['hasTitle'], isTrue);
    expect(
      node.actions,
      isEmpty,
      reason: 'dismissal belongs to the route that presents a dialog',
    );
  });

  testWidgets('semantic dismiss pops a presented dialog', (tester) async {
    late BuildContext ctx;
    tester.pumpWidget(Navigator(home: _Host((c) => ctx = c)));
    Navigator.of(
      ctx,
    ).present<void>(const Dialog(title: 'Confirm', child: Text('ok')));
    tester.pump(const Duration(milliseconds: 300));
    expect(Navigator.of(ctx).depth, 2);

    // The presented dialog's route carries its dismiss.
    await tester
        .target(role: SemanticRole.route, label: 'Dialog')
        .perform(SemanticAction.dismiss);

    tester.pump(const Duration(milliseconds: 300));
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(Navigator.of(ctx).depth, 1);
  });

  testWidgets('a must-answer dialog offers no dismiss to semantics', (
    tester,
  ) async {
    late BuildContext ctx;
    tester.pumpWidget(Navigator(home: _Host((c) => ctx = c)));
    Navigator.of(ctx).present<bool>(
      const Dialog(title: 'Confirm', child: Text('must answer')),
      barrierDismissible: false,
    );
    tester.pump(const Duration(milliseconds: 300));

    final tree = tester.semantics();
    final dialog = tree.single(role: SemanticRole.dialog, label: 'Confirm');
    final route = tree.single(role: SemanticRole.route, label: 'Dialog');
    expect(dialog.actions, isNot(contains(SemanticAction.dismiss)));
    expect(route.actions, isNot(contains(SemanticAction.dismiss)));
    expect(Navigator.of(ctx).depth, 2);
  });

  testWidgets('dismissing a guarded dialog asks its PopScope', (tester) async {
    late BuildContext ctx;
    var blocked = 0;
    tester.pumpWidget(Navigator(home: _Host((c) => ctx = c)));
    Navigator.of(ctx).present<void>(
      Dialog(
        title: 'Edit',
        child: PopScope(
          canPop: false,
          onBlocked: () => blocked++,
          child: const Text('unsaved'),
        ),
      ),
    );
    tester.pump(const Duration(milliseconds: 300));

    final result = await tester.invokeSemanticAction(
      SemanticAction.dismiss,
      role: SemanticRole.route,
      label: 'Dialog',
      allowFailure: true,
    );
    tester.pump(const Duration(milliseconds: 300));

    expect(blocked, 1);
    expect(Navigator.of(ctx).depth, 2);
    // Refused, and reported as not done rather than completed.
    expect(result.status, SemanticActionInvocationStatus.unsupported);
  });

  testWidgets('a dialog shown inline offers no dismiss', (tester) async {
    late BuildContext ctx;
    tester.pumpWidget(Navigator(home: _Host((c) => ctx = c)));
    Navigator.of(ctx).push<void>(
      const Dialog(title: 'Inline', child: Text('part of the page')),
    );
    tester.pump(const Duration(milliseconds: 300));

    final dialog = tester.semantics().single(
      role: SemanticRole.dialog,
      label: 'Inline',
    );
    expect(dialog.actions, isNot(contains(SemanticAction.dismiss)));
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
