import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _accent = RgbColor(0x3D, 0xDC, 0x97);
const _theme = ThemeData(
  borderStyle: BorderStyle.rounded,
  mutedStyle: CellStyle(dim: true),
  colorScheme: ColorScheme(primary: _accent),
);

Widget _panel({
  bool focused = false,
  Widget? trailing,
  bool expandChild = true,
  String? semanticLabel,
}) {
  return Theme(
    data: _theme,
    child: Panel(
      title: 'CPU',
      trailing: trailing,
      focused: focused,
      expandChild: expandChild,
      semanticLabel: semanticLabel,
      child: const Text('body'),
    ),
  );
}

void main() {
  testWidgets('renders the border, title row, and body', (tester) {
    tester.pumpWidget(_panel());
    final out = tester.renderToString(size: const CellSize(12, 5));
    expect(out, contains('╭'));
    expect(out, contains('CPU'));
    expect(out, contains('body'));
  });

  testWidgets('trailing widget is right-aligned on the title row', (tester) {
    tester.pumpWidget(_panel(trailing: const Text('42%')));
    final out = tester.renderToString(size: const CellSize(14, 5));
    final titleRow = out.split('\n')[1];
    expect(titleRow, contains('CPU'));
    expect(titleRow, contains('42%'));
    expect(
      titleRow.indexOf('42%'),
      greaterThan(titleRow.indexOf('CPU')),
      reason: 'trailing sits right of the title',
    );
  });

  testWidgets('focused panel uses the accent for border and title', (tester) {
    tester.pumpWidget(_panel(focused: true));
    final buf = tester.render(size: const CellSize(12, 5));
    // Border corner cell (0,0) and the title's first cell both take the
    // accent when focused.
    expect(buf.atColRow(0, 0).style.foreground, _accent);
    final title = buf.atColRow(2, 1); // inside border + 1-cell padding
    expect(title.grapheme, 'C');
    expect(title.style.foreground, _accent);
    expect(title.style.bold, isTrue);

    tester.pumpWidget(_panel());
    final rest = tester.render(size: const CellSize(12, 5));
    expect(rest.atColRow(0, 0).style.foreground, isNot(_accent));
  });

  testWidgets('accents itself while focus is inside it', (tester) {
    final body = FocusNode(debugLabel: 'body');
    Widget build() => Theme(
      data: _theme,
      child: Panel(
        title: 'CPU',
        expandChild: false,
        child: Focus(focusNode: body, child: const Text('body')),
      ),
    );

    tester.pumpWidget(build());
    expect(
      tester.render(size: const CellSize(12, 5)).atColRow(0, 0).style.foreground,
      isNot(_accent),
      reason: 'at rest the border stays muted',
    );

    body.requestFocus();
    final buf = tester.render(size: const CellSize(12, 5));
    expect(
      buf.atColRow(0, 0).style.foreground,
      _accent,
      reason: 'focus landing inside should accent the pane, unasked',
    );
    expect(buf.atColRow(2, 1).style.foreground, _accent, reason: 'title too');
  });

  testWidgets('an explicit focused pins the chrome against the focus tree', (
    tester,
  ) {
    final body = FocusNode(debugLabel: 'body');
    tester.pumpWidget(
      Theme(
        data: _theme,
        child: Panel(
          title: 'CPU',
          expandChild: false,
          focused: false,
          child: Focus(focusNode: body, child: const Text('body')),
        ),
      ),
    );
    body.requestFocus();
    expect(
      tester.render(size: const CellSize(12, 5)).atColRow(0, 0).style.foreground,
      isNot(_accent),
      reason: 'an explicit false wins over detected focus',
    );
  });

  testWidgets('is a semantic region named by the title', (tester) {
    tester.pumpWidget(_panel());
    final region = tester.semantics().single(role: SemanticRole.region);
    expect(region.label, 'CPU');
  });

  testWidgets('semanticLabel overrides the region name', (tester) {
    tester.pumpWidget(_panel(semanticLabel: 'CPU usage panel'));
    final region = tester.semantics().single(role: SemanticRole.region);
    expect(region.label, 'CPU usage panel');
  });

  testWidgets('expandChild fills the panel; false hugs the content', (tester) {
    tester.pumpWidget(_panel());
    final expanded = tester.renderToString(size: const CellSize(12, 6));
    // Bottom border sits on the last row when the child expands.
    expect(expanded.trimRight().split('\n').length, 6);

    tester.pumpWidget(
      Align(alignment: Alignment.topLeft, child: _panel(expandChild: false)),
    );
    final hugged = tester.renderToString(size: const CellSize(12, 6));
    // Title row + body row + borders = 4 rows; the rest stays empty.
    expect(hugged.trimRight().split('\n').length, lessThan(6));
  });
}
