import 'dart:async' show unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'component_theme.dart';

/// Logical row type in a [DiffView].
enum DiffLineKind {
  metadata,
  fileHeader,
  hunkHeader,
  context,
  addition,
  deletion,
  marker,
}

/// Clipboard/export mode for [DiffView] selected-row copy.
enum DiffViewCopyMode {
  /// Copy the selected visible row.
  line,

  /// Copy the selected row's hunk, including its header.
  hunk,
}

/// A parsed unified diff document.
final class DiffDocument {
  const DiffDocument({
    required this.rows,
    required this.fileCount,
    required this.hunkCount,
    required this.additionCount,
    required this.deletionCount,
  });

  factory DiffDocument.parseUnified(
    /// Unified-diff source text to parse and sanitize.
    String source,
  ) {
    return parseUnifiedDiff(source);
  }

  /// Parsed diff rows in source order.
  final List<DiffLine> rows;

  /// Number of files represented by parsed file headers.
  final int fileCount;

  /// Number of parsed unified-diff hunks.
  final int hunkCount;

  /// Number of added source lines, excluding headers.
  final int additionCount;

  /// Number of deleted source lines, excluding headers.
  final int deletionCount;

  bool get isEmpty => rows.isEmpty;
}

/// One parsed unified-diff row.
final class DiffLine {
  const DiffLine({
    required this.index,
    required this.kind,
    required this.text,
    required this.displayText,
    required this.fileIndex,
    required this.hunkIndex,
    required this.oldLine,
    required this.newLine,
    required this.oldPath,
    required this.newPath,
    required this.outputSanitized,
    required this.outputTruncated,
    required this.outputOriginalLength,
  });

  /// Zero-based row index in the containing [DiffDocument].
  final int index;

  /// Logical unified-diff row classification.
  final DiffLineKind kind;

  /// Sanitized source row, including its unified-diff prefix.
  final String text;

  /// Render-ready row after optional truncation.
  final String displayText;

  /// Zero-based inferred file-section index, or null until a file header or
  /// hunk is parsed.
  final int? fileIndex;

  /// Zero-based hunk index, or null when the row is outside a hunk.
  final int? hunkIndex;

  /// One-based old-file line number when this row maps to the old file.
  final int? oldLine;

  /// One-based new-file line number when this row maps to the new file.
  final int? newLine;

  /// Normalized path parsed from the current old-file header.
  final String? oldPath;

  /// Normalized path parsed from the current new-file header.
  final String? newPath;

  /// Whether unsafe terminal text was replaced while producing [text].
  final bool outputSanitized;

  /// Whether [displayText] was shortened to the configured line limit.
  final bool outputTruncated;

  /// Source row length before sanitization or display truncation.
  final int outputOriginalLength;

  String? get filePath => newPath ?? oldPath;
}

/// Controller for [DiffView] selection.
class DiffViewController extends ChangeNotifier {
  DiffViewController({
    /// Zero-based row selected when the controller is created.
    int selectedIndex = 0,
  }) : _list = ListController(selectedIndex: selectedIndex) {
    _list.addListener(notifyListeners);
  }

  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    _list.jumpToIndex(index);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('DiffViewController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _list.removeListener(notifyListeners);
    _list.dispose();
    super.dispose();
  }
}

