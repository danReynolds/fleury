// Compile-checked source for the Commands guide.

import 'dart:async' show unawaited;

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

const saveFile = CommandId('editor.save');
const openCommands = CommandId('commands.open');

Future<void> main() => runApp(
  const FleuryApp(title: 'Command guide', home: CommandGuideDemo()),
  mode: const TerminalMode(mouse: true),
);

/// One file action presented as a button, shortcut, palette row, semantic
/// command, and stable programmatic ID.
class CommandGuideDemo extends StatefulWidget {
  const CommandGuideDemo({super.key});

  @override
  State<CommandGuideDemo> createState() => _CommandGuideDemoState();
}

class _CommandGuideDemoState extends State<CommandGuideDemo> {
  static const _initialDraft = 'Commands keep every surface in sync';

  late final TextEditingController _draft = TextEditingController(
    text: _initialDraft,
  );
  var _savedDraft = _initialDraft;
  var _saveCount = 0;

  bool get _dirty => _draft.text != _savedDraft;

  List<AppCommand> _commands() => <AppCommand>[
    AppCommand(
      id: openCommands,
      title: 'Open commands',
      description: 'Search every action available in this screen',
      category: 'Application',
      shortcuts: <KeySequence>[KeySequence.ctrl.k],
      showInPalette: false,
      semanticAction: SemanticAction.open,
      run: (command) {
        final source = command.buildContext;
        if (source != null) unawaited(CommandPalette.open(source));
      },
    ),
    AppCommand(
      id: saveFile,
      title: 'Save current file',
      description: 'Save the document being edited',
      category: 'File',
      shortcuts: <KeySequence>[KeySequence.ctrl.s],
      enabled: (_) => _dirty,
      semanticAction: SemanticAction.submit,
      run: (_) => _save(),
    ),
  ];

  void _save() {
    if (!_dirty) return;
    setState(() {
      _savedDraft = _draft.text;
      _saveCount += 1;
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    home: CommandScope(
      label: 'Editor commands',
      commands: _commands(),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('COMMANDS IN ONE PLACE', style: CellStyle(bold: true)),
            const Text('Edit the draft, then save from any command surface.'),
            const SizedBox(height: 1),
            TextInput(
              controller: _draft,
              autofocus: true,
              semanticLabel: 'Draft',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 1),
            Row(
              children: const <Widget>[
                CommandButton(
                  command: saveFile,
                  label: 'Save',
                  variant: ButtonVariant.primary,
                ),
                SizedBox(width: 1),
                CommandButton(command: openCommands, label: 'Commands'),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              _dirty
                  ? 'UNSAVED · Save is available everywhere'
                  : 'SAVED · $_saveCount saves · Save is disabled everywhere',
            ),
            const Spacer(),
            const KeyHintBar(maxBindings: 3),
          ],
        ),
      ),
    ),
  );
}
