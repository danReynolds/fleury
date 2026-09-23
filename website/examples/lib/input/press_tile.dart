import 'package:fleury/fleury_core.dart';

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

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      KeyBindings(
        bindings: [
          KeyBinding(KeySequence.enter, onTrigger: (_) => open()),
          KeyBinding(KeySequence.space, onTrigger: (_) => open()),
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
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => pressed = true),
                    onTapUp: (_) => setState(() => pressed = false),
                    onTapCancel: () => setState(() {
                      pressed = false;
                      status = 'Cancelled';
                    }),
                    onTap: open,
                    onSecondaryTap: details,
                    child: Text(
                      '[ Open notes.md ]',
                      style: CellStyle(inverse: pressed, underline: focused),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Button(text: 'Details', onPressed: details),
      // #enddocregion interaction
      const SizedBox(height: 1),
      Text(pressed ? 'Pressed…' : status),
      const Text('Enter: open · I: details', style: CellStyle(dim: true)),
    ],
  );
}