/// Options for copying a [DiffView] selected row.
final class DiffViewCopyOptions {
  const DiffViewCopyOptions({
    this.mode = DiffViewCopyMode.line,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  /// Whether copy exports one row or its complete containing hunk.
  final DiffViewCopyMode mode;

  /// Transport-selection policy for platform tools, SSH, and OSC 52 writes.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [DiffView] copies a row or hunk.
final class DiffViewCopyResult {
  const DiffViewCopyResult({
    required this.rowIndex,
    required this.row,
    required this.text,
    required this.report,
  });

  /// Zero-based index of the row selected for the copy operation.
  final int rowIndex;

  /// Selected parsed diff row.
  final DiffLine row;

  /// Sanitized row or hunk text submitted to the clipboard.
  final String text;

  /// Transport outcome and capability diagnostics for the clipboard write.
  final ClipboardWriteReport report;
}

/// Parses a unified diff into sanitized [DiffLine] rows.
DiffDocument parseUnifiedDiff(String source, {int? maxLineLength = 1000}) {
  final rows = <DiffLine>[];
  var fileIndex = -1;
  var hunkIndex = -1;
  int? currentHunkIndex;
  var additionCount = 0;
  var deletionCount = 0;
  String? oldPath;
  String? newPath;
  int? oldCursor;
  int? newCursor;
  // Unconsumed old/new-side lines promised by the current hunk's `@@` header.
  // While either is positive we are inside a hunk body, where a leading
  // '-'/'+' is always a removed/added content line (its remaining text is
  // arbitrary) — never a '---'/'+++' file header.
  var remainingOld = 0;
  var remainingNew = 0;

  void addRow({
    required DiffLineKind kind,
    required String text,
    int? oldLine,
    int? newLine,
  }) {
    final formatted = _formatDiffLine(kind, text, maxLineLength);
    rows.add(
      DiffLine(
        index: rows.length,
        kind: kind,
        text: formatted.safeText,
        displayText: formatted.displayText,
        fileIndex: fileIndex >= 0 ? fileIndex : null,
        hunkIndex: currentHunkIndex,
        oldLine: oldLine,
        newLine: newLine,
        oldPath: oldPath,
        newPath: newPath,
        outputSanitized: formatted.sanitized,
        outputTruncated: formatted.truncated,
        outputOriginalLength: text.length,
      ),
    );
  }

  final rawLines = source.split('\n');
  if (rawLines.isNotEmpty && rawLines.last.isEmpty) rawLines.removeLast();
  for (final raw in rawLines) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    final inHunkBody = remainingOld > 0 || remainingNew > 0;
    // `diff --git` and `@@` never carry a +/-/space prefix, so a bare one at
    // column 0 is unambiguous even mid-hunk — a new file/hunk resets the body.
    if (line.startsWith('diff --git ')) {
      fileIndex += 1;
      oldPath = null;
      newPath = null;
      oldCursor = null;
      newCursor = null;
      remainingOld = 0;
      remainingNew = 0;
      currentHunkIndex = null;
      addRow(kind: DiffLineKind.fileHeader, text: line);
      continue;
    }
    // '---'/'+++' are file headers only outside a hunk body; inside one an
    // identical prefix is a deleted/added line whose content starts with -/+.
    if (!inHunkBody && line.startsWith('--- ')) {
      oldPath = _normalizeDiffPath(line.substring(4));
      if (fileIndex < 0) fileIndex = 0;
      currentHunkIndex = null;
      addRow(kind: DiffLineKind.fileHeader, text: line);
      continue;
    }
    if (!inHunkBody && line.startsWith('+++ ')) {
      newPath = _normalizeDiffPath(line.substring(4));
      if (fileIndex < 0) fileIndex = 0;
      currentHunkIndex = null;
      addRow(kind: DiffLineKind.fileHeader, text: line);
      continue;
    }
    final hunk = _hunkPattern.firstMatch(line);
    if (hunk != null) {
      hunkIndex += 1;
      oldCursor = int.parse(hunk.group(1)!);
      newCursor = int.parse(hunk.group(3)!);
      // Groups 2/4 are the old/new line counts (absent ⇒ 1); they bound the
      // hunk body so the parser knows when '---'/'+++' become headers again.
      remainingOld = hunk.group(2) != null ? int.parse(hunk.group(2)!) : 1;
      remainingNew = hunk.group(4) != null ? int.parse(hunk.group(4)!) : 1;
      if (fileIndex < 0) fileIndex = 0;
      currentHunkIndex = hunkIndex;
      addRow(kind: DiffLineKind.hunkHeader, text: line);
      continue;
    }
    // '\ No newline at end of file' annotates the previous line and consumes
    // no old/new line, so it is handled regardless of the remaining counts.
    if (line.startsWith(r'\ ')) {
      addRow(kind: DiffLineKind.marker, text: line);
      continue;
    }
    if (inHunkBody && line.startsWith('+')) {
      final currentNew = newCursor;
      addRow(kind: DiffLineKind.addition, text: line, newLine: currentNew);
      if (newCursor != null) newCursor += 1;
      additionCount += 1;
      if (remainingNew > 0) remainingNew -= 1;
      continue;
    }
    if (inHunkBody && line.startsWith('-')) {
      final currentOld = oldCursor;
      addRow(kind: DiffLineKind.deletion, text: line, oldLine: currentOld);
      if (oldCursor != null) oldCursor += 1;
      deletionCount += 1;
      if (remainingOld > 0) remainingOld -= 1;
      continue;
    }
    if (inHunkBody && line.startsWith(' ')) {
      final currentOld = oldCursor;
      final currentNew = newCursor;
      addRow(
        kind: DiffLineKind.context,
        text: line,
        oldLine: currentOld,
        newLine: currentNew,
      );
      if (oldCursor != null) oldCursor += 1;
      if (newCursor != null) newCursor += 1;
      if (remainingOld > 0) remainingOld -= 1;
      if (remainingNew > 0) remainingNew -= 1;
      continue;
    }
    currentHunkIndex = null;
    addRow(kind: DiffLineKind.metadata, text: line);
  }

  final fileCount = rows
      .where((row) => row.kind == DiffLineKind.fileHeader)
      .map((row) => row.fileIndex)
      .whereType<int>()
      .toSet()
      .length;
  return DiffDocument(
    rows: List<DiffLine>.unmodifiable(rows),
    fileCount: fileCount,
    hunkCount: hunkIndex + 1,
    additionCount: additionCount,
    deletionCount: deletionCount,
  );
}

/// Exports the selected line or containing hunk as sanitized diff text.
String exportDiffSelection(
  DiffDocument document, {
  required int rowIndex,
  DiffViewCopyOptions options = const DiffViewCopyOptions(),
}) {
  if (document.rows.isEmpty) return '';
  final selectedIndex = rowIndex.clamp(0, document.rows.length - 1);
  final row = document.rows[selectedIndex];
  return switch (options.mode) {
    DiffViewCopyMode.line => row.text,
    DiffViewCopyMode.hunk => _exportHunk(document, row, selectedIndex),
  };
}

/// A unified-diff viewer: additions, deletions, and hunk/file headers each
/// styled, with the conventional old | new line-number gutter. The selection
/// moves by row with the keyboard, and Ctrl+C copies the selected line — or
/// its whole hunk, header included.
class DiffView extends StatefulWidget {
  DiffView({
    super.key,

    /// Unified-diff source parsed into [document] before mounting.
    required String diff,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Diff',
    this.maxLineLength = 1000,
    this.showLineNumbers = true,
    this.copySelection = true,
    this.copyOptions = const DiffViewCopyOptions(),
    this.onCopy,
  }) : document = parseUnifiedDiff(diff, maxLineLength: maxLineLength),
       assert(maxLineLength == null || maxLineLength >= 0);

  /// Creates a viewer from an already parsed [DiffDocument].
  ///
  /// The document's sanitized, optionally truncated rows are reused without
  /// parsing the unified-diff source again.
  const DiffView.document({
    super.key,
    required this.document,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Diff',
    this.maxLineLength = 1000,
    this.showLineNumbers = true,
    this.copySelection = true,
    this.copyOptions = const DiffViewCopyOptions(),
    this.onCopy,
  }) : assert(maxLineLength == null || maxLineLength >= 0);

  /// Parsed unified diff document to render.
  final DiffDocument document;

  /// External selection and visible-range controller.
  final DiffViewController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the viewer should request focus when mounted.
  final bool autofocus;

  /// Semantic label (the accessibility name; not rendered) for the diff viewer.
  final String semanticLabel;

  /// Maximum displayed line length.
  final int? maxLineLength;

  /// Render an old | new line-number gutter (the universal unified-diff
  /// convention — delta, GitHub, git pager). The data is tracked either way.
  final bool showLineNumbers;

  /// Whether Ctrl+C and semantic copy export the selected row/hunk.
  final bool copySelection;

  /// Clipboard/export options for copied diff text.
  final DiffViewCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(DiffViewCopyResult result)? onCopy;

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  late DiffViewController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DiffViewController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'DiffView');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant DiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? DiffViewController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'DiffView');
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  void _onControllerChange() => setState(() {});

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  DiffLine? _selectedRow() {
    final rows = widget.document.rows;
    if (rows.isEmpty) return null;
    final selected = (_controller.selectedIndex ?? 0).clamp(0, rows.length - 1);
    return rows[selected];
  }

