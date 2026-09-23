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
        child: Row(
          children: [
            Expanded(
              child: Text('notes.md', style: CellStyle(inverse: hovered)),
            ),
            Button(
              text: pinned ? 'Unpin' : 'Pin',
              onPressed: () => setState(() => pinned = !pinned),
            ),
          ],
        ),
      ),
      const SizedBox(height: 1),
      Text(hovered ? 'Row hovered' : 'Row not hovered'),
      Text(pinned ? 'Pinned to sidebar' : 'Not pinned'),
    ],
  );
  // #enddocregion focus
}
