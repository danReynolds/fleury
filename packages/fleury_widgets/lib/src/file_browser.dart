import 'dart:async' show unawaited;
import 'dart:io';

import 'package:fleury/fleury.dart';

/// Type of filesystem entry rendered by [FileBrowser].
enum FileBrowserEntryType { directory, file, link, other }

/// One filesystem row in a [FileBrowser].
final class FileBrowserEntry {
  const FileBrowserEntry({
    required this.path,
    required this.name,
    required this.type,
    this.sizeBytes,
    this.modified,
    this.hidden = false,
  });

  final String path;
  final String name;
  final FileBrowserEntryType type;
  final int? sizeBytes;
  final DateTime? modified;
  final bool hidden;

  bool get isDirectory => type == FileBrowserEntryType.directory;
  bool get isFile => type == FileBrowserEntryType.file;
}

/// Filesystem filter applied by [FileBrowser].
final class FileBrowserFilterDescriptor {
  const FileBrowserFilterDescriptor({this.query = '', this.showHidden = false});

  final String query;
  final bool showHidden;

  bool get isEmpty => query.trim().isEmpty && !showHidden;
}

/// Predicate for filesystem entries before they become browser rows.
typedef FileBrowserEntityFilter = bool Function(FileSystemEntity entity);

/// Clipboard behavior for [FileBrowser] selected-entry copy.
final class FileBrowserCopyOptions {
  const FileBrowserCopyOptions({
    this.copyAbsolutePath = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  final bool copyAbsolutePath;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [FileBrowser] copies the selected entry.
final class FileBrowserCopyResult {
  const FileBrowserCopyResult({
    required this.entryIndex,
    required this.viewIndex,
    required this.entry,
    required this.text,
    required this.report,
  });

  /// Index in the current directory's source entry list.
  final int entryIndex;

  /// Index in the current filtered/logical view.
  final int viewIndex;

  final FileBrowserEntry entry;
  final String text;
  final ClipboardWriteReport report;
}

/// Controller for [FileBrowser] selection and visible-range observation.
class FileBrowserController extends ChangeNotifier {
  FileBrowserController({int? selectedIndex})
    : _list = ListController(selectedIndex: selectedIndex ?? 0) {
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
      throw StateError('FileBrowserController has been disposed.');
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

/// Returns source entry indexes in display order after applying [filter].
List<int> buildFileBrowserEntryOrder(
  List<FileBrowserEntry> entries, {
  FileBrowserFilterDescriptor filter = const FileBrowserFilterDescriptor(),
}) {
  final query = _sanitizeFileText(filter.query).trim().toLowerCase();
  if (query.isEmpty && filter.showHidden) {
    return List<int>.generate(entries.length, (index) => index);
  }
  final order = <int>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    if (!filter.showHidden && entry.hidden) continue;
    if (query.isNotEmpty && !_entryMatches(entry, query)) continue;
    order.add(index);
  }
  return List<int>.unmodifiable(order);
}

/// Exports one [FileBrowserEntry] as sanitized single-line clipboard text.
String exportFileBrowserEntry(
  FileBrowserEntry entry, {
  FileBrowserCopyOptions options = const FileBrowserCopyOptions(),
}) {
  return _sanitizeFileText(options.copyAbsolutePath ? entry.path : entry.name);
}

/// Keyboard-navigable filesystem browser with semantic rows and safe copy.
class FileBrowser extends StatefulWidget {
  const FileBrowser({
    super.key,
    required this.initialDirectory,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.label = 'Files',
    this.maxVisible = 12,
    this.filter = const FileBrowserFilterDescriptor(),
    this.entityFilter,
    this.copySelection = true,
    this.copyOptions = const FileBrowserCopyOptions(),
    this.onActivate,
    this.onDirectoryChanged,
    this.onCopy,
  }) : assert(maxVisible > 0);

  final String initialDirectory;
  final FileBrowserController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String label;
  final int maxVisible;
  final FileBrowserFilterDescriptor filter;
  final FileBrowserEntityFilter? entityFilter;
  final bool copySelection;
  final FileBrowserCopyOptions copyOptions;

  /// Called when Enter activates a non-directory entry.
  final void Function(FileBrowserEntry entry)? onActivate;

  /// Called after the browser changes directories.
  final void Function(String directory)? onDirectoryChanged;

  final void Function(FileBrowserCopyResult result)? onCopy;

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  late FileBrowserController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  late String _currentDirectory;
  List<FileBrowserEntry> _entries = const [];
  String? _error;
  bool _updatingController = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? FileBrowserController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'FileBrowser');
    _ownsFocusNode = widget.focusNode == null;
    _currentDirectory = Directory(widget.initialDirectory).absolute.path;
    _reloadCurrentDirectory();
  }

  @override
  void didUpdateWidget(covariant FileBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? FileBrowserController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
      _resetSelection();
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'FileBrowser');
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.initialDirectory != oldWidget.initialDirectory) {
      _currentDirectory = Directory(widget.initialDirectory).absolute.path;
      _reloadCurrentDirectory();
    } else if (widget.entityFilter != oldWidget.entityFilter ||
        widget.filter.showHidden != oldWidget.filter.showHidden) {
      _reloadCurrentDirectory();
    } else if (widget.filter.query != oldWidget.filter.query) {
      _resetSelection();
    }
  }

