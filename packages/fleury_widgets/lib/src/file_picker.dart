import 'package:fleury/fleury_core.dart';

import 'file_source.dart';
import 'file_source_default_stub.dart'
    if (dart.library.io) 'file_source_default_io.dart';

/// A keyboard-driven file picker. Shows the contents of one directory at
/// a time as a scrollable list; Up/Down navigates, Enter opens a folder
/// (or selects a file), Backspace / Left goes to the parent directory.
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
/// platforms. A browser embed passes one, such as a [MemoryFileSource].
/// Directory reads are synchronous — fine for a picker UI on local disks, but
/// don't point this at a slow network mount.
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

  /// Called with the chosen file when Enter is pressed on a file row.
  /// Directories are opened in place — not passed to this callback.
  final void Function(FileEntry file) onSelect;

  /// Where directories are read from. Defaults to the local disk on native
  /// platforms; in the browser, pass one, such as a [MemoryFileSource].
  final FileSource? source;

  /// Optional predicate to hide entries. Receives every entry before it's
  /// rendered; return `false` to skip. Use to filter by extension, hide
  /// build artifacts, etc.
  final FileEntryFilter? filter;

  /// When `false` (default), entries whose name starts with `.` are
  /// hidden — matches the unix convention. Set `true` to include them.
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
  List<FileEntry> _entries = const [];
  String? _error;
  FileSource? _defaultSource;

  // The selected row lives on a ListController so the entries can render in a
  // scrolling ListView that keeps the cursor in view (a plain Column clipped
  // long directories and let the cursor move off-screen).
  final ListController _list = ListController(initialIndex: 0);
  int get _cursor => _list.currentIndex ?? 0;
  set _cursor(int value) => _list.currentIndex = value;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'file-picker');
    _owns = widget.focusNode == null;
    _cwd = _source.absolute(widget.initialDirectory);
    _listEntries(_cwd);
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
    if (widget.showHidden != oldWidget.showHidden ||
        !identical(widget.filter, oldWidget.filter) ||
        !identical(widget.source, oldWidget.source)) {
      _listEntries(_cwd);
    }
  }

  @override
  void dispose() {
    _list.dispose();
    if (_owns) _node.dispose();
    super.dispose();
  }

  /// Lists [dir] and, on success, commits it as the current directory:
  /// entries filtered (hidden-file rule, [FilePicker.filter]) and sorted
  /// directories first, files after, both alphabetically; cursor reset to
  /// the top. When the listing fails — unreadable or just-deleted directory
  /// — `_cwd`/`_entries` are left untouched and the failure is surfaced as
  /// a dim error row instead of an uncaught [FileSourceException].
  void _listEntries(String dir) {
    final List<FileEntry> all;
    try {
      all = _source.list(dir);
    } on FileSourceException catch (error) {
      _error = error.message;
      return;
    }
    final filter = widget.filter;
    final filtered = <FileEntry>[
      for (final e in all)
        if ((widget.showHidden || !e.hidden) && (filter == null || filter(e)))
          e,
    ];
    filtered.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _error = null;
    _cwd = dir;
    _entries = filtered;
    _list.currentIndex = filtered.isEmpty ? null : 0;
  }

  String _safeText(String text) {
    return sanitizeSingleLine(text);
  }

  String _displayName(FileEntry entry) {
    final name = _safeText(entry.name);
    return entry.isDirectory ? '$name/' : name;
  }

  bool _canOpen(FileEntry entry) => entry.isDirectory || entry.isFile;

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
      setState(() => _listEntries(e.path));
    } else if (e.isFile) {
      widget.onSelect(e);
    }
  }

  void _goUp() {
    final parent = _source.parent(_cwd);
    if (parent == _cwd) return; // already at the root
    setState(() => _listEntries(parent));
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
      child: GestureDetector(
        onTap: canOpen ? () => _activateEntryAt(i) : null,
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
    // the wrap-around Up/Down), so the list itself stays non-focusable.
    final Widget listing = _entries.isEmpty
        ? const Text('  (empty)', style: CellStyle(dim: true))
        : ListView.builder(
            controller: _list,
            itemCount: _entries.length,
            itemBuilder: (context, i, _) => _entryRow(theme, i, focused),
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
