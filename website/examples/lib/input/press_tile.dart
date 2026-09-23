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
  String? feedback;

  void open() => setState(() {
    status = 'Opened notes.md';
    feedback = null;
  });
  void details() => setState(() {
    status = 'notes.md · Markdown · 2 KB';
    feedback = null;
  });

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
      feedback = 'Cancelled';
    }),
    onTap: open,
    onSecondaryTap: details,
    child: fileTile,
  );
  // #enddocregion focus

  Widget get fileTile => SizedBox(
    width: 31,
    child: Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        'notes.md\nPlanning notes\nOpen preview',
        style: CellStyle(
          inverse: pressed,
          underline: focused,
          foreground: pressed ? Colors.yellow : Colors.cyan,
        ),
      ),
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
      const SizedBox(height: 1),
      Button(text: 'Details', onPressed: details),
      const SizedBox(height: 1),
      NotePreview(status: status, feedback: pressed ? 'Pressed…' : feedback),
      const SizedBox(height: 1),
      Button(
        text: 'Close preview',
        onPressed: () => setState(() {
          status = 'Ready';
          feedback = null;
        }),
      ),
      const SizedBox(height: 1),
      const Text('Enter: open · I: details', style: CellStyle(dim: true)),
    ],
  );
}
