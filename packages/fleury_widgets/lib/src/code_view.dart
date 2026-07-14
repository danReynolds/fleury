import 'dart:async' show unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'component_theme.dart';

/// Coarse source-line classification used by [CodeView].
enum CodeLineKind {
  blank,
  comment,
  import,
  declaration,
  keyword,
  string,
  plain,
}

/// Clipboard/export mode for [CodeView] selected-line copy.
enum CodeViewCopyMode {
  /// Copy the selected source line.
  line,

  /// Copy the whole sanitized document.
  document,
}

/// Parsed source document rendered by [CodeView].
final class CodeDocument {
  const CodeDocument({
    required this.lines,
    required this.language,
    required this.filePath,
    required this.lineCount,
    required this.nonEmptyLineCount,
    required this.commentCount,
    required this.blankCount,
    required this.showLineNumbers,
    required this.tabSize,
  });

  factory CodeDocument.parse(
    String source, {
    String? language,
    String? filePath,
    int? maxLineLength = 1000,
    int tabSize = 2,
    bool showLineNumbers = true,
  }) {
    return parseCodeDocument(
      source,
      language: language,
      filePath: filePath,
      maxLineLength: maxLineLength,
      tabSize: tabSize,
      showLineNumbers: showLineNumbers,
    );
  }

  final List<CodeLine> lines;
  final String? language;
  final String? filePath;
  final int lineCount;
  final int nonEmptyLineCount;
  final int commentCount;
  final int blankCount;
  final bool showLineNumbers;
  final int tabSize;

  bool get isEmpty => lines.isEmpty;
}

/// One rendered source line in a [CodeView].
final class CodeLine {
  const CodeLine({
    required this.index,
    required this.lineNumber,
    required this.kind,
    required this.text,
    required this.displayText,
    required this.indentation,
    required this.outputSanitized,
    required this.outputTruncated,
    required this.outputOriginalLength,
  });

  final int index;
  final int lineNumber;
  final CodeLineKind kind;
  final String text;
  final String displayText;
  final int indentation;
  final bool outputSanitized;
  final bool outputTruncated;
  final int outputOriginalLength;
}

