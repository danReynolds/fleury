import 'package:fleury/fleury_core.dart';

class SplitPane extends StatefulWidget {
  const SplitPane({super.key});

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  int leftWidth = 14;
  bool dragging = false;

  void resize(int delta) => setState(() {
    leftWidth = (leftWidth + delta).clamp(8, 24);
  });

  void finish() => setState(() => dragging = false);

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
                KeyBinding(KeySequence.left, onTrigger: (_) => resize(-1)),
                KeyBinding(KeySequence.right, onTrigger: (_) => resize(1)),
              ],
              child: Focus(
                autofocus: true,
                // #docregion interaction
                child: MouseRegion(
                  cursor: MouseCursor.resizeLeftRight,
                  child: GestureDetector(
                    onDragStart: (_) => setState(() => dragging = true),
                    onDragUpdate: (details) => resize(details.delta.col),
                    onDragEnd: (_) => finish(),
                    onDragCancel: finish,
                    child: const SizedBox(
                      width: 1,
                      child: Text(
                        '│\n│\n│\n│\n│',
                        style: CellStyle(inverse: true),
                      ),
                    ),
                  ),
                ),
                // #enddocregion interaction
              ),
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 1),
                child: Text('Preview\n\nReady to edit.'),
              ),
            ),
          ],
        ),
      ),
      Text(dragging ? 'Resizing…' : 'Width: $leftWidth · ← → resize'),
    ],
  );
}
