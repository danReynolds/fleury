import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:fleury/fleury_host.dart';

import 'component_theme.dart';

/// JSON value type represented by a [JsonViewRow].
enum JsonValueType { object, array, string, number, boolean, nullValue }

/// Clipboard/export mode for [JsonView] selected-node copy.
enum JsonViewCopyMode {
  /// Copy the selected JSON value or subtree as JSON.
  node,

  /// Copy the selected visible row text.
  line,
}

/// Parsed or already-materialized JSON content rendered by [JsonView].
final class JsonViewDocument {
  const JsonViewDocument.value(this.value) : source = null, error = null;

  const JsonViewDocument._({
    required this.value,
    required this.source,
    required this.error,
  });

  factory JsonViewDocument.parse(String source) {
    try {
      return JsonViewDocument._(
        value: jsonDecode(source),
        source: source,
        error: null,
      );
    } on FormatException catch (error) {
      return JsonViewDocument._(value: null, source: source, error: error);
    }
  }

  final Object? value;
  final String? source;
  final FormatException? error;

  bool get valid => error == null;
}

/// Options for copying a [JsonView] selected row.
final class JsonViewCopyOptions {
  const JsonViewCopyOptions({
    this.mode = JsonViewCopyMode.node,
    this.pretty = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  final JsonViewCopyMode mode;
  final bool pretty;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [JsonView] copies the selected row.
final class JsonViewCopyResult {
  const JsonViewCopyResult({
    required this.rowIndex,
    required this.row,
    required this.text,
    required this.report,
  });

  final int rowIndex;
  final JsonViewRow row;
  final String text;
  final ClipboardWriteReport report;
}

/// Controller for [JsonView] expansion and selection.
class JsonViewController extends ChangeNotifier {
  JsonViewController({
    Iterable<String> expandedPointers = const <String>[],
    Iterable<String> collapsedPointers = const <String>[],
    int selectedIndex = 0,
  }) : _expandedPointers = Set<String>.of(expandedPointers),
       _collapsedPointers = Set<String>.of(collapsedPointers),
       _list = ListController(selectedIndex: selectedIndex) {
    _list.addListener(notifyListeners);
  }

  final Set<String> _expandedPointers;
  final Set<String> _collapsedPointers;
  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  Set<String> get expandedPointers =>
      Set<String>.unmodifiable(_expandedPointers);

  Set<String> get collapsedPointers =>
      Set<String>.unmodifiable(_collapsedPointers);

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  bool isExpanded(
    String pointer, {
    required int depth,
    required int initialExpandedDepth,
  }) {
    if (_collapsedPointers.contains(pointer)) return false;
    return _expandedPointers.contains(pointer) || depth < initialExpandedDepth;
  }

  void expand(String pointer) {
    _checkNotDisposed();
    final changed =
        _collapsedPointers.remove(pointer) | _expandedPointers.add(pointer);
    if (changed) notifyListeners();
  }

  void collapse(String pointer) {
    _checkNotDisposed();
    final changed =
        _expandedPointers.remove(pointer) | _collapsedPointers.add(pointer);
    if (changed) notifyListeners();
  }

  void toggle(String pointer, {required bool expanded}) {
    _checkNotDisposed();
    if (expanded) {
      collapse(pointer);
    } else {
      expand(pointer);
    }
  }

  void jumpToIndex(int index) {
    _checkNotDisposed();
    _list.jumpToIndex(index);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('JsonViewController has been disposed.');
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

/// One visible row in a [JsonView].
final class JsonViewRow {
  const JsonViewRow({
    required this.pointer,
    required this.path,
    required this.key,
    required this.depth,
    required this.type,
    required this.value,
    required this.childCount,
    required this.expandable,
    required this.expanded,
    required this.label,
    required this.preview,
    required this.line,
    required this.outputSanitized,
    required this.outputTruncated,
    required this.outputOriginalLength,
  });

  final String pointer;
  final String path;
  final String? key;
  final int depth;
  final JsonValueType type;
  final Object? value;
  final int childCount;
  final bool expandable;
  final bool expanded;
  final String label;
  final String preview;
  final String line;
  final bool outputSanitized;
  final bool outputTruncated;
  final int outputOriginalLength;
}

/// Builds the visible [JsonViewRow] list without mounting widgets.
List<JsonViewRow> buildJsonViewRows(
  Object? value, {
  int initialExpandedDepth = 1,
  Set<String> expandedPointers = const <String>{},
  Set<String> collapsedPointers = const <String>{},
  int? maxLineLength = 1000,
}) {
  final root = _normalizeJsonValue(value);
  final rows = <JsonViewRow>[];

  bool expandedFor(String pointer, int depth, bool expandable) {
    if (!expandable) return false;
    if (collapsedPointers.contains(pointer)) return false;
    return expandedPointers.contains(pointer) || depth < initialExpandedDepth;
  }

  void visit(
    Object? node,
    String? key,
    int depth,
    String pointer,
    String path,
  ) {
    final type = _typeOf(node);
    final childCount = _childCount(node);
    final expandable =
        childCount > 0 &&
        (type == JsonValueType.object || type == JsonValueType.array);
    final expanded = expandedFor(pointer, depth, expandable);
    final label = key == null ? r'$' : _sanitizeJsonLabel(key);
    final preview = _previewFor(node, type, childCount);
    final rawLine = _lineFor(
      label: label,
      preview: preview,
      depth: depth,
      expandable: expandable,
      expanded: expanded,
      root: key == null,
      primitive: !expandable,
    );
    final line = _truncateGraphemes(rawLine, maxLineLength);
    rows.add(
      JsonViewRow(
        pointer: pointer,
        path: path,
        key: key,
        depth: depth,
        type: type,
        value: node,
        childCount: childCount,
        expandable: expandable,
        expanded: expanded,
        label: label,
        preview: preview,
        line: line,
        outputSanitized:
            _jsonValueNeedsSanitization(node) || (key != null && label != key),
        outputTruncated: line != rawLine,
        outputOriginalLength: rawLine.length,
      ),
    );
    if (!expanded) return;
    if (node is Map<String, Object?>) {
      for (final entry in node.entries) {
        final childPointer = '$pointer/${_escapePointerToken(entry.key)}';
        final childPath = '$path.${_pathSegment(entry.key)}';
        visit(entry.value, entry.key, depth + 1, childPointer, childPath);
      }
    } else if (node is List<Object?>) {
      for (var index = 0; index < node.length; index++) {
        final key = '[$index]';
        visit(node[index], key, depth + 1, '$pointer/$index', '$path[$index]');
      }
    }
  }

  visit(root, null, 0, '', r'$');
  return List<JsonViewRow>.unmodifiable(rows);
}

/// Exports a [JsonViewRow] as sanitized text.
String exportJsonViewRow(
  JsonViewRow row, {
  JsonViewCopyOptions options = const JsonViewCopyOptions(),
}) {
  return switch (options.mode) {
    JsonViewCopyMode.line => row.line,
    JsonViewCopyMode.node => _encodeJsonValue(
      _sanitizeJsonValue(row.value),
      pretty: options.pretty,
    ),
  };
}

/// Keyboard-navigable, collapsible JSON structure viewer.
class JsonView extends StatefulWidget {
  JsonView({
    super.key,
    required Object? value,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.label = 'JSON',
    this.initialExpandedDepth = 1,
    this.maxLineLength = 1000,
    this.copySelection = true,
    this.copyOptions = const JsonViewCopyOptions(),
    this.onCopy,
  }) : document = JsonViewDocument.value(value),
       assert(initialExpandedDepth >= 0),
       assert(maxLineLength == null || maxLineLength >= 0);

  const JsonView.document({
    super.key,
    required this.document,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.label = 'JSON',
    this.initialExpandedDepth = 1,
    this.maxLineLength = 1000,
    this.copySelection = true,
    this.copyOptions = const JsonViewCopyOptions(),
    this.onCopy,
  }) : assert(initialExpandedDepth >= 0),
       assert(maxLineLength == null || maxLineLength >= 0);

  factory JsonView.string(
    String source, {
    Key? key,
    JsonViewController? controller,
    FocusNode? focusNode,
    bool autofocus = false,
    String label = 'JSON',
    int initialExpandedDepth = 1,
    int? maxLineLength = 1000,
    bool copySelection = true,
    JsonViewCopyOptions copyOptions = const JsonViewCopyOptions(),
    void Function(JsonViewCopyResult result)? onCopy,
  }) {
    return JsonView.document(
      key: key,
      document: JsonViewDocument.parse(source),
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      label: label,
      initialExpandedDepth: initialExpandedDepth,
      maxLineLength: maxLineLength,
      copySelection: copySelection,
      copyOptions: copyOptions,
      onCopy: onCopy,
    );
  }

  /// Parsed or already-materialized JSON document to render.
  final JsonViewDocument document;

  /// External expansion, selection, and visible-range controller.
  final JsonViewController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the viewer should request focus when mounted.
  final bool autofocus;

  /// Semantic and visual label for the JSON viewer.
  final String label;

  /// Depth expanded by default before user-controlled collapse state applies.
  final int initialExpandedDepth;

  /// Maximum displayed row length.
  final int? maxLineLength;

  /// Whether Ctrl+C and semantic copy export the selected row/node.
  final bool copySelection;

  /// Clipboard/export options for copied JSON text.
  final JsonViewCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(JsonViewCopyResult result)? onCopy;

  @override
  State<JsonView> createState() => _JsonViewState();
}

class _JsonViewState extends State<JsonView> {
  late JsonViewController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? JsonViewController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'JsonView');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant JsonView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? JsonViewController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'JsonView');
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

  List<JsonViewRow> get _rows => buildJsonViewRows(
    widget.document.value,
    initialExpandedDepth: widget.initialExpandedDepth,
    expandedPointers: _controller._expandedPointers,
    collapsedPointers: _controller._collapsedPointers,
    maxLineLength: widget.maxLineLength,
  );

  JsonViewRow? _selectedRow(List<JsonViewRow> rows) {
    if (rows.isEmpty) return null;
    final selected = (_controller.selectedIndex ?? 0).clamp(0, rows.length - 1);
    return rows[selected];
  }

  KeyEventResult _expandOrEnter(List<JsonViewRow> rows) {
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= rows.length) {
      return KeyEventResult.ignored;
    }
    final row = rows[selectedIndex];
    if (!row.expandable) return KeyEventResult.ignored;
    if (!row.expanded) {
      _controller.expand(row.pointer);
      return KeyEventResult.handled;
    }
    _controller.selectedIndex = (selectedIndex + 1).clamp(0, rows.length - 1);
    return KeyEventResult.handled;
  }

  KeyEventResult _collapseOrParent(List<JsonViewRow> rows) {
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= rows.length) {
      return KeyEventResult.ignored;
    }
    final row = rows[selectedIndex];
    if (row.expandable && row.expanded) {
      _controller.collapse(row.pointer);
      return KeyEventResult.handled;
    }
    for (var index = selectedIndex - 1; index >= 0; index--) {
      if (rows[index].depth < row.depth) {
        _controller.selectedIndex = index;
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _toggleSelected(List<JsonViewRow> rows, int index) {
    if (index < 0 || index >= rows.length) return;
    final row = rows[index];
    if (!row.expandable) return;
    _controller.toggle(row.pointer, expanded: row.expanded);
  }

  Future<void> _copySelection(List<JsonViewRow> rows) async {
    if (!widget.copySelection || rows.isEmpty) return;
    final selected = (_controller.selectedIndex ?? 0).clamp(0, rows.length - 1);
    final row = rows[selected];
    final text = exportJsonViewRow(row, options: widget.copyOptions);
    final report = await Clipboard.instance.writeWithReport(
      text,
      policy: widget.copyOptions.clipboardPolicy,
    );
    if (!mounted) return;
    widget.onCopy?.call(
      JsonViewCopyResult(
        rowIndex: selected,
        row: row,
        text: text,
        report: report,
      ),
    );
  }

  void _openRow(List<JsonViewRow> rows, int index) {
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    final row = rows[index];
    if (row.expandable && !row.expanded) _controller.expand(row.pointer);
  }

  void _closeRow(List<JsonViewRow> rows, int index) {
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    final row = rows[index];
    if (row.expandable && row.expanded) _controller.collapse(row.pointer);
  }

  Future<void> _copyRow(List<JsonViewRow> rows, int index) async {
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection(rows);
  }

  Future<void> _handleJsonAction(
    SemanticAction action,
    List<JsonViewRow> rows,
  ) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.copy:
        await _copySelection(rows);
        return;
      case _:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.document.valid) return _buildInvalidDocument();

    final rows = _rows;
    final selected = _selectedRow(rows);
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && rows.isNotEmpty;
    Widget list = Focus(
      canRequestFocus: false,
      onKey: (event) => switch (event.keyCode) {
        KeyCode.arrowRight => _expandOrEnter(rows),
        KeyCode.arrowLeft => _collapseOrParent(rows),
        _ => KeyEventResult.ignored,
      },
      child: ListView.builder(
        controller: _controller._listController,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        itemCount: rows.length,
        onSelect: (index) => _toggleSelected(rows, index),
        itemBuilder: (context, index, activeSelected) {
          final selected = index == _controller.selectedIndex;
          return _JsonRowWidget(
            row: rows[index],
            rowIndex: index,
            selected: selected,
            activeSelection: activeSelected,
            copyEnabled: copyEnabled,
            onOpen: () => _openRow(rows, index),
            onClose: () => _closeRow(rows, index),
            onCopy: () => _copyRow(rows, index),
          );
        },
      ),
    );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy JSON node',
            onEvent: (_) => unawaited(_copySelection(rows)),
          ),
        ],
        child: list,
      );
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.json,
        label: widget.label,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: (action) => _handleJsonAction(action, rows),
        state: SemanticState({
          'valid': true,
          'collectionRowCount': rows.length,
          'rootType': rows.first.type.name,
          'expandedCount': rows
              .where((row) => row.expandable && row.expanded)
              .length,
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
            'selectedKey': selected.pointer,
            'selectedPath': selected.path,
            'selectedType': selected.type.name,
          },
        }),
        child: list,
      ),
    );
  }

  Widget _buildInvalidDocument() {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final error = widget.document.error!;
    final safeMessage = _sanitizeJsonLabel(error.message);
    return Semantics(
      role: SemanticRole.json,
      label: widget.label,
      validationError: safeMessage,
      state: SemanticState({
        'valid': false,
        'parseError': safeMessage,
        'sourceLength': widget.document.source?.length ?? 0,
      }),
      child: Text(
        'Invalid JSON: $safeMessage',
        style: widgetTheme.resolveJsonError(theme),
      ),
    );
  }
}

