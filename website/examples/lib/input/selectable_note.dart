import 'package:fleury/fleury_core.dart';

class SelectableNote extends StatefulWidget {
  const SelectableNote({super.key});

  @override
  State<SelectableNote> createState() => _SelectableNoteState();
}

class _SelectableNoteState extends State<SelectableNote> {
  String selected = '';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      SelectionArea(
        onSelectionChanged: (content) => setState(() {
          selected = content?.plainText ?? '';
        }),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Planning notes', style: CellStyle(bold: true)),
            Text('Ship the guide.\nReview the gestures.'),
          ],
        ),
      ),
      // #enddocregion interaction
      const SizedBox(height: 1),
      Text(
        selected.isEmpty
            ? 'Drag across the note'
            : '${selected.length} characters selected',
      ),
      const Text(
        'Ctrl+A: all · Ctrl+C: copy · Esc',
        style: CellStyle(dim: true),
      ),
      const SizedBox(height: 1),
      const Text('REPLY', style: CellStyle(dim: true)),
      const TextInput(
        semanticLabel: 'Reply',
        placeholder: 'Type here, then select the note',
        autofocus: true,
      ),
    ],
  );
}
