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

int _cellsWithForeground(
  FleuryTester tester,
  Color color, {
  CellSize size = const CellSize(40, 10),
}) {
  final buffer = tester.render(size: size);
  var count = 0;
  for (var row = 0; row < size.rows; row++) {
    for (var col = 0; col < size.cols; col++) {
      if (buffer.atColRow(col, row).style.foreground == color) count++;
    }
  }
  return count;
}

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

  testWidgets('switch track theme uses base and selected state styling', (
    tester,
  ) {
    Widget themedSwitch(bool value) => Theme(
      data: const ThemeData(
        extensions: [
          FleuryWidgetTheme(
            switchTrackStyle: CellStyle.interactive(
              base: CellStyle(foreground: AnsiColor(8)),
              selected: CellStyle(foreground: AnsiColor(2)),
            ),
          ),
        ],
      ),
      child: Switch(value: value, onChanged: _ignoreBool),
    );

    tester.pumpWidget(themedSwitch(false));
    expect(_styleAt(tester, 1, 0).foreground, const AnsiColor(8));

    tester.pumpWidget(themedSwitch(true));
    expect(_styleAt(tester, 1, 0).foreground, const AnsiColor(2));
  });

  testWidgets('control focus style comes from ThemeData.interactiveStyle', (
    tester,
  ) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          interactiveStyle: CellStyle.interactive(
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

  testWidgets('disabled button style comes from ThemeData.interactiveStyle', (
    tester,
  ) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          interactiveStyle: CellStyle.interactive(
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
          interactiveStyle: CellStyle.interactive(
            focused: CellStyle(underline: true),
          ),
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
          interactiveStyle: CellStyle.interactive(
            focused: CellStyle(foreground: AnsiColor(5), bold: true),
          ),
        ),
        child: Checkbox(
          value: false,
          autofocus: true,
          onChanged: _ignoreBool,
          style: CellStyle.interactive(focused: CellStyle(underline: true)),
        ),
      ),
    );

    final style = _styleAt(tester, 0, 0);
    expect(style.foreground, isNull);
    expect(style.bold, isFalse);
    expect(style.underline, isTrue);
  });

  testWidgets('CellStyle.none suppresses one inherited state cue', (tester) {
    tester.pumpWidget(
      const Theme(
        data: ThemeData(
          interactiveStyle: CellStyle.interactive(
            focused: CellStyle(underline: true),
          ),
        ),
        child: Checkbox(
          value: false,
          autofocus: true,
          onChanged: _ignoreBool,
          style: CellStyle.interactive(focused: CellStyle.none),
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
          interactiveStyle: CellStyle.interactive(
            selected: CellStyle(underline: true),
          ),
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
        style: CellStyle.interactive(
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
          interactiveStyle: CellStyle.interactive(
            hovered: CellStyle(underline: true),
          ),
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

  testWidgets('TextInput and PasswordInput forward focused styling', (tester) {
    const focused = AnsiColor(13);
    tester.pumpWidget(
      const TextInput(
        autofocus: true,
        placeholder: 'Name',
        style: CellStyle.interactive(focused: CellStyle(foreground: focused)),
      ),
    );
    expect(_cellsWithForeground(tester, focused), greaterThan(0));

    tester.pumpWidget(
      const PasswordInput(
        autofocus: true,
        placeholder: 'Secret',
        style: CellStyle.interactive(focused: CellStyle(foreground: focused)),
      ),
    );
    expect(_cellsWithForeground(tester, focused), greaterThan(0));
  });

  testWidgets('Select, Stepper, and RangeSlider emit focused styling', (
    tester,
  ) {
    const focused = AnsiColor(13);
    tester.pumpWidget(
      Select<String>(
        options: const [SelectOption(value: 'a', label: 'Alpha')],
        value: 'a',
        autofocus: true,
        onChanged: _ignoreString,
        style: const CellStyle.interactive(
          focused: CellStyle(foreground: focused),
        ),
      ),
    );
    expect(_styleAt(tester, 0, 0).foreground, focused);

    tester.pumpWidget(
      Stepper(
        value: 1,
        autofocus: true,
        onChanged: _ignoreNum,
        style: const CellStyle.interactive(
          focused: CellStyle(foreground: focused),
        ),
      ),
    );
    expect(_styleAt(tester, 0, 0).foreground, focused);

    tester.pumpWidget(
      RangeSlider(
        values: const (2, 8),
        min: 0,
        max: 10,
        autofocus: true,
        onChanged: _ignoreRange,
        style: const CellStyle.interactive(
          focused: CellStyle(foreground: focused),
        ),
      ),
    );
    expect(_cellsWithForeground(tester, focused), greaterThan(0));
  });

  testWidgets('MultiSelect emits selected styling', (tester) {
    const selected = AnsiColor(13);
    tester.pumpWidget(
      MultiSelect<String>(
        options: const [SelectOption(value: 'a', label: 'Alpha')],
        values: const {'a'},
        onChanged: _ignoreStrings,
        style: const CellStyle.interactive(
          selected: CellStyle(foreground: selected),
        ),
      ),
    );

    expect(_cellsWithForeground(tester, selected), greaterThan(0));
  });

  testWidgets('ColorPicker emits selected styling', (tester) {
    const selected = AnsiColor(13);
    tester.pumpWidget(
      ColorPicker(
        value: const AnsiColor(0),
        onChanged: _ignoreColor,
        style: const CellStyle.interactive(
          selected: CellStyle(foreground: selected),
        ),
      ),
    );

    expect(_cellsWithForeground(tester, selected), greaterThan(0));
  });

  testWidgets('DatePicker selected styling targets the selected date', (
    tester,
  ) {
    const selected = AnsiColor(13);
    tester.pumpWidget(
      DatePicker(
        value: DateTime(2024, 1, 15),
        onChanged: _ignoreDate,
        style: const CellStyle.interactive(
          selected: CellStyle(foreground: selected),
        ),
      ),
    );

    final buffer = tester.render(size: const CellSize(30, 8));
    expect(buffer.atColRow(2, 0).style.foreground, isNot(selected));
    expect(buffer.atColRow(3, 4).style.foreground, selected);
  });

  testWidgets('changing ThemeData updates mounted control styling', (tester) {
    Widget themed(Color color) => Theme(
      data: ThemeData(interactiveStyle: CellStyle(foreground: color)),
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

  testWidgets('ProgressBar inherits semantic theme roles by default', (tester) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          mutedStyle: CellStyle(foreground: AnsiColor(8)),
          colorScheme: ColorScheme(primary: AnsiColor(6)),
        ),
        child: SizedBox(width: 10, child: ProgressBar(value: 0.5)),
      ),
    );

    expect(_styleAt(tester, 0, 0).foreground, const AnsiColor(6));
    expect(_styleAt(tester, 7, 0).foreground, const AnsiColor(8));
    expect(_styleAt(tester, 7, 0).dim, isTrue);
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

  testWidgets('JsonView invalid document falls back to ThemeData.errorStyle', (
    tester,
  ) {
    tester.pumpWidget(
      Theme(
        data: const ThemeData(
          errorStyle: CellStyle(foreground: AnsiColor(1), underline: true),
        ),
        child: JsonView.string('{ bad json'),
      ),
    );

    final style = _styleAt(tester, 0, 0);
    expect(style.foreground, const AnsiColor(1));
    expect(style.underline, isTrue);
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
void _ignoreColor(Color _) {}
void _ignoreDate(DateTime _) {}
void _ignoreNum(num _) {}
void _ignoreRange((num, num) _) {}
void _ignoreString(String _) {}
void _ignoreStrings(Set<String> _) {}
void _noop() {}

String _dataCell(int rowIndex, String columnId) => 'row-$rowIndex';