class _JsonRowWidget extends StatelessWidget {
  const _JsonRowWidget({
    required this.row,
    required this.rowIndex,
    required this.selected,
    required this.activeSelection,
    required this.copyEnabled,
    required this.onOpen,
    required this.onClose,
    required this.onCopy,
  });

  final JsonViewRow row;
  final int rowIndex;
  final bool selected;
  final bool activeSelection;
  final bool copyEnabled;
  final void Function() onOpen;
  final void Function() onClose;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.jsonNode,
      label: row.label,
      value: row.preview,
      selected: selected,
      expanded: row.expandable ? row.expanded : null,
      actions: {
        // Symmetric expand/collapse — collapsing was Left-arrow-only.
        if (row.expandable && !row.expanded) SemanticAction.open,
        if (row.expandable && row.expanded) SemanticAction.close,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.open:
            if (row.expandable) onOpen();
            return;
          case SemanticAction.close:
            if (row.expandable) onClose();
            return;
          case SemanticAction.copy:
            if (copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': rowIndex,
        'rowKey': row.pointer,
        'jsonPointer': row.pointer,
        'jsonPath': row.path,
        if (row.key != null) 'jsonKey': row.key,
        'jsonType': row.type.name,
        'depth': row.depth,
        'childCount': row.childCount,
        'isBranch': row.expandable,
        'expanded': row.expanded,
        'outputSanitized': row.outputSanitized,
        'outputTruncated': row.outputTruncated,
        'outputOriginalLength': row.outputOriginalLength,
      }),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    if (activeSelection) return Text(row.line, style: theme.selectionStyle);
    if (selected) return Text(row.line, style: theme.mutedStyle);
    // Color just the value by type (jless / fx convention) without changing the
    // text: the preview is the line's suffix, so split there.
    if (row.preview.isEmpty || row.preview.length > row.line.length) {
      return Text(row.line);
    }
    final prefix = row.line.substring(0, row.line.length - row.preview.length);
    return RichText(
      text: TextSpan(
        text: prefix,
        children: <TextSpan>[
          TextSpan(text: row.preview, style: _jsonTypeStyle(row.type, theme)),
        ],
      ),
    );
  }
}

