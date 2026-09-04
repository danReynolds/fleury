import 'dart:async' show unawaited;

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'scaffold.dart';

const _openCommandsId = CommandId('workbench.open-commands');
const _newFileId = CommandId('files.new-file');
const _saveCurrentFileId = CommandId('editor.save');

/// A compact introduction to exposing one action through every command surface.
class CommandIntroApp extends StatelessWidget {
  const CommandIntroApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: Navigator(home: _CommandIntro()));
}

class _CommandIntro extends StatefulWidget {
  const _CommandIntro();

  @override
  State<_CommandIntro> createState() => _CommandIntroState();
}

class _CommandIntroState extends State<_CommandIntro> {
  static const _initialText = 'Hello, Fleury!';

  final _document = TextEditingController(text: _initialText);
  String _savedText = _initialText;
  int _saveCount = 0;

  bool get _isDirty => _document.text != _savedText;

  @override
  void dispose() {
    _document.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _savedText = _document.text;
      _saveCount += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saveCommand = AppCommand(
      id: _saveCurrentFileId,
      title: 'Save current file',
      description: 'Save the document being edited',
      category: 'File',
      shortcuts: <KeySequence>[KeySequence.ctrl.s],
      enabled: (_) => _isDirty,
      semanticAction: SemanticAction.submit,
      run: (_) => _save(),
    );
    final openCommands = AppCommand(
      id: _openCommandsId,
      title: 'Open commands',
      description: 'Search commands available in the editor',
      category: 'Application',
      shortcuts: <KeySequence>[KeySequence.ctrl.k],
      showInPalette: false,
      semanticAction: SemanticAction.open,
      run: (command) {
        final source = command.buildContext;
        if (source != null) {
          unawaited(CommandPalette.open(source, width: 46, maxVisible: 5));
        }
      },
    );

    return CommandScope(
      label: 'Editor commands',
      commands: <AppCommand>[openCommands, saveCommand],
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'ONE COMMAND · EVERY ENTRY POINT',
              style: CellStyle(
                foreground: theme.colorScheme.primary,
                bold: true,
              ),
            ),
            const Text(
              'Save current file · editor.save',
              style: CellStyle(dim: true),
            ),
            const SizedBox(height: 1),
            SizedBox(
              height: 3,
              child: TextArea(
                controller: _document,
                autofocus: true,
                semanticLabel: 'Intro document',
                onChanged: (_) => setState(() {}),
                minLines: 3,
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 1),
            Row(
              children: <Widget>[
                const CommandButton(
                  command: _saveCurrentFileId,
                  label: 'Save',
                  variant: ButtonVariant.primary,
                ),
                const SizedBox(width: 2),
                const Text('Ctrl+S', style: CellStyle(dim: true)),
                const Spacer(),
                const Text('Ctrl+K ', style: CellStyle(dim: true)),
                const CommandButton(
                  command: _openCommandsId,
                  label: 'Commands',
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _isDirty ? 'UNSAVED' : 'SAVED · $_saveCount',
                style: CellStyle(
                  foreground: _isDirty
                      ? theme.colorScheme.warning
                      : theme.colorScheme.success,
                  bold: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A deterministic editor showing commands shared by controls, shortcuts,
/// palettes, semantics, and tests.
class CommandWorkbenchApp extends StatelessWidget {
  const CommandWorkbenchApp({super.key, this.openPaletteInitially = false});

  /// Opens the command palette once the workbench's first frame is painted.
  final bool openPaletteInitially;

  @override
  Widget build(BuildContext context) => SampleScaffold(
    child: Navigator(
      home: _CommandWorkbench(openPaletteInitially: openPaletteInitially),
    ),
  );
}

final class _EditorFile {
  _EditorFile({required this.name, required String text})
    : savedText = text,
      draftText = text;

  final String name;
  String savedText;
  String draftText;

  bool get isDirty => draftText != savedText;
}

class _CommandWorkbench extends StatefulWidget {
  const _CommandWorkbench({required this.openPaletteInitially});

  final bool openPaletteInitially;

  @override
  State<_CommandWorkbench> createState() => _CommandWorkbenchState();
}

class _CommandWorkbenchState extends State<_CommandWorkbench> {
  final _files = <_EditorFile>[
    _EditorFile(
      name: 'main.dart',
      text: "void main() {\n  print('Hello!');\n}",
    ),
    _EditorFile(
      name: 'commands.dart',
      text: 'const save = CommandId(\'editor.save\');',
    ),
    _EditorFile(name: 'README.md', text: '# Tiny editor'),
  ];

  late final TextEditingController _editor = TextEditingController(
    text: _files.first.draftText,
  );
  int _currentIndex = 0;
  int _nextFile = 1;
  int _saveCount = 0;
  String _activity = 'Ready';

  _EditorFile get _currentFile => _files[_currentIndex];

  bool get _canSave => _currentFile.isDirty;

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    setState(() {
      _currentFile.draftText = text;
      _activity = 'Editing ${_currentFile.name}';
    });
  }

  void _selectFile(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentFile.draftText = _editor.text;
      _currentIndex = index;
      _editor.text = _currentFile.draftText;
      _activity = 'Opened ${_currentFile.name}';
    });
  }

  void _newFile() {
    setState(() {
      _currentFile.draftText = _editor.text;
      final file = _EditorFile(name: 'untitled_${_nextFile++}.dart', text: '');
      file.draftText = '// Start typing…';
      _files.add(file);
      _currentIndex = _files.length - 1;
      _editor.text = file.draftText;
      _activity = 'New file · ${file.name}';
    });
  }

  void _saveCurrentFile() {
    setState(() {
      _currentFile.draftText = _editor.text;
      _currentFile.savedText = _currentFile.draftText;
      _saveCount += 1;
      _activity = 'Saved ${_currentFile.name}';
    });
  }

  List<AppCommand> _commands() => <AppCommand>[
    AppCommand(
      id: _openCommandsId,
      title: 'Open commands',
      description: 'Search the editor command palette',
      category: 'Application',
      shortcuts: <KeySequence>[KeySequence.ctrl.k],
      showInPalette: false,
      semanticAction: SemanticAction.open,
      run: (command) {
        final source = command.buildContext;
        if (source != null) {
          unawaited(CommandPalette.open(source, width: 48, maxVisible: 6));
        }
      },
    ),
    AppCommand(
      id: _newFileId,
      title: 'New file',
      description: 'Create and open an untitled file',
      category: 'File',
      shortcuts: <KeySequence>[KeySequence.ctrl.n],
      semanticAction: SemanticAction.start,
      run: (_) => _newFile(),
    ),
    AppCommand(
      id: _saveCurrentFileId,
      title: 'Save current file',
      description: 'Save the document being edited',
      category: 'File',
      shortcuts: <KeySequence>[KeySequence.ctrl.s],
      enabled: (_) => _canSave,
      semanticAction: SemanticAction.submit,
      run: (_) => _saveCurrentFile(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CommandScope(
      label: 'Editor commands',
      commands: _commands(),
      child: _OpenPaletteOnce(
        enabled: widget.openPaletteInitially,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _WorkbenchHeader(fileCount: _files.length, dirty: _canSave),
              const SizedBox(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: 22,
                      child: _FileRail(
                        files: _files,
                        currentIndex: _currentIndex,
                        onSelect: _selectFile,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _CurrentFileEditor(
                        file: _currentFile,
                        editor: _editor,
                        saveCount: _saveCount,
                        onChanged: _onTextChanged,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'LAST COMMAND · $_activity',
                style: Theme.of(context).mutedStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenPaletteOnce extends StatefulWidget {
  const _OpenPaletteOnce({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_OpenPaletteOnce> createState() => _OpenPaletteOnceState();
}

class _OpenPaletteOnceState extends State<_OpenPaletteOnce> {
  var _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.enabled || _scheduled) return;
    _scheduled = true;
    TuiBinding.of(context).addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(CommandPalette.open(context, width: 48, maxVisible: 6));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({required this.fileCount, required this.dirty});

  final int fileCount;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'COMMAND EDITOR',
              style: CellStyle(
                foreground: theme.colorScheme.primary,
                bold: true,
              ),
            ),
            const Spacer(),
            Text('$fileCount FILES', style: theme.mutedStyle),
          ],
        ),
        const Text(
          'New and Save stay in sync across the toolbar, shortcuts, and palette.',
          style: CellStyle(dim: true),
        ),
        const SizedBox(height: 1),
        Row(
          children: <Widget>[
            const CommandButton(
              command: _newFileId,
              label: 'New file',
              variant: ButtonVariant.primary,
            ),
            const SizedBox(width: 1),
            const CommandButton(command: _saveCurrentFileId, label: 'Save'),
            const SizedBox(width: 2),
            Text(
              dirty ? 'Ctrl+S available' : 'Ctrl+S saved',
              style: dirty
                  ? CellStyle(foreground: theme.colorScheme.warning)
                  : theme.mutedStyle,
            ),
            const Spacer(),
            const Text('Ctrl+K ', style: CellStyle(dim: true)),
            const CommandButton(command: _openCommandsId, label: 'Commands'),
          ],
        ),
      ],
    );
  }
}

class _FileRail extends StatelessWidget {
  const _FileRail({
    required this.files,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<_EditorFile> files;
  final int currentIndex;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container.framed(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('FILES', style: CellStyle(bold: true)),
          const Text('Ctrl+N creates one', style: CellStyle(dim: true)),
          const SizedBox(height: 1),
          for (var index = 0; index < files.length; index++)
            Row(
              children: <Widget>[
                Expanded(
                  child: Button(
                    label: files[index].name,
                    variant: index == currentIndex
                        ? ButtonVariant.primary
                        : ButtonVariant.normal,
                    onPressed: () => onSelect(index),
                  ),
                ),
                Text(files[index].isDirty ? '*' : ' '),
              ],
            ),
          const Spacer(),
          const Text('* unsaved', style: CellStyle(dim: true)),
        ],
      ),
    );
  }
}

class _CurrentFileEditor extends StatelessWidget {
  const _CurrentFileEditor({
    required this.file,
    required this.editor,
    required this.saveCount,
    required this.onChanged,
  });

  final _EditorFile file;
  final TextEditingController editor;
  final int saveCount;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container.framed(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(file.name, style: const CellStyle(bold: true)),
              ),
              Text(
                file.isDirty ? 'UNSAVED' : 'SAVED',
                style: CellStyle(
                  foreground: file.isDirty
                      ? theme.colorScheme.warning
                      : theme.colorScheme.success,
                  bold: true,
                ),
              ),
            ],
          ),
          const Text(
            'Edit the file, then save from any command surface.',
            style: CellStyle(dim: true),
          ),
          const SizedBox(height: 1),
          SizedBox(
            height: 6,
            child: TextArea(
              controller: editor,
              autofocus: true,
              semanticLabel: 'Current file contents',
              onChanged: onChanged,
              minLines: 6,
              maxLines: 6,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            children: <Widget>[
              const Text('Ctrl+S · Save current file'),
              const Spacer(),
              Text('SAVES $saveCount', style: theme.mutedStyle),
            ],
          ),
        ],
      ),
    );
  }
}
