// Every copy/export path hands text to the clipboard, and from there it is
// pasted into terminals, shells, and editors. A control character that
// survives into a copy can ring the bell, erase what the user sees, or (as
// an escape sequence) drive the terminal it is pasted into. The screen is
// already safe; these pin the copies.
//
// Each export gets hostile text in every string field it copies.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// Escape-led sequences (a CSI colour and an OSC 52 clipboard write), CR,
/// TAB and LF, among quieter controls.
const _loud =
    'a\x00b\x07c\x1B[31md\x1B]52;c;ZXZpbA==\x07e\x7Ff\x9B31mg\x90dcs\x9Ch'
    '\ri\tj\nk';

/// Controls with no escape, CR, LF or TAB beside them: NUL, BEL, BS, VT, FF,
/// SO, DEL, and the C1 controls NEL and ST.
const _quiet = 'a\x00b\x07c\x08d\x0Be\x0Cf\x0Eg\x7Fh\x85i\x9Cj';

/// The code units a copy must not carry: every C0 control except TAB and LF,
/// DEL, and every C1 control.
List<String> _controlsIn(String text) => [
  for (final unit in text.codeUnits)
    if ((unit < 0x20 && unit != 0x09 && unit != 0x0A) ||
        unit == 0x7F ||
        (unit >= 0x80 && unit <= 0x9F))
      'U+${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}',
];

/// Copies [copy] makes of both hostile texts carry no control and no escape
/// payload.
void _expectSafeCopies(Iterable<String> Function(String text) copy) {
  for (final text in const [_loud, _quiet]) {
    for (final copied in copy(text)) {
      expect(_controlsIn(copied), isEmpty, reason: 'copied: $copied');
      expect(
        copied,
        isNot(contains('52;c;')),
        reason: 'an escape sequence goes as a unit, payload included',
      );
    }
  }
}