/// Controller for [CodeView] selection.
class CodeViewController extends ChangeNotifier {
  CodeViewController({int selectedIndex = 0})
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
      throw StateError('CodeViewController has been disposed.');
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

/// Options for copying from [CodeView].
final class CodeViewCopyOptions {
  const CodeViewCopyOptions({
    this.mode = CodeViewCopyMode.line,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  final CodeViewCopyMode mode;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [CodeView] copies source text.
final class CodeViewCopyResult {
  const CodeViewCopyResult({
    required this.lineIndex,
    required this.line,
    required this.text,
    required this.report,
  });

  final int lineIndex;
  final CodeLine line;
  final String text;
  final ClipboardWriteReport report;
}

/// Parses source text into sanitized [CodeLine] rows.
CodeDocument parseCodeDocument(
  String source, {
  String? language,
  String? filePath,
  int? maxLineLength = 1000,
  int tabSize = 2,
  bool showLineNumbers = true,
}) {
  assert(tabSize > 0);
  final rawLines = source.split('\n');
  if (rawLines.isNotEmpty && rawLines.last.isEmpty) rawLines.removeLast();
  final width = rawLines.isEmpty ? 1 : rawLines.length.toString().length;
  final lines = <CodeLine>[];
  var commentCount = 0;
  var blankCount = 0;
  var nonEmptyLineCount = 0;
  for (var index = 0; index < rawLines.length; index++) {
    final raw = rawLines[index].endsWith('\r')
        ? rawLines[index].substring(0, rawLines[index].length - 1)
        : rawLines[index];
    final safe = _sanitizeCodeText(raw, tabSize: tabSize);
    final kind = _classifyCodeLine(safe, language: language);
    if (kind == CodeLineKind.comment) commentCount += 1;
    if (kind == CodeLineKind.blank) blankCount += 1;
    if (kind != CodeLineKind.blank) nonEmptyLineCount += 1;
    final indentation = _leadingSpaces(safe);
    final lineNumber = index + 1;
    final linePrefix = showLineNumbers
        ? '${lineNumber.toString().padLeft(width)} │ '
        : '';
    final rawDisplay = '$linePrefix$safe';
    final display = _truncateGraphemes(rawDisplay, maxLineLength);
    lines.add(
      CodeLine(
        index: index,
        lineNumber: lineNumber,
        kind: kind,
        text: safe,
        displayText: display,
        indentation: indentation,
        outputSanitized: safe != raw,
        outputTruncated: display != rawDisplay,
        outputOriginalLength: raw.length,
      ),
    );
  }
  return CodeDocument(
    lines: List<CodeLine>.unmodifiable(lines),
    language: language,
    filePath: filePath == null ? null : _sanitizeCodeText(filePath),
    lineCount: lines.length,
    nonEmptyLineCount: nonEmptyLineCount,
    commentCount: commentCount,
    blankCount: blankCount,
    showLineNumbers: showLineNumbers,
    tabSize: tabSize,
  );
}

/// Exports the selected line or whole source document as sanitized text.
String exportCodeSelection(
  CodeDocument document, {
  required int lineIndex,
  CodeViewCopyOptions options = const CodeViewCopyOptions(),
}) {
  if (document.lines.isEmpty) return '';
  final selectedIndex = lineIndex.clamp(0, document.lines.length - 1);
  return switch (options.mode) {
    CodeViewCopyMode.line => document.lines[selectedIndex].text,
    CodeViewCopyMode.document => [
      for (final line in document.lines) line.text,
    ].join('\n'),
  };
}

/// Keyboard-navigable source-code viewer.
class CodeView extends StatefulWidget {
  CodeView({
    super.key,
    required String source,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Code',
    this.language,
    this.filePath,
    this.maxLineLength = 1000,
    this.tabSize = 2,
    this.showLineNumbers = true,
    this.copySelection = true,
    this.copyOptions = const CodeViewCopyOptions(),
    this.onCopy,
  }) : document = parseCodeDocument(
         source,
         language: language,
         filePath: filePath,
         maxLineLength: maxLineLength,
         tabSize: tabSize,
         showLineNumbers: showLineNumbers,
       ),
       assert(maxLineLength == null || maxLineLength >= 0),
       assert(tabSize > 0);

  const CodeView.document({
    super.key,
    required this.document,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Code',
    this.language,
    this.filePath,
    this.maxLineLength = 1000,
    this.tabSize = 2,
    this.showLineNumbers = true,
    this.copySelection = true,
    this.copyOptions = const CodeViewCopyOptions(),
    this.onCopy,
  }) : assert(maxLineLength == null || maxLineLength >= 0),
       assert(tabSize > 0);

  /// Parsed source document to render.
  final CodeDocument document;

  /// External selection and visible-range controller.
  final CodeViewController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the viewer should request focus when mounted.
  final bool autofocus;

  /// Semantic label (the accessibility name; not rendered) for the code viewer.
  final String semanticLabel;

  /// Optional language hint used for coarse line classification.
  final String? language;

  /// Optional file path exposed through semantics.
  final String? filePath;

  /// Maximum displayed line length.
  final int? maxLineLength;

  /// Number of spaces used when expanding tabs.
  final int tabSize;

  /// Whether rendered rows include line-number prefixes.
  final bool showLineNumbers;

  /// Whether Ctrl+C and semantic copy export the selected text.
  final bool copySelection;

  /// Clipboard/export options for copied source text.
  final CodeViewCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(CodeViewCopyResult result)? onCopy;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  late CodeViewController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? CodeViewController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'CodeView');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? CodeViewController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'CodeView');
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

  CodeLine? _selectedLine() {
    final lines = widget.document.lines;
    if (lines.isEmpty) return null;
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      lines.length - 1,
    );
    return lines[selected];
  }

  Future<void> _copySelection() async {
    final lines = widget.document.lines;
    if (!widget.copySelection || lines.isEmpty) return;
    final selectedIndex = (_controller.selectedIndex ?? 0).clamp(
      0,
      lines.length - 1,
    );
    final text = exportCodeSelection(
      widget.document,
      lineIndex: selectedIndex,
      options: widget.copyOptions,
    );
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      CodeViewCopyResult(
        lineIndex: selectedIndex,
        line: lines[selectedIndex],
        text: text,
        report: report,
      ),
    );
  }

  Future<void> _copyLineAt(int index) async {
    final lines = widget.document.lines;
    if (index < 0 || index >= lines.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection();
  }

  void _selectLineAt(int index) {
    final lines = widget.document.lines;
    if (index < 0 || index >= lines.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
  }

  Future<void> _handleCodeAction(SemanticAction action) async {
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
    final lines = widget.document.lines;
    final selected = _selectedLine();
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && lines.isNotEmpty;
    Widget list = lines.isEmpty
        ? const Text('  (empty source)', style: CellStyle(dim: true))
        : ListView.builder(
            controller: _controller._listController,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            itemCount: lines.length,
            itemBuilder: (context, index, activeSelected) {
              final selected = index == _controller.selectedIndex;
              return _CodeLineWidget(
                line: lines[index],
                selected: selected,
                activeSelection: activeSelected,
                copyEnabled: copyEnabled,
                onActivate: () => _selectLineAt(index),
                onCopy: () => _copyLineAt(index),
              );
            },
          );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy code selection',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.code,
        label: widget.semanticLabel,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleCodeAction,
        state: SemanticState({
          'collectionRowCount': lines.length,
          'lineCount': widget.document.lineCount,
          'nonEmptyLineCount': widget.document.nonEmptyLineCount,
          'commentCount': widget.document.commentCount,
          'blankCount': widget.document.blankCount,
          'showLineNumbers': widget.document.showLineNumbers,
          'tabSize': widget.document.tabSize,
          'copyEnabled': copyEnabled,
          'copyMode': widget.copyOptions.mode.name,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (widget.document.language != null)
            'language': widget.document.language,
          if (widget.document.filePath != null)
            'filePath': widget.document.filePath,
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          if (_controller.selectedIndex != null)
            'selectedIndex': _controller.selectedIndex,
          if (selected != null) ...{
            'selectedKey': selected.lineNumber,
            'selectedLineNumber': selected.lineNumber,
            'selectedCodeLineKind': selected.kind.name,
          },
        }),
        child: list,
      ),
    );
  }
}

