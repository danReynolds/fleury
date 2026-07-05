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

  factory DiffDocument.parseUnified(String source) {
    return parseUnifiedDiff(source);
  }

  final List<DiffLine> rows;
  final int fileCount;
  final int hunkCount;
  final int additionCount;
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

  final int index;
  final DiffLineKind kind;
  final String text;
  final String displayText;
  final int? fileIndex;
  final int? hunkIndex;
  final int? oldLine;
  final int? newLine;
  final String? oldPath;
  final String? newPath;
  final bool outputSanitized;
  final bool outputTruncated;
  final int outputOriginalLength;

  String? get filePath => newPath ?? oldPath;
}

/// Controller for [DiffView] selection.
class DiffViewController extends ChangeNotifier {
  DiffViewController({int selectedIndex = 0})
    : _list = ListController(selectedIndex: selectedIndex) {
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

  final DiffViewCopyMode mode;
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

  final int rowIndex;
  final DiffLine row;
  final String text;
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
    if (line.startsWith('diff --git ')) {
      fileIndex += 1;
      oldPath = null;
      newPath = null;
      oldCursor = null;
      newCursor = null;
      currentHunkIndex = null;
      addRow(kind: DiffLineKind.fileHeader, text: line);
      continue;
    }
    if (line.startsWith('--- ')) {
      oldPath = _normalizeDiffPath(line.substring(4));
      if (fileIndex < 0) fileIndex = 0;
      currentHunkIndex = null;
      addRow(kind: DiffLineKind.fileHeader, text: line);
      continue;
    }
    if (line.startsWith('+++ ')) {
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
      if (fileIndex < 0) fileIndex = 0;
      currentHunkIndex = hunkIndex;
      addRow(kind: DiffLineKind.hunkHeader, text: line);
      continue;
    }
    if (line.startsWith(r'\ ')) {
      addRow(kind: DiffLineKind.marker, text: line);
      continue;
    }
    if (line.startsWith('+') && !line.startsWith('+++')) {
      final currentNew = newCursor;
      addRow(kind: DiffLineKind.addition, text: line, newLine: currentNew);
      if (newCursor != null) newCursor += 1;
      additionCount += 1;
      continue;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      final currentOld = oldCursor;
      addRow(kind: DiffLineKind.deletion, text: line, oldLine: currentOld);
      if (oldCursor != null) oldCursor += 1;
      deletionCount += 1;
      continue;
    }
    if (line.startsWith(' ')) {
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

/// Keyboard-navigable unified diff viewer.
class DiffView extends StatefulWidget {
  DiffView({
    super.key,
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
  return sanitizeForDisplay(
    text,
  ).replaceAll('\r', r'\r').replaceAll('\n', r'\n').replaceAll('\t', '  ');
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
