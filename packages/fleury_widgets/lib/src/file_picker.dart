import 'dart:io';

import 'package:fleury/fleury.dart';

/// A keyboard-driven file picker. Shows the contents of one directory at
/// a time as a scrollable list; Up/Down navigates, Enter opens a folder
/// (or selects a file), Backspace / Left goes to the parent directory.
///
/// ```dart
/// FilePicker(
///   initialDirectory: '/home/user/projects',
///   filter: (entity) => entity is Directory || entity.path.endsWith('.dart'),
///   onSelected: (file) => openInEditor(file.path),
/// )
/// ```
///
/// Filesystem reads are synchronous — fine for a picker UI on local
/// disks, but don't point this at a slow network mount.
class FilePicker extends StatefulWidget {
  const FilePicker({
    super.key,
    required this.initialDirectory,
    required this.onSelected,
    this.filter,
    this.showHidden = false,
    this.semanticLabel = 'Files',
    this.focusNode,
    this.autofocus = false,
  });

  /// Directory the picker opens in. Must exist; missing dirs throw on
  /// first listing attempt.
  final String initialDirectory;

  /// Called with the chosen [File] when Enter is pressed on a file row.
  /// Directories are opened in place — not passed to this callback.
  final void Function(File file) onSelected;

  /// Optional predicate to hide entries. Receives every [Directory] /
  /// [File] before they're rendered; return `false` to skip. Use to
  /// filter by extension, hide build artifacts, etc.
  final bool Function(FileSystemEntity entity)? filter;

  /// When `false` (default), entries whose name starts with `.` are
  /// hidden — matches the unix convention. Set `true` to include them.
  final bool showHidden;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<FilePicker> createState() => _FilePickerState();
}

class _FilePickerState extends State<FilePicker> {
  late FocusNode _node;
  bool _owns = false;
  late Directory _cwd;
  late List<FileSystemEntity> _entries;
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'file-picker');
    _owns = widget.focusNode == null;
    _cwd = Directory(widget.initialDirectory);
    _listEntries();
  }

  @override
  void didUpdateWidget(FilePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'file-picker');
      _owns = widget.focusNode == null;
    }
    if (widget.showHidden != oldWidget.showHidden ||
        !identical(widget.filter, oldWidget.filter)) {
      _listEntries();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context);
  }

  @override
  void dispose() {
    if (_owns) _node.dispose();
    super.dispose();
  }

  /// Lists `_cwd` into `_entries`, applying the filter and the hidden-
  /// file rule, then sorts: directories first, files after, both
  /// alphabetically. Resets the cursor to the top.
  void _listEntries() {
    final all = _cwd.listSync(followLinks: false);
    final filtered = <FileSystemEntity>[];
    for (final e in all) {
      final name = _basename(e.path);
      if (!widget.showHidden && name.startsWith('.')) continue;
      if (widget.filter != null && !widget.filter!(e)) continue;
      filtered.add(e);
    }
    filtered.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return _basename(
        a.path,
      ).toLowerCase().compareTo(_basename(b.path).toLowerCase());
    });
    _entries = filtered;
    _cursor = 0;
  }

  String _basename(String path) {
    final i = path.lastIndexOf(Platform.pathSeparator);
    return i < 0 ? path : path.substring(i + 1);
  }

  String _safeText(String text) {
    return sanitizeForDisplay(
      text.replaceAll(_filePickerLineBreakPattern, ' '),
    );
  }

  String _entryType(FileSystemEntity entry) {
    if (entry is Directory) return 'directory';
    if (entry is File) return 'file';
    if (entry is Link) return 'link';
    return 'other';
  }

  String _displayName(FileSystemEntity entry) {
    final name = _safeText(_basename(entry.path));
    return entry is Directory ? '$name/' : name;
  }

  bool _canOpen(FileSystemEntity entry) => entry is Directory || entry is File;

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
    if (e is Directory) {
      setState(() {
        _cwd = e;
        _listEntries();
      });
    } else if (e is File) {
      widget.onSelected(e);
    }
  }

  void _goUp() {
    final parent = _cwd.parent;
    if (parent.path == _cwd.path) return; // already at filesystem root
    setState(() {
      _cwd = parent;
      _listEntries();
    });
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = _node.hasFocus;
    final safeCwd = _safeText(_cwd.path);
    final selected = _entries.isEmpty ? null : _entries[_cursor];
    final rows = <Widget>[Text(safeCwd, style: theme.mutedStyle)];
    if (_entries.isEmpty) {
      rows.add(const Text('  (empty)', style: CellStyle(dim: true)));
    }
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      final isDir = e is Directory;
      final isSelected = i == _cursor;
      final marker = isDir ? '▸ ' : '  ';
      final rawName = _basename(e.path) + (isDir ? '/' : '');
      final name = _displayName(e);
      final style = isSelected
          ? (focused ? theme.focusedStyle : theme.selectionStyle)
          : CellStyle.empty;
      final safePath = _safeText(e.path);
      final canOpen = _canOpen(e);
      rows.add(
        Semantics(
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
            'entryType': _entryType(e),
            'isDirectory': isDir,
            'hidden': _basename(e.path).startsWith('.'),
            'outputSanitized': safePath != e.path || name != rawName,
          }),
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
        'outputSanitized': safeCwd != _cwd.path,
        if (selected != null) ...{
          'selectedIndex': _cursor,
          'selectedKey': _safeText(selected.path),
          'selectedPath': _safeText(selected.path),
          'selectedEntryType': _entryType(selected),
          'selectedIsDirectory': selected is Directory,
        },
      }),
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKey: _onKey,
        child: GestureDetector(
          onTap: () => _node.requestFocus(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ),
    );
  }
}

final _filePickerLineBreakPattern = RegExp(r'[\r\n\t]');