CellStyle _jsonTypeStyle(JsonValueType type, ThemeData theme) {
  return switch (type) {
    JsonValueType.string => CellStyle(foreground: theme.colorScheme.success),
    JsonValueType.number => const CellStyle(foreground: AnsiColor(14)),
    JsonValueType.boolean => CellStyle(foreground: theme.colorScheme.warning),
    JsonValueType.nullValue => const CellStyle(dim: true),
    JsonValueType.object || JsonValueType.array => theme.mutedStyle,
  };
}

Object? _normalizeJsonValue(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) return value.isFinite ? value : value.toString();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _normalizeJsonValue(entry.value),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final item in value) _normalizeJsonValue(item)];
  }
  return value.toString();
}

JsonValueType _typeOf(Object? value) {
  if (value is Map<String, Object?>) return JsonValueType.object;
  if (value is List<Object?>) return JsonValueType.array;
  if (value is String) return JsonValueType.string;
  if (value is num) return JsonValueType.number;
  if (value is bool) return JsonValueType.boolean;
  return JsonValueType.nullValue;
}

int _childCount(Object? value) {
  if (value is Map<String, Object?>) return value.length;
  if (value is List<Object?>) return value.length;
  return 0;
}

String _previewFor(Object? value, JsonValueType type, int childCount) {
  return switch (type) {
    JsonValueType.object => childCount == 0 ? '{}' : '{object $childCount}',
    JsonValueType.array => childCount == 0 ? '[]' : '[array $childCount]',
    JsonValueType.string => _encodeJsonValue(_sanitizeJsonValue(value)),
    JsonValueType.number ||
    JsonValueType.boolean ||
    JsonValueType.nullValue => _encodeJsonValue(value),
  };
}

