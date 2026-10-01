import 'package:fleury/fleury_core.dart';

import 'file_source.dart';
import 'file_source_default_stub.dart'
    if (dart.library.io) 'file_source_default_io.dart';

/// A file picker that shows one directory at a time as a scrollable list and
/// passes the file the user chooses to [onSelect].
///
/// Up and Down move the cursor, wrapping at the ends, and Home and End jump.
/// Enter, Right, or a click on a row opens a folder in place or chooses a
/// file; on a link or other entry, they do nothing. Left or Backspace, or a
/// click on the `..` row, goes to the parent directory.
///
/// ```dart
/// FilePicker(
///   initialDirectory: '/home/user/projects',
///   filter: (entry) => entry.isDirectory || entry.name.endsWith('.dart'),
///   onSelect: (file) => openInEditor(file.path),
/// )
/// ```
///
/// It lists directories from [source]: the local disk by default on native
/// platforms. A browser embed passes one, such as a [MemoryFileSource]. It
/// reads a directory when it opens one or is given a different [source];
/// [filter] and [showHidden] narrow what was read. Directory reads are
/// synchronous — fine for a picker UI on local disks, but don't point this at
/// a slow network mount.
class FilePicker extends StatefulWidget {
  const FilePicker({
    super.key,
    required this.initialDirectory,
    required this.onSelect,
    this.source,
    this.filter,
    this.showHidden = false,
    this.maxVisible = 12,
    this.semanticLabel = 'Files',
    this.focusNode,
    this.autofocus = false,
  }) : assert(maxVisible > 0);

  /// Directory the picker opens in. If it can't be listed (missing or
  /// unreadable), the picker renders a dim error row instead of entries.
  final String initialDirectory;

  /// Called with the chosen file when the user presses Enter or Right on a
  /// file row, or clicks it. Directories open in place instead; links and
  /// other non-file entries do nothing.
  final void Function(FileEntry file) onSelect;

  /// Where directories are read from. Defaults to the local disk on native
  /// platforms; in the browser, pass one, such as a [MemoryFileSource].
  ///
  /// A different source object reads the current directory again, and the
  /// cursor stays on its entry if the new source lists it. Keep one source
  /// across rebuilds (create it outside `build`) so that a rebuild doesn't
  /// read.
  final FileSource? source;

  /// Optional predicate that hides entries: return `false` to skip one. It
  /// runs on the entries of the directory that pass the [showHidden] rule.
  /// Use it to filter by extension, hide build artifacts, and so on.
  ///
  /// A different function applies at once to the entries already read,
  /// without reading the directory again, and the cursor stays on its entry
  /// while that is still shown. So a closure written inline in `build` is
  /// fine, and one that captures state, such as a "Dart files only" toggle,
  /// takes effect on the rebuild that changes it.
  final FileEntryFilter? filter;

  /// Whether to list hidden entries, such as dot-files. Defaults to `false`.
  /// Like a new [filter], a change applies to the entries already read and
  /// keeps the cursor on its entry.
  final bool showHidden;

  /// Maximum rows shown at once; longer directories scroll within this height,
  /// keeping the cursor in view.
  final int maxVisible;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the picker requests focus when mounted.
  final bool autofocus;

  @override
  State<FilePicker> createState() => _FilePickerState();
}

class _FilePickerState extends State<FilePicker> {
  late FocusNode _node;
  bool _owns = false;
  late String _cwd;

  /// [_cwd]'s entries as last read from the source, sorted, before the
  /// [FilePicker.showHidden] rule and [FilePicker.filter] narrow them.
  List<FileEntry> _listing = const [];

  /// The rows shown: [_listing] narrowed by [_visible].
  List<FileEntry> _entries = const [];
  String? _error;
  FileSource? _defaultSource;