void main() {
  test('ToolCallCard: exportToolCallSummary', () {
    _expectSafeCopies(
      (text) => [
        exportToolCallSummary(
          ToolCallRecord(
            id: 'call',
            name: text,
            description: text,
            arguments: {text: text},
            output: text,
          ),
        ),
        exportToolCallSummary(
          ToolCallRecord(id: 'call', name: 'run', error: text),
        ),
      ],
    );
  });

  test('LogRegion: exportLogEntries', () {
    _expectSafeCopies(
      (text) => [
        exportLogEntries([LogEntry(message: text, source: text)]).text,
      ],
    );
  });

  test('MessageList: exportMessages', () {
    _expectSafeCopies(
      (text) => [
        exportMessages([MessageEntry(text: text, author: text)]).text,
      ],
    );
  });

  test('TaskGraph: exportTaskGraphNode', () {
    _expectSafeCopies(
      (text) => [
        exportTaskGraphNode(
          TaskGraphNode(
            id: 'task',
            title: text,
            description: text,
            dependsOn: [text],
          ),
        ),
      ],
    );
  });

  test('SearchPanel: exportSearchResult', () {
    _expectSafeCopies(
      (text) => [
        exportSearchResult(
          SearchResult(
            title: text,
            subtitle: text,
            category: text,
            source: text,
            detail: text,
          ),
        ),
      ],
    );
  });

  test('ContextPanel: exportContextItem', () {
    _expectSafeCopies(
      (text) => [
        exportContextItem(
          ContextItem(id: 'item', label: text, source: text, detail: text),
        ),
      ],
    );
  });

  test('TraceTimeline: exportTraceTimelineEntry', () {
    _expectSafeCopies(
      (text) => [
        exportTraceTimelineEntry(
          TraceTimelineEntry(
            id: 'event',
            label: text,
            source: text,
            detail: text,
          ),
        ),
      ],
    );
  });

  test('ConversationNavigator: exportConversation', () {
    _expectSafeCopies(
      (text) => [
        exportConversation(
          ConversationEntry(id: 'thread', title: text, latestMessage: text),
        ),
      ],
    );
  });

  test('PatchReview: exportPatchReviewFile', () {
    _expectSafeCopies(
      (text) => [
        exportPatchReviewFile(PatchReviewFile(path: text, summary: text)),
      ],
    );
  });

  test('FileMentionPicker: exportFileMention', () {
    _expectSafeCopies(
      (text) => [
        for (final copyMentionText in const [true, false])
          exportFileMention(
            FileMentionEntry(path: text, detail: text),
            options: FileMentionCopyOptions(
              copyMentionText: copyMentionText,
              includeDetail: true,
            ),
          ),
      ],
    );
  });

  test('FileBrowser: exportFileBrowserEntry', () {
    _expectSafeCopies(
      (text) => [
        for (final copyAbsolutePath in const [true, false])
          exportFileBrowserEntry(
            FileEntry(path: text, name: text, type: FileEntryType.file),
            options: FileBrowserCopyOptions(copyAbsolutePath: copyAbsolutePath),
          ),
      ],
    );
  });

  test('DataTable: exportDataTableRows', () {
    _expectSafeCopies(
      (text) => [
        for (final format in DataTableExportFormat.values)
          exportDataTableRows(
            rowCount: 1,
            columns: [DataTableColumn(id: 'c', title: text)],
            cellBuilder: (row, column) => text,
            options: DataTableExportOptions(format: format),
          ).text,
      ],
    );
  });

  test('Table: exportTableRows', () {
    _expectSafeCopies(
      (text) => [
        for (final format in TableExportFormat.values)
          exportTableRows(
            rows: [
              [Text(text)],
            ],
            header: [Text(text)],
            options: TableExportOptions(format: format),
          ).text,
      ],
    );
  });

  test('TreeTable: exportTreeTableRows', () {
    _expectSafeCopies((text) {
      final columns = [
        DataTableColumn(id: 'name', title: text),
        DataTableColumn(id: 'size', title: text),
      ];
      final rows = buildTreeTableRows<void>(
        roots: [
          TreeTableNode(key: 'k', label: text, cells: {'size': text}),
        ],
        columns: columns,
      );
      return [
        for (final format in DataTableExportFormat.values)
          exportTreeTableRows<void>(
            rows: rows,
            columns: columns,
            options: TreeTableExportOptions(format: format),
          ).text,
      ];
    });
  });

  test('CodeView: exportCodeSelection', () {
    _expectSafeCopies((text) {
      final document = CodeDocument.parse(text);
      return [
        for (final mode in CodeViewCopyMode.values)
          for (var line = 0; line < document.lines.length; line++)
            exportCodeSelection(
              document,
              lineIndex: line,
              options: CodeViewCopyOptions(mode: mode),
            ),
      ];
    });
  });

  test('DiffView: exportDiffSelection', () {
    _expectSafeCopies((text) {
      final document = DiffDocument.parseUnified(
        '--- a/$text\n+++ b/$text\n@@ -1 +1 @@ $text\n-$text\n+$text\n',
      );
      return [
        for (final mode in DiffViewCopyMode.values)
          for (var row = 0; row < document.rows.length; row++)
            exportDiffSelection(
              document,
              rowIndex: row,
              options: DiffViewCopyOptions(mode: mode),
            ),
      ];
    });
  });

  test('MarkdownView: exportMarkdownSelection', () {
    _expectSafeCopies((text) {
      final document = MarkdownDocument.parse(
        '# $text\n\n$text\n\n```\n$text\n```\n',
      );
      return [
        for (final mode in MarkdownViewCopyMode.values)
          for (var block = 0; block < document.blocks.length; block++)
            exportMarkdownSelection(
              document,
              blockIndex: block,
              options: MarkdownViewCopyOptions(mode: mode),
            ),
      ];
    });
  });

  test('JsonView: exportJsonViewRow', () {
    _expectSafeCopies((text) {
      final rows = buildJsonViewRows({
        text: text,
        'list': [text],
      }, defaultExpandedDepth: 3);
      return [
        for (final mode in JsonViewCopyMode.values)
          for (final row in rows)
            exportJsonViewRow(row, options: JsonViewCopyOptions(mode: mode)),
      ];
    });
  });
}
