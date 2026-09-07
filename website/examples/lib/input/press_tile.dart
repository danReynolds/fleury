import 'package:fleury/fleury_core.dart';

class PressTile extends StatefulWidget {
  const PressTile({super.key});

  @override
  State<PressTile> createState() => _PressTileState();
}

class _PressTileState extends State<PressTile> {
  bool pressed = false;
  String status = 'Ready';

  void open() => setState(() => status = 'Opened notes.md');
  void details() => setState(() => status = 'notes.md · Markdown · 2 KB');

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KeyBindings(
        bindings: [
          KeyBinding(KeySequence.enter, onTrigger: (_) => open()),
          KeyBinding(KeySequence.space, onTrigger: (_) => open()),
          KeyBinding(KeySequence.i, onTrigger: (_) => details()),
        ],
        child: Focus(
          autofocus: true,
          child: Semantics(
            role: SemanticRole.button,
            label: 'Open notes',
            actions: const {SemanticAction.activate},
            onAction: (_) => open(),
            // #docregion interaction
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
                style: CellStyle(inverse: pressed),
              ),
            ),
            // #enddocregion interaction
          ),
        ),
      ),
      const SizedBox(height: 1),
      Text(pressed ? 'Pressed…' : status),
      const Text('Enter: open · I: details', style: CellStyle(dim: true)),
    ],
  );
}