  Future<void> _copySelection() async {
    final rows = widget.document.rows;
    if (!widget.copySelection || rows.isEmpty) return;
    final selectedIndex = (_controller.selectedIndex ?? 0).clamp(
      0,
      rows.length - 1,
    );
    final text = exportDiffSelection(
      widget.document,
      rowIndex: selectedIndex,
      options: widget.copyOptions,
    );
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      DiffViewCopyResult(
        rowIndex: selectedIndex,
        row: rows[selectedIndex],
        text: text,
        report: report,
      ),
    );
  }

  Future<void> _copyRowAt(int index) async {
    final rows = widget.document.rows;
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection();
  }

  void _selectRowAt(int index) {
    final rows = widget.document.rows;
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
  }

  Future<void> _handleDiffAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.document.rows;
    final selected = _selectedRow();
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && rows.isNotEmpty;
    final gutterWidth = widget.showLineNumbers ? _diffGutterWidth(rows) : 0;
    Widget list = rows.isEmpty
        ? const Text('  (empty diff)', style: CellStyle(dim: true))
        : ListView.builder(
            controller: _controller._listController,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            itemCount: rows.length,
            itemBuilder: (context, index, activeSelected) {
              final selected = index == _controller.selectedIndex;
              return _DiffLineWidget(
                row: rows[index],
                selected: selected,
                activeSelection: activeSelected,
                copyEnabled: copyEnabled,
                gutterWidth: gutterWidth,
                onActivate: () => _selectRowAt(index),
                onCopy: () => _copyRowAt(index),
              );
            },
          );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy diff selection',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.diff,
        label: widget.semanticLabel,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleDiffAction,
        state: SemanticState({
          'collectionRowCount': rows.length,
          'fileCount': widget.document.fileCount,
          'hunkCount': widget.document.hunkCount,
          'additionCount': widget.document.additionCount,
          'deletionCount': widget.document.deletionCount,
          'copyEnabled': copyEnabled,
          'copyMode': widget.copyOptions.mode.name,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          if (_controller.selectedIndex != null)
            'selectedIndex': _controller.selectedIndex,
          if (selected != null) ...{
            'selectedKey': selected.index,
            'selectedDiffKind': selected.kind.name,
            if (selected.filePath != null)
              'selectedFilePath': selected.filePath,
            if (selected.hunkIndex != null)
              'selectedHunkIndex': selected.hunkIndex,
            if (selected.oldLine != null) 'selectedOldLine': selected.oldLine,
            if (selected.newLine != null) 'selectedNewLine': selected.newLine,
          },
        }),
        child: list,
      ),
    );
  }
}

