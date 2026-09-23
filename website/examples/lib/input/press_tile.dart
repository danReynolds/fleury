import 'package:fleury/fleury_core.dart';
import 'note_preview.dart';

class PressTile extends StatefulWidget {
  const PressTile({super.key});

  @override
  State<PressTile> createState() => _PressTileState();
}

class _PressTileState extends State<PressTile> {
  final focus = FocusNode();
  bool focused = false;
  bool pressed = false;
  String status = 'Ready';

  void open() => setState(() => status = 'Opened notes.md');
  void details() => setState(() => status = 'notes.md · Markdown · 2 KB');

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  // #docregion focus
  Widget get pressTarget => GestureDetector(
    onTapDown: (_) => setState(() => pressed = true),
    onTapUp: (_) => setState(() => pressed = false),
    onTapCancel: () => setState(() {
      pressed = false;
      status = 'Cancelled';
    }),
    onTap: open,
    onSecondaryTap: details,
    child: fileTile,
  );
  // #enddocregion focus

  Widget get fileTile => Text(
    '  notes.md                     \n  Planning notes               \n  Open preview                 ',
    style: CellStyle(
      inverse: pressed,
      underline: focused,
      foreground: pressed ? Colors.yellow : Colors.cyan,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KeyBindings(
        bindings: [
          KeyBinding(
            KeySequence.enter,
            aliases: [KeySequence.space],
            onTrigger: (_) => open(),
          ),
          KeyBinding(KeySequence.i, onTrigger: (_) => details()),
        ],
        child: FocusDetector(
          onFocusChange: (value) => setState(() => focused = value),
          child: Focus(
            focusNode: focus,
            autofocus: true,
            child: Semantics(
              role: SemanticRole.button,
              label: 'Open notes',
              focused: focused,
              actions: const {SemanticAction.focus, SemanticAction.activate},
              onAction: (action) {
                focus.requestFocus();
                if (action == SemanticAction.activate) open();
              },
              child: SelectionArea.disabled(
                child: MouseRegion(
                  cursor: MouseCursor.pointer,
                  child: pressTarget,
                ),
              ),
            ),
          ),
        ),
      ),
      Button(text: 'Details', onPressed: details),
      const SizedBox(height: 1),
      NotePreview(status: pressed ? 'Pressed…' : status),
      Button(
        text: 'Close preview',
        onPressed: () => setState(() => status = 'Ready'),
      ),
      const Text('Enter: open · I: details', style: CellStyle(dim: true)),
    ],
  );
}
