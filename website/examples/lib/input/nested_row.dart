import 'package:fleury/fleury_core.dart';

class NestedRow extends StatefulWidget {
  const NestedRow({super.key});

  @override
  State<NestedRow> createState() => _NestedRowState();
}

class _NestedRowState extends State<NestedRow> {
  // #docregion focus
  bool hovered = false;
  bool pinned = false;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MouseRegion(
        onEnter: () => setState(() => hovered = true),
        onExit: () => setState(() => hovered = false),
        child: Container.framed(
          width: 26,
          padding: const EdgeInsets.symmetric(horizontal: 1),
          border: BoxBorder(
            cellStyle: CellStyle(foreground: hovered ? Colors.cyan : null),
          ),
          child: Row(
            children: [
              const Text('notes.md'),
              const SizedBox(width: 2),
              Button(
                text: pinned ? 'Unpin' : 'Pin',
                onPressed: () => setState(() => pinned = !pinned),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 1),
      Text(hovered ? 'Inside file row' : 'Outside file row'),
      Text(pinned ? 'Pinned to sidebar' : 'Not pinned'),
    ],
  );
  // #enddocregion focus
}
