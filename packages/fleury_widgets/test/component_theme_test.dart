import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

CellStyle _styleAt(FleuryTester tester, int col, int row) {
  return tester.render(size: const CellSize(40, 6)).atColRow(col, row).style;
}

MouseEvent _moveTo(int col, int row) => MouseEvent(
  kind: MouseEventKind.moved,
  button: MouseButton.none,
  col: col,
  row: row,
);

void main() {
  test('FleuryWidgetTheme participates in ThemeData extension lookup', () {
    const componentTheme = FleuryWidgetTheme(
      progressFilledStyle: CellStyle(underline: true),
    );
    final theme = ThemeData(extensions: const [componentTheme]);

    expect(FleuryWidgetTheme.from(theme), componentTheme);
    expect(
      componentTheme.copyWith(progressTrackStyle: const CellStyle(dim: true)),
      const FleuryWidgetTheme(
        progressFilledStyle: CellStyle(underline: true),
        progressTrackStyle: CellStyle(dim: true),
      ),
    );
  });

  testWidgets('control focus style comes from ThemeData.controlStyle', (
    tester,
  ) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          controlStyle: CellStyle.state(
            focused: CellStyle(underline: true, bold: false),
          ),
        ),
        child: Checkbox(value: false, autofocus: true, onChanged: _ignoreBool),
      ),
    );

    final style = _styleAt(tester, 0, 0);
    expect(style.underline, isTrue);
    expect(style.bold, isFalse);
  });

  testWidgets('disabled button style comes from ThemeData.controlStyle', (
    tester,
  ) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          controlStyle: CellStyle.state(
            disabled: CellStyle(foreground: AnsiColor(13)),
          ),
        ),
        child: Button(label: 'Save', onPressed: null),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(13));
    expect(_styleAt(tester, 0, 0).dim, isFalse);
  });

  testWidgets('a plain local style keeps the inherited focus cue', (tester) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(
          controlStyle: CellStyle.state(focused: CellStyle(underline: true)),
        ),
        child: Checkbox(
          value: false,
          autofocus: true,
          onChanged: _ignoreBool,
          style: CellStyle(foreground: AnsiColor(6)),
        ),
      ),
    );

    final style = _styleAt(tester, 0, 0);
    expect(style.foreground, const AnsiColor(6));
    expect(style.underline, isTrue);
  });

  testWidgets('a local state patch replaces the corresponding theme patch', (
    tester,
  ) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(
          controlStyle: CellStyle.state(
            focused: CellStyle(foreground: AnsiColor(5), bold: true),
          ),
        ),
        child: Checkbox(
          value: false,
          autofocus: true,
          onChanged: _ignoreBool,
          style: CellStyle.state(focused: CellStyle(underline: true)),
        ),
      ),
    );

    final style = _styleAt(tester, 0, 0);
    expect(style.foreground, isNull);
    expect(style.bold, isFalse);
    expect(style.underline, isTrue);
  });

  testWidgets('CellStyle.empty suppresses one inherited state cue', (tester) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(
          controlStyle: CellStyle.state(focused: CellStyle(underline: true)),
        ),
        child: Checkbox(
          value: false,
          autofocus: true,
          onChanged: _ignoreBool,
          style: CellStyle.state(focused: CellStyle.empty),
        ),
      ),
    );

    expect(_styleAt(tester, 0, 0).underline, isFalse);
  });

  testWidgets('selected is emitted by value controls but not buttons', (
    tester,
  ) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          controlStyle: CellStyle.state(selected: CellStyle(underline: true)),
        ),
        child: Column(
          children: [
            Checkbox(value: true, onChanged: _ignoreBool),
            Button(label: 'Run', onPressed: _noop),
          ],
        ),
      ),
    );

    expect(_styleAt(tester, 0, 0).underline, isTrue);
    expect(_styleAt(tester, 0, 1).underline, isFalse);
  });

  testWidgets('disabled is exclusive of selected styling', (tester) {
    tester.pumpWidget(
      const Checkbox(
        value: true,
        onChanged: null,
        style: CellStyle.state(
          selected: CellStyle(foreground: AnsiColor(2)),
          disabled: CellStyle(foreground: AnsiColor(13)),
        ),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(13));
  });

  testWidgets('hover styling follows pointer entry and exit', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          controlStyle: CellStyle.state(hovered: CellStyle(underline: true)),
        ),
        child: Button(label: 'Run', onPressed: _noop),
      ),
    );
    tester.render(size: const CellSize(40, 6));

    tester.sendMouse(_moveTo(2, 0));
    expect(_styleAt(tester, 0, 0).underline, isTrue);

    tester.sendMouse(_moveTo(2, 3));
    expect(_styleAt(tester, 0, 0).underline, isFalse);
  });

  testWidgets('changing ThemeData updates mounted control styling', (tester) {
    Widget themed(Color color) => Theme(
      data: ThemeData(controlStyle: CellStyle(foreground: color)),
      child: const Checkbox(value: false, onChanged: _ignoreBool),
    );

    tester.pumpWidget(themed(const AnsiColor(2)));
    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(2));

    tester.pumpWidget(themed(const AnsiColor(4)));
    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(4));
  });

  testWidgets('ProgressBar uses component theme defaults', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              progressFilledStyle: CellStyle(foreground: AnsiColor(10)),
              progressTrackStyle: CellStyle(foreground: AnsiColor(8)),
            ),
          ],
        ),
        child: SizedBox(width: 10, child: ProgressBar(value: 0.5)),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(10));
    expect(_styleAt(tester, 7, 0).foreground, const AnsiColor(8));
  });

  testWidgets('data widget selection and separators use component theme', (
    tester,
  ) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              dataSelectedStyle: CellStyle(background: AnsiColor(5)),
              dataSeparatorStyle: CellStyle(foreground: AnsiColor(8)),
            ),
          ],
        ),
        child: DataTable(
          rowCount: 1,
          autofocus: true,
          columns: [
            DataTableColumn(
              id: 'name',
              title: 'Name',
              width: FixedColumnWidth(8),
            ),
          ],
          cellBuilder: _dataCell,
        ),
      ),
    );

    expect(_styleAt(tester, 0, 1).foreground, const AnsiColor(8));
    expect(_styleAt(tester, 0, 2).background, const AnsiColor(5));
  });

  testWidgets('explicit data selection style overrides component theme', (
    tester,
  ) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(
          extensions: [
            FleuryWidgetTheme(
              dataSelectedStyle: CellStyle(background: AnsiColor(5)),
            ),
          ],
        ),
        child: DataTable(
          rowCount: 1,
          autofocus: true,
          selectedStyle: CellStyle(background: AnsiColor(2)),
          columns: [
            DataTableColumn(
              id: 'name',
              title: 'Name',
              width: FixedColumnWidth(8),
            ),
          ],
          cellBuilder: _dataCell,
        ),
      ),
    );

    expect(_styleAt(tester, 0, 2).background, const AnsiColor(2));
  });

  testWidgets('TreeTable empty state uses data empty style', (tester) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(
          extensions: [
            FleuryWidgetTheme(
              dataEmptyStyle: CellStyle(foreground: AnsiColor(12)),
            ),
          ],
        ),
        child: TreeTable<Object?>(
          roots: [],
          columns: [
            DataTableColumn(
              id: 'name',
              title: 'Name',
              width: FixedColumnWidth(8),
            ),
          ],
        ),
      ),
    );

    expect(_styleAt(tester, 2, 2).foreground, const AnsiColor(12));
  });

  testWidgets('LogRegion severity styles use component theme', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              logWarningStyle: CellStyle(foreground: AnsiColor(11)),
            ),
          ],
        ),
        child: LogRegion(
          controller: LogRegionController(followTail: false),
          entries: const [
            LogEntry(severity: LogSeverity.warning, message: 'careful'),
          ],
        ),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(11));
  });

  testWidgets('CodeView line-kind styles use component theme', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              codeImportStyle: CellStyle(foreground: AnsiColor(6)),
              codeCommentStyle: CellStyle(foreground: AnsiColor(8)),
              codeDeclarationStyle: CellStyle(
                foreground: AnsiColor(13),
                underline: true,
              ),
              codeKeywordStyle: CellStyle(foreground: AnsiColor(12)),
              codeStringStyle: CellStyle(foreground: AnsiColor(10)),
            ),
          ],
        ),
        child: CodeView(
          source:
              "import 'dart:io';\n"
              '// note\n'
              'final class Demo {}\n'
              'return value;\n'
              "'string';\n",
          showLineNumbers: false,
        ),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(6));
    expect(_styleAt(tester, 0, 1).foreground, const AnsiColor(8));
    expect(_styleAt(tester, 0, 2).foreground, const AnsiColor(13));
    expect(_styleAt(tester, 0, 2).underline, isTrue);
    expect(_styleAt(tester, 0, 3).foreground, const AnsiColor(12));
    expect(_styleAt(tester, 0, 4).foreground, const AnsiColor(10));
  });

  testWidgets('DiffView line-kind styles use component theme', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              diffAdditionStyle: CellStyle(foreground: AnsiColor(2)),
              diffDeletionStyle: CellStyle(foreground: AnsiColor(1)),
            ),
          ],
        ),
        // showLineNumbers off so cell coordinates address the diff text
        // directly (this test asserts line-kind colors, not the gutter).
        child: DiffView(
          diff: '@@ -1 +1 @@\n-old\n+new\n',
          showLineNumbers: false,
        ),
      ),
    );

    expect(_styleAt(tester, 0, 1).foreground, const AnsiColor(1));
    expect(_styleAt(tester, 0, 2).foreground, const AnsiColor(2));
  });

  testWidgets('JsonView invalid-document style uses component theme', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              jsonErrorStyle: CellStyle(foreground: AnsiColor(9)),
            ),
          ],
        ),
        child: JsonView.string('{ bad json'),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(9));
  });

  testWidgets('explicit ProgressBar styles override component theme', (tester) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(
          extensions: [
            FleuryWidgetTheme(
              progressFilledStyle: CellStyle(foreground: AnsiColor(10)),
              progressTrackStyle: CellStyle(foreground: AnsiColor(8)),
            ),
          ],
        ),
        child: SizedBox(
          width: 10,
          child: ProgressBar(
            value: 0.5,
            filledStyle: CellStyle(foreground: AnsiColor(2)),
            trackStyle: CellStyle(foreground: AnsiColor(3)),
          ),
        ),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(2));
    expect(_styleAt(tester, 7, 0).foreground, const AnsiColor(3));
  });

  testWidgets('MarkdownView block styles come from component theme', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              markdownHeadingStyle: CellStyle(foreground: AnsiColor(14)),
              markdownCodeBlockStyle: CellStyle(background: AnsiColor(5)),
            ),
          ],
        ),
        child: MarkdownView(
          markdown: '# Title\n```dart\nfinal x = 1;\n```',
          controller: MarkdownViewController(selectedIndex: 1),
        ),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(14));
    expect(_styleAt(tester, 0, 1).background, const AnsiColor(5));
  });
}

void _ignoreBool(bool _) {}
void _noop() {}

String _dataCell(int rowIndex, String columnId) => 'row-$rowIndex';
