import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

CellStyle _styleAt(FleuryTester tester, int col, int row) {
  return tester.render(size: const CellSize(40, 6)).atColRow(col, row).style;
}

void main() {
  test('FleuryWidgetTheme participates in ThemeData extension lookup', () {
    const componentTheme = FleuryWidgetTheme(
      controlFocusStyle: CellStyle(underline: true),
    );
    final theme = ThemeData(extensions: const [componentTheme]);

    expect(FleuryWidgetTheme.from(theme), componentTheme);
    expect(
      componentTheme.copyWith(disabledStyle: const CellStyle(dim: true)),
      const FleuryWidgetTheme(
        controlFocusStyle: CellStyle(underline: true),
        disabledStyle: CellStyle(dim: true),
      ),
    );
  });

  testWidgets('control focus style comes from FleuryWidgetTheme', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              controlFocusStyle: CellStyle(underline: true, bold: false),
            ),
          ],
        ),
        child: Checkbox(value: false, autofocus: true, onChanged: _ignoreBool),
      ),
    );

    final style = _styleAt(tester, 0, 0);
    expect(style.underline, isTrue);
    expect(style.bold, isFalse);
  });

  testWidgets('disabled button style comes from FleuryWidgetTheme', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          extensions: [
            FleuryWidgetTheme(
              disabledStyle: CellStyle(foreground: AnsiColor(13)),
            ),
          ],
        ),
        child: Button(label: 'Save', onPressed: null),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(13));
    expect(_styleAt(tester, 0, 0).dim, isFalse);
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
        child: DiffView(diff: '@@ -1 +1 @@\n-old\n+new\n'),
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

String _dataCell(int rowIndex, String columnId) => 'row-$rowIndex';