  void _onControllerChange() {
    if (_updatingController) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _reloadCurrentDirectory() {
    _entries = _readEntries(_currentDirectory);
    _resetSelection();
  }

  List<FileBrowserEntry> _readEntries(String directory) {
    try {
      final entities = Directory(directory).listSync(followLinks: false);
      final entries = <FileBrowserEntry>[];
      for (final entity in entities) {
        if (widget.entityFilter != null && !widget.entityFilter!(entity)) {
          continue;
        }
        final entry = _entryFromEntity(entity);
        if (!widget.filter.showHidden && entry.hidden) continue;
        entries.add(entry);
      }
      entries.sort(_compareEntries);
      _error = null;
      return List<FileBrowserEntry>.unmodifiable(entries);
    } on FileSystemException catch (error) {
      _error = error.message;
      return const <FileBrowserEntry>[];
    }
  }

  FileBrowserEntry _entryFromEntity(FileSystemEntity entity) {
    final path = entity.absolute.path;
    final name = _basename(path);
    FileStat? stat;
    try {
      stat = entity.statSync();
    } on FileSystemException {
      stat = null;
    }
    return FileBrowserEntry(
      path: path,
      name: name,
      type: _typeFor(entity, stat),
      sizeBytes: stat?.type == FileSystemEntityType.file ? stat!.size : null,
      modified: stat?.modified,
      hidden: name.startsWith('.'),
    );
  }

  FileBrowserEntryType _typeFor(FileSystemEntity entity, FileStat? stat) {
    if (entity is Directory) return FileBrowserEntryType.directory;
    if (entity is File) return FileBrowserEntryType.file;
    if (entity is Link) return FileBrowserEntryType.link;
    return switch (stat?.type) {
      FileSystemEntityType.directory => FileBrowserEntryType.directory,
      FileSystemEntityType.file => FileBrowserEntryType.file,
      FileSystemEntityType.link => FileBrowserEntryType.link,
      _ => FileBrowserEntryType.other,
    };
  }

  int _compareEntries(FileBrowserEntry a, FileBrowserEntry b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _resetSelection() {
    final order = _currentOrder;
    _updatingController = true;
    try {
      _controller.selectedIndex = order.isEmpty ? null : 0;
    } finally {
      _updatingController = false;
    }
  }

  List<int> get _currentOrder =>
      buildFileBrowserEntryOrder(_entries, filter: widget.filter);

  _SelectedFileEntry? _selectedEntry(List<int> order) {
    if (order.isEmpty) return null;
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) return null;
    final viewIndex = selectedIndex.clamp(0, order.length - 1);
    final sourceIndex = order[viewIndex];
    return _SelectedFileEntry(
      viewIndex: viewIndex,
      sourceIndex: sourceIndex,
      entry: _entries[sourceIndex],
    );
  }

  void _activateSelected() {
    final selected = _selectedEntry(_currentOrder);
    if (selected == null) return;
    final entry = selected.entry;
    if (entry.isDirectory) {
      _openDirectory(entry.path);
    } else {
      widget.onActivate?.call(entry);
    }
  }

  void _activateEntryAt(int viewIndex) {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = viewIndex;
    _activateSelected();
  }

  Future<void> _copyEntryAt(int viewIndex) async {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = viewIndex;
    await _copySelection();
  }

  Future<void> _handleBrowserAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.open:
        _activateSelected();
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  void _openDirectory(String path) {
    setState(() {
      _currentDirectory = Directory(path).absolute.path;
      _reloadCurrentDirectory();
    });
    widget.onDirectoryChanged?.call(_currentDirectory);
  }

  void _goUp() {
    final parent = Directory(_currentDirectory).parent.absolute.path;
    if (parent == _currentDirectory) return;
    _openDirectory(parent);
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection) return;
    final selected = _selectedEntry(_currentOrder);
    if (selected == null) return;
    final text = exportFileBrowserEntry(
      selected.entry,
      options: widget.copyOptions,
    );
    final report = await Clipboard.instance.writeWithReport(
      text,
      policy: widget.copyOptions.clipboardPolicy,
    );
    if (!mounted) return;
    widget.onCopy?.call(
      FileBrowserCopyResult(
        entryIndex: selected.sourceIndex,
        viewIndex: selected.viewIndex,
        entry: selected.entry,
        text: text,
        report: report,
      ),
    );
  }