String _lineFor({
  required String label,
  required String preview,
  required int depth,
  required bool expandable,
  required bool expanded,
  required bool root,
  required bool primitive,
}) {
  final marker = expandable ? (expanded ? '▾ ' : '▸ ') : '  ';
  final indent = '  ' * depth;
  if (root) return '$indent$marker$label $preview';
  if (primitive) return '$indent$marker$label: $preview';
  return '$indent$marker$label $preview';
}

String _truncateGraphemes(String text, int? maxLength) {
  if (maxLength == null) return text;
  if (maxLength <= 0) return '';
  final chars = text.characters;
  if (chars.length <= maxLength) return text;
  if (maxLength == 1) return '…';
  return '${chars.take(maxLength - 1)}…';
}

String _sanitizeJsonLabel(String text) => sanitizeForDisplay(
  text,
).replaceAll('\r', r'\r').replaceAll('\n', r'\n').replaceAll('\t', r'\t');

Object? _sanitizeJsonValue(Object? value) {
  if (value is String) return _sanitizeJsonLabel(value);
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries)
        _sanitizeJsonLabel(entry.key): _sanitizeJsonValue(entry.value),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _sanitizeJsonValue(item)];
  }
  return value;
}

bool _jsonValueNeedsSanitization(Object? value) {
  if (value is String) return _sanitizeJsonLabel(value) != value;
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      if (_sanitizeJsonLabel(entry.key) != entry.key) return true;
      if (_jsonValueNeedsSanitization(entry.value)) return true;
    }
  }
  if (value is List<Object?>) {
    for (final item in value) {
      if (_jsonValueNeedsSanitization(item)) return true;
    }
  }
  return false;
}

String _encodeJsonValue(Object? value, {bool pretty = false}) {
  final encoder = pretty
      ? const JsonEncoder.withIndent('  ')
      : const JsonEncoder();
  return encoder.convert(value);
}

String _escapePointerToken(String token) =>
    token.replaceAll('~', '~0').replaceAll('/', '~1');

String _pathSegment(String key) {
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) return key;
  return '[${_encodeJsonValue(_sanitizeJsonLabel(key))}]';
}