  // The selected row lives on a ListController so the entries can render in a
  // scrolling ListView that keeps the cursor in view (a plain Column clipped
  // long directories and let the cursor move off-screen).
  final ListController _list = ListController(initialIndex: 0);
  // Read for the current rows: a cursor [_replaceEntries] placed among new
  // rows counts until the list shows them.
  int get _cursor => _list.cursorFor(itemCount: _entries.length) ?? 0;
  set _cursor(int value) => _list.currentIndex = value;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'file-picker');
    _owns = widget.focusNode == null;
    _cwd = _source.absolute(widget.initialDirectory);
    _openDirectory(_cwd);
  }

  FileSource get _source =>
      widget.source ?? (_defaultSource ??= defaultFileSource());

  @override
  void didUpdateWidget(FilePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'file-picker');
      _owns = widget.focusNode == null;
    }
    if (!identical(widget.source, oldWidget.source)) {
      // A different source has its own entries for this directory.
      final listing = _read(_cwd);
      if (listing != null) _listing = listing;
      _replaceEntries(_visible(_listing));
    } else if (widget.showHidden != oldWidget.showHidden ||
        !identical(widget.filter, oldWidget.filter)) {
      // Both narrow what was already read, so nothing is read again. That
      // matters because a filter closure written inline in the parent's
      // build is a new function on every rebuild.
      _replaceEntries(_visible(_listing));
    }
  }

  @override
  void dispose() {
    _list.dispose();
    if (_owns) _node.dispose();
    super.dispose();
  }

  /// Reads [dir] and, on success, commits it as the current directory with
  /// the cursor on the first row. When the read fails — unreadable or
  /// just-deleted directory — `_cwd`/`_entries` are left untouched and the
  /// failure is surfaced as a dim error row instead of an uncaught
  /// [FileSourceException].
  void _openDirectory(String dir) {
    final listing = _read(dir);
    if (listing == null) return;
    _cwd = dir;
    _listing = listing;
    _entries = _visible(listing);
    _list.currentIndex = _entries.isEmpty ? null : 0;
  }

  /// [dir]'s entries from the source, directories first and files after,
  /// both alphabetically; null when [dir] can't be listed, with the failure
  /// recorded in [_error].
  List<FileEntry>? _read(String dir) {
    final List<FileEntry> listing;
    try {
      listing = [..._source.list(dir)];
    } on FileSourceException catch (error) {
      _error = error.message;
      return null;
    }
    _error = null;
    return listing..sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  /// The rows [listing] shows under the hidden-file rule and
  /// [FilePicker.filter], in listing order.
  List<FileEntry> _visible(List<FileEntry> listing) {
    final filter = widget.filter;
    return <FileEntry>[
      for (final e in listing)
        if ((widget.showHidden || !e.hidden) && (filter == null || filter(e)))
          e,
    ];
  }

  /// Shows [entries] in place of the current rows, keeping the cursor on the
  /// entry it was on while that is still shown, else on the first row.
  void _replaceEntries(List<FileEntry> entries) {
    final before = _entries.isEmpty ? null : _entries[_cursor].path;
    _entries = entries;
    final index = before == null
        ? -1
        : entries.indexWhere((e) => e.path == before);
    if (entries.isEmpty) {
      _list.currentIndex = null;
    } else {
      // The list still counts the old rows; place the cursor among the new.
      _list.moveCursor(index < 0 ? 0 : index, itemCount: entries.length);
    }
  }

  String _safeText(String text) {
    return sanitizeSingleLine(text);
  }

  String _displayName(FileEntry entry) {
    final name = _safeText(entry.name);
    return entry.isDirectory ? '$name/' : name;
  }

  bool _canOpen(FileEntry entry) => entry.isDirectory || entry.isFile;

  static void _ignorePress() {}

  void _activateEntryAt(int index) {
    if (index < 0 || index >= _entries.length) return;
    _node.requestFocus();
    setState(() => _cursor = index);
    _enterCurrent();
  }

  void _handlePickerAction(SemanticAction action) {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _node.requestFocus();
        setState(() {});
        return;
      case SemanticAction.open:
        _node.requestFocus();
        _enterCurrent();
        return;
      case _:
        return;
    }
  }

  void _enterCurrent() {
    if (_entries.isEmpty) return;
    final e = _entries[_cursor];
    if (e.isDirectory) {
      setState(() => _openDirectory(e.path));
    } else if (e.isFile) {
      widget.onSelect(e);
    }
  }

  void _goUp() {
    final parent = _source.parent(_cwd);
    if (parent == _cwd) return; // already at the root
    setState(() => _openDirectory(parent));
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.code) {
      case KeyCode.arrowDown:
        if (_entries.isEmpty) return KeyEventResult.handled;
        setState(() => _cursor = (_cursor + 1) % _entries.length);
        return KeyEventResult.handled;
      case KeyCode.arrowUp:
        if (_entries.isEmpty) return KeyEventResult.handled;
        setState(
          () => _cursor = (_cursor - 1 + _entries.length) % _entries.length,
        );
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
      case KeyCode.enter:
        _enterCurrent();
        return KeyEventResult.handled;
      case KeyCode.arrowLeft:
      case KeyCode.backspace:
        _goUp();
        return KeyEventResult.handled;
      case KeyCode.home:
        setState(() => _cursor = 0);
        return KeyEventResult.handled;
      case KeyCode.end:
        if (_entries.isNotEmpty) {
          setState(() => _cursor = _entries.length - 1);
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Widget _entryRow(ThemeData theme, int i, bool focused) {
    final e = _entries[i];
    final isDir = e.isDirectory;
    final isSelected = i == _cursor;
    final marker = isDir ? '▸ ' : '  ';
    final rawName = e.name + (isDir ? '/' : '');
    final name = _displayName(e);
    final style = isSelected
        ? (focused ? theme.selectionStyle : theme.mutedStyle)
        : CellStyle.none;
    final safePath = _safeText(e.path);
    final canOpen = _canOpen(e);
    return Semantics(
      role: SemanticRole.treeItem,
      label: name,
      value: safePath,
      selected: isSelected,
      enabled: true,
      actions: {if (canOpen) SemanticAction.open},
      onAction: (action) {
        switch (action) {
          case SemanticAction.open:
            if (canOpen) _activateEntryAt(i);
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': i,
        'rowKey': safePath,
        'path': safePath,
        'entryType': e.type.name,
        'isDirectory': isDir,
        'hidden': e.hidden,
        'outputSanitized': safePath != e.path || name != rawName,
      }),
      // Click a row to activate it: a directory opens in place, a file is
      // selected — the same single action the keyboard's Enter/Right performs.
      // A row that can't open still owns its press and ignores it. Otherwise
      // the list's own row gesture takes the press and moves the cursor.
      child: GestureDetector(
        onTap: canOpen ? () => _activateEntryAt(i) : _ignorePress,
        child: Row(
          children: [
            Text(' ', style: style),
            Text(marker, style: style),
            Text(name, style: style),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = context.listen(_node).hasFocus;
    final safeCwd = _safeText(_cwd);
    final selected = _entries.isEmpty ? null : _entries[_cursor];
    final visible = _entries.isEmpty
        ? 1
        : (_entries.length > widget.maxVisible
              ? widget.maxVisible
              : _entries.length);
    // A controller-driven ListView windows long directories and scrolls to keep
    // the cursor in view; keys are still handled by the outer Focus (preserving
    // the wrap-around Up/Down), so the list itself is kept out of focus. A
    // press that focused it would hand the arrows and Enter to its plain
    // cursor instead.
    final Widget listing = _entries.isEmpty
        ? const Text('  (empty)', style: CellStyle(dim: true))
        : ExcludeFocus(
            child: ListView.builder(
              controller: _list,
              itemCount: _entries.length,
              itemBuilder: (context, i, _) => _entryRow(theme, i, focused),
            ),
          );
    // A clickable parent-directory row so the mouse can climb out of a folder
    // without the keyboard (Backspace / Left). Hidden at the filesystem root.
    final canGoUp = _source.parent(_cwd) != _cwd;
    final Widget? upRow = canGoUp
        ? Semantics(
            role: SemanticRole.treeItem,
            label: 'Parent directory',
            value: _safeText(_source.parent(_cwd)),
            enabled: true,
            actions: {SemanticAction.open},
            onAction: (action) {
              if (action == SemanticAction.open) {
                _node.requestFocus();
                _goUp();
              }
            },
            child: GestureDetector(
              onTap: () {
                _node.requestFocus();
                _goUp();
              },
              child: Row(
                children: [
                  Text(' ', style: theme.mutedStyle),
                  Text('▴ ', style: theme.mutedStyle),
                  Text('..', style: theme.mutedStyle),
                ],
              ),
            ),
          )
        : null;
    return Semantics(
      role: SemanticRole.tree,
      label: widget.semanticLabel,
      value: safeCwd,
      focused: focused,
      actions: {
        SemanticAction.focus,
        SemanticAction.navigate,
        if (selected != null && _canOpen(selected)) SemanticAction.open,
      },
      onAction: _handlePickerAction,
      state: SemanticState({
        'currentDirectory': safeCwd,
        'collectionRowCount': _entries.length,
        'showHidden': widget.showHidden,
        'outputSanitized': safeCwd != _cwd,
        if (_error != null) 'error': _safeText(_error!),
        if (selected != null) ...{
          'currentIndex': _cursor,
          'selectedKey': _safeText(selected.path),
          'selectedPath': _safeText(selected.path),
          'selectedEntryType': selected.type.name,
          'selectedIsDirectory': selected.isDirectory,
        },
      }),
      child: KeyDetector(
        onKey: (event) {
          if ((_onKey)(event) == KeyEventResult.handled) event.consume();
        },
        child: Focus(
          focusNode: _node,
          autofocus: widget.autofocus,
          child: GestureDetector(
            onTap: () => _node.requestFocus(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(safeCwd, style: theme.mutedStyle),
                // A failed listing (unreadable / just-deleted directory) shows
                // up as a dim status row; the retained listing stays usable.
                if (_error != null)
                  Text(
                    '  ${_safeText(_error!)}',
                    style: const CellStyle(dim: true),
                  ),
                ?upRow,
                SizedBox(height: visible, child: listing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