  KeyEventResult _onNavigationKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowRight:
        _activateSelected();
        return KeyEventResult.handled;
      case KeyCode.arrowLeft:
      case KeyCode.backspace:
        _goUp();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _currentOrder;
    final visible = order.isEmpty
        ? 1
        : (order.length > widget.maxVisible ? widget.maxVisible : order.length);
    final visibleRange = _controller.visibleRange;
    final selected = _selectedEntry(order);
    final copyEnabled = widget.copySelection && selected != null;
    final canActivate =
        widget.onActivate != null || selected?.entry.isDirectory == true;

    Widget body = _error != null
        ? Text('  $_error', style: const CellStyle(dim: true))
        : order.isEmpty
        ? const Text('  (empty)', style: CellStyle(dim: true))
        : Focus(
            canRequestFocus: false,
            onKey: _onNavigationKey,
            child: ListView.builder(
              controller: _controller._listController,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              itemCount: order.length,
              onSelect: (_) => _activateSelected(),
              itemBuilder: (context, viewIndex, activeSelected) {
                final sourceIndex = order[viewIndex];
                final selected = viewIndex == _controller.selectedIndex;
                return _FileBrowserRow(
                  entry: _entries[sourceIndex],
                  sourceIndex: sourceIndex,
                  viewIndex: viewIndex,
                  selected: selected,
                  activeSelection: activeSelected,
                  copyEnabled: copyEnabled,
                  canActivate:
                      widget.onActivate != null ||
                      _entries[sourceIndex].isDirectory,
                  onOpen: () => _activateEntryAt(viewIndex),
                  onCopy: () => _copyEntryAt(viewIndex),
                );
              },
            ),
          );

    body = SizedBox(height: visible, child: body);

    if (copyEnabled) {
      body = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy file path',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: body,
      );
    }

    return Semantics(
      role: SemanticRole.tree,
      label: widget.label,
      value: _sanitizeFileText(_currentDirectory),
      focused: _focusNode.hasFocus,
      actions: {
        SemanticAction.focus,
        if (canActivate) SemanticAction.open,
        if (copyEnabled) SemanticAction.copy,
        SemanticAction.navigate,
      },
      onAction: _handleBrowserAction,
      state: SemanticState({
        'currentDirectory': _sanitizeFileText(_currentDirectory),
        'collectionRowCount': order.length,
        'totalEntryCount': _entries.length,
        'filteredEntryCount': order.length,
        'filterText': _sanitizeFileText(widget.filter.query),
        'showHidden': widget.filter.showHidden,
        'copyEnabled': copyEnabled,
        'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
        if (_error != null) 'error': _sanitizeFileText(_error!),
        if (visibleRange != null && order.isNotEmpty) ...{
          'visibleRangeStart': visibleRange.first,
          'visibleRangeEnd': visibleRange.last,
        },
        if (_controller.selectedIndex != null)
          'selectedIndex': _controller.selectedIndex,
        if (selected != null) ..._selectedEntryState(selected.entry),
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sanitizeFileText(_currentDirectory),
            style: Theme.of(context).mutedStyle,
          ),
          const SizedBox(height: 1),
          body,
        ],
      ),
    );
  }
}

