import 'package:fleury/fleury_core.dart';

class SplitPane extends StatefulWidget {
  const SplitPane({super.key});

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  final focus = FocusNode();
  bool focused = false;
  int leftWidth = 14;
  bool dragging = false;

  void resize(int delta) => setState(() {
    leftWidth = (leftWidth + delta).clamp(8, 24);
  });

  void finish() => setState(() => dragging = false);

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  // #docregion focus
  Widget get dividerGesture => MouseRegion(
    cursor: MouseCursor.resizeLeftRight,
    child: GestureDetector(
      onDragStart: (_) => setState(() => dragging = true),
      onDragUpdate: (details) => resize(details.delta.col),
      onDragEnd: (_) => finish(),
      onDragCancel: finish,
      child: SizedBox(
        width: 1,
        child: Text(
          '│\n│\n│\n│\n│',
          allowSelect: false,
          style: CellStyle(inverse: focused, bold: dragging),
        ),
      ),
    ),
  );
  // #enddocregion focus

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 5,
        child: Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: const Text('Files\n\nnotes.md\nsketches.txt'),
            ),
            KeyBindings(
              bindings: [
                KeyBinding(
                  KeySequence.left,
                  includeRepeats: true,
                  onTrigger: (_) => resize(-1),
                ),
                KeyBinding(
                  KeySequence.right,
                  includeRepeats: true,
                  onTrigger: (_) => resize(1),
                ),
              ],
              child: FocusDetector(
                onFocusChange: (value) => setState(() => focused = value),
                child: Focus(
                  focusNode: focus,
                  autofocus: true,
                  child: Semantics(
                    role: SemanticRole.slider,
                    label: 'File pane width',
                    value: leftWidth,
                    focused: focused,
                    state: const SemanticState({
                      'min': 8,
                      'max': 24,
                      'step': 1,
                    }),
                    actions: {
                      SemanticAction.focus,
                      if (leftWidth < 24) SemanticAction.increment,
                      if (leftWidth > 8) SemanticAction.decrement,
                    },
                    onAction: (action) {
                      focus.requestFocus();
                      if (action == SemanticAction.increment) resize(1);
                      if (action == SemanticAction.decrement) resize(-1);
                    },
                    child: dividerGesture,
                  ),
                ),
              ),
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 1),
                child: Text(
                  'notes.md\n\nMeet on Tuesday.\nBring the sketches.',
                ),
              ),
            ),
          ],
        ),
      ),
      Text(dragging ? 'Resizing…' : 'Width: $leftWidth · ← → resize'),
      Button(
        text: 'Reset width',
        onPressed: () => setState(() => leftWidth = 14),
      ),
    ],
  );
}