class _DiffLineWidget extends StatelessWidget {
  const _DiffLineWidget({
    required this.row,
    required this.selected,
    required this.activeSelection,
    required this.copyEnabled,
    required this.gutterWidth,
    required this.onActivate,
    required this.onCopy,
  });

  final DiffLine row;
  final bool selected;
  final bool activeSelection;
  final bool copyEnabled;
  final int gutterWidth;
  final VoidCallback onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final style = _styleForKind(row.kind, widgetTheme, theme).merge(
      activeSelection
          ? theme.selectionStyle
          : selected
          ? theme.mutedStyle
          : CellStyle.empty,
    );
    return Semantics(
      role: SemanticRole.diffLine,
      label: row.displayText,
      value: row.text,
      selected: selected,
      actions: {
        SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            onActivate();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': row.index,
        'rowKey': row.index,
        'diffKind': row.kind.name,
        if (row.fileIndex != null) 'fileIndex': row.fileIndex,
        if (row.hunkIndex != null) 'hunkIndex': row.hunkIndex,
        if (row.oldLine != null) 'oldLine': row.oldLine,
        if (row.newLine != null) 'newLine': row.newLine,
        if (row.oldPath != null) 'oldPath': row.oldPath,
        if (row.newPath != null) 'newPath': row.newPath,
        if (row.filePath != null) 'filePath': row.filePath,
        'outputSanitized': row.outputSanitized,
        'outputTruncated': row.outputTruncated,
        'outputOriginalLength': row.outputOriginalLength,
      }),
      child: gutterWidth <= 0
          ? Text(row.displayText, style: style)
          : Row(
              children: [
                Text(_gutterFor(row, gutterWidth), style: theme.mutedStyle),
                Text(row.displayText, style: style),
              ],
            ),
    );
  }
}

