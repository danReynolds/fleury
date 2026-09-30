import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';
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
      tester
          .render(size: const CellSize(12, 5))
          .atColRow(0, 0)
          .style
          .foreground,
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

  group('accents while focus is inside a widget that watches focus too', () {
    // LogRegion and DataTable each wrap themselves in their own
    // FocusDetector. Focus inside them is still inside the panel.
    Object? cornerWith(FleuryTester tester, Widget child) {
      tester.pumpWidget(
        Theme(
          data: _theme,
          child: Panel(title: 'Pane', child: child),
        ),
      );
      return tester
          .render(size: const CellSize(24, 6))
          .atColRow(0, 0)
          .style
          .foreground;
    }

    testWidgets('a LogRegion', (tester) {
      expect(
        cornerWith(
          tester,
          const LogRegion(
            autofocus: true,
            entries: [
              LogEntry(
                id: 'a',
                severity: LogSeverity.info,
                source: 'system',
                message: 'booted',
              ),
            ],
          ),
        ),
        _accent,
      );
    });

    testWidgets('a DataTable', (tester) {
      expect(
        cornerWith(
          tester,
          DataTable(
            autofocus: true,
            rowCount: 2,
            columns: const [
              DataTableColumn(
                id: 'run',
                title: 'Run',
                width: FixedColumnWidth(8),
              ),
            ],
            cellBuilder: (row, column) => 'run-$row',
          ),
        ),
        _accent,
      );
    });
  });

  testWidgets('nested panels both accent while focus is in the inner one', (
    tester,
  ) {
    final body = FocusNode(debugLabel: 'body');
    final elsewhere = FocusNode(debugLabel: 'elsewhere');
    tester.pumpWidget(
      Theme(
        data: _theme,
        child: Column(
          children: [
            Expanded(
              child: Panel(
                title: 'Outer',
                child: Panel(
                  title: 'Inner',
                  child: Focus(focusNode: body, child: const Text('body')),
                ),
              ),
            ),
            Focus(focusNode: elsewhere, child: const Text('elsewhere')),
          ],
        ),
      ),
    );

    body.requestFocus();
    var buf = tester.render(size: const CellSize(20, 8));
    expect(buf.atColRow(0, 0).style.foreground, _accent, reason: 'outer');
    // The inner panel's corner: one border cell and one padding cell in, on
    // the row under the outer title.
    expect(buf.atColRow(2, 2).grapheme, '╭');
    expect(buf.atColRow(2, 2).style.foreground, _accent, reason: 'inner');

    elsewhere.requestFocus();
    buf = tester.render(size: const CellSize(20, 8));
    expect(buf.atColRow(0, 0).style.foreground, isNot(_accent));
    expect(buf.atColRow(2, 2).style.foreground, isNot(_accent));
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
      tester
          .render(size: const CellSize(12, 5))
          .atColRow(0, 0)
          .style
          .foreground,
      isNot(_accent),
      reason: 'an explicit false wins over detected focus',
    );
  });

  testWidgets('unpinning follows focus that moved while pinned', (tester) {
    final body = FocusNode(debugLabel: 'body');
    Widget build({bool? focused}) => Theme(
      data: _theme,
      child: Panel(
        title: 'CPU',
        expandChild: false,
        focused: focused,
        child: Focus(focusNode: body, child: const Text('body')),
      ),
    );
    tester.pumpWidget(build(focused: false));
    body.requestFocus();
    tester.render(size: const CellSize(12, 5));

    tester.pumpWidget(build());
    expect(
      tester
          .render(size: const CellSize(12, 5))
          .atColRow(0, 0)
          .style
          .foreground,
      _accent,
      reason: 'focus entered while pinned is still inside once unpinned',
    );
  });

  group('pinning focused pins only the chrome', () {
    bool regionFocused(FleuryTester tester, String title) => tester
        .semantics()
        .single(role: SemanticRole.region, label: title)
        .focused;

    Object? cornerColor(FleuryTester tester) => tester
        .render(size: const CellSize(20, 8))
        .atColRow(0, 0)
        .style
        .foreground;

    testWidgets('a pinned panel with no focus inside draws the accent but '
        'reports no focus', (tester) {
      tester.pumpWidget(_panel(focused: true));
      expect(cornerColor(tester), _accent, reason: 'the chrome is pinned');
      expect(
        regionFocused(tester, 'CPU'),
        isFalse,
        reason: 'nothing inside the panel has focus',
      );
    });

    testWidgets('what has focus is the control after a pinned panel', (tester) {
      // A showcase pins a pane's chrome while the keys are with a button
      // after it in tree order.
      tester.pumpWidget(
        Theme(
          data: _theme,
          child: Column(
            children: [
              const Expanded(
                child: Panel(title: 'CPU', focused: true, child: Text('42%')),
              ),
              Button(text: 'Deploy', autofocus: true, onPressed: () {}),
            ],
          ),
        ),
      );
      expect(cornerColor(tester), _accent);

      final tree = tester.semantics();
      expect(tree.focusedNode?.role, SemanticRole.button);
      expect(tree.focusedNode?.label, 'Deploy');
      expect(tester.accessibilitySnapshot().focusedNode?.label, 'Deploy');
      final ui = _getUi(tree);
      final focusedId = ui['focusedNodeId'] as String?;
      expect(
        tree.nodes.where((node) => node.id.value == focusedId).single.label,
        'Deploy',
        reason: "fleury_mcp get_ui's focusedNodeId",
      );
    });

    for (final pinned in [true, false]) {
      testWidgets('pinned $pinned, the region reports focus only while focus '
          'is inside it', (tester) {
        final body = FocusNode(debugLabel: 'body');
        final elsewhere = FocusNode(debugLabel: 'elsewhere');
        tester.pumpWidget(
          Theme(
            data: _theme,
            child: Column(
              children: [
                Expanded(
                  child: Panel(
                    title: 'CPU',
                    focused: pinned,
                    child: Focus(focusNode: body, child: const Text('body')),
                  ),
                ),
                Focus(focusNode: elsewhere, child: const Text('elsewhere')),
              ],
            ),
          ),
        );
        final chrome = pinned ? _accent : isNot(_accent);

        body.requestFocus();
        expect(regionFocused(tester, 'CPU'), isTrue);
        expect(cornerColor(tester), chrome);

        elsewhere.requestFocus();
        expect(regionFocused(tester, 'CPU'), isFalse);
        expect(cornerColor(tester), chrome);
      });
    }
  });

  group('what has focus is the control in the panel, not the panel', () {
    // The panel's region reports focus while focus is anywhere inside it,
    // and it comes first in tree order. What agents read (the inspection
    // snapshot's focusedNodeId) and the accessibility snapshot must still
    // name the control that holds focus.
    void expectFocused(FleuryTester tester, Widget child, SemanticRole role) {
      tester.pumpWidget(
        Theme(
          data: _theme,
          child: Panel(title: 'Pane', child: child),
        ),
      );
      tester.render(size: const CellSize(24, 6));
      final tree = tester.semantics();
      expect(
        tree.single(role: SemanticRole.region, label: 'Pane').focused,
        isTrue,
        reason: 'the panel reports focus within it',
      );
      expect(tree.focusedNode?.role, role);

      final inspection = tester.semanticInspectionSnapshot();
      expect(inspection.nodeById(inspection.focusedNodeId!)?.role, role.name);
      final accessibility = tester.accessibilitySnapshot();
      expect(accessibility.focusedNode?.role, role);
      expect(
        accessibility.summary.focusedNodeId,
        accessibility.focusedNode?.sourceId,
      );
    }

    testWidgets('a LogRegion', (tester) {
      expectFocused(
        tester,
        const LogRegion(
          autofocus: true,
          entries: [
            LogEntry(
              id: 'a',
              severity: LogSeverity.info,
              source: 'system',
              message: 'booted',
            ),
          ],
        ),
        SemanticRole.log,
      );
    });

    testWidgets('a Button', (tester) {
      expectFocused(
        tester,
        Button(text: 'Deploy', autofocus: true, onPressed: () {}),
        SemanticRole.button,
      );
    });
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

/// What fleury_mcp's `get_ui` serves for [tree]: a served app sends the tree
/// over the semantic wire, the bridge decodes it, and `get_ui` returns the
/// decoded tree's inspection snapshot, capped.
Map<String, Object?> _getUi(SemanticTree tree) {
  final decoded = SemanticsWireDecoder().apply(
    SemanticsWireEncoder().encodeTree(tree)!,
  )!;
  return decoded.toInspectionSnapshot().toJsonCapped(maxNodes: 800);
}