class _CodeLineWidget extends StatelessWidget {
  const _CodeLineWidget({
    required this.line,
    required this.selected,
    required this.activeSelection,
    required this.copyEnabled,
    required this.onActivate,
    required this.onCopy,
  });

  final CodeLine line;
  final bool selected;
  final bool activeSelection;
  final bool copyEnabled;
  final VoidCallback onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final style = _styleForKind(line.kind, theme, widgetTheme).merge(
      activeSelection
          ? theme.selectionStyle
          : selected
          ? theme.mutedStyle
          : CellStyle.empty,
    );
    return Semantics(
      role: SemanticRole.codeLine,
      label: line.text,
      value: line.text,
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
        'rowIndex': line.index,
        'rowKey': line.lineNumber,
        'lineNumber': line.lineNumber,
        'codeLineKind': line.kind.name,
        'indentation': line.indentation,
        'outputSanitized': line.outputSanitized,
        'outputTruncated': line.outputTruncated,
        'outputOriginalLength': line.outputOriginalLength,
      }),
      child: Text(line.displayText, style: style),
    );
  }
}

CodeLineKind _classifyCodeLine(String line, {String? language}) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return CodeLineKind.blank;
  if (trimmed.startsWith('//') ||
      trimmed.startsWith('#') ||
      trimmed.startsWith('/*') ||
      trimmed.startsWith('*')) {
    return CodeLineKind.comment;
  }
  if (_isImportLine(trimmed, language: language)) return CodeLineKind.import;
  if (_isDeclarationLine(trimmed, language: language)) {
    return CodeLineKind.declaration;
  }
  if (_looksLikeStringLiteral(trimmed)) return CodeLineKind.string;
  if (_startsWithKeyword(trimmed)) return CodeLineKind.keyword;
  return CodeLineKind.plain;
}

bool _isImportLine(String line, {String? language}) {
  return line.startsWith('import ') ||
      line.startsWith('export ') ||
      line.startsWith('part ') ||
      line.startsWith('from ') ||
      line.startsWith('#include');
}

bool _isDeclarationLine(String line, {String? language}) {
  return line.startsWith('class ') ||
      line.startsWith('enum ') ||
      line.startsWith('mixin ') ||
      line.startsWith('extension ') ||
      line.startsWith('typedef ') ||
      line.startsWith('final class ') ||
      line.startsWith('sealed class ') ||
      line.startsWith('abstract class ') ||
      line.startsWith('function ') ||
      line.startsWith('def ') ||
      line.startsWith('struct ') ||
      line.startsWith('interface ');
}

bool _startsWithKeyword(String line) {
  const keywords = {
    'final',
    'const',
    'var',
    'return',
    'if',
    'else',
    'for',
    'while',
    'switch',
    'case',
    'try',
    'catch',
    'await',
    'async',
  };
  final first = line.split(RegExp(r'\s+')).first;
  return keywords.contains(first);
}

bool _looksLikeStringLiteral(String line) {
  return line.startsWith("'") ||
      line.startsWith('"') ||
      line.startsWith('r"') ||
      line.startsWith("r'");
}

String _sanitizeCodeText(String text, {int tabSize = 2}) {
  final expandedTabs = text.replaceAll('\t', ' ' * tabSize);
  // Visible \r/\n BEFORE sanitizing — sanitizeForDisplay rewrites them to
  // U+FFFD, so doing it after would leave these replaceAlls as dead no-ops.
  return sanitizeForDisplay(
    expandedTabs.replaceAll('\r', r'\r').replaceAll('\n', r'\n'),
  );
}

int _leadingSpaces(String text) {
  var count = 0;
  while (count < text.length && text.codeUnitAt(count) == 0x20) {
    count += 1;
  }
  return count;
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
  CodeLineKind kind,
  ThemeData theme,
  FleuryWidgetTheme widgetTheme,
) {
  return switch (kind) {
    CodeLineKind.blank => widgetTheme.resolveCodeBlank(theme),
    CodeLineKind.comment => widgetTheme.resolveCodeComment(theme),
    CodeLineKind.import => widgetTheme.resolveCodeImport(theme),
    CodeLineKind.declaration => widgetTheme.resolveCodeDeclaration(theme),
    CodeLineKind.keyword => widgetTheme.resolveCodeKeyword(theme),
    CodeLineKind.string => widgetTheme.resolveCodeString(theme),
    CodeLineKind.plain => widgetTheme.resolveCodePlain(theme),
  };
}