/// `old new │ ` — both columns right-aligned to [width]; blank where a side has
/// no line number (additions have no old, deletions no new, hunk headers
/// neither). Matches the unified-diff gutter of delta / GitHub.
String _gutterFor(DiffLine row, int width) {
  final old = (row.oldLine?.toString() ?? '').padLeft(width);
  final neu = (row.newLine?.toString() ?? '').padLeft(width);
  return '$old $neu │ ';
}

int _diffGutterWidth(List<DiffLine> rows) {
  var max = 1;
  for (final row in rows) {
    final o = row.oldLine, n = row.newLine;
    if (o != null && o.toString().length > max) max = o.toString().length;
    if (n != null && n.toString().length > max) max = n.toString().length;
  }
  return max;
}

final _hunkPattern = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

String _exportHunk(DiffDocument document, DiffLine row, int selectedIndex) {
  final hunkIndex = row.hunkIndex;
  if (hunkIndex == null) return row.text;
  var start = selectedIndex;
  while (start > 0 && document.rows[start - 1].hunkIndex == hunkIndex) {
    start -= 1;
  }
  while (start > 0 &&
      document.rows[start].kind != DiffLineKind.hunkHeader &&
      document.rows[start - 1].kind == DiffLineKind.hunkHeader &&
      document.rows[start - 1].hunkIndex == hunkIndex) {
    start -= 1;
  }
  var end = selectedIndex;
  while (end + 1 < document.rows.length &&
      document.rows[end + 1].hunkIndex == hunkIndex) {
    end += 1;
  }
  return [
    for (var index = start; index <= end; index++) document.rows[index].text,
  ].join('\n');
}

String _normalizeDiffPath(String path) {
  final trimmed = path.trim();
  if (trimmed == '/dev/null') return trimmed;
  final withoutPrefix = trimmed.startsWith('a/') || trimmed.startsWith('b/')
      ? trimmed.substring(2)
      : trimmed;
  final tab = withoutPrefix.indexOf('\t');
  final value = tab == -1 ? withoutPrefix : withoutPrefix.substring(0, tab);
  return _sanitizeDiffText(value);
}

({String safeText, String displayText, bool sanitized, bool truncated})
_formatDiffLine(DiffLineKind kind, String raw, int? maxLineLength) {
  final safe = _sanitizeDiffText(raw);
  final display = _truncateGraphemes(safe, maxLineLength);
  return (
    safeText: safe,
    displayText: display,
    sanitized: safe != raw,
    truncated: display != safe,
  );
}

String _sanitizeDiffText(String text) {
  // Replace breaks/tabs with their visible forms BEFORE sanitizing —
  // sanitizeForDisplay rewrites \r\n\t to U+FFFD, so doing it after would make
  // these replaceAlls dead no-ops and render `�` for tab-indented / CRLF diffs.
  return sanitizeForDisplay(
    text.replaceAll('\r', r'\r').replaceAll('\n', r'\n').replaceAll('\t', '  '),
  );
}

String _truncateGraphemes(String text, int? maxLength) {
  if (maxLength == null) return text;
  if (maxLength <= 0) return '';
  final chars = text.characters;
  if (chars.length <= maxLength) return text;
  if (maxLength == 1) return '…';
  return '${chars.take(maxLength - 1)}…';
}

CellStyle _styleForKind(
  DiffLineKind kind,
  FleuryWidgetTheme widgetTheme,
  ThemeData theme,
) {
  return switch (kind) {
    DiffLineKind.addition => widgetTheme.resolveDiffAddition(theme),
    DiffLineKind.deletion => widgetTheme.resolveDiffDeletion(theme),
    DiffLineKind.hunkHeader => widgetTheme.resolveDiffHunkHeader(theme),
    DiffLineKind.fileHeader => widgetTheme.resolveDiffFileHeader(theme),
    DiffLineKind.metadata ||
    DiffLineKind.marker => widgetTheme.resolveDiffMetadata(theme),
    DiffLineKind.context => CellStyle.empty,
  };
}