final class _SelectedFileEntry {
  const _SelectedFileEntry({
    required this.viewIndex,
    required this.sourceIndex,
    required this.entry,
  });

  final int viewIndex;
  final int sourceIndex;
  final FileBrowserEntry entry;
}

class _FileBrowserRow extends StatelessWidget {
  const _FileBrowserRow({
    required this.entry,
    required this.sourceIndex,
    required this.viewIndex,
    required this.selected,
    required this.activeSelection,
    required this.copyEnabled,
    required this.canActivate,
    required this.onOpen,
    required this.onCopy,
  });

  final FileBrowserEntry entry;
  final int sourceIndex;
  final int viewIndex;
  final bool selected;
  final bool activeSelection;
  final bool copyEnabled;
  final bool canActivate;
  final void Function() onOpen;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final name = _sanitizeFileText(entry.name);
    final displayName = entry.isDirectory ? '$name/' : name;
    final marker = switch (entry.type) {
      FileBrowserEntryType.directory => '▸ ',
      FileBrowserEntryType.file => '  ',
      FileBrowserEntryType.link => '@ ',
      FileBrowserEntryType.other => '? ',
    };
    final prefix = activeSelection ? '> ' : '  ';
    final style = activeSelection
        ? Theme.of(context).selectionStyle
        : selected
        ? Theme.of(context).mutedStyle
        : CellStyle.empty;
    final sanitizedPath = _sanitizeFileText(entry.path);
    return Semantics(
      role: SemanticRole.treeItem,
      label: displayName,
      value: sanitizedPath,
      selected: selected,
      enabled: true,
      actions: {
        if (canActivate) SemanticAction.open,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.open:
            if (canActivate) onOpen();
            return;
          case SemanticAction.copy:
            if (copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        ..._safeMetadata(entry),
        'rowIndex': sourceIndex,
        'viewIndex': viewIndex,
        'rowKey': sanitizedPath,
        'path': sanitizedPath,
        'entryType': entry.type.name,
        'isDirectory': entry.isDirectory,
        'hidden': entry.hidden,
        'outputSanitized': _entryWasSanitized(entry),
      }),
      child: Text('$prefix$marker$displayName', style: style),
    );
  }
}

Map<String, Object?> _safeMetadata(FileBrowserEntry entry) {
  return <String, Object?>{
    if (entry.sizeBytes != null) 'sizeBytes': entry.sizeBytes,
    if (entry.modified != null) 'modified': entry.modified!.toIso8601String(),
  };
}

Map<String, Object?> _selectedEntryState(FileBrowserEntry entry) {
  return <String, Object?>{
    'selectedKey': _sanitizeFileText(entry.path),
    'selectedPath': _sanitizeFileText(entry.path),
    'selectedEntryType': entry.type.name,
    'selectedIsDirectory': entry.isDirectory,
  };
}

bool _entryMatches(FileBrowserEntry entry, String query) {
  final text = [
    entry.name,
    entry.path,
    entry.type.name,
  ].map(_sanitizeFileText).join(' ').toLowerCase();
  return text.contains(query) || _isSubsequence(query, text);
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay[j] == needle[i]) i++;
  }
  return i == needle.length;
}

String _basename(String path) {
  final separator = Platform.pathSeparator;
  final normalized = path.endsWith(separator) && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final i = normalized.lastIndexOf(separator);
  return i < 0 ? normalized : normalized.substring(i + 1);
}

final _fileLineBreakPattern = RegExp(r'[\r\n\t]');

String _sanitizeFileText(String text) {
  return sanitizeForDisplay(text.replaceAll(_fileLineBreakPattern, ' '));
}

bool _entryWasSanitized(FileBrowserEntry entry) {
  return entry.name != _sanitizeFileText(entry.name) ||
      entry.path != _sanitizeFileText(entry.path);
}
